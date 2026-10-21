# backend/wgpu/pipeline.jl — the mp4 pipeline: the readback one frame behind,
# over MapRead buffers, feeding the encoder thread.
#
# Reading a frame back synchronously stalls the render: at 1080p the wait
# costs 5.1 ms of a 6.6 ms frame, and one frame behind, 0.004 ms. So frame k
# is copied into staging buffer k while frame k−1 is harvested from the other:
#
#   copyTextureToBuffer → staging[k]; submit
#   map staging[k−1] + poll(index k−1) + copy into a CPU buffer
#   close_pipeline! drains the last frame
#
# Two properties make this simple on WebGPU:
#
#   · WebGPU orders work per queue: a copy submitted after a render pass sees
#     what that pass left, and the next pass cannot overtake a copy already
#     submitted. The rule that remains — never write into a buffer that is
#     still mapped — applies to the staging buffer, which is why there are
#     two of them.
#   · The wait is `wgpuDevicePoll` on the SUBMISSION INDEX of the copy being
#     harvested, not on everything: the GPU goes on with frame k while the
#     CPU reads frame k−1.
#
# The CPU buffers the render thread fills hold the PADDED RGBA rows exactly
# as the GPU wrote them (one memcpy per frame, nothing else). A CONVERTER
# task of its own crops them to tight rows and drops the alpha (4 → 3) into a
# second pool, and the encoder task (`_spawn_encoder` / `_spawn_encoder_alpha`,
# video_impl.jl) consumes those. Cropping on its own thread overlaps with both
# neighbours; on the encoder's thread the 0.6 ms crop (1080p) sat in series
# with VideoIO's write and cost about 5 % of the throughput.
#
# The risk this design carries: the LAST frame is still in a staging buffer
# when the scene ends, and forgetting to drain it fails silently — the file
# is one frame short and nothing says so. `close_pipeline!` drains
# (`drain = false` exists to demonstrate the loss and for nothing else).
#
# The second risk: a stage that DIES. The pool is three buffers deep, and a
# dead encoder returns none of them — the converter crops three frames and
# blocks on its fourth `take!(free_tight)`, the render thread has two left and
# blocks on its seventh `take!(free)`, and nothing says a word (an output
# whose directory did not exist hung exactly like that). Two things fix it:
# each stage's return channel is BOUND to its task (`Base.bind`), so a task
# that fails closes the channel its neighbour waits on and hands it the
# failure; and `enqueue!` and `close_pipeline!` ASK (`_check_stages!`) before
# they block, because a closed channel still serves what its buffer holds.

# The pool's size, the copy-free wrappers VideoIO writes through and the
# un-premultiply of the transparent route.
using Colors: RGB, RGBA
using FixedPointNumbers: N0f8

const _N_BUFS = 3    # pool: render writes one, encoder reads another, one spare

"""
    _FRAME_TAP

The frame tap: `nothing`, or a function `(k, bytes)` the converter task calls
with every TIGHT frame — `k` from 0, `bytes` exactly what the encoder is about
to receive (RGB rows; RGBA on the transparent route) — before handing it on.
One branch a frame when unset. Hashing the frames of two renders through it
measures «the same frames» where it is ours: x264 at ONE thread can write a
different tail of the IDR slice for identical input frames under CPU load, so
the mp4's bytes are informative, not the bar. The callback runs on the
converter's task: keep it short, and touch nothing the encoder reads.
"""
const _FRAME_TAP = Ref{Any}(nothing)

"Copy-free wrapper: contiguous scanlines → Matrix (width, height) for scanline_major."
_wrap(bytes::Vector{UInt8}, W, H) = reshape(reinterpret(RGB{N0f8}, bytes), W, H)
_wrap_rgba(bytes::Vector{UInt8}, W, H) = reshape(reinterpret(RGBA{N0f8}, bytes), W, H)

"""
    _unpremultiply!(bytes)

The engine composites in PREMULTIPLIED alpha — that is what makes a
layer's surface correct, and it is measurable: a 50%-opacity yellow
reads (128,128,0,128), not (255,255,0,128). Editors and ProRes expect
STRAIGHT alpha, so handing them the buffer as-is produces the classic dark
fringe the moment anyone composites the clip. Undoing it is `rgb / a`, in
place, on the encoder's thread — never on the render thread.

Fully transparent pixels keep rgb = 0: there is no colour to recover, and
dividing by zero would invent one.
"""
function _unpremultiply!(bytes::Vector{UInt8})
    @inbounds for i in 1:4:length(bytes)
        a = bytes[i+3]
        (a == 0x00 || a == 0xff) && continue
        inv = 255.0f0 / a
        bytes[i]   = round(UInt8, min(255f0, bytes[i]   * inv))
        bytes[i+1] = round(UInt8, min(255f0, bytes[i+1] * inv))
        bytes[i+2] = round(UInt8, min(255f0, bytes[i+2] * inv))
    end
    return bytes
end

"""
    FramePipeline(gpu, target, path; fps, crf, preset, encoder_threads, transparent)

The mp4 pipeline: opens the encoder on `path` and streams `target` into it,
one `enqueue!` per frame, a `close_pipeline!` at the end.
"""
mutable struct FramePipeline
    gpu::GPU
    target::GPUTarget
    path::String
    width::Int
    height::Int
    bpr::Int                        # padded bytes per row
    nbytes::Int                     # bpr · height, the staging size
    staging::Vector{WGPUBuffer}     # behind + 1 = 2
    index::Vector{UInt64}           # submission index of the copy into each staging
    bufs::Vector{Vector{UInt8}}     # the padded pool the render thread fills
    free::Channel{Int}              # render ← converter
    filled::Channel{Int}            # render → converter
    tight::Vector{Vector{UInt8}}    # the tight pool the encoder reads (RGB, or RGBA)
    free_tight::Channel{Int}        # converter ← encoder
    filled_tight::Channel{Int}      # converter → encoder
    converter::Task
    encoder::Task
    k::Int                          # frames enqueued
    frames_written::Int
    transparent::Bool
    closed::Bool
end

const _N_STAGING = 2

"""
The converter task: every padded frame the render thread hands over is
cropped to tight rows — RGB for the opaque route, RGBA (still premultiplied)
for the transparent one — into the pool the encoder consumes. It ends when
`filled` closes, and closes `filled_tight` behind it so the encoder ends too.
"""
function _spawn_converter(bufs, tight, free, filled, free_tight, filled_tight,
                          W::Int, H::Int, bpr::Int, transparent::Bool)
    return Threads.@spawn begin
        n = 0
        try
            for ib in filled
                it = take!(free_tight)
                GC.@preserve bufs begin
                    transparent ? _crop_rows!(tight[it], pointer(bufs[ib]), W, H, bpr) :
                                  _crop_rows_rgb!(tight[it], pointer(bufs[ib]), W, H, bpr)
                end
                tap = _FRAME_TAP[]
                tap === nothing || tap(n, tight[it])     # the frame as the encoder gets it
                put!(free, ib)
                put!(filled_tight, it)
                n += 1
            end
        finally
            close(filled_tight)
        end
        n
    end
end

function FramePipeline(gpu::GPU, target::GPUTarget, path::String;
                       fps::Int = 60, crf::Int = 23, preset::String = "medium",
                       encoder_threads::Union{Nothing, Int} = nothing,
                       transparent::Bool = false)
    W, H = target.width, target.height
    bpr = padded_bytes_per_row(W)
    nbytes = bpr * H
    nch = transparent ? 4 : 3
    bufs = [Vector{UInt8}(undef, nbytes) for _ in 1:_N_BUFS]
    tight = [Vector{UInt8}(undef, nch * W * H) for _ in 1:_N_BUFS]
    free, filled = Channel{Int}(_N_BUFS), Channel{Int}(_N_BUFS)
    free_tight, filled_tight = Channel{Int}(_N_BUFS), Channel{Int}(_N_BUFS)
    foreach(i -> put!(free, i), 1:_N_BUFS)
    foreach(i -> put!(free_tight, i), 1:_N_BUFS)
    staging = [_create_staging(gpu, nbytes) for _ in 1:_N_STAGING]
    _ensure_video!()
    # the encoder (video_impl.jl): tight frames in, x264 out
    encoder = Base.invokelatest(_spawn_encoder, path, tight, W, H,
                                free_tight, filled_tight, fps, crf, preset,
                                encoder_threads, transparent)::Task
    converter = _spawn_converter(bufs, tight, free, filled, free_tight, filled_tight,
                                 W, H, bpr, transparent)
    # A stage that dies must not leave its upstream neighbour waiting:
    # a channel bound to a task is closed when the task ends, and if the task
    # FAILED, every waiter on it receives that task's TaskFailedException
    # (Base's `close_chnl_on_taskdone`). The encoder returns buffers through
    # `free_tight` (the converter waits there); the converter through `free`
    # (the render thread waits there). Normal termination closes them too,
    # harmlessly: each is read only upstream of its owner, and by the time
    # the owner ends its reader has stopped taking.
    Base.bind(free_tight, encoder)
    Base.bind(free, converter)
    return FramePipeline(gpu, target, path, W, H, bpr, nbytes, staging,
                         zeros(UInt64, _N_STAGING), bufs, free, filled,
                         tight, free_tight, filled_tight, converter, encoder,
                         0, 0, transparent, false)
end

"Map staging `slot`, wait for its copy, memcpy it into `dest`, unmap."
function _harvest!(p::FramePipeline, slot::Int, dest::Vector{UInt8})
    _with_mapped(p.gpu, p.staging[slot], p.nbytes, p.index[slot]) do ptr
        unsafe_copyto!(pointer(dest), ptr, p.nbytes)
    end
    return dest
end

"""
    _check_stages!(p)

The question `enqueue!` and `close_pipeline!` ask before they block:
did a downstream stage die? The encoder first, because its failure is the
ROOT of the converter's (the bound channel hands it up wrapped once more);
then the converter. The bound channels alone do not give a prompt answer: a
`take!` on a closed channel still returns what its buffer holds, so without
this the render thread would draw up to `_N_BUFS` more frames into a dead
encoder before its channel ran dry. Two field reads a frame.
"""
function _check_stages!(p::FramePipeline)
    istaskfailed(p.encoder) && throw(TaskFailedException(p.encoder))
    istaskfailed(p.converter) && throw(TaskFailedException(p.converter))
    return nothing
end

"""
    enqueue!(p::FramePipeline)

Copy the frame just drawn into staging k and harvest k−1 into a free CPU
buffer for the encoder (only blocks when the encoder is backed up). The
first call only copies: frame 0 leaves with frame 1's call, and the last
one with `close_pipeline!`. A stage that has died is reported here, as its
own failure, before anything is copied.
"""
function enqueue!(p::FramePipeline)
    _check_stages!(p)
    slot = 1 + p.k % _N_STAGING
    p.index[slot] = _copy_target_to_buffer!(p.gpu, p.target, p.staging[slot])
    _check_gpu_errors!(p.gpu)
    if p.k > 0
        prev = 1 + (p.k - 1) % _N_STAGING
        ib = take!(p.free)
        _harvest!(p, prev, p.bufs[ib])
        put!(p.filled, ib)
        p.frames_written += 1
    end
    p.k += 1
    return p
end

"""
    close_pipeline!(p::FramePipeline; drain = true) → frames written

Harvest the frame still in flight, close the channel, wait for the converter
and the encoder (either rethrows if it failed), release the staging buffers.
`drain = false` is the pipeline that forgets its last frame, and has no
other use.

A stage that has already died is reported BEFORE the drain (there is
nobody to drain into, and the drain's `take!` is where a dead converter used
to hang the close), `filled` is closed whatever happened so a converter still
waiting for frames can end, and the staging buffers are released in a
`finally`: a close that fails must not also leak them.
"""
function close_pipeline!(p::FramePipeline; drain::Bool = true)
    p.closed && return p.frames_written
    p.closed = true
    written = 0
    try
        _check_stages!(p)
        if p.k > 0 && drain
            last = 1 + (p.k - 1) % _N_STAGING
            ib = take!(p.free)
            _harvest!(p, last, p.bufs[ib])
            put!(p.filled, ib)
            p.frames_written += 1
        end
        close(p.filled)                 # the converter ends, and closes filled_tight
        wait(p.converter)               # rethrows if the crop failed
        written = fetch(p.encoder)      # rethrows if the encoder failed
    finally
        close(p.filled)                 # idempotent; lets a waiting converter end
        for b in p.staging
            wgpuBufferDestroy(b)
            wgpuBufferRelease(b)
        end
    end
    return written
end
