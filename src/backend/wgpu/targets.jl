# backend/wgpu/targets.jl — render targets and the synchronous readback.
#
# Two facts shape this file:
#
#   · WebGPU has no RGB8 texture. Colour is `rgba8unorm`, so a readback is
#     always four channels; the alpha is dropped by whoever wants three
#     (on the encoder's thread, never on the render thread).
#   · `copyTextureToBuffer` wants `bytesPerRow` to be a multiple of 256. At
#     four bytes per pixel that is true of 640, 1280, 1920, 2560 and 3840,
#     and FALSE of 854 (3416 B → 13.34 rows of 256): the default of
#     `render_frame` and the `-ql` preset — the path a user exercises most —
#     is the one that pays the padding. The staging buffer is padded, and
#     the copy into RAM crops each row (`_crop_rows!`).
#
# Orientation: WebGPU's texture rows run top to bottom, so what comes out of
# the copy is already the top-down frame the encoder and the PNG want, so no
# vertical flip is needed on the way out.

"""
    GPUTarget

An `rgba8unorm` texture that can be rendered into and copied out of, with its
view; optionally a `depth24plus-stencil8` companion (the scene's z-buffer
and the fill's count). Created by [`create_target`](@ref), released by
[`close_target!`](@ref).
"""
mutable struct GPUTarget
    texture::WGPUTexture
    view::WGPUTextureView
    depth::WGPUTexture
    depth_view::WGPUTextureView
    width::Int
    height::Int
    closed::Bool
end

const _TARGET_LABEL = "Janim target"
const _DEPTH_LABEL = "Janim depth"

"Bytes per padded row of an RGBA8 texture `width` pixels wide."
padded_bytes_per_row(width::Int) = cld(4 * width, 256) * 256

function _create_texture(gpu::GPU, width::Int, height::Int, format, usage, label::String;
                         samples::Int = 1)
    desc = Ref(WGPUTextureDescriptor(
        C_NULL, WGPUStringView(pointer(label), sizeof(label)), usage,
        WGPUTextureDimension_2D, WGPUExtent3D(UInt32(width), UInt32(height), 1),
        format, 1, UInt32(samples), 0, C_NULL))
    tex = GC.@preserve desc _error_scope(gpu) do
        wgpuDeviceCreateTexture(gpu.device, desc)
    end
    tex == C_NULL && throw(GPUValidationError("wgpuDeviceCreateTexture returned NULL for $(width)×$(height) $label"))
    return tex
end

"""
    create_target(gpu, width, height; depth = false, samples = 1, format = rgba8unorm) → GPUTarget

A colour target of `width × height` (RenderAttachment + CopySrc +
TextureBinding + CopyDst: the preview samples it and the live loop writes
into it), and a depth-stencil texture beside it when asked
(`depth24plus-stencil8`, the fill's count in the stencil aspect).
`samples > 1` makes the MULTISAMPLE twin — colour and depth at that sample count, render
attachments only (a multisampled texture cannot be copied out or sampled;
its one exit is the `resolveTarget` of its last pass). `format` is the
compositor's `rgba16float` for a layer's twin.
"""
function create_target(gpu::GPU, width::Int, height::Int; depth::Bool = false,
                       samples::Int = 1, format = WGPUTextureFormat_RGBA8Unorm)
    (width > 0 && height > 0) || throw(ArgumentError("a target needs a positive size, got $(width)×$(height)"))
    samples >= 1 || throw(ArgumentError("a target needs samples ≥ 1, got $samples"))
    # A single-sample target is also sampled by the preview's present
    # pass (TextureBinding) and written by the live loop's blit and strip
    # (CopyDst); usage does not touch rasterisation
    usage = samples == 1 ? WGPUTextureUsage_RenderAttachment | WGPUTextureUsage_CopySrc |
                           WGPUTextureUsage_TextureBinding | WGPUTextureUsage_CopyDst :
                           WGPUTextureUsage_RenderAttachment
    tex = _create_texture(gpu, width, height, format, usage, _TARGET_LABEL; samples)
    view = wgpuTextureCreateView(tex, C_NULL)
    dtex, dview = WGPUTexture(C_NULL), WGPUTextureView(C_NULL)
    if depth
        # `depth24plus-stencil8` — the fill's count lives in the stencil aspect
        dtex = _create_texture(gpu, width, height, _DS_FORMAT,
                               WGPUTextureUsage_RenderAttachment, _DEPTH_LABEL; samples)
        dview = wgpuTextureCreateView(dtex, C_NULL)
    end
    t = GPUTarget(tex, view, dtex, dview, width, height, false)
    finalizer(close_target!, t)
    return t
end

"""
Release the views and textures. Idempotent; also the finalizer — and the
ONLY finalizer that releases them: the VM's and the compositor's finalizers
leave their targets to this one, because a target can outlive its owner in a
caller's hands (see `_finalize_render_vm!`).
"""
function close_target!(t::GPUTarget)
    t.closed && return nothing
    t.closed = true
    wgpuTextureViewRelease(t.view)
    wgpuTextureRelease(t.texture)
    if t.depth != C_NULL
        wgpuTextureViewRelease(t.depth_view)
        wgpuTextureRelease(t.depth)
    end
    return nothing
end

"""
    _check_open(t::GPUTarget, what)

The guard: a closed target never reaches wgpu. Its handles are released,
and wgpu-core answers a released handle not with an error but with a panic
that aborts the process (`Texture[Id(4,1)] does not exist`) — so the check
is ours, before any ccall, and what a caller gets is a `GPUValidationError` that names it.
"""
function _check_open(t::GPUTarget, what::AbstractString)
    t.closed && throw(GPUValidationError("the target was closed before $what: a released texture must not reach wgpu"))
    return nothing
end

# ── staging buffers and the copy ────────────────────────────────────────

const _STAGING_LABEL = "Janim readback"

"A MapRead + CopyDst buffer of `nbytes`."
function _create_staging(gpu::GPU, nbytes::Int)
    desc = Ref(WGPUBufferDescriptor(
        C_NULL, WGPUStringView(pointer(_STAGING_LABEL), sizeof(_STAGING_LABEL)),
        WGPUBufferUsage_MapRead | WGPUBufferUsage_CopyDst, UInt64(nbytes), 0))
    buf = GC.@preserve desc wgpuDeviceCreateBuffer(gpu.device, desc)
    buf == C_NULL && throw(GPUValidationError("wgpuDeviceCreateBuffer returned NULL for a $nbytes-byte readback buffer"))
    return buf
end

"""
Record and submit «copy the target into `staging`» (rows padded to 256 B).
Returns the submission index, which `_wait_gpu!` can wait on alone.
"""
function _copy_target_to_buffer!(gpu::GPU, t::GPUTarget, staging::WGPUBuffer)
    _check_open(t, "its readback")
    bpr = padded_bytes_per_row(t.width)
    enc = wgpuDeviceCreateCommandEncoder(gpu.device, C_NULL)
    src = Ref(WGPUTexelCopyTextureInfo(t.texture, 0, WGPUOrigin3D(0, 0, 0), WGPUTextureAspect_All))
    dst = Ref(WGPUTexelCopyBufferInfo(
        WGPUTexelCopyBufferLayout(0, UInt32(bpr), UInt32(t.height)), staging))
    ext = Ref(WGPUExtent3D(UInt32(t.width), UInt32(t.height), 1))
    GC.@preserve src dst ext wgpuCommandEncoderCopyTextureToBuffer(enc, src, dst, ext)
    cmd = wgpuCommandEncoderFinish(enc, C_NULL)
    wgpuCommandEncoderRelease(enc)
    return _submit!(gpu, cmd)
end

# The map callback's reply. One render thread, one map in flight at a time
# (the pipeline maps one buffer per frame, synchronously): a single mailbox.
const _MAP_REPLY = _Reply()

function _on_map(status::WGPUMapAsyncStatus, message::WGPUStringView, ud1::Ptr{Cvoid}, ::Ptr{Cvoid})
    _reply_post!(unsafe_pointer_to_objref(ud1)::_Reply, status, C_NULL, message)
    return nothing
end

"""
Map `staging` for reading once the submission `index` is done, hand its
bytes to `f(ptr)`, and unmap. The wait is `wgpuDevicePoll` on that index —
so the GPU keeps working on whatever was submitted AFTER it.
"""
function _with_mapped(f, gpu::GPU, staging::WGPUBuffer, nbytes::Int, index::UInt64)
    reply = _MAP_REPLY
    reply.fired = false
    cbi = WGPUBufferMapCallbackInfo(C_NULL, WGPUCallbackMode_AllowProcessEvents,
        @cfunction(_on_map, Cvoid, (WGPUMapAsyncStatus, WGPUStringView, Ptr{Cvoid}, Ptr{Cvoid})),
        pointer_from_objref(reply), C_NULL)
    wgpuBufferMapAsync(staging, WGPUMapMode_Read, 0, nbytes, cbi)
    _wait_gpu!(gpu, index)
    reply.fired || _wait_gpu!(gpu, nothing)      # the index alone was not enough: everything
    _check_gpu_errors!(gpu)
    reply.fired || error("the map callback never fired after wgpuDevicePoll(wait)")
    reply.status == WGPUMapAsyncStatus_Success ||
        throw(GPUValidationError("wgpuBufferMapAsync failed (status $(reply.status)): $(_reply_message(reply))"))
    ptr = Ptr{UInt8}(wgpuBufferGetConstMappedRange(staging, 0, nbytes))
    ptr == C_NULL && throw(GPUValidationError("wgpuBufferGetConstMappedRange returned NULL"))
    try
        return f(ptr)
    finally
        wgpuBufferUnmap(staging)
    end
end

# ── row cropping: padded RGBA rows → the frame the caller wants ─────────

"`W×H` RGBA pixels with padded rows at `src` → tight RGBA into `dest` (4·W·H bytes)."
function _crop_rows!(dest::Vector{UInt8}, src::Ptr{UInt8}, W::Int, H::Int, bpr::Int)
    @assert length(dest) >= 4 * W * H
    row = 4 * W
    p = pointer(dest)
    @inbounds for y in 0:H-1
        unsafe_copyto!(p + y * row, src + y * bpr, row)
    end
    return dest
end

"""
`W×H` RGBA pixels with padded rows at `src` → tight RGB into `dest`
(3·W·H bytes), dropping the alpha. The opaque route's 4 → 3, written
for the encoder's thread — the render thread never runs it.
"""
function _crop_rows_rgb!(dest::Vector{UInt8}, src::Ptr{UInt8}, W::Int, H::Int, bpr::Int)
    @assert length(dest) >= 3 * W * H
    k = 1
    @inbounds for y in 0:H-1
        s = src + y * bpr
        for x in 0:W-1
            dest[k]   = unsafe_load(s, 4x + 1)
            dest[k+1] = unsafe_load(s, 4x + 2)
            dest[k+2] = unsafe_load(s, 4x + 3)
            k += 3
        end
    end
    return dest
end

# ── the synchronous readback ────────────────────────────────────────────

"""
    read_rgba_topdown(gpu, target) → Array{UInt8,3}  (4 × W × H)

Copy the target into a fresh staging buffer, wait for THAT copy, crop the
padded rows, release the buffer. Top-down by construction; premultiplied,
as the compositor produces it (`save_png` un-premultiplies). This is the
readback of `render_frame`; the mp4 path uses the one-frame-behind
[`FramePipeline`](@ref) instead.
"""
function read_rgba_topdown(gpu::GPU, t::GPUTarget)
    bpr = padded_bytes_per_row(t.width)
    nbytes = bpr * t.height
    staging = _create_staging(gpu, nbytes)
    img = Array{UInt8}(undef, 4, t.width, t.height)
    try
        index = _copy_target_to_buffer!(gpu, t, staging)
        _with_mapped(gpu, staging, nbytes, index) do ptr
            _crop_rows!(vec(img), ptr, t.width, t.height, bpr)
        end
    finally
        wgpuBufferDestroy(staging)
        wgpuBufferRelease(staging)
    end
    return img
end

"""
    read_rgb_topdown!(gpu, target, staging, img) → img

The in-place readback: the target into `staging`
(a MapRead buffer of the target's padded size the CALLER keeps — the live
loop's VM holds one, so a tick creates no GPU buffer), cropped RGB into
`img` (3 × W × H, a recycled cache slot). The frame loop's readback.
"""
function read_rgb_topdown!(gpu::GPU, t::GPUTarget, staging::WGPUBuffer, img::Array{UInt8,3})
    size(img) == (3, t.width, t.height) || throw(ArgumentError("a $(t.width)×$(t.height) target cannot be read into a $(size(img)) array"))
    bpr = padded_bytes_per_row(t.width)
    nbytes = bpr * t.height
    index = _copy_target_to_buffer!(gpu, t, staging)
    _with_mapped(gpu, staging, nbytes, index) do ptr
        _crop_rows_rgb!(vec(img), ptr, t.width, t.height, bpr)
    end
    return img
end

"""
    read_rgb_topdown(gpu, target) → Array{UInt8,3}  (3 × W × H)

The same readback, alpha dropped on this thread — for the one-off paths
(`render_frame`, stills), never for the frame loop.
"""
function read_rgb_topdown(gpu::GPU, t::GPUTarget)
    bpr = padded_bytes_per_row(t.width)
    nbytes = bpr * t.height
    staging = _create_staging(gpu, nbytes)
    img = Array{UInt8}(undef, 3, t.width, t.height)
    try
        index = _copy_target_to_buffer!(gpu, t, staging)
        _with_mapped(gpu, staging, nbytes, index) do ptr
            _crop_rows_rgb!(vec(img), ptr, t.width, t.height, bpr)
        end
    finally
        wgpuBufferDestroy(staging)
        wgpuBufferRelease(staging)
    end
    return img
end
