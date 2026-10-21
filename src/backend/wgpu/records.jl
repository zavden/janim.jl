# backend/wgpu/records.jl — what the renderer remembers between frames: the
# run records, the mirrors, the mesh records and the draw cache, the vertex
# arena the runs live in, and the render VM that holds them all.
#
#   · a run's six SoA arrays are the very arrays `expanded_data` and
#     `_concat_expanded` produce, written into a SPAN of the VM's vertex arena
#     (below);
#   · every VMobject's source rows are mirrored and memcmp'd once per pass
#     (`_sync_mirror!`), a member whose rows moved is re-expanded and its
#     RANGE of every array goes up with `wgpuQueueWriteBuffer`, a run whose
#     members, gradient or curve counts changed is rebuilt whole;
#   · meshes and clouds keep one buffer per array, an index buffer when
#     indexed, and re-upload the array whose mirror differs — WHOLE, into the
#     same buffer when the size fits, into a new one when it grew (a write
#     cannot exceed the buffer);
#   · the sweep every 64 passes releases what no pass drew in the last 8.
#
# One number per member is kept for the stroke: the largest sqrt(area) of its
# curves, from the same expanded triples the stroke's shader reads. The
# instanced stroke draws `6·(S − 1)` vertices per curve with S the run's
# largest n_steps, and this is what S is computed from every frame
# (`_step_budget`), so a run of straight lines costs 12 vertices a curve
# instead of the 186 a fixed budget would charge. The shader recomputes its
# own n_steps from the same formula and collapses whatever the budget has
# past it; S carries one step of margin against the rounding of `sqrt`.
#
# The runs' six arrays do not live in six buffers PER RUN: they live in six
# buffers per render VM — the `VertexArena` — from which every run
# sub-allocates a stable span in expanded-vertex units (a free list, first
# fit, coalesced; a span is freed when its record is rebuilt or swept, and
# the arena grows by copying itself on the queue when a span does not fit).
# The reason is a measurement: with a buffer per run, a frame of 3 000
# stroke-only roots spent 0.74 µs a run in the pass encoder — eight calls
# into wgpu-native per draw, five of them `SetVertexBuffer` — while the same
# 3 000 shapes in ONE run were several times faster. With one arena the five
# buffers are bound once per pass and a run is
# `draw(…, first_instance = base ÷ 3)`: the instance-stepped attributes are
# fetched from its span. A moved member uploads its bytes and nothing else,
# a hot frame uploads nothing, an inserted mobject rebuilds its run and no
# other.
#
# The uploads write through the queue, which orders them before the
# frame's command buffer and after the previous frame's: no stall, no
# orphaning, no fence — and destroying a buffer a submitted frame still
# reads is safe, wgpu frees it when that submission completes.

using GeometryBasics: Point3f, Vec4f

"One run's GPU side: its span in the vertex arena, and the step budget."
mutable struct GPURunRecord
    members::Vector{VMobject}    # the run this record holds (a copy of the loop's vector)
    grad::Union{Nothing,FillGradient}
    n::Int                       # expanded vertices in the run (3 · curves) = the span's length
    offsets::Vector{Int}         # per member: first expanded vertex (0-based, within the span)
    counts::Vector{Int}          # per member: 3 · curves
    gens::Vector{Int}            # per member: the mirror gen the arena holds
    fills::Vector{Bool}          # per member: has a fill
    strokes::Vector{Bool}        # per member: has a stroke
    sqrt_area::Vector{Float32}   # per member: max √area over its curves — the stroke's step budget
    base::Int                    # first expanded vertex of the span in the VertexArena
    last_pass::Int
end

"One VMobject's rows as the cache last saw them (see `VMirror`)."
mutable struct GPUVMirror
    points::Vector{Point3f}
    stroke_rgba::Vector{Vec4f}
    fill_rgba::Vector{Vec4f}
    stroke_width::Vector{Float32}
    gen::Int
    has_fill::Bool
    has_stroke::Bool
    last_pass::Int
    runs::Vector{GPURunRecord}
end

"A mesh or a cloud: one buffer per array, an index buffer when indexed, a mirror per array."
mutable struct GPUMeshRecord
    bufs::Vector{WGPUBuffer}
    sizes::Vector{Int}
    mirrors::Vector{Vector}      # one copy per buffer, compared bit for bit
    index::WGPUBuffer            # C_NULL without one
    index_size::Int
    index_mirror::Vector{Int32}
    count::Int                   # vertices (arrays) or indices to draw
    last_pass::Int
end

mutable struct GPUDrawCache
    pass::Int                                 # rises with every _draw_list!
    mirrors::IdDict{VMobject,GPUVMirror}      # and, through them, the run records
    meshes::IdDict{Mobject,GPUMeshRecord}
end
GPUDrawCache() = GPUDrawCache(0, IdDict{VMobject,GPUVMirror}(), IdDict{Mobject,GPUMeshRecord}())

"A texture the cache holds: the GPU objects, its bind group (group 2), and the pinned pixels."
struct GPUTextureEntry
    texture::WGPUTexture
    view::WGPUTextureView
    bind_group::WGPUBindGroup
    pixels::Array{UInt8,3}
end

"""
One draw the frame's pass will record, collected while the draw list is
walked (records brought up to date, blocks staged) and encoded afterwards,
once the arena is known to fit: the pipeline's key, the block's slot, the
record whose buffers (or span) it draws, the counts, the texture's bind
group (an image, a gradient's ramp), and `first`, the draw's first instance
in the vertex arena in curves — a run's base for its stroke; a
`:stencil` / `:cover` command (and their `_grad` twins) is ONE member's
fill, the count and the paint of that member's curves alone, two draws in
the frame's one pass, and `first` is its span's base plus its offset.
"""
struct DrawCmd
    kind::Symbol
    depth::Bool
    z_pass::Bool
    block::Int
    rec::Any
    vertices::Int
    instances::Int
    tex::WGPUBindGroup
    first::Int
end
DrawCmd(kind, depth, z_pass, block, rec, vertices, instances, tex) =
    DrawCmd(kind, depth, z_pass, block, rec, vertices, instances, tex, 0)

"A gradient's ramp on the GPU: the texture, its view, its bind group (group 2), the pinned ramp."
struct GPURampEntry
    texture::WGPUTexture
    view::WGPUTextureView
    bind_group::WGPUBindGroup
    ramp::Vector{Float32}
end

"""
    VertexArena

The eight SoA arrays of every run of a render VM, in eight buffers
(`Vertex | CopyDst | CopySrc`), sub-allocated in spans of expanded
vertices: `point`, `fill_rgba`, `stroke_rgba`, `stroke_width`,
`joint_angle`, `base_normal`, and the gradient's `grad_uv` and
`grad_uv_base` (12, 16, 16, 4, 4, 12, 8, 8 bytes an element) — the last
two written only for a gradient run and read only by its draw, in the
arena all the same because an instanced draw fetches EVERY per-instance
slot at `first_instance`, and a buffer of the run's own would have to
start `base ÷ 3` instances early (WebGPU validates the bound range: the
draw is refused). A span is a whole number of curves (three
elements each), so a run's `first_instance` is `base ÷ 3`, and a member's
(its own count and cover) `(base + offset) ÷ 3`. `free` holds the
free spans as (offset, length), sorted and coalesced. The eight buffers
are bound ONCE per pass at slots 0–7 (`_bind_arena!`).
"""
mutable struct VertexArena
    capacity::Int                 # elements
    bufs::Vector{WGPUBuffer}
    free::Vector{Tuple{Int,Int}}
    # What a walk gives back is not free until the frame's command
    # buffer is SUBMITTED: a compositor draws several lists into one buffer,
    # and a pass already recorded reads the span it was given and the
    # buffers it was bound to. `pending` are spans freed since the last
    # drain, `retired` the buffers of a growth (their contents copied across
    # on the queue), destroyed at the drain.
    pending::Vector{Tuple{Int,Int}}
    retired::Vector{WGPUBuffer}
end

"""
    GPURenderVM

The renderer's VM: the GPU, the scene target (colour + `depth24plus-stencil8`)
and its multisample twin (the fill's antialiasing, so 4 samples unless 1 is
asked), the layouts and pipelines, the frame ring, the
mobject arena, the vertex arena, the sampler, the texture and ramp caches,
the draw cache, the frame's command list. Built by
`setup_render_vm(gpu, width, height)`, released by `close_render_vm!`.
"""
mutable struct GPURenderVM
    gpu::GPU
    target::GPUTarget
    ms::Union{Nothing,GPUTarget}               # the multisample twin of the target (samples > 1)
    width::Int
    height::Int
    samples::Int                               # EFFECTIVE: 4 where 0 was asked, 1 the aliased control
    layout_frame::WGPUBindGroupLayout
    layout_mob::WGPUBindGroupLayout
    layout_tex::WGPUBindGroupLayout
    pipeline_layout::WGPUPipelineLayout        # groups 0 and 1
    pipeline_layout_tex::WGPUPipelineLayout    # groups 0, 1 and 2 (a texture, a ramp)
    modules::Dict{Symbol,WGPUShaderModule}
    pipelines::Dict{Tuple{Symbol,Bool,Bool,Int,WGPUTextureFormat},WGPURenderPipeline}
    frame_ring::ParamArena{FrameUniforms}      # one frame block per camera the frame draws with
    frame_bg::WGPUBindGroup                    # …bound with a dynamic offset
    arena::UniformArena
    varena::VertexArena
    sampler::WGPUSampler
    tex_cache::Dict{UInt64,GPUTextureEntry}
    ramp_cache::Dict{UInt64,GPURampEntry}      # the gradients' ramps
    cache::GPUDrawCache
    cmds::Vector{DrawCmd}
    ephemeral::Vector{Any}       # records to release after the submit (_DISABLE_DRAW_CACHE)
    pending::Vector{Any}         # buffers and texture/ramp entries to destroy after the submit
    offset_ref::Base.RefValue{UInt32}   # the dynamic offset handed to SetBindGroup, allocation-free
    scratch::Vector{UInt8}       # the RGBA expansion of a blitted frame (grown once, kept)
    staging::WGPUBuffer          # the in-place readback's MapRead buffer (made on first use, kept)
    closed::Bool
end

# ── buffers ─────────────────────────────────────────────────────────────

const _VERTEX_USAGE = WGPUBufferUsage_Vertex | WGPUBufferUsage_CopyDst
const _INDEX_USAGE = WGPUBufferUsage_Index | WGPUBufferUsage_CopyDst
const _RUN_LABEL = "Janim run"
const _MESH_LABEL = "Janim mesh"
const _INDEX_LABEL = "Janim index"

"A new buffer holding `arr` whole."
function _array_buffer(gpu::GPU, arr::AbstractVector, usage, label::String)
    n = _nbytes(arr)
    buf = _gpu_buffer(gpu, n, usage, label)
    GC.@preserve arr _write_buffer!(gpu, buf, 0, pointer(arr), n)
    return buf
end

"Write `arr` into `buf` starting at element `offset_elems`."
function _write_range!(gpu::GPU, buf::WGPUBuffer, arr::AbstractVector, offset_elems::Int)
    GC.@preserve arr _write_buffer!(gpu, buf, offset_elems * sizeof(eltype(arr)), pointer(arr), _nbytes(arr))
end

function _destroy_buffer!(buf::WGPUBuffer)
    buf == C_NULL && return nothing
    wgpuBufferDestroy(buf)
    wgpuBufferRelease(buf)
    return nothing
end

# ── the vertex arena ────────────────────────────────────────────────────

const _ARENA_ELEM = (12, 16, 16, 4, 4, 12, 8, 8)     # sizeof(Point3f), Vec4f, Vec4f, Float32, Float32, Point3f, Vec2f, Vec2f
const _VARENA_LABEL = "Janim vertex arena"
const _VARENA_USAGE = WGPUBufferUsage_Vertex | WGPUBufferUsage_CopyDst | WGPUBufferUsage_CopySrc

function VertexArena(gpu::GPU; capacity::Int = 3 * 4096)
    bufs = WGPUBuffer[_gpu_buffer(gpu, capacity * e, _VARENA_USAGE, _VARENA_LABEL) for e in _ARENA_ELEM]
    return VertexArena(capacity, bufs, [(0, capacity)], Tuple{Int,Int}[], WGPUBuffer[])
end

function _release!(a::VertexArena)
    _drain!(a)
    foreach(_destroy_buffer!, a.bufs)
    empty!(a.bufs)
    return nothing
end

"After a submit: the retired buffers destroyed, the pending spans free."
function _drain!(a::VertexArena)
    foreach(_destroy_buffer!, a.retired)
    empty!(a.retired)
    if !isempty(a.pending)
        append!(a.free, a.pending)
        empty!(a.pending)
        _coalesce!(a)
    end
    return nothing
end

"""
A span of `n` expanded vertices: first fit in the free list, or the arena
grown to hold it — new buffers of at least twice the size, the old contents
copied across on the queue (ordered before the frame that will read them),
the old buffers destroyed (wgpu frees them once the copies are done).
"""
function _alloc!(a::VertexArena, gpu::GPU, n::Int)
    n == 0 && return 0
    for (k, (off, len)) in enumerate(a.free)
        len < n && continue
        if len == n
            deleteat!(a.free, k)
        else
            a.free[k] = (off + n, len - n)
        end
        return off
    end
    old_cap = a.capacity
    new_cap = max(2 * old_cap, old_cap + n)
    new_bufs = WGPUBuffer[_gpu_buffer(gpu, new_cap * e, _VARENA_USAGE, _VARENA_LABEL) for e in _ARENA_ELEM]
    enc = wgpuDeviceCreateCommandEncoder(gpu.device, C_NULL)
    for (k, e) in enumerate(_ARENA_ELEM)
        wgpuCommandEncoderCopyBufferToBuffer(enc, a.bufs[k], UInt64(0), new_bufs[k], UInt64(0),
                                             UInt64(old_cap * e))
    end
    cmd = wgpuCommandEncoderFinish(enc, C_NULL)
    wgpuCommandEncoderRelease(enc)
    _submit!(gpu, cmd)
    append!(a.retired, a.bufs)          # destroyed at the drain: a recorded pass may still read them
    a.bufs = new_bufs
    a.capacity = new_cap
    push!(a.free, (old_cap, new_cap - old_cap))
    _coalesce!(a)
    return _alloc!(a, gpu, n)
end

"Give a span back — free once the frame that may still read it is submitted (`_drain!`)."
function _free!(a::VertexArena, off::Int, n::Int)
    n == 0 && return nothing
    push!(a.pending, (off, n))
    return nothing
end

function _coalesce!(a::VertexArena)
    sort!(a.free; by = first)
    out = Tuple{Int,Int}[]
    for (off, len) in a.free
        if !isempty(out) && out[end][1] + out[end][2] == off
            out[end] = (out[end][1], out[end][2] + len)
        else
            push!(out, (off, len))
        end
    end
    a.free = out
    return nothing
end

"Elements in use: the capacity minus the free spans (the pending ones counted free)."
_arena_used(a::VertexArena) = a.capacity - sum(last, a.free; init = 0) - sum(last, a.pending; init = 0)

# ── the step budget of the instanced stroke ─────────────────────────────

"""
The largest sqrt(area) over the expanded triples of one member, in Float32
and in the shader's own order of operations (0.5 · |cross(p1 − p0, p2 − p0)|).
"""
function _max_sqrt_area(points::AbstractVector{Point3f})
    best = 0f0
    @inbounds for k in 1:3:length(points) - 2
        p0, p1, p2 = points[k], points[k + 1], points[k + 2]
        ax, ay, az = p1[1] - p0[1], p1[2] - p0[2], p1[3] - p0[3]
        bx, by, bz = p2[1] - p0[1], p2[2] - p0[2], p2[3] - p0[3]
        cx, cy, cz = ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx
        area = 0.5f0 * sqrt(cx * cx + cy * cy + cz * cz)
        best = max(best, sqrt(area))
    end
    return best
end

const _MAX_STEPS = 32           # the shader's MAX_STEPS
const _POLYLINE_FACTOR = 100f0  # …and its POLYLINE_FACTOR

"""
S for a run: the largest n_steps its curves can ask for at this frame unit
(`2 + round(100·√area / frame_unit)`, capped at 32), plus one of margin —
so the draw is `6·(S − 1)` vertices per curve, never fewer than the shader
will fill.
"""
function _step_budget(rec::GPURunRecord, frame_unit::Float32)
    s = 0f0
    for a in rec.sqrt_area
        s = max(s, a)
    end
    count = round(Int, _POLYLINE_FACTOR * s / frame_unit)
    return min(2 + count, _MAX_STEPS) + 1
end

# ── mirrors ─────────────────────────────────────────────────────────────

"Compare a mobject's source rows with its mirror once per pass; `gen` bumps on a change."
function _sync_mirror!(cache::GPUDrawCache, m::VMobject)
    mir = get(cache.mirrors, m, nothing)
    if mir === nothing
        mir = GPUVMirror(copy(m.points), copy(m.stroke_rgba), copy(m.fill_rgba),
                         copy(m.stroke_width), 1, _has_fill(m.fill_rgba),
                         _has_stroke(m.stroke_width, m.stroke_rgba), cache.pass,
                         GPURunRecord[])
        cache.mirrors[m] = mir
        return mir
    end
    if mir.last_pass != cache.pass
        mir.last_pass = cache.pass
        if !(_bits_equal(mir.points, m.points) &&
             _bits_equal(mir.stroke_rgba, m.stroke_rgba) &&
             _bits_equal(mir.fill_rgba, m.fill_rgba) &&
             _bits_equal(mir.stroke_width, m.stroke_width))
            _mirror!(mir.points, m.points)
            _mirror!(mir.stroke_rgba, m.stroke_rgba)
            _mirror!(mir.fill_rgba, m.fill_rgba)
            _mirror!(mir.stroke_width, m.stroke_width)
            mir.gen += 1
            mir.has_fill = _has_fill(m.fill_rgba)
            mir.has_stroke = _has_stroke(m.stroke_width, m.stroke_rgba)
        end
    end
    return mir
end

"""
Test hatch: copy `m`'s CURRENT rows into its mirror without uploading
anything. The next pass then finds the rows "unchanged" and draws the stale
span — which is the only way to prove that the comparison is what stands
between an edit and a wrong frame.
"""
function _poison_mirror!(rv::GPURenderVM, m::VMobject)
    mir = rv.cache.mirrors[m]
    _mirror!(mir.points, m.points)
    _mirror!(mir.stroke_rgba, m.stroke_rgba)
    _mirror!(mir.fill_rgba, m.fill_rgba)
    _mirror!(mir.stroke_width, m.stroke_width)
    return mir
end

# ── run records ─────────────────────────────────────────────────────────

"Give the run's span back to the arena."
function _release!(rv::GPURenderVM, rec::GPURunRecord)
    _free!(rv.varena, rec.base, rec.n)
    rec.n = 0
    return nothing
end

"A run's span from scratch, written into the vertex arena."
function _build_record(rv::GPURenderVM, run, grad, gens::Vector{Int})
    datas = [expanded_data(m; grad) for m in run]
    datos = _concat_expanded(datas)
    counts = [d.n for d in datas]
    offsets = similar(counts)
    acc = 0
    for i in eachindex(counts)
        offsets[i] = acc
        acc += counts[i]
    end
    fills = [grad !== nothing || _has_fill(m.fill_rgba) for m in run]
    strokes = [_has_stroke(m.stroke_width, m.stroke_rgba) for m in run]
    sqrt_area = Float32[_max_sqrt_area(d.point) for d in datas]
    gpu = rv.gpu
    a = rv.varena
    base = _alloc!(a, gpu, datos.n)
    arrays = (datos.point, datos.fill_rgba, datos.stroke_rgba, datos.stroke_width,
              datos.joint_angle, datos.base_normal)
    for k in 1:6
        _write_range!(gpu, a.bufs[k], arrays[k], base)
    end
    if grad !== nothing
        _write_range!(gpu, a.bufs[7], datos.grad_uv, base)
        _write_range!(gpu, a.bufs[8], datos.grad_uv_base, base)
    end
    return GPURunRecord(copy(run), grad, datos.n, offsets, counts, copy(gens), fills, strokes,
                        sqrt_area, base, 0)
end

"Re-expand member `i` and upload its range of every array, into the run's span."
function _upload_member!(rv::GPURenderVM, rec::GPURunRecord, i::Int, d)
    off = rec.base + rec.offsets[i]
    gpu = rv.gpu
    a = rv.varena
    _write_range!(gpu, a.bufs[1], d.point, off)
    _write_range!(gpu, a.bufs[2], d.fill_rgba, off)
    _write_range!(gpu, a.bufs[3], d.stroke_rgba, off)
    _write_range!(gpu, a.bufs[4], d.stroke_width, off)
    _write_range!(gpu, a.bufs[5], d.joint_angle, off)
    _write_range!(gpu, a.bufs[6], d.base_normal, off)
    if rec.grad !== nothing
        _write_range!(gpu, a.bufs[7], d.grad_uv, off)
        _write_range!(gpu, a.bufs[8], d.grad_uv_base, off)
    end
    rec.sqrt_area[i] = _max_sqrt_area(d.point)
    return nothing
end

"The record of this run, brought up to date."
function _run_record!(rv::GPURenderVM, run::Vector{VMobject}, grad)
    cache = rv.cache
    if _DISABLE_DRAW_CACHE[]
        return _build_record(rv, run, grad, zeros(Int, length(run)))
    end
    head = _sync_mirror!(cache, run[1])
    rec = nothing
    for r in head.runs
        if _same_members(r.members, run)
            rec = r
            break
        end
    end
    rebuild = rec === nothing || rec.grad !== grad
    if !rebuild
        for (i, m) in enumerate(run)
            if rec.counts[i] != 3 * get_num_curves(m)
                rebuild = true
                break
            end
        end
    end
    if rebuild
        gens = [_sync_mirror!(cache, m).gen for m in run]
        if rec === nothing
            rec = _build_record(rv, run, grad, gens)
            push!(head.runs, rec)
        else
            _release!(rv, rec)
            slot = findfirst(r -> r === rec, head.runs)
            rec = _build_record(rv, run, grad, gens)
            head.runs[slot] = rec
        end
    else
        for (i, m) in enumerate(run)
            mir = _sync_mirror!(cache, m)
            if rec.gens[i] != mir.gen
                _upload_member!(rv, rec, i, expanded_data(m; grad))
                rec.gens[i] = mir.gen
                rec.fills[i] = grad !== nothing || mir.has_fill
                rec.strokes[i] = mir.has_stroke
            end
        end
    end
    rec.last_pass = cache.pass
    return rec::GPURunRecord
end

# ── mesh records ────────────────────────────────────────────────────────

function _release!(rv::GPURenderVM, rec::GPUMeshRecord)
    append!(rv.pending, rec.bufs)       # destroyed after the submit
    empty!(rec.bufs)
    rec.index == C_NULL || push!(rv.pending, rec.index)
    rec.index = WGPUBuffer(C_NULL)
    return nothing
end

"""
After a submit: destroy the buffers a walk retired, release the
texture and ramp entries it evicted, free the arena spans it gave back.
wgpu keeps a destroyed resource alive until the GPU is done with the
submissions that use it, so nothing here waits.
"""
function _drain_pending!(rv::GPURenderVM)
    for x in rv.pending
        if x isa WGPUBuffer
            _destroy_buffer!(x)
        elseif x isa GPUTextureEntry
            _release_texture!(x)
        elseif x isa GPURampEntry
            _release_ramp!(x)
        else
            error("_drain_pending!: unknown pending object $(typeof(x))")
        end
    end
    empty!(rv.pending)
    _drain!(rv.varena)
    return nothing
end

"""
The persistent buffers of a mesh or a cloud, keyed by the mobject: one buffer per array, an index buffer when `indices` is
given, each array compared bit for bit with its mirror and re-uploaded
WHOLE when it differs — into the same buffer when it still fits, into a new
one when it grew. With `_DISABLE_DRAW_CACHE` a fresh record, released after
the frame.
"""
function _mesh_record!(rv::GPURenderVM, key::Mobject, slots, indices::Union{Nothing,Vector{Int32}})
    cache = rv.cache
    gpu = rv.gpu
    rec = _DISABLE_DRAW_CACHE[] ? nothing : get(cache.meshes, key, nothing)
    count = indices === nothing ? length(slots[1][2]) : length(indices)
    if rec === nothing
        bufs = WGPUBuffer[]
        sizes = Int[]
        mirrors = Vector[]
        for (loc, arr, ncomp) in slots
            push!(bufs, _array_buffer(gpu, arr, _VERTEX_USAGE, _MESH_LABEL))
            push!(sizes, max(_nbytes(arr), 4))
            push!(mirrors, copy(arr))
        end
        index = WGPUBuffer(C_NULL)
        isize = 0
        imirror = Int32[]
        if indices !== nothing
            index = _array_buffer(gpu, indices, _INDEX_USAGE, _INDEX_LABEL)
            isize = max(_nbytes(indices), 4)
            imirror = copy(indices)
        end
        rec = GPUMeshRecord(bufs, sizes, mirrors, index, isize, imirror, count, cache.pass)
        _DISABLE_DRAW_CACHE[] || (cache.meshes[key] = rec)
        return rec
    end
    for (k, (loc, arr, ncomp)) in enumerate(slots)
        mir = rec.mirrors[k]
        _bits_equal(mir, arr) && continue
        n = _nbytes(arr)
        if n > rec.sizes[k]
            push!(rv.pending, rec.bufs[k])
            rec.bufs[k] = _array_buffer(gpu, arr, _VERTEX_USAGE, _MESH_LABEL)
            rec.sizes[k] = max(n, 4)
        else
            GC.@preserve arr _write_buffer!(gpu, rec.bufs[k], 0, pointer(arr), n)
        end
        if mir isa Vector{eltype(arr)}
            _mirror!(mir, arr)
        else
            rec.mirrors[k] = copy(arr)
        end
    end
    if indices !== nothing && !_bits_equal(rec.index_mirror, indices)
        n = _nbytes(indices)
        if n > rec.index_size
            push!(rv.pending, rec.index)
            rec.index = _array_buffer(gpu, indices, _INDEX_USAGE, _INDEX_LABEL)
            rec.index_size = max(n, 4)
        else
            GC.@preserve indices _write_buffer!(gpu, rec.index, 0, pointer(indices), n)
        end
        _mirror!(rec.index_mirror, indices)
    end
    rec.count = count
    rec.last_pass = cache.pass
    return rec
end

"Every 64 passes: release what no pass drew in the last 8 (the keys pin the mobjects)."
function _sweep_cache!(rv::GPURenderVM)
    cache = rv.cache
    limit = cache.pass - _KEEP_PASSES
    filter!(cache.mirrors) do kv
        mir = kv.second
        if mir.last_pass < limit
            for r in mir.runs
                _release!(rv, r)
            end
            return false
        end
        filter!(mir.runs) do r
            keep = r.last_pass >= limit
            keep || _release!(rv, r)
            keep
        end
        return true
    end
    filter!(cache.meshes) do kv
        keep = kv.second.last_pass >= limit
        keep || _release!(rv, kv.second)
        keep
    end
    return nothing
end

# ── textures ────────────────────────────────────────────────────────────

const _TEXTURE_LABEL = "Janim texture"
const _TEXTURE_BG_LABEL = "Janim texture bind group"

"""
Upload (or fetch) the texture for this pixel array and its bind group
(group 2: the view and the shared sampler). Keyed by the array's identity
with the array pinned — textures.jl's convention — and emptied whole at 64
entries. The rows go up as they are (4×w×h, row 1 on top): that is
`wgpuQueueWriteTexture`'s layout with v = 0 at the top, so a uv reads the
texel ManimGL's would.
"""
function _ensure_texture!(rv::GPURenderVM, pixels::Array{UInt8,3})
    key = objectid(pixels)
    entry = get(rv.tex_cache, key, nothing)
    entry !== nothing && return entry.bind_group
    if length(rv.tex_cache) >= 64                     # session bound (textures.jl)
        for e in values(rv.tex_cache)
            push!(rv.pending, e)                      # released after the submit
        end
        empty!(rv.tex_cache)
    end
    gpu = rv.gpu
    w, h = size(pixels, 2), size(pixels, 3)
    tex = _create_texture(gpu, w, h, WGPUTextureFormat_RGBA8Unorm,
                          WGPUTextureUsage_TextureBinding | WGPUTextureUsage_CopyDst, _TEXTURE_LABEL)
    _GPU_OBJECTS[] += 1
    dst = Ref(WGPUTexelCopyTextureInfo(tex, 0, WGPUOrigin3D(0, 0, 0), WGPUTextureAspect_All))
    layout = Ref(WGPUTexelCopyBufferLayout(0, UInt32(4w), UInt32(h)))
    ext = Ref(WGPUExtent3D(UInt32(w), UInt32(h), 1))
    GC.@preserve pixels dst layout ext wgpuQueueWriteTexture(gpu.queue, dst, pointer(pixels),
                                                            Csize_t(sizeof(pixels)), layout, ext)
    _GPU_UPLOAD_BYTES[] += sizeof(pixels)
    _GPU_UPLOAD_CALLS[] += 1
    view = wgpuTextureCreateView(tex, C_NULL)
    entries = [WGPUBindGroupEntry(C_NULL, 0, WGPUBuffer(C_NULL), 0, 0, WGPUSampler(C_NULL), view),
               WGPUBindGroupEntry(C_NULL, 1, WGPUBuffer(C_NULL), 0, 0, rv.sampler, WGPUTextureView(C_NULL))]
    bg = _bind_group(gpu, rv.layout_tex, entries, _TEXTURE_BG_LABEL)
    rv.tex_cache[key] = GPUTextureEntry(tex, view, bg, pixels)
    return bg
end

function _release_texture!(e::GPUTextureEntry)
    wgpuBindGroupRelease(e.bind_group)
    wgpuTextureViewRelease(e.view)
    wgpuTextureDestroy(e.texture)
    wgpuTextureRelease(e.texture)
    return nothing
end

const _RAMP_LABEL = "Janim ramp"
const _RAMP_BG_LABEL = "Janim ramp bind group"

"""
Upload (or fetch) the 1D ramp texture of a FillGradient and its bind group
(group 2, the texture layout: LINEAR, `float32-filterable`), keyed by the
ramp vector's identity with the vector pinned, `rgba32float` because the
stops were computed in Float64; emptied whole at 64 entries.
"""
function _ensure_ramp!(rv::GPURenderVM, ramp::Vector{Float32})
    key = objectid(ramp)
    entry = get(rv.ramp_cache, key, nothing)
    entry !== nothing && return entry.bind_group
    if length(rv.ramp_cache) >= 64                    # session bound (textures.jl)
        for e in values(rv.ramp_cache)
            push!(rv.pending, e)                      # released after the submit
        end
        empty!(rv.ramp_cache)
    end
    length(ramp) == 4 * RAMP_RESOLUTION ||
        throw(ArgumentError("a ramp has 4·$(RAMP_RESOLUTION) floats, got $(length(ramp))"))
    gpu = rv.gpu
    tex = _create_texture(gpu, RAMP_RESOLUTION, 1, WGPUTextureFormat_RGBA32Float,
                          WGPUTextureUsage_TextureBinding | WGPUTextureUsage_CopyDst, _RAMP_LABEL)
    _GPU_OBJECTS[] += 1
    dst = Ref(WGPUTexelCopyTextureInfo(tex, 0, WGPUOrigin3D(0, 0, 0), WGPUTextureAspect_All))
    layout = Ref(WGPUTexelCopyBufferLayout(0, UInt32(16 * RAMP_RESOLUTION), UInt32(1)))
    ext = Ref(WGPUExtent3D(UInt32(RAMP_RESOLUTION), 1, 1))
    GC.@preserve ramp dst layout ext wgpuQueueWriteTexture(gpu.queue, dst, pointer(ramp),
                                                          Csize_t(sizeof(ramp)), layout, ext)
    _GPU_UPLOAD_BYTES[] += sizeof(ramp)
    _GPU_UPLOAD_CALLS[] += 1
    view = wgpuTextureCreateView(tex, C_NULL)
    entries = [WGPUBindGroupEntry(C_NULL, 0, WGPUBuffer(C_NULL), 0, 0, WGPUSampler(C_NULL), view),
               WGPUBindGroupEntry(C_NULL, 1, WGPUBuffer(C_NULL), 0, 0, rv.sampler, WGPUTextureView(C_NULL))]
    bg = _bind_group(gpu, rv.layout_tex, entries, _RAMP_BG_LABEL)
    rv.ramp_cache[key] = GPURampEntry(tex, view, bg, ramp)
    return bg
end

function _release_ramp!(e::GPURampEntry)
    wgpuBindGroupRelease(e.bind_group)
    wgpuTextureViewRelease(e.view)
    wgpuTextureDestroy(e.texture)
    wgpuTextureRelease(e.texture)
    return nothing
end
