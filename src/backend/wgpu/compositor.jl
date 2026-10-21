# backend/wgpu/compositor.jl — the compositor on WebGPU: layers, blend modes,
# precomps, masks and mattes, per-layer cameras and windows, the two borders
# of the linear world, the five blurs and the eleven editor effects, and MSAA,
# all on `rgba16float` surfaces:
#
#   · A quad pass is a RENDER PASS: `_quad!` begins one over its
#     destination (cleared, no blend, no depth), sets the entry point's
#     pipeline and one bind group — the two textures, the sampler, the
#     parameter block at a dynamic offset in a ring (uniforms.jl's
#     ParamArena) — draws a strip of four, ends. Where a pass clears and
#     then draws (the window, the mask, the content) that is one pass with
#     `loadOp = Clear`.
#   · The CURRENT texture. `_render_layer!` carries the slot that holds the
#     picture NOW: every pass writes a free scratch slot and hands its index
#     on (`_apply_effect!` returns the slot it wrote), so no pass copies a
#     result back into the layer slot, decodes to a temporary and back, or
#     copies a precomp into its parent's slot — and zero pixels move, since a
#     COPY under NEAREST is the identity. The Bloom's first pyramid step is a
#     saturating copy: `min(0 + 1·B, 1)` is `min(B, 1)` to the bit.
#     `_scratch` gives the lowest slot of the pool (4, 1, 3, 5, 6) not in
#     use; 2 (the mask) and 7 (the window) have fixed roles; the accumulators
#     are never scratch. A slot that must survive a nested chain (the layer
#     under its mask, the source under the Bloom's halo) is pushed on `live`
#     for its duration.
#   · ONE command buffer per frame. The content of a layer is a frame —
#     `_draw_list!` and its one pass — recorded onto the layer slot with
#     `_record_frame!` between the quad passes, in the same encoder, and
#     the whole composition is submitted once (`_end_frame!`). Three things
#     follow. The frame block is a RING (one slot per camera the frame
#     draws with: a layer with a CameraFrame, a mask in the parent's space,
#     a matte with its own), because every write to one buffer would land
#     before the submit and every pass would see the last camera. The
#     mobject arena is not reset between the layers' walks, and never
#     grows under a recorded pass: a walk that overflows it makes the
#     compositor FLUSH — submit what it has, start the rings again — grow,
#     and walk again (`_content!`). And what a walk retires (a swept
#     record's span, a mesh's outgrown buffer, an evicted texture) is only
#     destroyed after the submit (`_drain_pending!`, records.jl), since a
#     pass already recorded reads it.
#   · MSAA (`samples = 4` by default: the fill's antialiasing): the layer
#     slot's multisample twin is the content's target and `resolveTarget` of
#     its last pass lands the picture in the slot BEFORE the decode, so the
#     samples average in sRGB exactly like the direct route's. A mask's
#     content goes through the twin too. `ms_warm` is an optional throwaway
#     first composition, off by default.
#   · Orientation: `flip_y` is HONOURED here, unlike in `draw_scene!`,
#     because the effects have vertical asymmetries (the VHS's torn band, the
#     CRT's roll, the zoom's centre) and the two routes differ in how the
#     picture lies in memory — the video route (`flip_y = true`) keeps it
#     upside down, the direct route (`render_composition` with
#     `flip_y = false`) upright, and every effect reads memory rows. The
#     compositor reproduces each route's MEMORY layout: WebGPU's row 0 is the
#     top, so the content draws with `camera_uniforms(cam; flip_y = !flip_y)`,
#     the window's rect is `_window_dst(…; flip_y)` and the quad's vertex
#     negates NDC y (once, in quad_common.wgsl, with `uv = tc`) so every pass
#     runs memory row to memory row; `_render_composition` flips the rows on
#     the CPU under `flip_y = false`.
#   · Readbacks: `render_composition` copies the scene target out (top-down
#     by construction); `read_layer_rgba` FINALs the layer straight into an
#     `rgba8unorm` scratch and copies it out, for inspecting a layer.
#
# The types (`Layer`, `Composition`, the effects) and the helpers `_focus!`,
# `_tick!`, `_resolved_camera`, `_project_ndc`, `_window_dst`, `_window_src`,
# `_gauss_weights`, `_sigma_px`, `_noise_seed` and `_BLEND_MODES` live in
# core/compositor_types.jl and core/effects_types.jl.

const _GPU_QUADS = Ref(0)            # quad passes recorded (a subset of _GPU_PASSES)
const _QUAD_RING_SLOTS = 256          # quad passes per frame before a flush
const _SCRATCH_POOL = (4, 1, 3, 5, 6) # where a chain may write, in order of preference
const _SLOT_LABELS = ("Janim slot scratchA", "Janim slot mask", "Janim slot layer", "Janim slot tmp",
                      "Janim slot haloA", "Janim slot haloB", "Janim slot window")
const _ACCUM_LABEL = "Janim slot accumulator"
const _QUAD_LAYOUT_LABEL = "Janim quad layout"
const _QUAD_PL_LABEL = "Janim quad pipeline layout"
const _QUAD_BG_LABEL = "Janim quad bind group"
const _QUAD_PARAMS_LABEL = "Janim quad params"
const _QUAD_SAMPLER_LABELS = ("Janim quad sampler nearest", "Janim quad sampler linear")
const _COMPOSITOR_DEPTH_LABEL = "Janim compositor depth"
const _REFEREE_LABEL = "Janim referee target"
const _VS_QUAD = "vs_quad"
const _VS_WINDOW = "vs_window"

"An `rgba16float` surface of the compositor: the texture and its view."
struct GPUSurface
    texture::WGPUTexture
    view::WGPUTextureView
end

function _surface(gpu::GPU, width::Int, height::Int, label::String)
    tex = _create_texture(gpu, width, height, WGPUTextureFormat_RGBA16Float,
                          WGPUTextureUsage_RenderAttachment | WGPUTextureUsage_TextureBinding, label)
    _GPU_OBJECTS[] += 1
    return GPUSurface(tex, wgpuTextureCreateView(tex, C_NULL))
end

function _release!(s::GPUSurface)
    wgpuTextureViewRelease(s.view)
    wgpuTextureDestroy(s.texture)
    wgpuTextureRelease(s.texture)
    return nothing
end

"""
    GPUCompositor

The compositor's state: the seven slots as `rgba16float`
surfaces (scratchA, mask, layer, tmp, haloA, haloB, window) followed by the
accumulator pairs per recursion depth, the z-buffer every content pass
attaches, the layer slot's multisample twin, the two samplers, the one
bind group layout of every quad pass and its pipeline layout, the modules
and pipelines by entry point and destination format, the bind groups by
the textures they tie, the parameter ring, the referee's `rgba8unorm`
scratch, and the frame's encoder while one is open.
"""
mutable struct GPUCompositor
    gpu::GPU
    width::Int
    height::Int
    samples::Int                     # EFFECTIVE: 4 where 0 was asked, 1 the aliased control
    slots::Vector{GPUSurface}
    depth::WGPUTexture
    depth_view::WGPUTextureView
    ms::Union{Nothing,GPUTarget}
    sampler_nearest::WGPUSampler
    sampler_linear::WGPUSampler
    layout::WGPUBindGroupLayout
    pipeline_layout::WGPUPipelineLayout
    modules::Dict{Symbol,WGPUShaderModule}
    user_gens::Dict{Symbol,Int}                  # which registration of a user effect each module holds
    pipelines::Dict{Tuple{Symbol,WGPUTextureFormat},WGPURenderPipeline}
    bind_groups::Dict{Tuple{WGPUTextureView,WGPUTextureView,WGPUSampler},WGPUBindGroup}
    params::ParamArena{QuadParams}
    referee::Union{Nothing,GPUTarget}
    ppu::Float64                     # pixels per scene unit (σ scene → σ px)
    live::Vector{Int}                # slots a chain must not write
    enc::WGPUCommandEncoder          # the open frame's encoder (C_NULL between frames)
    offset_ref::Base.RefValue{UInt32}
    ms_warm::Bool                    # an optional throwaway first composition (off)
    frames::Int
    closed::Bool
end

"A sampler with `filter` and REPEAT on both axes."
function _quad_sampler(gpu::GPU, filter, label::String)
    sdesc = Ref(WGPUSamplerDescriptor(C_NULL, _sv(label),
                                      WGPUAddressMode_Repeat, WGPUAddressMode_Repeat,
                                      WGPUAddressMode_ClampToEdge, filter, filter,
                                      WGPUMipmapFilterMode_Nearest,
                                      0f0, 32f0, WGPUCompareFunction_Undefined, 1))
    s = GC.@preserve label sdesc _error_scope(gpu) do
        wgpuDeviceCreateSampler(gpu.device, sdesc)
    end
    s == C_NULL && throw(GPUValidationError("wgpuDeviceCreateSampler returned NULL ($label)"))
    _GPU_OBJECTS[] += 1
    return s
end

"""
The one bind group layout of every quad pass: two filterable float textures
at 0 and 1, a filtering sampler at 2, the parameter block at 3 with a
dynamic offset — visible to the vertex stage too, for the window's rect.
"""
function _quad_layout(gpu::GPU)
    none_buf = WGPUBufferBindingLayout(C_NULL, WGPUBufferBindingType_BindingNotUsed, 0, 0)
    none_sam = WGPUSamplerBindingLayout(C_NULL, WGPUSamplerBindingType_BindingNotUsed)
    none_tex = WGPUTextureBindingLayout(C_NULL, WGPUTextureSampleType_BindingNotUsed,
                                        WGPUTextureViewDimension_Undefined, 0)
    none_st = WGPUStorageTextureBindingLayout(C_NULL, WGPUStorageTextureAccess_BindingNotUsed,
                                              WGPUTextureFormat_Undefined, WGPUTextureViewDimension_Undefined)
    tex = WGPUTextureBindingLayout(C_NULL, WGPUTextureSampleType_Float, WGPUTextureViewDimension_2D, 0)
    entries = [
        WGPUBindGroupLayoutEntry(C_NULL, 0, WGPUShaderStage_Fragment, none_buf, none_sam, tex, none_st),
        WGPUBindGroupLayoutEntry(C_NULL, 1, WGPUShaderStage_Fragment, none_buf, none_sam, tex, none_st),
        WGPUBindGroupLayoutEntry(C_NULL, 2, WGPUShaderStage_Fragment, none_buf,
            WGPUSamplerBindingLayout(C_NULL, WGPUSamplerBindingType_Filtering), none_tex, none_st),
        WGPUBindGroupLayoutEntry(C_NULL, 3, WGPUShaderStage_Vertex | WGPUShaderStage_Fragment,
            WGPUBufferBindingLayout(C_NULL, WGPUBufferBindingType_Uniform, WGPUBool(1), UInt64(QUAD_PARAMS_BYTES)),
            none_sam, none_tex, none_st)]
    return _bind_group_layout(gpu, entries, _QUAD_LAYOUT_LABEL)
end

"""
    setup_compositor(gpu, width, height; samples = 0) → GPUCompositor

A compositor on `gpu`: the seven slots, the depth, the multisample
twin when `samples > 0`, the samplers, the layouts, the ring. Pipelines,
modules, bind groups and accumulators are made on first use.
"""
function setup_compositor(gpu::GPU, width::Int, height::Int; samples::Int = 0)
    (width > 0 && height > 0) || throw(ArgumentError("a compositor needs a positive size, got $(width)×$(height)"))
    samples in (0, 1, 4) || throw(ArgumentError("samples = $samples: WebGPU renders at 1 or 4 samples (0 = off)"))
    # the same effective sample count as the render VM it pairs with
    # (`setup_render_vm`): the 4× resolve is the fill's antialiasing
    samples == 0 && (samples = 4)
    slots = GPUSurface[_surface(gpu, width, height, lab) for lab in _SLOT_LABELS]
    depth = _create_texture(gpu, width, height, _DS_FORMAT,
                            WGPUTextureUsage_RenderAttachment, _COMPOSITOR_DEPTH_LABEL)
    _GPU_OBJECTS[] += 1
    depth_view = wgpuTextureCreateView(depth, C_NULL)
    ms = samples > 1 ? create_target(gpu, width, height; depth = true, samples,
                                     format = WGPUTextureFormat_RGBA16Float) : nothing
    s_near = _quad_sampler(gpu, WGPUFilterMode_Nearest, _QUAD_SAMPLER_LABELS[1])
    s_lin = _quad_sampler(gpu, WGPUFilterMode_Linear, _QUAD_SAMPLER_LABELS[2])
    layout = _quad_layout(gpu)
    pl = _pipeline_layout(gpu, [layout], _QUAD_PL_LABEL)
    params = ParamArena{QuadParams}(gpu, _QUAD_PARAMS_LABEL; capacity = _QUAD_RING_SLOTS)
    cg = GPUCompositor(gpu, width, height, samples, slots, depth, depth_view, ms, s_near, s_lin,
                       layout, pl, Dict{Symbol,WGPUShaderModule}(), Dict{Symbol,Int}(),
                       Dict{Tuple{Symbol,WGPUTextureFormat},WGPURenderPipeline}(),
                       Dict{Tuple{WGPUTextureView,WGPUTextureView,WGPUSampler},WGPUBindGroup}(),
                       params, nothing, width / FRAME_WIDTH_DEF, Int[], WGPUCommandEncoder(C_NULL),
                       Ref{UInt32}(0), false, 0, false)
    finalizer(_finalize_compositor!, cg)
    return cg
end

# the Scene builds its compositor by the render VM it holds
_setup_compositor_for(rv::GPURenderVM, width::Int, height::Int; samples::Int = 0) =
    setup_compositor(rv.gpu, width, height; samples)
_close_compositor!(cg::GPUCompositor) = close_compositor!(cg)
_close_compositor!(::Any) = nothing          # a Scene without a composition holds `nothing`

"""
    setup_compositor(width, height; samples = 0) → GPUCompositor

A compositor on the PROCESS's GPU (`_shared_gpu`). Pair it with a render VM of the same size:
`render_composition(comp, cam; rv, cg)`.
"""
setup_compositor(width::Int, height::Int; samples::Int = 0) =
    setup_compositor(_shared_gpu(), width, height; samples)

"""
    close_compositor!(cg; targets = true)

Release everything the compositor made — with `targets`, its referee and
its multisample twin too. Idempotent. The explicit close closes
everything; the finalizer is [`_finalize_compositor!`](@ref).
"""
function close_compositor!(cg::GPUCompositor; targets::Bool = true)
    cg.closed && return nothing
    cg.closed = true
    cg.enc == C_NULL || wgpuCommandEncoderRelease(cg.enc)
    cg.enc = WGPUCommandEncoder(C_NULL)
    foreach(wgpuBindGroupRelease, values(cg.bind_groups))
    empty!(cg.bind_groups)
    foreach(wgpuRenderPipelineRelease, values(cg.pipelines))
    empty!(cg.pipelines)
    foreach(wgpuShaderModuleRelease, values(cg.modules))
    empty!(cg.modules)
    _release!(cg.params)
    wgpuPipelineLayoutRelease(cg.pipeline_layout)
    wgpuBindGroupLayoutRelease(cg.layout)
    wgpuSamplerRelease(cg.sampler_linear)
    wgpuSamplerRelease(cg.sampler_nearest)
    if targets
        cg.referee === nothing || close_target!(cg.referee)
        cg.ms === nothing || close_target!(cg.ms)
    end
    wgpuTextureViewRelease(cg.depth_view)
    wgpuTextureDestroy(cg.depth)
    wgpuTextureRelease(cg.depth)
    foreach(_release!, cg.slots)
    empty!(cg.slots)
    return nothing
end

"""
The compositor's finalizer: `close_compositor!` without its targets
(`cg.referee`, `cg.ms`), which are `GPUTarget`s with a finalizer of their
own and may be in a caller's hands while the compositor is not — the
rule and the abort it stops are `_finalize_render_vm!`'s (render.jl).
"""
_finalize_compositor!(cg::GPUCompositor) = close_compositor!(cg; targets = false)

# ── slots ───────────────────────────────────────────────────────────────

"The accumulator pair of a recursion depth, created once and kept: (a, b) as slot indices."
function _accums_at!(cg::GPUCompositor, depth::Int)
    while length(cg.slots) < 7 + 2depth
        push!(cg.slots, _surface(cg.gpu, cg.width, cg.height, _ACCUM_LABEL))
    end
    return 7 + 2depth - 1, 7 + 2depth
end

"""
A slot a chain may write now: the first of the pool (4, 1, 3, 5, 6) that is
neither `busy` nor on `cg.live`. A user effect writes into
`_scratch(cg, src)` and returns it (docs/src/compositor.md).
"""
function _scratch(cg::GPUCompositor, busy::Int...)
    for s in _SCRATCH_POOL
        (s in busy || s in cg.live) && continue
        return s
    end
    error("the compositor has no free scratch slot: busy $(busy), live $(cg.live)")
end

"Run `f()` with these slots protected from `_scratch`."
function _with_live(f, cg::GPUCompositor, slots::Int...)
    n = length(cg.live)
    append!(cg.live, slots)
    try
        return f()
    finally
        resize!(cg.live, n)
    end
end

_view(cg::GPUCompositor, slot::Int) = cg.slots[slot].view

# ── the quad pass ───────────────────────────────────────────────────────

# ── an effect of your own: its WGSL ─────────────────────────────────────
#
# The eleven built-in effects are one module (`effects.wgsl`); an effect
# written OUTSIDE the engine — the tutorial's Posterize, yours — brings its
# own fragment and must not edit that file. So a user fragment is a module of
# its own, keyed by its entry point: the engine splices the same inserts the
# built-ins see (the quad's bind group and `QuadParams`, the noise, the
# straight-alpha helpers), compiles it on first use in every compositor that
# runs it, and rebuilds it when the source is registered again (a live
# session editing its shader).

const _EFFECT_INSERTS = ("quad_common.wgsl", "noise.wgsl", "straight.wgsl")
const _USER_WGSL = Dict{Symbol,Tuple{String,Int}}()      # entry => (module source, generation)
const _USER_WGSL_GEN = Ref(0)

_quad_builtin(entry::Symbol) =
    entry in (:comb, :blur, :copy, :saturate, :mask, :bright, :add2, :decode, :final, :zoom, :window) ? :quad :
    entry in (:glitch, :crt, :vhs, :color, :pixelate, :vignette, :grain, :chroma, :sharpen, :wave, :edge) ? :effects :
    nothing

"""
    effect_shader!(entry::Symbol, fragment::AbstractString) → entry

Register the WGSL of a layer effect of your own. `fragment` is the function
`fn fs_<entry>(in: QuadOut) -> @location(0) vec4<f32>` (with its `@fragment`
attribute) over the compositor's shared quad — it reads the layer through
`sample_a(in.uv)`, its dials from `P.f0`/`P.f1` (four floats each) and
`P.i0` (four ints), the pixel from `in.position.xy`, and it may call the
noise (`janim_noise_px`, `janim_noise_steps`, `janim_frame_step`,
`seed_plus`) and the straight-alpha helpers (`unpremult`, `luma`): the
engine splices those inserts in front of it, exactly as it does for the
built-in effects. Then ONE method

    Janim._apply_effect!(cg::GPUCompositor, rv, ef::MyEffect, src::Int) =
        Janim._quad!(cg, rv, :<entry>, Janim._scratch(cg, src); a = src,
                     params = Janim.QuadParams(f0 = (…,), i0 = (…,)))

runs it. Registering the same entry again replaces the shader: every
compositor recompiles it at its next use, so a live session can edit the
fragment and see it land. A built-in entry point cannot be replaced.
The walkthrough is `examples/tutorial/c2_06_shaders/01_write_a_layer_effect.jl`.
"""
function effect_shader!(entry::Symbol, fragment::AbstractString)
    _quad_builtin(entry) === nothing ||
        throw(ArgumentError("`$entry` is the entry point of a built-in effect: pick another name"))
    occursin("fs_$(entry)", fragment) ||
        throw(ArgumentError("the fragment must define `fn fs_$(entry)(in: QuadOut) -> @location(0) vec4<f32>`"))
    io = IOBuffer()
    for name in _EFFECT_INSERTS
        println(io, "// ── ", name, " ──")
        print(io, read(joinpath(_WGSL_DIR, "inserts", name), String))
        println(io)
    end
    print(io, fragment)
    _USER_WGSL[entry] = (String(take!(io)), _USER_WGSL_GEN[] += 1)
    return entry
end

"The module an entry point lives in: the compositor's ten in `quad`, the editor effects in `effects`, a registered one in a module of its own name."
function _quad_module(entry::Symbol)
    m = _quad_builtin(entry)
    m === nothing || return m
    haskey(_USER_WGSL, entry) && return entry
    error("no quad entry point named $entry — a layer effect of your own registers its WGSL with effect_shader!($(repr(entry)), …) first")
end

function _quad_shader!(cg::GPUCompositor, name::Symbol)
    user = get(_USER_WGSL, name, nothing)
    m = get(cg.modules, name, nothing)
    if user !== nothing && m !== nothing && get(cg.user_gens, name, 0) != user[2]
        # the fragment was registered again: drop the module and every
        # pipeline made from it, and compile the new source below
        for key in collect(keys(cg.pipelines))
            key[1] === name || continue
            wgpuRenderPipelineRelease(pop!(cg.pipelines, key))
        end
        wgpuShaderModuleRelease(pop!(cg.modules, name))
        m = nothing
    end
    m === nothing || return m
    src = user === nothing ? getfield(WGSL_SOURCES, name) : user[1]
    m = compile_wgsl(cg.gpu, src; label = String(name))
    cg.modules[name] = m
    user === nothing || (cg.user_gens[name] = user[2])
    return m
end

"""
The pipeline of `entry` onto `format` (`rgba16float` for the slots,
`rgba8unorm` for the scene target and the referee's scratch): the quad's
vertex — the window's own for `:window` — no blend, no depth, one sample,
a strip of four, no vertex buffers.
"""
function _quad_pipeline!(cg::GPUCompositor, entry::Symbol, format)
    # a registered effect may have been registered AGAIN since this
    # compositor compiled it: let the shader cache drop the stale pipelines
    haskey(_USER_WGSL, entry) && _quad_shader!(cg, entry)
    key = (entry, format)
    p = get(cg.pipelines, key, nothing)
    p === nothing || return p
    gpu = cg.gpu
    shader = _quad_shader!(cg, _quad_module(entry))
    label = string("Janim quad ", entry)
    vs = entry === :window ? _VS_WINDOW : _VS_QUAD
    fs = string("fs_", entry)
    targets = [WGPUColorTargetState(C_NULL, format, C_NULL, WGPUColorWriteMask_All)]
    frag = Ref(WGPUFragmentState(C_NULL, shader, _sv(fs), 0, C_NULL, length(targets), pointer(targets)))
    desc = Ref(WGPURenderPipelineDescriptor(
        C_NULL, _sv(label), cg.pipeline_layout,
        WGPUVertexState(C_NULL, shader, _sv(vs), 0, C_NULL, 0, C_NULL),
        WGPUPrimitiveState(C_NULL, WGPUPrimitiveTopology_TriangleStrip, WGPUIndexFormat_Undefined,
                           WGPUFrontFace_CCW, WGPUCullMode_None, 0),
        C_NULL, WGPUMultisampleState(C_NULL, 1, 0xffffffff, 0),
        Base.unsafe_convert(Ptr{WGPUFragmentState}, frag)))
    p = GC.@preserve label vs fs targets frag desc _error_scope(gpu) do
        wgpuDeviceCreateRenderPipeline(gpu.device, desc)
    end
    p == C_NULL && throw(GPUValidationError("wgpuDeviceCreateRenderPipeline returned NULL for $label"))
    _GPU_OBJECTS[] += 1
    cg.pipelines[key] = p
    return p
end

"The bind group tying two texture views, a sampler and the parameter ring, cached by the three."
function _quad_bind_group!(cg::GPUCompositor, va::WGPUTextureView, vb::WGPUTextureView, sampler::WGPUSampler)
    key = (va, vb, sampler)
    bg = get(cg.bind_groups, key, nothing)
    bg === nothing || return bg
    entries = [WGPUBindGroupEntry(C_NULL, 0, WGPUBuffer(C_NULL), 0, 0, WGPUSampler(C_NULL), va),
               WGPUBindGroupEntry(C_NULL, 1, WGPUBuffer(C_NULL), 0, 0, WGPUSampler(C_NULL), vb),
               WGPUBindGroupEntry(C_NULL, 2, WGPUBuffer(C_NULL), 0, 0, sampler, WGPUTextureView(C_NULL)),
               WGPUBindGroupEntry(C_NULL, 3, cg.params.buffer, 0, UInt64(QUAD_PARAMS_BYTES),
                                  WGPUSampler(C_NULL), WGPUTextureView(C_NULL))]
    bg = _bind_group(cg.gpu, cg.layout, entries, _QUAD_BG_LABEL)
    cg.bind_groups[key] = bg
    return bg
end

"""
One quad pass of `entry` onto `view` (of `format`): begin (cleared to
transparent — every quad covers the attachment, the window's leaves the
rest transparent on purpose), pipeline, the bind group over `va`/`vb` and
the nearest or the linear sampler, the parameters at their ring slot,
four vertices, end. Recorded into the open frame's encoder; a full ring
flushes first.
"""
function _quad_view!(cg::GPUCompositor, rv::GPURenderVM, entry::Symbol, view::WGPUTextureView, format;
                     va::WGPUTextureView, vb::WGPUTextureView = va, linear::Bool = false,
                     params::QuadParams = QuadParams())
    _has_room(cg.params) || _flush!(cg, rv)
    k = _push!(cg.params, params)
    pipe = _quad_pipeline!(cg, entry, format)
    bg = _quad_bind_group!(cg, va, vb, linear ? cg.sampler_linear : cg.sampler_nearest)
    color = [WGPURenderPassColorAttachment(C_NULL, view, WGPU_DEPTH_SLICE_UNDEFINED, WGPUTextureView(C_NULL),
                                           WGPULoadOp_Clear, WGPUStoreOp_Store, WGPUColor(0.0, 0.0, 0.0, 0.0))]
    desc = Ref(WGPURenderPassDescriptor(C_NULL, _EMPTY_SV, length(color), pointer(color), C_NULL,
                                        WGPUQuerySet(C_NULL), C_NULL))
    pass = GC.@preserve color desc wgpuCommandEncoderBeginRenderPass(cg.enc, desc)
    _GPU_PASSES[] += 1
    _GPU_QUADS[] += 1
    wgpuRenderPassEncoderSetPipeline(pass, pipe)
    cg.offset_ref[] = UInt32(k * cg.params.stride)
    wgpuRenderPassEncoderSetBindGroup(pass, UInt32(0), bg, Csize_t(1),
                                      Base.unsafe_convert(Ptr{UInt32}, cg.offset_ref))
    wgpuRenderPassEncoderDraw(pass, UInt32(4), UInt32(1), UInt32(0), UInt32(0))
    wgpuRenderPassEncoderEnd(pass)
    wgpuRenderPassEncoderRelease(pass)
    _DRAW_CALLS[] += 1
    return nothing
end

"A quad pass of `entry` from slot `a` (and `b`) onto slot `dst`; returns `dst`."
function _quad!(cg::GPUCompositor, rv::GPURenderVM, entry::Symbol, dst::Int; a::Int, b::Int = a,
                linear::Bool = false, params::QuadParams = QuadParams())
    (dst == a || dst == b) && error("a quad pass cannot read and write slot $dst")
    _quad_view!(cg, rv, entry, _view(cg, dst), WGPUTextureFormat_RGBA16Float;
                va = _view(cg, a), vb = _view(cg, b), linear, params)
    return dst
end

"A clear-only pass: `slot` set to `rgba` (the accumulator's decoded ground, the empty window)."
function _clear!(cg::GPUCompositor, rv::GPURenderVM, slot::Int, rgba::NTuple{4,Float32})
    color = [WGPURenderPassColorAttachment(C_NULL, _view(cg, slot), WGPU_DEPTH_SLICE_UNDEFINED,
                                           WGPUTextureView(C_NULL), WGPULoadOp_Clear, WGPUStoreOp_Store,
                                           WGPUColor(Float64(rgba[1]), Float64(rgba[2]), Float64(rgba[3]),
                                                     Float64(rgba[4])))]
    desc = Ref(WGPURenderPassDescriptor(C_NULL, _EMPTY_SV, length(color), pointer(color), C_NULL,
                                        WGPUQuerySet(C_NULL), C_NULL))
    pass = GC.@preserve color desc wgpuCommandEncoderBeginRenderPass(cg.enc, desc)
    _GPU_PASSES[] += 1
    wgpuRenderPassEncoderEnd(pass)
    wgpuRenderPassEncoderRelease(pass)
    return slot
end

# ── the frame's command buffer ──────────────────────────────────────────

"Open the frame: a fresh encoder, the rings and the arena at zero."
function _begin_frame!(cg::GPUCompositor, rv::GPURenderVM)
    cg.enc == C_NULL || error("the compositor's previous frame was never ended")
    cg.enc = wgpuDeviceCreateCommandEncoder(cg.gpu.device, C_NULL)
    rv.frame_ring.n = 0
    cg.params.n = 0
    rv.arena.n = 0
    return nothing
end

"Upload the rings, finish and submit the encoder; the deferred releases after it."
function _submit_frame!(cg::GPUCompositor, rv::GPURenderVM)
    gpu = cg.gpu
    rv.arena.n <= rv.arena.capacity ||
        error("the mobject arena grew under a recorded pass ($(rv.arena.n) > $(rv.arena.capacity))")
    _upload_blocks!(rv.arena, gpu, rv.layout_mob)
    _upload!(rv.frame_ring, gpu)
    _upload!(cg.params, gpu)
    cmd = _error_scope(gpu) do
        wgpuCommandEncoderFinish(cg.enc, C_NULL)
    end
    wgpuCommandEncoderRelease(cg.enc)
    cg.enc = WGPUCommandEncoder(C_NULL)
    index = _submit!(gpu, cmd)
    _after_submit!(rv)
    return index
end

"Submit what is recorded and open a new encoder: the rings start again (a write after a submit executes after it)."
function _flush!(cg::GPUCompositor, rv::GPURenderVM)
    _submit_frame!(cg, rv)
    _begin_frame!(cg, rv)
    return nothing
end

"Close the frame: submit, and surface any error the device mailed."
function _end_frame!(cg::GPUCompositor, rv::GPURenderVM)
    _submit_frame!(cg, rv)
    _check_gpu_errors!(cg.gpu)
    cg.frames += 1
    return nothing
end

"""
A content list drawn as a frame — the walk, the one pass — onto
`(view, depth_view)` of `format` at `samples`, resolving into `resolve` when
given, cleared to transparent, with `cam_u` as its camera (a fresh slot of
the frame ring). A walk that overflows the mobject arena or the frame ring
flushes, grows, and walks again: nothing of it was recorded yet, and the
records it built are cached.
"""
function _content!(cg::GPUCompositor, rv::GPURenderVM, content, cam_u, view::WGPUTextureView,
                   depth_view::WGPUTextureView, resolve::WGPUTextureView, samples::Int, format)
    gpu = cg.gpu
    while true
        n0 = rv.arena.n
        _reset_draw!(rv)
        # a layer's list is drawn in z order like the scene's roots
        # (`set_z_index!`: «inside its layer»); the list itself stays as it
        # was added, so the sort allocates only when a z is set
        content === nothing || _draw_list!(rv, _draw_order(content), cam_u)
        needed = rv.arena.n
        (needed <= rv.arena.capacity && _has_room(rv.frame_ring)) && break
        # what this walk staged past the capacity is dropped — the pass that
        # would read it was never recorded — so the flush uploads and submits
        # only what the earlier passes hold; then the arena grows and the
        # walk runs again (the count must not stay: `_submit_frame!` refuses
        # an arena that grew under a recorded pass).
        rv.arena.n = n0
        _flush!(cg, rv)
        needed > rv.arena.capacity && _ensure_arena!(rv.arena, gpu, rv.layout_mob, 2 * (needed - n0))
    end
    slot = _push!(rv.frame_ring, FrameUniforms(cam_u))
    _record_frame!(cg.enc, rv, (0f0, 0f0, 0f0, 0f0),
                   _FrameTarget(view, depth_view, resolve, samples, format, slot))
    return nothing
end

"""
The layer's content into slot 3 — through the multisample twin with a
resolve when the compositor has one — then DECODED into a scratch,
which is the layer's current slot. Masks and mattes reuse it.
"""
function _content_layer!(cg::GPUCompositor, rv::GPURenderVM, content, cam_u)
    if cg.ms === nothing
        _content!(cg, rv, content, cam_u, _view(cg, 3), cg.depth_view, WGPUTextureView(C_NULL), 1,
                  WGPUTextureFormat_RGBA16Float)
    else
        _content!(cg, rv, content, cam_u, cg.ms.view, cg.ms.depth_view, _view(cg, 3), cg.samples,
                  WGPUTextureFormat_RGBA16Float)
    end
    return _quad!(cg, rv, :decode, _scratch(cg, 3); a = 3)
end

# ── effects ─────────────────────────────────────────────────────────────

_step_h(cg::GPUCompositor) = (Float32(1 / cg.width), 0f0)     # (1/W, 0) horizontal
_step_v(cg::GPUCompositor) = (0f0, Float32(1 / cg.height))    # (0, 1/H) vertical

"Separable H+V through a scratch; the result lands back in `cur`, which is returned."
function _blur_hv!(cg::GPUCompositor, rv::GPURenderVM, cur::Int, radius::Int, weights::Vector{Float32})
    tmp = _scratch(cg, cur)
    _quad!(cg, rv, :blur, tmp; a = cur, params = QuadParams(f0 = _step_h(cg), i0 = (radius,), w = weights))
    _quad!(cg, rv, :blur, cur; a = tmp, params = QuadParams(f0 = _step_v(cg), i0 = (radius,), w = weights))
    return cur
end

"H+V of `src` into a fresh slot, `src` untouched (the Sharpen keeps its original); returns the slot."
function _blur_to!(cg::GPUCompositor, rv::GPURenderVM, src::Int, radius::Int, weights::Vector{Float32})
    return _with_live(cg, src) do
        h = _scratch(cg, src)
        _quad!(cg, rv, :blur, h; a = src, params = QuadParams(f0 = _step_h(cg), i0 = (radius,), w = weights))
        v = _scratch(cg, src, h)
        _quad!(cg, rv, :blur, v; a = h, params = QuadParams(f0 = _step_v(cg), i0 = (radius,), w = weights))
        v
    end
end

"""
    _apply_effect!(cg::GPUCompositor, rv::GPURenderVM, ef, src::Int) → Int

Apply `ef` to the layer whose picture is in slot `src` and return the slot
that holds the result — `src` itself when the effect is an exact no-op or
works in place (the separable blurs), a scratch otherwise. The contract of
a user effect (docs/src/compositor.md): write into `_scratch(cg, src)` and
return it; never write `src`.
"""
function _apply_effect!(cg::GPUCompositor, rv::GPURenderVM, ef::Blur, src::Int)
    σ = _sigma_px(cg, ef.sigma, ef.in_pixels)
    σ < 0.3 && return src                     # imperceptible: continuity towards σ=0
    return _blur_hv!(cg, rv, src, _gauss_weights(σ)...)
end

_apply_effect!(cg::GPUCompositor, rv::GPURenderVM, ef::Dof, src::Int) =
    ef.current_sigma > 1e-6 ? _apply_effect!(cg, rv, Blur(ef.current_sigma), src) : src

function _apply_effect!(cg::GPUCompositor, rv::GPURenderVM, ef::BoxBlur, src::Int)
    requested = max(round(Int, ef.radius * cg.ppu), 1)
    r = min(requested, 63)                    # the same weights[64] wall
    requested > 63 && @warn(
        "box-kernel-radius-limit: radius $(ef.radius) units is $requested px, " *
        "the shader's weights[64] caps it at 63",
        maxlog = 1)
    return _blur_hv!(cg, rv, src, r, fill(Float32(1 / (2r + 1)), r + 1))
end

function _apply_effect!(cg::GPUCompositor, rv::GPURenderVM, ef::DirectionalBlur, src::Int)
    σ = _sigma_px(cg, ef.sigma, false)
    σ < 0.3 && return src
    radius, weights = _gauss_weights(σ)
    step_uv = (Float32(cos(ef.angle) / cg.width), Float32(sin(ef.angle) / cg.height))
    return _quad!(cg, rv, :blur, _scratch(cg, src); a = src,
                  params = QuadParams(f0 = step_uv, i0 = (radius,), w = weights))
end

function _apply_effect!(cg::GPUCompositor, rv::GPURenderVM, ef::RadialBlur, src::Int)
    cx = Float32(0.5 + ef.center_point[1] / FRAME_WIDTH_DEF)
    cy = Float32(0.5 + ef.center_point[2] / FRAME_HEIGHT_DEF)
    return _quad!(cg, rv, :zoom, _scratch(cg, src); a = src,
                  params = QuadParams(f0 = (cx, cy, Float32(ef.strength))))
end

function _apply_effect!(cg::GPUCompositor, rv::GPURenderVM, ef::Bloom, src::Int)
    σ0 = max(_sigma_px(cg, ef.sigma, false), 0.5)
    hp = 5                                    # halo ping-pong: slots 5/6
    first = true
    _with_live(cg, src, 5, 6) do
        for σ in (σ0, 2σ0, 4σ0)               # the pyramid of blurs
            bright = _quad!(cg, rv, :bright, _scratch(cg, src); a = src,
                            params = QuadParams(f0 = (Float32(ef.threshold),)))
            # `_gauss_weights` truncates the true Gaussian and says so when
            # the wall bites
            _blur_hv!(cg, rv, bright, _gauss_weights(σ)...)
            other = hp == 5 ? 6 : 5
            if first
                # ADD2 over the cleared halo, `min(0 + 1·B, 1)`, is `min(B, 1)`
                _quad!(cg, rv, :saturate, other; a = bright)
            else
                _quad!(cg, rv, :add2, other; a = hp, b = bright, params = QuadParams(f0 = (1f0,)))
            end
            hp = other
            first = false
        end
    end
    return _with_live(cg, hp) do
        _quad!(cg, rv, :add2, _scratch(cg, src); a = src, b = hp,
               params = QuadParams(f0 = (Float32(ef.intensity),)))
    end
end

function _apply_effect!(cg::GPUCompositor, rv::GPURenderVM, ef::Glitch, src::Int)
    ef.intensity <= 0 && return src           # the exact no-op
    return _quad!(cg, rv, :glitch, _scratch(cg, src); a = src, params = QuadParams(
        i0 = (ef.current_frame, _noise_seed(ef, ef.seed), max(ef.rate, 1), max(ef.slices, 1)),
        f0 = (Float32(clamp(ef.intensity, 0, 1)), Float32(ef.rgb_shift * cg.ppu / cg.width),
              Float32(max(ef.block * cg.ppu / cg.width, 1e-4)), Float32(max(ef.block * cg.ppu / cg.height, 1e-4)))))
end

function _apply_effect!(cg::GPUCompositor, rv::GPURenderVM, ef::CRT, src::Int)
    ef.intensity <= 0 && return src
    return _quad!(cg, rv, :crt, _scratch(cg, src); a = src, params = QuadParams(
        f0 = (Float32(clamp(ef.intensity, 0, 1)), Float32(max(ef.scanlines, 0)),
              Float32(clamp(ef.scan_depth, 0, 1)), Float32(clamp(ef.mask, 0, 1))),
        f1 = (Float32(ef.curvature), Float32(clamp(ef.vignette, 0, 1)), Float32(ef.roll), Float32(cg.height))))
end

function _apply_effect!(cg::GPUCompositor, rv::GPURenderVM, ef::VHS, src::Int)
    ef.intensity <= 0 && return src
    return _quad!(cg, rv, :vhs, _scratch(cg, src); a = src, params = QuadParams(
        i0 = (ef.current_frame, _noise_seed(ef, ef.seed), max(ef.rate, 1)),
        f0 = (Float32(clamp(ef.intensity, 0, 1)), Float32(ef.jitter * cg.ppu / cg.width),
              Float32(ef.chroma_bleed * cg.ppu / cg.width), Float32(clamp(ef.noise, 0, 1))),
        f1 = (Float32(clamp(ef.head_switch, 0, 1)),)))
end

function _apply_effect!(cg::GPUCompositor, rv::GPURenderVM, ef::ColorAdjust, src::Int)
    (ef.brightness == 1 && ef.contrast == 1 && ef.saturation == 1 && ef.hue == 0) &&
        return src                            # the exact identity
    return _quad!(cg, rv, :color, _scratch(cg, src); a = src, params = QuadParams(
        f0 = (Float32(ef.brightness), Float32(ef.contrast), Float32(ef.saturation), Float32(ef.hue))))
end

function _apply_effect!(cg::GPUCompositor, rv::GPURenderVM, ef::Pixelate, src::Int)
    px = ef.size * cg.ppu
    px < 1 && return src                      # below one pixel there is no mosaic
    return _quad!(cg, rv, :pixelate, _scratch(cg, src); a = src,
                  params = QuadParams(f0 = (Float32(px / cg.width), Float32(px / cg.height))))
end

function _apply_effect!(cg::GPUCompositor, rv::GPURenderVM, ef::Vignette, src::Int)
    ef.amount <= 0 && return src
    return _quad!(cg, rv, :vignette, _scratch(cg, src); a = src, params = QuadParams(
        f0 = (Float32(clamp(ef.amount, 0, 1)), Float32(ef.radius), Float32(ef.feather))))
end

function _apply_effect!(cg::GPUCompositor, rv::GPURenderVM, ef::Grain, src::Int)
    ef.amount <= 0 && return src
    return _quad!(cg, rv, :grain, _scratch(cg, src); a = src, params = QuadParams(
        i0 = (ef.current_frame, _noise_seed(ef, ef.seed), max(ef.rate, 1), max(ef.levels, 1)),
        f0 = (Float32(clamp(ef.amount, 0, 1)),)))
end

function _apply_effect!(cg::GPUCompositor, rv::GPURenderVM, ef::ChromaticAberration, src::Int)
    ef.amount == 0 && return src
    px = ef.amount * cg.ppu
    return _quad!(cg, rv, :chroma, _scratch(cg, src); a = src,
                  params = QuadParams(f0 = (Float32(2px / cg.width), Float32(2px / cg.height))))
end

function _apply_effect!(cg::GPUCompositor, rv::GPURenderVM, ef::Sharpen, src::Int)
    ef.amount <= 0 && return src
    σ = _sigma_px(cg, ef.sigma, false)
    σ < 0.3 && return src                     # no blur to subtract
    blurred = _blur_to!(cg, rv, src, _gauss_weights(σ)...)
    return _with_live(cg, blurred) do
        _quad!(cg, rv, :sharpen, _scratch(cg, src); a = src, b = blurred,
               params = QuadParams(f0 = (Float32(ef.amount),)))
    end
end

function _apply_effect!(cg::GPUCompositor, rv::GPURenderVM, ef::Wave, src::Int)
    ef.amplitude == 0 && return src
    apx = ef.amplitude * cg.ppu
    λpx = max(ef.wavelength * cg.ppu, 1.0)
    # the wave travels along `angle`; the displacement is perpendicular to it;
    # phase mod 2π: the sine is periodic, but Float32 is not
    return _quad!(cg, rv, :wave, _scratch(cg, src); a = src, params = QuadParams(
        f0 = (Float32(-sin(ef.angle) * apx / cg.width), Float32(cos(ef.angle) * apx / cg.height),
              Float32(2π / λpx), Float32(mod(ef.phase, 2π))),
        f1 = (Float32(cos(ef.angle) * cg.width), Float32(sin(ef.angle) * cg.height))))
end

function _apply_effect!(cg::GPUCompositor, rv::GPURenderVM, ef::EdgeDetect, src::Int)
    ef.amount <= 0 && return src
    # the edge colour is named in sRGB and painted INTO the linear world
    rgb = ef.color === nothing ? (0f0, 0f0, 0f0) :
          Float32.((srgb_to_linear(_rgba(ef.color, 1)[1]),
                    srgb_to_linear(_rgba(ef.color, 1)[2]),
                    srgb_to_linear(_rgba(ef.color, 1)[3])))
    return _quad!(cg, rv, :edge, _scratch(cg, src); a = src, params = QuadParams(
        f0 = (Float32(ef.thickness / cg.width), Float32(ef.thickness / cg.height), Float32(ef.amount)),
        f1 = rgb, i0 = (Int32(ef.color !== nothing),)))
end

# ── windows and masks ─────────────────────────────────────────────────

"""
The finished layer picture placed into its window (slot 7): the `src` crop
of `cur` drawn into the `dst` rect — sampled LINEAR — over a transparent
clear, in one pass. A degenerate window shows nothing (the slot cleared).
"""
function _apply_window!(cg::GPUCompositor, rv::GPURenderVM, cam::Camera, layer::Layer, lcam::Camera, cur::Int;
                        flip_y::Bool)
    dst = _window_dst(cam, layer.window; flip_y)          # the rect for this route; vs_window negates y
    dst === nothing && return _clear!(cg, rv, 7, (0f0, 0f0, 0f0, 0f0))
    src = _window_src(cg, lcam, dst)
    return _quad!(cg, rv, :window, 7; a = cur, linear = true,
                  params = QuadParams(f0 = Float32.(dst), f1 = Float32.(src)))
end

"""
The mask multiplies. Its content draws into slot 2 in the PARENT's
space, crosses the border, feathers with the parent's ppu, and the
MASK pass writes a scratch, which is returned.
"""
function _apply_mask!(cg::GPUCompositor, rv::GPURenderVM, cam::Camera, cam_u, m::Mask, cur::Int)
    return _with_live(cg, cur) do
        if cg.ms !== nothing
            # a mask's fill is antialiased by the same 4× resolve as a
            # layer's — through the twin, into slot 2
            _content!(cg, rv, m.content, cam_u, cg.ms.view, cg.ms.depth_view, _view(cg, 2), cg.samples,
                      WGPUTextureFormat_RGBA16Float)
        else
            _content!(cg, rv, m.content, cam_u, _view(cg, 2), cg.depth_view, WGPUTextureView(C_NULL), 1,
                      WGPUTextureFormat_RGBA16Float)
        end
        mcur = _quad!(cg, rv, :decode, _scratch(cg, 2); a = 2)
        cg.ppu = cam.width / cam.frame_width  # …so its feather converts there too
        m.feather > 0 && (mcur = _apply_effect!(cg, rv, Blur(m.feather), mcur))
        _with_live(cg, mcur) do
            _quad!(cg, rv, :mask, _scratch(cg, cur); a = cur, b = mcur,
                   params = QuadParams(i0 = (Int32(m.luma), Int32(m.invert), Int32(m.hard))))
        end
    end
end

# ── compositing ─────────────────────────────────────────────────────────

"""
Renders a layer and returns the slot holding it, premultiplied linear:
content through the layer's RESOLVED camera, effects in the layer's world,
then the window, then the mask (drawn with the PARENT camera, applied after
the placement), slot by slot.
"""
function _render_layer!(cg::GPUCompositor, rv::GPURenderVM, cam::Camera, cam_u, layer::Layer;
                        flip_y::Bool = false, depth::Int = 1)
    lcam = layer.camera === nothing ? cam : _resolved_camera(layer, cam)
    lcam_u = layer.camera === nothing ? cam_u : camera_uniforms(lcam; flip_y = !flip_y)
    cur = if layer.content isa Composition
        # precomp: the whole nested stack composes under this layer's camera,
        # and comes out linear already (no decode)
        _compose_into!(cg, rv, lcam, lcam_u, layer.content; flip_y, depth = depth + 1)
    else
        _content_layer!(cg, rv, layer.content, lcam_u)
    end
    # AFTER the content render on purpose: a precomp's recursion sets ppu per
    # inner layer, and this layer's own effects must convert σ through THIS
    # layer's world
    cg.ppu = lcam.width / lcam.frame_width
    for ef in layer.effects
        cur = _apply_effect!(cg, rv, ef, cur)
    end
    layer.window === nothing || (cur = _apply_window!(cg, rv, cam, layer, lcam, cur; flip_y))
    layer.mask === nothing || (cur = _apply_mask!(cg, rv, cam, cam_u, layer.mask, cur))
    return cur
end

"""
Composites `comp` and returns the accumulator slot holding the result
(premultiplied linear, over comp.background). The ping-pong pair is this
depth's own, so a precomp composes without trampling its parent's. `cam` is
this composition's AMBIENT camera.
"""
function _compose_into!(cg::GPUCompositor, rv::GPURenderVM, cam::Camera, cam_u, comp::Composition;
                        flip_y::Bool = false, depth::Int = 1)
    accum = _accums_at!(cg, depth)
    a = 1
    # the accumulator lives in linear, so its ground is decoded here
    _clear!(cg, rv, accum[a], _decode_premult_srgb(comp.background))
    i = 1
    while i <= length(comp.layers)
        layer = comp.layers[i]
        if layer.content === nothing          # adjustment layer
            cg.ppu = cam.width / cam.frame_width   # adjusts the COMPOSITION's world
            cur = accum[a]
            _with_live(cg, accum[1], accum[2]) do
                for ef in layer.effects       # effects over what is BELOW
                    cur = _apply_effect!(cg, rv, ef, cur)
                end
            end
            # the result must live in the accumulator: a scratch would not
            # survive the next layer's chain
            cur == accum[a] || _quad!(cg, rv, :copy, accum[a]; a = cur)
            i += 1
            continue
        end
        _check_layer(layer, i, length(comp.layers))
        cur = _render_layer!(cg, rv, cam, cam_u, layer; flip_y, depth)

        if layer.matte !== nothing            # track matte: layer i+1 (AE)
            matte = comp.layers[i+1]
            # the matte's content draws with ITS camera when it has one
            mcam_u = matte.camera === nothing ? cam_u :
                     camera_uniforms(_resolved_camera(matte, cam); flip_y = !flip_y)
            # slot 3 is about to be redrawn: a layer still sitting in it moves
            cur == 3 && (cur = _quad!(cg, rv, :copy, _scratch(cg, 3); a = 3))
            cur = _with_live(cg, cur) do
                mcur = _content_layer!(cg, rv, matte.content, mcam_u)
                _with_live(cg, mcur) do
                    _quad!(cg, rv, :mask, _scratch(cg, cur); a = cur, b = mcur, params = QuadParams(
                        i0 = (Int32(layer.matte in (:luma, :luma_inv)),
                              Int32(layer.matte in (:alpha_inv, :luma_inv)), Int32(0))))
                end
            end
            i += 1                            # the matte is consumed (not drawn)
        end

        b = 3 - a                             # accumulator ping-pong
        _quad!(cg, rv, :comb, accum[b]; a = accum[a], b = cur, params = QuadParams(
            i0 = (_BLEND_MODES[layer.blend],), f0 = (Float32(layer.opacity),)))
        a = b
        i += 1
    end
    return accum[a]
end

"The checks a layer has to pass before it is composed: a known blend, and a matte that names a mode and has a layer above it."
function _check_layer(layer::Layer, i::Int, n::Int)
    haskey(_BLEND_MODES, layer.blend) || throw(ArgumentError(
        "unknown blend mode :$(layer.blend) — use one of " *
        join(":" .* String.(sort(collect(keys(_BLEND_MODES)))), ", ")))
    layer.matte === nothing && return nothing
    i + 1 <= n || throw(ArgumentError(
        "matte=:$(layer.matte) with no layer above it — the matte is the " *
        "NEXT layer in the list, which then stops being drawn"))
    layer.matte in (:alpha, :luma, :alpha_inv, :luma_inv) || throw(ArgumentError(
        "unknown matte :$(layer.matte) — :alpha, :luma, :alpha_inv or :luma_inv"))
    return nothing
end

"The same checks over the whole tree BEFORE a frame opens: a composition that fails them has recorded nothing."
function _validate_composition(comp::Composition)
    n = length(comp.layers)
    for (i, layer) in enumerate(comp.layers)
        layer.content === nothing && continue     # an adjustment layer
        _check_layer(layer, i, n)
        layer.content isa Composition && _validate_composition(layer.content)
    end
    return nothing
end

"""
Drop the frame that was being recorded: the encoder goes without being
finished or submitted, the live list empties, and the next `_begin_frame!`
opens a fresh one. Otherwise an error in the middle of a frame (an effect
with no shader, a user effect that threw, a validation error the device
mailed) would leave `cg.enc` set, and every later frame on that compositor
would answer «the previous frame was never ended».
"""
function _abort_frame!(cg::GPUCompositor, rv::GPURenderVM)
    if cg.enc != C_NULL
        wgpuCommandEncoderRelease(cg.enc)
        cg.enc = WGPUCommandEncoder(C_NULL)
    end
    empty!(cg.live)
    rv.frame_ring.n = 0
    cg.params.n = 0
    rv.arena.n = 0
    return nothing
end

"The FINAL pass of the composition in `slot` onto `view`, over `background` (decoded), in the convention `premult_out`."
function _final!(cg::GPUCompositor, rv::GPURenderVM, slot::Int, view::WGPUTextureView, format,
                 background::NTuple{4,Float32}, premult_out::Int)
    _quad_view!(cg, rv, :final, view, format; va = _view(cg, slot),
                params = QuadParams(f0 = background, i0 = (premult_out,)))
    return nothing
end

"""
    draw_composition!(rv::GPURenderVM, cg::GPUCompositor, comp, cam; flip_y = false, frame = 0)

Composites `comp` over the camera background straight into the scene
target (no readback), in one command buffer. `flip_y = true` is the
Scene's route and leaves the target upright (row 0 the top); `false` is
the direct route, upside down in memory, for `_render_composition` to flip
on the CPU. `frame` is the scene's frame
index, for the effects that asked for the clock.
"""
function draw_composition!(rv::GPURenderVM, cg::GPUCompositor, comp::Composition, cam::Camera;
                           flip_y::Bool = false, frame::Int = 0)
    (cg.width == rv.width && cg.height == rv.height) ||
        error("the compositor is $(cg.width)×$(cg.height) and the render VM $(rv.width)×$(rv.height)")
    # the camera too: its size sets the pixels-per-unit of every effect
    # (`cg.ppu`), and one of another size (Camera(100×100) on a 480×270
    # compositor) would draw without a word — it is refused
    (cam.width == cg.width && cam.height == cg.height) ||
        error("the camera is $(cam.width)×$(cam.height) and the compositor $(cg.width)×$(cg.height)")
    _validate_composition(comp)               # refused BEFORE a frame opens
    cg.ppu = cam.width / cam.frame_width
    cam_u = camera_uniforms(cam; flip_y = !flip_y)
    _focus!(comp, cam)                        # each Dof's σ from this frame's camera
    _tick!(comp, frame)                       # the frame index, for the effects that asked
    empty!(cg.live)
    _begin_frame!(cg, rv)
    try
        if cg.ms_warm && cg.frames == 0 && cg.ms !== nothing
            # an optional throwaway first composition (`ms_warm`, off by
            # default)
            _compose_into!(cg, rv, cam, cam_u, comp; flip_y)
            _flush!(cg, rv)
            _wait_gpu!(cg.gpu)
        end
        result = _compose_into!(cg, rv, cam, cam_u, comp; flip_y)
        # the exit border: the over with the camera background happens IN
        # LINEAR inside FINAL, and the single OETF writes the target in its
        # convention (encoded straight × α)
        _final!(cg, rv, result, rv.target.view, WGPUTextureFormat_RGBA8Unorm,
                _decode_premult_srgb(cam.background), 1)
        _end_frame!(cg, rv)
    catch
        _abort_frame!(cg, rv)                 # the frame is dropped, not left open
        rethrow()
    end
    return rv
end

"`render_composition`: draw, the synchronous readback, and the CPU flip under `flip_y = false`."
function _render_composition(rv::GPURenderVM, comp::Composition, cam::Camera,
                             cg::Union{Nothing,GPUCompositor}; flip_y::Bool = false, frame::Int = 0)
    cg = cg === nothing ? setup_compositor(rv.gpu, cam.width, cam.height; samples = rv.samples) : cg
    # the VM and the compositor are held through the readback (`_finalize_render_vm!`)
    img = GC.@preserve rv cg begin
        draw_composition!(rv, cg, comp, cam; flip_y, frame)
        read_rgb_topdown(rv)
    end
    flip_y && return img
    return img[:, :, end:-1:1]
end

"""
The layer as-is (premultiplied RGBA → straight RGBA), for inspecting a
layer outside the engine: rendered, FINALed over a zero background straight
into an `rgba8unorm` scratch (`premult_out = 0`) and copied out in the direct
route's layout (row 1 the bottom of the picture — the caller flips). `cam` is
the ambient camera a layer's own camera resolves against; without one a
default at the compositor's resolution stands in. `cam_u` is accepted for
call compatibility and is rebuilt here for the layer's orientation.
"""
function read_layer_rgba(cg::GPUCompositor, rv::GPURenderVM, cam_u, layer::Layer;
                         frame::Int = 0, cam::Union{Nothing,Camera} = nothing)
    _tick!(layer, frame)
    acam = cam === nothing ? Camera(; width = cg.width, height = cg.height) : cam
    cg.ppu = acam.width / acam.frame_width
    cg.referee === nothing && (cg.referee = create_target(cg.gpu, cg.width, cg.height))
    empty!(cg.live)
    _begin_frame!(cg, rv)
    slot = _render_layer!(cg, rv, acam, camera_uniforms(acam; flip_y = true), layer; flip_y = false)
    _final!(cg, rv, slot, cg.referee.view, WGPUTextureFormat_RGBA8Unorm, (0f0, 0f0, 0f0, 0f0), 0)
    _end_frame!(cg, rv)
    return GC.@preserve cg read_rgba_topdown(cg.gpu, cg.referee)
end
