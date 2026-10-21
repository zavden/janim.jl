# backend/wgpu/uniforms.jl — the two uniform blocks and the arena the mobject
# blocks live in.
#
# A uniform is a BUFFER with a layout, and the shader reads a struct out of
# it. Two blocks, as `shaders/inserts/uniforms.wgsl` declares them:
#
#   FrameUniforms   112 B · group 0 · one buffer, written once per pass —
#                   the six camera fields of `camera_uniforms`.
#   MobjectUniforms  64 B · group 1 · ONE block per run, in an arena with
#                   dynamic offsets: what the stroke, the fill, the dots and
#                   the textures read, in one layout and one bind group for
#                   the whole zoo. `z_pass` is not here: it is a constant of
#                   the PASS, compiled into the stroke module (pipelines.jl).
#
# The Julia structs are isbits with WGSL's layout written out — a vec3
# followed by the f32 that fits beside it — so that an `unsafe_store!` of the
# struct IS the upload. The two sizes and every field offset must match the
# WGSL block's (`FRAME_UNIFORMS_OFFSETS`, `MOBJECT_UNIFORMS_OFFSETS`).
#
# The arena holds one block per RUN, not per mobject: Janim's colour is a
# row per point, so a whole run shares its block (`_draw_run!` takes it from
# `run[1]`). Its slot stride is the block rounded up to the device's
# `minUniformBufferOffsetAlignment` — 32 on common adapters, 256 at the
# spec's maximum: read from the device, never assumed.
# The blocks of a frame are staged in a CPU buffer as the draw list is
# walked and go up in ONE `wgpuQueueWriteBuffer` before the frame's command
# buffer is submitted (the queue orders a write before the submits that
# follow it); the arena grows between the walk and the pass when a frame
# needs more slots than it has.

"""
The frame's block (group 0): `camera_uniforms`' six camera fields, in the
order and at the offsets of `FrameUniforms` in `inserts/uniforms.wgsl`.
"""
struct FrameUniforms
    view::NTuple{16,Float32}            # column-major, ManimGL's view.T.flatten()
    frame_rescale_factors::NTuple{3,Float32}
    frame_scale::Float32
    camera_position::NTuple{3,Float32}
    pixel_size::Float32
    light_position::NTuple{3,Float32}
    _pad::Float32
end

"""
The mobject's block (group 1): every field a pass reads, the
unused ones at their inert value. One per run.
"""
struct MobjectUniforms
    shading::NTuple{3,Float32}
    is_fixed_in_frame::Float32
    anti_alias_width::Float32
    joint_type::Float32
    flat_stroke::Float32
    stroke_width_in_scene_units::Float32
    grad_focus::NTuple{3,Float32}       # the gradient's fields
    grad_kind::Float32
    spread_mode::Float32
    grad_opacity::Float32
    glow_factor::Float32                # DotCloud
    opacity::Float32                    # ImageMobject / TexturedSurface
end

const FRAME_UNIFORMS_BYTES = 112
const MOBJECT_UNIFORMS_BYTES = 64

"The byte offset WGSL gives each field of `FrameUniforms` (vec3 aligned to 16, f32 to 4)."
const FRAME_UNIFORMS_OFFSETS = (view = 0, frame_rescale_factors = 64, frame_scale = 76,
                                camera_position = 80, pixel_size = 92,
                                light_position = 96, _pad = 108)
"…and of `MobjectUniforms`."
const MOBJECT_UNIFORMS_OFFSETS = (shading = 0, is_fixed_in_frame = 12, anti_alias_width = 16,
                                  joint_type = 20, flat_stroke = 24,
                                  stroke_width_in_scene_units = 28, grad_focus = 32,
                                  grad_kind = 44, spread_mode = 48, grad_opacity = 52,
                                  glow_factor = 56, opacity = 60)

"The frame's block from `camera_uniforms(cam; flip_y = false)`'s NamedTuple."
function FrameUniforms(cam_u::NamedTuple)
    v = cam_u.view::Matrix{Float32}
    return FrameUniforms(NTuple{16,Float32}(vec(v)), cam_u.frame_rescale_factors,
                         cam_u.frame_scale, cam_u.camera_position, cam_u.pixel_size,
                         cam_u.light_position, 0f0)
end

_f3(t) = (Float32(t[1]), Float32(t[2]), Float32(t[3]))

"""
    MobjectUniforms(; shading, is_fixed_in_frame, anti_alias_width, joint_type,
                      flat_stroke, stroke_width_in_scene_units, grad_focus,
                      grad_kind, spread_mode, grad_opacity, glow_factor, opacity)

A block with every field named; the ones a pass does not read stay at the
value that makes them inert (a zero shading, opacity 1, no glow).
"""
function MobjectUniforms(; shading = (0f0, 0f0, 0f0), is_fixed_in_frame = 0f0,
                         anti_alias_width = 1.5f0, joint_type = 1f0, flat_stroke = 0f0,
                         stroke_width_in_scene_units = 0f0, grad_focus = (0f0, 0f0, 0f0),
                         grad_kind = 0f0, spread_mode = 0f0, grad_opacity = 1f0,
                         glow_factor = 0f0, opacity = 1f0)
    return MobjectUniforms(_f3(shading), Float32(is_fixed_in_frame), Float32(anti_alias_width),
                           Float32(joint_type), Float32(flat_stroke),
                           Float32(stroke_width_in_scene_units), _f3(grad_focus),
                           Float32(grad_kind), Float32(spread_mode), Float32(grad_opacity),
                           Float32(glow_factor), Float32(opacity))
end

# ── the objects around them ─────────────────────────────────────────────

const _GPU_OBJECTS = Ref(0)         # buffers, textures, samplers, bind groups, layouts and pipelines the backend creates
const _GPU_UPLOAD_BYTES = Ref(0)    # bytes through wgpuQueueWriteBuffer / wgpuQueueWriteTexture
const _GPU_UPLOAD_CALLS = Ref(0)    # how many of those calls

_sv(s::String) = WGPUStringView(pointer(s), sizeof(s))

"A buffer of `nbytes` with `usage`, created in an error scope and counted."
function _gpu_buffer(gpu::GPU, nbytes::Integer, usage, label::String)
    n = max(Int(nbytes), 4)
    desc = Ref(WGPUBufferDescriptor(C_NULL, _sv(label), usage, UInt64(n), 0))
    buf = GC.@preserve label desc _error_scope(gpu) do
        wgpuDeviceCreateBuffer(gpu.device, desc)
    end
    buf == C_NULL && throw(GPUValidationError("wgpuDeviceCreateBuffer returned NULL for $n bytes ($label)"))
    _GPU_OBJECTS[] += 1
    return buf
end

"Write `nbytes` at `ptr` into `buf` at `offset` through the queue, counted."
function _write_buffer!(gpu::GPU, buf::WGPUBuffer, offset::Integer, ptr::Ptr, nbytes::Integer)
    nbytes == 0 && return 0
    wgpuQueueWriteBuffer(gpu.queue, buf, UInt64(offset), Ptr{Cvoid}(ptr), Csize_t(nbytes))
    _GPU_UPLOAD_BYTES[] += Int(nbytes)
    _GPU_UPLOAD_CALLS[] += 1
    return Int(nbytes)
end

"""
The bind group layout of one uniform block at binding 0, visible to both
stages; `dynamic` gives it a dynamic offset (the mobject arena).
"""
function _uniform_layout(gpu::GPU, nbytes::Int, label::String; dynamic::Bool)
    entries = [WGPUBindGroupLayoutEntry(
        C_NULL, 0, WGPUShaderStage_Vertex | WGPUShaderStage_Fragment,
        WGPUBufferBindingLayout(C_NULL, WGPUBufferBindingType_Uniform, WGPUBool(dynamic), UInt64(nbytes)),
        WGPUSamplerBindingLayout(C_NULL, WGPUSamplerBindingType_BindingNotUsed),
        WGPUTextureBindingLayout(C_NULL, WGPUTextureSampleType_BindingNotUsed,
                                 WGPUTextureViewDimension_Undefined, 0),
        WGPUStorageTextureBindingLayout(C_NULL, WGPUStorageTextureAccess_BindingNotUsed,
                                        WGPUTextureFormat_Undefined, WGPUTextureViewDimension_Undefined))]
    return _bind_group_layout(gpu, entries, label)
end

"The layout of group 2: a filterable 2D texture at binding 0, a filtering sampler at binding 1."
function _texture_layout(gpu::GPU, label::String)
    none_buf = WGPUBufferBindingLayout(C_NULL, WGPUBufferBindingType_BindingNotUsed, 0, 0)
    none_sam = WGPUSamplerBindingLayout(C_NULL, WGPUSamplerBindingType_BindingNotUsed)
    none_tex = WGPUTextureBindingLayout(C_NULL, WGPUTextureSampleType_BindingNotUsed,
                                        WGPUTextureViewDimension_Undefined, 0)
    none_st = WGPUStorageTextureBindingLayout(C_NULL, WGPUStorageTextureAccess_BindingNotUsed,
                                              WGPUTextureFormat_Undefined, WGPUTextureViewDimension_Undefined)
    entries = [
        WGPUBindGroupLayoutEntry(C_NULL, 0, WGPUShaderStage_Fragment, none_buf, none_sam,
            WGPUTextureBindingLayout(C_NULL, WGPUTextureSampleType_Float, WGPUTextureViewDimension_2D, 0),
            none_st),
        WGPUBindGroupLayoutEntry(C_NULL, 1, WGPUShaderStage_Fragment, none_buf,
            WGPUSamplerBindingLayout(C_NULL, WGPUSamplerBindingType_Filtering), none_tex, none_st)]
    return _bind_group_layout(gpu, entries, label)
end

function _bind_group_layout(gpu::GPU, entries::Vector{WGPUBindGroupLayoutEntry}, label::String)
    desc = Ref(WGPUBindGroupLayoutDescriptor(C_NULL, _sv(label), length(entries), pointer(entries)))
    bgl = GC.@preserve label entries desc _error_scope(gpu) do
        wgpuDeviceCreateBindGroupLayout(gpu.device, desc)
    end
    bgl == C_NULL && throw(GPUValidationError("wgpuDeviceCreateBindGroupLayout returned NULL ($label)"))
    _GPU_OBJECTS[] += 1
    return bgl
end

"A bind group over `layout` with these entries, in an error scope, counted."
function _bind_group(gpu::GPU, layout::WGPUBindGroupLayout, entries::Vector{WGPUBindGroupEntry}, label::String)
    desc = Ref(WGPUBindGroupDescriptor(C_NULL, _sv(label), layout, length(entries), pointer(entries)))
    bg = GC.@preserve label entries desc _error_scope(gpu) do
        wgpuDeviceCreateBindGroup(gpu.device, desc)
    end
    bg == C_NULL && throw(GPUValidationError("wgpuDeviceCreateBindGroup returned NULL ($label)"))
    _GPU_OBJECTS[] += 1
    return bg
end

"A pipeline layout over these bind group layouts (groups 0, 1[, 2])."
function _pipeline_layout(gpu::GPU, layouts::Vector{WGPUBindGroupLayout}, label::String)
    desc = Ref(WGPUPipelineLayoutDescriptor(C_NULL, _sv(label), length(layouts), pointer(layouts)))
    pl = GC.@preserve label layouts desc _error_scope(gpu) do
        wgpuDeviceCreatePipelineLayout(gpu.device, desc)
    end
    pl == C_NULL && throw(GPUValidationError("wgpuDeviceCreatePipelineLayout returned NULL ($label)"))
    _GPU_OBJECTS[] += 1
    return pl
end

"The device's limits, as the struct wgpu fills in."
function _device_limits(gpu::GPU)
    lim = Ref(WGPULimits(C_NULL, ntuple(_ -> 0, fieldcount(WGPULimits) - 1)...))
    st = GC.@preserve lim wgpuDeviceGetLimits(gpu.device, lim)
    st == WGPUStatus_Success || throw(GPUValidationError("wgpuDeviceGetLimits failed (status $st)"))
    return lim[]
end

"""
    UniformArena

The mobject blocks of a frame: a CPU staging area written block by block as
the draw list is walked, one Uniform buffer they go up into, and the bind
group with a dynamic offset over it. `stride` is the block rounded up to the
device's offset alignment; `capacity` slots exist on the GPU side, and a
frame that needs more grows the buffer (and the bind group) before its pass.
"""
mutable struct UniformArena
    stride::Int
    capacity::Int
    buffer::WGPUBuffer
    bind_group::WGPUBindGroup
    staging::Vector{UInt8}
    n::Int                        # blocks written this frame
end

const _ARENA_LABEL = "Janim mobject uniforms"
const _ARENA_BG_LABEL = "Janim mobject bind group"

function _arena_objects(gpu::GPU, layout::WGPUBindGroupLayout, stride::Int, capacity::Int)
    buf = _gpu_buffer(gpu, stride * capacity, WGPUBufferUsage_Uniform | WGPUBufferUsage_CopyDst, _ARENA_LABEL)
    entries = [WGPUBindGroupEntry(C_NULL, 0, buf, 0, UInt64(MOBJECT_UNIFORMS_BYTES),
                                  WGPUSampler(C_NULL), WGPUTextureView(C_NULL))]
    bg = _bind_group(gpu, layout, entries, _ARENA_BG_LABEL)
    return buf, bg
end

function UniformArena(gpu::GPU, layout::WGPUBindGroupLayout; capacity::Int = 256)
    align = Int(_device_limits(gpu).minUniformBufferOffsetAlignment)
    align > 0 || (align = 256)
    stride = MOBJECT_UNIFORMS_BYTES + mod(-MOBJECT_UNIFORMS_BYTES, align)
    buf, bg = _arena_objects(gpu, layout, stride, capacity)
    return UniformArena(stride, capacity, buf, bg, zeros(UInt8, stride * capacity), 0)
end

"""
Stage one block; returns its slot (0-based). A block identical to the one
staged just before it gets the SAME slot — consecutive runs that share
their key (a Tex's glyphs as one run each, 3 000 loose squares) then share
one bind-group offset, and the pass skips the rebind.
"""
function _push_block!(a::UniformArena, u::MobjectUniforms)
    k = a.n
    if k > 0
        s = a.staging
        last = GC.@preserve s unsafe_load(Ptr{MobjectUniforms}(pointer(s) + (k - 1) * a.stride))
        last === u && return k - 1
    end
    needed = (k + 1) * a.stride
    if length(a.staging) < needed
        resize!(a.staging, max(needed, 2 * length(a.staging)))
    end
    s = a.staging
    GC.@preserve s unsafe_store!(Ptr{MobjectUniforms}(pointer(s) + k * a.stride), u)
    a.n = k + 1
    return k
end

"""
Grow the GPU side to hold `n` blocks when it does not: a new buffer and a
new bind group. Only ever called with nothing recorded against the old
ones — the direct route grows between the walk and the encoding, the
compositor at a flush (compositor.jl): a pass already recorded holds the
bind group it was given, and a destroyed buffer under it is a fatal error
at submit.
"""
function _ensure_arena!(a::UniformArena, gpu::GPU, layout::WGPUBindGroupLayout, n::Int)
    n <= a.capacity && return a
    wgpuBindGroupRelease(a.bind_group)
    wgpuBufferDestroy(a.buffer)
    wgpuBufferRelease(a.buffer)
    a.capacity = max(2 * a.capacity, n)
    a.buffer, a.bind_group = _arena_objects(gpu, layout, a.stride, a.capacity)
    return a
end

"Grow the GPU side to this frame's block count if it does not fit, then upload the blocks in one write."
function _upload_blocks!(a::UniformArena, gpu::GPU, layout::WGPUBindGroupLayout)
    _ensure_arena!(a, gpu, layout, a.n)
    a.n == 0 && return 0
    s = a.staging
    return GC.@preserve s _write_buffer!(gpu, a.buffer, 0, pointer(s), a.n * a.stride)
end

function _release!(a::UniformArena)
    wgpuBindGroupRelease(a.bind_group)
    wgpuBufferDestroy(a.buffer)
    wgpuBufferRelease(a.buffer)
    return nothing
end

# ── the parameter rings ───────────────────────────────────────────
#
# Two more blocks travel in rings with a dynamic offset, on the model of
# the mobject arena but without its dedupe and without growing under a
# recorded pass:
#
#   FrameUniforms   one slot per CAMERA a frame draws with — the direct
#                   route uses slot 0 and nothing else; the compositor
#                   takes one per content draw (a layer with its own
#                   CameraFrame, a mask in the parent's space, a matte),
#                   because every write to ONE buffer would land before the
#                   frame's single submit and every pass would see the last
#                   camera (compositor.jl).
#   QuadParams      one slot per QUAD PASS of the compositor: the fields of
#                   every entry point of quad.wgsl and effects.wgsl as four
#                   generic floats, four more, four ints, and the blur's 64
#                   weights as sixteen vec4 — an `array<f32, 64>` is illegal
#                   in a uniform (stride 16), so the shader reads
#                   `w[i >> 2][i & 3]`. 304 bytes.
#
# A ring is staged on the CPU as the frame is walked and goes up in ONE
# `wgpuQueueWriteBuffer` before the submit. When a ring is full the
# compositor FLUSHES — submits what it has recorded and starts the rings
# again — which the queue's order makes safe: a write issued after a submit
# executes after it.

"""
The parameters of one quad pass (group 0, binding 3 of quad_common.wgsl):
`f0`, `f1` four floats each, `i0` four ints, `w` the 64 blur weights.
"""
struct QuadParams
    f0::NTuple{4,Float32}
    f1::NTuple{4,Float32}
    i0::NTuple{4,Int32}
    w::NTuple{64,Float32}
end

const QUAD_PARAMS_BYTES = 304
const QUAD_PARAMS_OFFSETS = (f0 = 0, f1 = 16, i0 = 32, w = 48)

const _ZERO4 = (0f0, 0f0, 0f0, 0f0)
const _ZERO4I = (Int32(0), Int32(0), Int32(0), Int32(0))
const _ZERO64 = ntuple(_ -> 0f0, 64)

_f4(t) = (Float32(t[1]), Float32(t[2]), Float32(t[3]), Float32(t[4]))
_i4(t) = (Int32(t[1]), Int32(t[2]), Int32(t[3]), Int32(t[4]))
"The 64-weight tuple from a kernel of `radius + 1` weights, zero beyond it."
_w64(w::AbstractVector{Float32}) = ntuple(i -> i <= length(w) ? w[i] : 0f0, 64)

"""
    QuadParams(; f0, f1, i0, w)

A block with every field named; the ones a pass does not read stay zero.
Tuples of any length up to four for `f0`/`f1`/`i0` (padded), a weight
vector of up to 64 for `w`.
"""
function QuadParams(; f0 = _ZERO4, f1 = _ZERO4, i0 = _ZERO4I, w = nothing)
    pad4(t, z) = (t[1], length(t) >= 2 ? t[2] : z, length(t) >= 3 ? t[3] : z, length(t) >= 4 ? t[4] : z)
    return QuadParams(_f4(pad4(f0, 0f0)), _f4(pad4(f1, 0f0)), _i4(pad4(i0, Int32(0))),
                      w === nothing ? _ZERO64 : _w64(w))
end

"""
    ParamArena{T}

A ring of `capacity` slots of the isbits block `T`, stride rounded up to
the device's uniform offset alignment: a CPU staging area, the GPU buffer
it goes up into, and `n`, the slots used since the last reset. The bind
group over it belongs to whoever binds it beside other resources (the
frame's alone, the compositor's with its textures).
"""
mutable struct ParamArena{T}
    stride::Int
    capacity::Int
    buffer::WGPUBuffer
    staging::Vector{UInt8}
    n::Int
end

"The device's uniform offset alignment (256 when it reports none)."
function _uniform_alignment(gpu::GPU)
    align = Int(_device_limits(gpu).minUniformBufferOffsetAlignment)
    return align > 0 ? align : 256
end

function ParamArena{T}(gpu::GPU, label::String; capacity::Int) where {T}
    isbitstype(T) || throw(ArgumentError("a ParamArena needs an isbits block, got $T"))
    align = _uniform_alignment(gpu)
    stride = sizeof(T) + mod(-sizeof(T), align)
    buf = _gpu_buffer(gpu, stride * capacity, WGPUBufferUsage_Uniform | WGPUBufferUsage_CopyDst, label)
    return ParamArena{T}(stride, capacity, buf, zeros(UInt8, stride * capacity), 0)
end

"Whether one more slot fits."
_has_room(a::ParamArena) = a.n < a.capacity

"Stage one block; returns its slot (0-based). The caller checks `_has_room` first and flushes when it is false."
function _push!(a::ParamArena{T}, u::T) where {T}
    a.n < a.capacity || error("the $(T) ring is full ($(a.capacity) slots): the caller had to flush")
    k = a.n
    s = a.staging
    GC.@preserve s unsafe_store!(Ptr{T}(pointer(s) + k * a.stride), u)
    a.n = k + 1
    return k
end

"Upload the slots used so far in one write."
function _upload!(a::ParamArena, gpu::GPU)
    a.n == 0 && return 0
    s = a.staging
    return GC.@preserve s _write_buffer!(gpu, a.buffer, 0, pointer(s), a.n * a.stride)
end

function _release!(a::ParamArena)
    wgpuBufferDestroy(a.buffer)
    wgpuBufferRelease(a.buffer)
    return nothing
end
