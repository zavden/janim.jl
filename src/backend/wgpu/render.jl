# backend/wgpu/render.jl — the frame on WebGPU: the render VM, the draw loop,
# and the frame's one pass.
#
#   · `_draw_list!` walks the roots in runs (one run per root, cut at a
#     DotCloud, a Surface, an image, a gradient, a depth-tested member, a
#     change of batch key, the end of a root), using the cached records of
#     records.jl. What it produces is a LIST of draws (`DrawCmd`), because the
#     pass is encoded AFTER the walk: the walk uploads the buffers and stages
#     the mobject blocks, and only then does the arena know how many blocks the
#     frame needs.
#   · A frame is ONE render pass — begin (clear colour to the camera's
#     background, depth to 1, the stencil to 0), every draw, end, submit. A
#     render pass costs 7.5–20 µs on RADV and 55 on lavapipe.
#   · The fill is stencil-then-cover, two draws per VMobject inside that one
#     pass: the COUNT of its curves' triangles into the stencil aspect by the
#     nonzero rule (stencil.wgsl: IncrementWrap on a front face, DecrementWrap
#     on a back face, the curve's coverage per sample through `sample_mask`),
#     then the COVER of the same triangles where the count is not zero
#     (cover.wgsl: the colour, once per sample, zeroing the count; the
#     triangle's own z, tested and written when the mobject depth-tests, with
#     a measured slope bias so a stroke on the same plane wins the tie). The
#     4× resolve of the pass is the fill's antialiasing: the scene target has
#     a multisample twin unless `samples = 1` is asked.
#   · The frame's pass is RECORDED into whatever encoder and onto whatever
#     target the caller names (`_record_frame!`): the scene target for
#     `draw_scene!`, a layer's slot for the compositor (compositor.jl), which
#     draws several such frames into one command buffer. With MSAA the pass
#     renders into the multisample twin of the target and resolves into it
#     through `resolveTarget`. The frame block lives in a RING with a dynamic
#     offset, one slot per camera a frame draws with (a composition draws with
#     several).
#   · `flip_y` is accepted and ignored: WebGPU's framebuffer has its origin
#     at the top-left, so `camera_uniforms(cam; flip_y = false)` already
#     lands row 0 on top.
#   · The stroke with a depth test is two draws in the same pass — the
#     prepass (colour mask 0, Z_PASS = 1, Less + write) and the colour pass
#     (LessEqual, no write).
#   · The vertex arena's eight buffers are bound ONCE per pass (`_bind_arena!`):
#     every arena pipeline declares the eight slots, so a run's count, cover
#     and stroke draws alternate with no rebind (thousands of runs a frame in
#     the heaviest scenes).

const _GPU_PASSES = Ref(0)          # render passes begun

const _FRAME_LABEL = "Janim frame uniforms"
const _FRAME_BG_LABEL = "Janim frame bind group"
const _SAMPLER_LABEL = "Janim sampler"
const _FRAME_RING_SLOTS = 64        # cameras per frame before the compositor flushes

"""
    setup_render_vm(gpu, width, height; samples = 0) → GPURenderVM

The renderer's VM on `gpu`: the scene target with its depth-stencil
attachment and its multisample twin (the twin is the fill's antialiasing, so
`samples = 0` means 4 and `1` is the aliased control), the
three bind group layouts, the frame ring, the mobject arena, the vertex
arena, the sampler; pipelines and modules are made on first use. A device
without `float32-filterable` (asked for at creation, context.jl) cannot
sample a gradient's `rgba32float` ramp and errors by name.
"""
function setup_render_vm(gpu::GPU, width::Int, height::Int; samples::Int = 0)
    samples >= 0 || throw(ArgumentError("samples must be ≥ 0 (0 = the fill's 4× resolve, 1 = no multisampling, 4 = manimlib's 3D value)"))
    samples in (0, 1, 4) || throw(ArgumentError("samples = $samples: WebGPU renders at 1 or 4 samples (0 = the default, 4)"))
    # the 4× resolve IS the fill's antialiasing
    samples == 0 && (samples = 4)
    :float32_filterable in gpu.features ||
        error("the device lacks float32-filterable: a gradient's rgba32float ramp is sampled LINEAR; " *
              "render on an adapter that has it (JANIM_ADAPTER=<name>, or JANIM_HEADLESS=1 for lavapipe)")
    target = create_target(gpu, width, height; depth = true)
    ms = samples > 1 ? create_target(gpu, width, height; depth = true, samples) : nothing
    layout_frame = _uniform_layout(gpu, FRAME_UNIFORMS_BYTES, "Janim frame layout"; dynamic = true)
    layout_mob = _uniform_layout(gpu, MOBJECT_UNIFORMS_BYTES, "Janim mobject layout"; dynamic = true)
    layout_tex = _texture_layout(gpu, "Janim texture layout")
    pl = _pipeline_layout(gpu, [layout_frame, layout_mob], "Janim pipeline layout")
    pl_tex = _pipeline_layout(gpu, [layout_frame, layout_mob, layout_tex], "Janim textured pipeline layout")
    frame_ring = ParamArena{FrameUniforms}(gpu, _FRAME_LABEL; capacity = _FRAME_RING_SLOTS)
    frame_bg = _bind_group(gpu, layout_frame,
                           [WGPUBindGroupEntry(C_NULL, 0, frame_ring.buffer, 0, UInt64(FRAME_UNIFORMS_BYTES),
                                               WGPUSampler(C_NULL), WGPUTextureView(C_NULL))],
                           _FRAME_BG_LABEL)
    arena = UniformArena(gpu, layout_mob)
    varena = VertexArena(gpu)
    sdesc = Ref(WGPUSamplerDescriptor(C_NULL, _sv(_SAMPLER_LABEL),
                                      WGPUAddressMode_ClampToEdge, WGPUAddressMode_ClampToEdge,
                                      WGPUAddressMode_ClampToEdge, WGPUFilterMode_Linear,
                                      WGPUFilterMode_Linear, WGPUMipmapFilterMode_Nearest,
                                      0f0, 32f0, WGPUCompareFunction_Undefined, 1))
    sampler = GC.@preserve sdesc _error_scope(gpu) do
        wgpuDeviceCreateSampler(gpu.device, sdesc)
    end
    sampler == C_NULL && throw(GPUValidationError("wgpuDeviceCreateSampler returned NULL"))
    _GPU_OBJECTS[] += 1
    rv = GPURenderVM(gpu, target, ms, width, height, samples,
                     layout_frame, layout_mob, layout_tex,
                     pl, pl_tex, Dict{Symbol,WGPUShaderModule}(),
                     Dict{Tuple{Symbol,Bool,Bool,Int,WGPUTextureFormat},WGPURenderPipeline}(),
                     frame_ring, frame_bg, arena, varena, sampler,
                     Dict{UInt64,GPUTextureEntry}(), Dict{UInt64,GPURampEntry}(),
                     GPUDrawCache(), DrawCmd[],
                     Any[], Any[], Ref{UInt32}(0), UInt8[], WGPUBuffer(C_NULL), false)
    finalizer(_finalize_render_vm!, rv)
    return rv
end

"""
    close_render_vm!(rv; targets = true)

Release everything the VM made — records, textures, ramps, pipelines,
modules, the arena, the frame ring, the layouts, the sampler and, with
`targets`, the scene target and its multisample twin — in an order the
device accepts. Idempotent. The explicit close (the Scene's, the live
loop's) closes everything; the finalizer is
[`_finalize_render_vm!`](@ref), which leaves the targets to their own.
"""
function close_render_vm!(rv::GPURenderVM; targets::Bool = true)
    rv.closed && return nothing
    rv.closed = true
    _drain_pending!(rv)
    for mir in values(rv.cache.mirrors)
        for r in mir.runs
            _release!(rv, r)
        end
    end
    empty!(rv.cache.mirrors)
    for rec in values(rv.cache.meshes)
        _release!(rv, rec)
    end
    empty!(rv.cache.meshes)
    for rec in rv.ephemeral
        _release!(rv, rec)
    end
    empty!(rv.ephemeral)
    _drain_pending!(rv)
    _release!(rv.varena)
    foreach(_release_texture!, values(rv.tex_cache))
    empty!(rv.tex_cache)
    foreach(_release_ramp!, values(rv.ramp_cache))
    empty!(rv.ramp_cache)
    foreach(wgpuRenderPipelineRelease, values(rv.pipelines))
    empty!(rv.pipelines)
    foreach(wgpuShaderModuleRelease, values(rv.modules))
    empty!(rv.modules)
    _release!(rv.arena)
    wgpuBindGroupRelease(rv.frame_bg)
    _release!(rv.frame_ring)
    wgpuSamplerRelease(rv.sampler)
    wgpuPipelineLayoutRelease(rv.pipeline_layout_tex)
    wgpuPipelineLayoutRelease(rv.pipeline_layout)
    wgpuBindGroupLayoutRelease(rv.layout_tex)
    wgpuBindGroupLayoutRelease(rv.layout_mob)
    wgpuBindGroupLayoutRelease(rv.layout_frame)
    if rv.staging != C_NULL
        wgpuBufferDestroy(rv.staging)
        wgpuBufferRelease(rv.staging)
        rv.staging = WGPUBuffer(C_NULL)
    end
    if targets
        rv.ms === nothing || close_target!(rv.ms)
        close_target!(rv.target)
    end
    return nothing
end

"""
    _finalize_render_vm!(rv)

The VM's finalizer: `close_render_vm!` without the targets. A finalizer may
only release what nothing else can reach, and `rv.target` and `rv.ms` are
`GPUTarget`s with a finalizer of their own that a caller may still hold:
`read_rgb_topdown(rv)` takes `rv.gpu` and `rv.target` and names the VM no
more, so a function-local VM unused after the call is unreachable during its
own readback, and a collection landing there would run `close_render_vm!`,
which would release the very texture the copy was about to name — wgpu-core
panics on the freed handle (`Texture[Id(4,1)] does not exist`) and the
process aborts. The targets fall when they are unreachable themselves.
"""
_finalize_render_vm!(rv::GPURenderVM) = close_render_vm!(rv; targets = false)

"A closed VM never reaches wgpu — its buffers and pipelines are released (see `_check_open`)."
function _check_open(rv::GPURenderVM, what::AbstractString)
    rv.closed && throw(GPUValidationError("the render VM was closed before $what: its objects are released"))
    return nothing
end

# what the Scene calls on close, whichever backend it holds
_close_render_vm!(rv::GPURenderVM) = close_render_vm!(rv)
_close_render_vm!(::Any) = nothing
"""
Closing a GPU held as a context closes it — unless it is the process's
shared one, which every Scene borrows and nobody closes.
"""
close_context(gpu::GPU) = (gpu === _SHARED_GPU[] || close_gpu!(gpu); nothing)

"Start a draw list: no commands."
function _reset_draw!(rv::GPURenderVM)
    empty!(rv.cmds)
    return nothing
end

# ── the draw loop ───────────────────────────────────────────────────────

_push_cmd!(rv::GPURenderVM, kind, depth, z_pass, block, rec, vertices, instances, tex = WGPUBindGroup(C_NULL)) =
    push!(rv.cmds, DrawCmd(kind, depth, z_pass, block, rec, vertices, instances, tex))

"""
One run: the FILL of each member that has one as its count and its cover
(two draws per VMobject over the record's span — its subpaths counted
together, its siblings painted in order each with its alpha), and the run's
STROKE as one instanced draw (two with a depth test) after all of them, as
ManimGL draws a family's fills before its strokes. The data lives in the
run's record and is only expanded and uploaded for the members whose rows
changed.
"""
function _draw_run!(rv::GPURenderVM, run, cam_u; grad::Union{Nothing,FillGradient} = nothing)
    first = run[1]
    rec = _run_record!(rv, run, grad)
    _DRAW_RUNS[] += 1
    _DISABLE_DRAW_CACHE[] && push!(rv.ephemeral, rec)
    rec.n > 0 || return rv
    fixed = first.fixed_in_frame
    # a gradient run faded to nothing draws no fill at all — its cover would
    # blend nothing and still write its depth (cover.wgsl)
    draw_fill = any(rec.fills) && !(grad !== nothing && fill_gradient_opacity(first) == 0)
    block = _push_block!(rv.arena, MobjectUniforms(;
        shading = first.shading,
        is_fixed_in_frame = Float32(fixed),
        anti_alias_width = 1.5f0,
        joint_type = _JOINT_CODE[first.joint_type],   # :auto unless asked
        flat_stroke = 0f0,
        stroke_width_in_scene_units = 0f0,
        grad_focus = grad === nothing ? (0f0, 0f0, 0f0) : (grad.focus[1], grad.focus[2], 0f0),
        grad_kind = grad === nothing ? 0f0 : (grad.kind === :radial ? 1f0 : 0f0),
        spread_mode = grad === nothing ? 0f0 : Float32(grad.spread),
        grad_opacity = grad === nothing ? 1f0 : fill_gradient_opacity(first)))
    if draw_fill
        tex = grad === nothing ? WGPUBindGroup(C_NULL) : _ensure_ramp!(rv, grad.ramp)
        count_kind = grad === nothing ? :stencil : :stencil_grad
        cover_kind = grad === nothing ? :cover : :cover_grad
        for i in eachindex(run)
            rec.fills[i] || continue
            n = rec.counts[i] ÷ 3
            n > 0 || continue
            f = (rec.base + rec.offsets[i]) ÷ 3
            push!(rv.cmds, DrawCmd(count_kind, false, false, block, rec, 6, n, WGPUBindGroup(C_NULL), f))
            push!(rv.cmds, DrawCmd(cover_kind, first.depth_test, false, block, rec, 6, n, tex, f))
        end
    end
    any(rec.strokes) || return rv
    frame_unit = fixed ? 1f0 : cam_u.frame_scale
    S = _step_budget(rec, frame_unit)
    vertices = 6 * (S - 1)
    instances = rec.n ÷ 3
    if first.depth_test
        _push_cmd!(rv, :stroke, true, true, block, rec, vertices, instances)
        _push_cmd!(rv, :stroke, true, false, block, rec, vertices, instances)
    else
        _push_cmd!(rv, :stroke, false, false, block, rec, vertices, instances)
    end
    return rv
end

function _flush_run!(rv::GPURenderVM, run, cam_u)
    isempty(run) && return nothing
    _draw_run!(rv, run, cam_u)
    empty!(run)
    return nothing
end

"The true_dot pass: six vertices per point, the points as instances."
function _draw_dots!(rv::GPURenderVM, dc, cam_u)
    rec = _mesh_record!(rv, dc, ((0, dc.points, 3), (1, dc.radii, 1), (2, dc.rgba, 4)), nothing)
    _DISABLE_DRAW_CACHE[] && push!(rv.ephemeral, rec)
    block = _push_block!(rv.arena, MobjectUniforms(;
        shading = dc.shading, is_fixed_in_frame = Float32(dc.fixed_in_frame),
        anti_alias_width = Float32(dc.anti_alias_width), glow_factor = Float32(dc.glow_factor)))
    _push_cmd!(rv, :dots, dc.depth_test, false, block, rec, 6, rec.count)
    return nothing
end

"uv Surface: (point, d_normal_point, rgba) + the index buffer, with depth and light."
function _draw_surface!(rv::GPURenderVM, s, cam_u)
    isempty(s.indices) && return nothing
    rec = _mesh_record!(rv, s, ((0, s.points, 3), (1, s.d_normal_points, 3), (2, s.rgba, 4)), s.indices)
    _DISABLE_DRAW_CACHE[] && push!(rv.ephemeral, rec)
    block = _push_block!(rv.arena, MobjectUniforms(;
        shading = s.shading, is_fixed_in_frame = Float32(s.fixed_in_frame)))
    _push_cmd!(rv, :surface, s.depth_test, false, block, rec, rec.count, 1)
    return nothing
end

"The textured quad: four corners as a strip, the texture in group 2."
function _draw_image!(rv::GPURenderVM, im::ImageMobject, cam_u)
    tex = _ensure_texture!(rv, im.pixels)
    rec = _mesh_record!(rv, im, ((0, im.points, 3), (1, _IMAGE_UV, 2)), nothing)
    _DISABLE_DRAW_CACHE[] && push!(rv.ephemeral, rec)
    block = _push_block!(rv.arena, MobjectUniforms(;
        is_fixed_in_frame = Float32(im.fixed_in_frame), opacity = Float32(im.opacity)))
    _push_cmd!(rv, :image, im.depth_test, false, block, rec, 4, 1, tex)
    return nothing
end

"The uv mesh with the texture as its colour, drawn indexed."
function _draw_textured_surface!(rv::GPURenderVM, s::TexturedSurface, cam_u)
    isempty(s.indices) && return nothing
    tex = _ensure_texture!(rv, s.pixels)
    rec = _mesh_record!(rv, s, ((0, s.points, 3), (1, s.d_normal_points, 3), (2, s.uv, 2)), s.indices)
    _DISABLE_DRAW_CACHE[] && push!(rv.ephemeral, rec)
    block = _push_block!(rv.arena, MobjectUniforms(;
        shading = s.shading, is_fixed_in_frame = Float32(s.fixed_in_frame),
        opacity = Float32(s.opacity)))
    _push_cmd!(rv, :textured_surface, s.depth_test, false, block, rec, rec.count, 1, tex)
    return nothing
end

# Only what is drawn cuts a run. An EMPTY DotCloud, ImageMobject, Surface or
# TexturedSurface between two strokes does not flush the run (two runs where
# there was one would put other bytes on the shared antialiased edge): a
# mobject the pass would draw nothing for is not there.
_draws(m::DotCloud) = has_points(m)
_draws(m::ImageMobject) = has_points(m)
_draws(m::Surface) = has_points(m) && !isempty(m.indices)
_draws(m::TexturedSurface) = has_points(m) && !isempty(m.indices)

"The mobject loop: one root at a time, in runs, producing the frame's draw list."
function _draw_list!(rv::GPURenderVM, mobs, cam_u)
    cache = rv.cache
    cache.pass += 1                 # one pass = one camera, one comparison per mobject
    run = VMobject[]
    key = nothing
    for mob in mobs
        for sub in _draw_family(mob)     # z per level, `submobjects` untouched
            if sub isa DotCloud
                _draws(sub) || continue
                _flush_run!(rv, run, cam_u); key = nothing
                _draw_dots!(rv, sub, cam_u)
                continue
            end
            if sub isa Surface
                _draws(sub) || continue
                _flush_run!(rv, run, cam_u); key = nothing
                _draw_surface!(rv, sub, cam_u)
                continue
            end
            if sub isa ImageMobject
                _draws(sub) || continue
                _flush_run!(rv, run, cam_u); key = nothing
                _draw_image!(rv, sub, cam_u)
                continue
            end
            if sub isa TexturedSurface
                _draws(sub) || continue
                _flush_run!(rv, run, cam_u); key = nothing
                _draw_textured_surface!(rv, sub, cam_u)
                continue
            end
            (sub isa VMobject && has_points(sub)) || continue
            grad = active_fill_gradient(sub)    # nothing when the rows diverged
            if grad !== nothing || sub.depth_test || _DISABLE_DRAW_BATCH[]
                _flush_run!(rv, run, cam_u); key = nothing
                push!(run, sub)
                _draw_run!(rv, run, cam_u; grad)
                empty!(run)
                continue
            end
            k = _batch_key(sub)
            if k != key
                _flush_run!(rv, run, cam_u)
                key = k
            end
            push!(run, sub)
        end
        _flush_run!(rv, run, cam_u); key = nothing   # a run never crosses a root
    end
    cache.pass % _SWEEP_EVERY == 0 && _sweep_cache!(rv)
    return rv
end

# ── the passes ──────────────────────────────────────────────────────────

@inline function _vb!(pass, slot::Int, rec, k::Int)
    wgpuRenderPassEncoderSetVertexBuffer(pass, UInt32(slot), rec.bufs[k], UInt64(0), UInt64(rec.sizes[k]))
end

"""
The encoder's state between draws: what is already set is not set again —
the pipeline, the mobject block's offset, the group-2 bind group (a
texture, a ramp), and the vertex arena's eight slots, bound once per pass
and left bound (a mesh draw rebinds its own slots and marks the arena as
gone). `samples` and `format` are the pass's, which every pipeline it sets
must share.
"""
mutable struct _PassState
    pipeline::WGPURenderPipeline
    block::Int
    tex::WGPUBindGroup
    arena_bound::Bool
    samples::Int
    format::WGPUTextureFormat
end
_PassState(samples::Int = 1, format = WGPUTextureFormat_RGBA8Unorm) =
    _PassState(WGPURenderPipeline(C_NULL), -1, WGPUBindGroup(C_NULL), false, samples, format)

@inline function _set_pipeline!(pass, rv, st::_PassState, kind, depth, z_pass)
    pipe = _pipeline!(rv, kind, depth, z_pass, st.samples, st.format)
    if pipe != st.pipeline
        wgpuRenderPassEncoderSetPipeline(pass, pipe)
        st.pipeline = pipe
    end
    return nothing
end

@inline function _set_block!(pass, rv, st::_PassState, block::Int)
    block == st.block && return nothing
    rv.offset_ref[] = UInt32(block * rv.arena.stride)
    wgpuRenderPassEncoderSetBindGroup(pass, UInt32(1), rv.arena.bind_group, Csize_t(1),
                                      Base.unsafe_convert(Ptr{UInt32}, rv.offset_ref))
    st.block = block
    return nothing
end

@inline function _set_tex!(pass, st::_PassState, tex::WGPUBindGroup)
    (tex == C_NULL || tex == st.tex) && return nothing
    wgpuRenderPassEncoderSetBindGroup(pass, UInt32(2), tex, Csize_t(0), C_NULL)
    st.tex = tex
    return nothing
end

"""
The arena's eight buffers at slots 0–7, in the arena's order: every
pipeline that draws from the arena — the stroke, the stencil count, the
covers — declares the eight and reads the ones it needs, so the pass binds
them ONCE and a run's fill and stroke draws alternate without a rebind.
"""
function _bind_arena!(pass, rv::GPURenderVM)
    a = rv.varena
    for k in 1:8
        wgpuRenderPassEncoderSetVertexBuffer(pass, UInt32(k - 1), a.bufs[k], UInt64(0),
                                             UInt64(a.capacity * _ARENA_ELEM[k]))
    end
    return nothing
end

_is_arena_kind(kind::Symbol) = kind === :stroke || kind === :stencil || kind === :stencil_grad ||
                               kind === :cover || kind === :cover_grad

"Record one draw into the destination pass: pipeline, the bind groups, the buffers, the draw."
function _record_draw!(pass, rv::GPURenderVM, cmd::DrawCmd, st::_PassState)
    _set_pipeline!(pass, rv, st, cmd.kind, cmd.depth, cmd.z_pass)
    _set_block!(pass, rv, st, cmd.block)
    _set_tex!(pass, st, cmd.tex)
    if _is_arena_kind(cmd.kind)
        rec = cmd.rec::GPURunRecord
        if !st.arena_bound
            _bind_arena!(pass, rv)
            st.arena_bound = true
        end
        inst0 = cmd.kind === :stroke ? rec.base ÷ 3 : cmd.first
        wgpuRenderPassEncoderDraw(pass, UInt32(cmd.vertices), UInt32(cmd.instances), UInt32(0), UInt32(inst0))
    elseif cmd.kind === :dots
        rec = cmd.rec::GPUMeshRecord
        _vb!(pass, 0, rec, 1); _vb!(pass, 1, rec, 2); _vb!(pass, 2, rec, 3)
        st.arena_bound = false
        wgpuRenderPassEncoderDraw(pass, UInt32(6), UInt32(cmd.instances), UInt32(0), UInt32(0))
    elseif cmd.kind === :image
        rec = cmd.rec::GPUMeshRecord
        _vb!(pass, 0, rec, 1); _vb!(pass, 1, rec, 2)
        st.arena_bound = false
        wgpuRenderPassEncoderDraw(pass, UInt32(4), UInt32(1), UInt32(0), UInt32(0))
    else                                # :surface, :textured_surface
        rec = cmd.rec::GPUMeshRecord
        _vb!(pass, 0, rec, 1); _vb!(pass, 1, rec, 2); _vb!(pass, 2, rec, 3)
        st.arena_bound = false
        wgpuRenderPassEncoderSetIndexBuffer(pass, rec.index, WGPUIndexFormat_Uint32, UInt64(0), UInt64(rec.index_size))
        wgpuRenderPassEncoderDrawIndexed(pass, UInt32(cmd.vertices), UInt32(1), UInt32(0), Int32(0), UInt32(0))
    end
    _DRAW_CALLS[] += 1
    return nothing
end

"""
Begin a render pass over `view` (and `depth_view` when given), counted;
group 0 bound at the frame ring's slot `frame_slot`. `resolve` names the
single-sample texture a multisampled `view` resolves into at the end of
the pass, `store`/`depth_store` what becomes of the attachments.
"""
function _begin_pass!(enc, rv::GPURenderVM, view::WGPUTextureView, load, clear::NTuple{4,Float32},
                      depth_view::WGPUTextureView, depth_load;
                      resolve::WGPUTextureView = WGPUTextureView(C_NULL),
                      store = WGPUStoreOp_Store, depth_store = WGPUStoreOp_Store,
                      frame_slot::Int = 0)
    color = [WGPURenderPassColorAttachment(C_NULL, view, WGPU_DEPTH_SLICE_UNDEFINED,
                                           resolve, load, store,
                                           WGPUColor(Float64(clear[1]), Float64(clear[2]),
                                                     Float64(clear[3]), Float64(clear[4])))]
    # The attachment carries the fill's count — cleared to 0 when the
    # pass opens, dropped when it ends (every cover zeroes what it paints;
    # nothing reads the aspect afterwards)
    ds = Ref(WGPURenderPassDepthStencilAttachment(depth_view, depth_load, depth_store, 1f0, 0,
                                                  WGPULoadOp_Clear, WGPUStoreOp_Discard, 0, 0))
    dsp = depth_view == C_NULL ? Ptr{WGPURenderPassDepthStencilAttachment}(C_NULL) :
          Base.unsafe_convert(Ptr{WGPURenderPassDepthStencilAttachment}, ds)
    desc = Ref(WGPURenderPassDescriptor(C_NULL, _EMPTY_SV, length(color), pointer(color), dsp,
                                        WGPUQuerySet(C_NULL), C_NULL))
    pass = GC.@preserve color ds desc wgpuCommandEncoderBeginRenderPass(enc, desc)
    _GPU_PASSES[] += 1
    rv.offset_ref[] = UInt32(frame_slot * rv.frame_ring.stride)
    wgpuRenderPassEncoderSetBindGroup(pass, UInt32(0), rv.frame_bg, Csize_t(1),
                                      Base.unsafe_convert(Ptr{UInt32}, rv.offset_ref))
    return pass
end

@inline function _end_pass!(pass)
    wgpuRenderPassEncoderEnd(pass)
    wgpuRenderPassEncoderRelease(pass)
    return nothing
end

"""
    _FrameTarget

Where a frame's pass lands: the colour view (the scene target, its
multisample twin, a layer's slot or ITS twin), the depth-stencil view
beside it, the texture the pass resolves into (none at one sample), the
pass's sample count and format, and the frame ring's slot of the camera
the frame draws with.
"""
struct _FrameTarget
    view::WGPUTextureView
    depth_view::WGPUTextureView
    resolve::WGPUTextureView
    samples::Int
    format::WGPUTextureFormat
    frame_slot::Int
end

"""
The frame's ONE pass: clear, every command in order — a member's count and
cover, a run's stroke, the meshes, the clouds, the images — end; resolving
into `tgt.resolve` when the pass is multisampled. A multisampled
attachment is dropped once resolved, and its depth-stencil with it:
nothing reads either afterwards.
"""
function _frame_pass!(enc, rv::GPURenderVM, clear::NTuple{4,Float32}, tgt::_FrameTarget)
    resolving = tgt.resolve != C_NULL
    store = resolving ? WGPUStoreOp_Discard : WGPUStoreOp_Store
    depth_store = tgt.samples > 1 ? WGPUStoreOp_Discard : WGPUStoreOp_Store
    pass = _begin_pass!(enc, rv, tgt.view, WGPULoadOp_Clear, clear, tgt.depth_view, WGPULoadOp_Clear;
                        resolve = resolving ? tgt.resolve : WGPUTextureView(C_NULL),
                        store, depth_store, frame_slot = tgt.frame_slot)
    st = _PassState(tgt.samples, tgt.format)
    for cmd in rv.cmds
        _record_draw!(pass, rv, cmd, st)
    end
    _end_pass!(pass)
    return nothing
end

"""
Record the frame's pass — the draw list as it stands — into `enc`, onto
`tgt`. Nothing is submitted here.
"""
_record_frame!(enc, rv::GPURenderVM, clear::NTuple{4,Float32}, tgt::_FrameTarget) =
    _frame_pass!(enc, rv, clear, tgt)

"The frame target of the scene: the target itself, or its multisample twin resolving into it."
function _scene_target(rv::GPURenderVM, frame_slot::Int)
    ms = rv.ms
    _check_open(rv.target, "the frame's pass")
    ms === nothing || _check_open(ms, "the frame's pass")
    ms === nothing && return _FrameTarget(rv.target.view, rv.target.depth_view, WGPUTextureView(C_NULL),
                                          1, WGPUTextureFormat_RGBA8Unorm, frame_slot)
    return _FrameTarget(ms.view, ms.depth_view, rv.target.view, rv.samples,
                        WGPUTextureFormat_RGBA8Unorm, frame_slot)
end

"""
The frame's pass in one command buffer, submitted: the direct route's
`_record_frame!` onto the scene target. Returns the submission index.
"""
function _encode_frame!(rv::GPURenderVM, clear::NTuple{4,Float32}, frame_slot::Int = 0)
    gpu = rv.gpu
    enc = wgpuDeviceCreateCommandEncoder(gpu.device, C_NULL)
    _record_frame!(enc, rv, clear, _scene_target(rv, frame_slot))
    # an encoding error surfaces HERE, as an exception with wgpu's message:
    # submitting an invalid command buffer is a fatal panic in wgpu-native
    # (the process aborts), and this scope is what keeps it an error
    cmd = _error_scope(gpu) do
        wgpuCommandEncoderFinish(enc, C_NULL)
    end
    wgpuCommandEncoderRelease(enc)
    return _submit!(gpu, cmd)
end

"""
    draw_scene!(rv::GPURenderVM, mobs, cam; flip_y = false)

Draws each mobject's family in order into the VM's target — the frame's
one pass. NO readback: `read_rgb_topdown(rv)` / `read_rgba_topdown(rv)`
and `FramePipeline` decide what to do with it. `flip_y` is accepted and
ignored: the target's row 0 is already the top.
"""
function draw_scene!(rv::GPURenderVM, mobs, cam::Camera; flip_y::Bool = false)
    _check_open(rv, "this frame")
    gpu = rv.gpu
    cam_u = camera_uniforms(cam; flip_y = false)
    rv.frame_ring.n = 0
    slot = _push!(rv.frame_ring, FrameUniforms(cam_u))
    rv.arena.n = 0
    _reset_draw!(rv)
    _draw_list!(rv, mobs, cam_u)                 # records up to date, blocks staged, draws listed
    _upload_blocks!(rv.arena, gpu, rv.layout_mob)
    _upload!(rv.frame_ring, gpu)
    _encode_frame!(rv, cam.background, slot)
    _check_gpu_errors!(gpu)
    _after_submit!(rv)
    return rv
end

"After a frame's submit: the deferred releases, and the test hatch's ephemeral records."
function _after_submit!(rv::GPURenderVM)
    if !isempty(rv.ephemeral)                    # test hatch: build, draw, release
        _wait_gpu!(rv.gpu)
        for rec in rv.ephemeral
            _release!(rv, rec)
        end
        empty!(rv.ephemeral)
    end
    _drain_pending!(rv)
    return nothing
end

# The VM is held for the length of its readback. The call reads `rv.gpu` and
# `rv.target` and would name the VM no more; a collection inside could run its
# finalizer on the target the copy was about to use (`_finalize_render_vm!`
# tells the rest).
read_rgb_topdown(rv::GPURenderVM) = GC.@preserve rv read_rgb_topdown(rv.gpu, rv.target)
read_rgba_topdown(rv::GPURenderVM) = GC.@preserve rv read_rgba_topdown(rv.gpu, rv.target)

"""
The in-place readback: the live loop recycles its cache slots through this,
and the VM keeps the one MapRead staging buffer it needs —
a tick allocates nothing on the GPU and nothing big in Julia.
"""
function read_rgb_topdown!(rv::GPURenderVM, img::Array{UInt8,3})
    _check_open(rv, "its readback")
    rv.staging == C_NULL &&
        (rv.staging = _create_staging(rv.gpu, padded_bytes_per_row(rv.width) * rv.height))
    return GC.@preserve rv read_rgb_topdown!(rv.gpu, rv.target, rv.staging, img)
end

# ── rendering without a Scene ───────────────────────────────

const _SHARED_GPU = Ref{Union{Nothing,GPU}}(nothing)
const _WGPU_SHARED_RVS = Dict{Tuple{Int,Int},GPURenderVM}()

"""
    _shared_gpu() → GPU

The process's ONE GPU: instance, adapter, device and queue, created on the
first call and kept — which lets the daemon serve `janim frame` without
creating a device per request (`create_gpu` is 15 of the 27 ms of a warm
`render_frame`; a VM per Scene is 2.4 ms and stays per Scene). A GPU
that was closed, or whose device is gone (`dead`, set when a
`GPUDeviceLostError` was thrown from it), is replaced on the next call:
every object of the old device is invalid, and so are the shared VMs of
`render_mobjects`, which are dropped with it.
"""
function _shared_gpu()
    gpu = _SHARED_GPU[]
    if gpu === nothing || gpu.closed || gpu.dead
        gpu === nothing || gpu.closed || close_gpu!(gpu)
        gpu = create_gpu()
        _SHARED_GPU[] = gpu
        empty!(_WGPU_SHARED_RVS)
    end
    return gpu
end

"""
A render VM of this size on the shared GPU, for `render_mobjects` without
an `rv`: made once per size, kept for the process.
"""
function _wgpu_render_vm(width::Int, height::Int)
    gpu = _shared_gpu()
    return get!(_WGPU_SHARED_RVS, (width, height)) do
        setup_render_vm(gpu, width, height)
    end
end

"`render_mobjects` on the WebGPU backend: draw_scene! + the synchronous readback."
function render_mobjects_wgpu(mobs, cam::Camera; rv = nothing)
    rv = rv === nothing ? _wgpu_render_vm(cam.width, cam.height) : rv
    draw_scene!(rv, mobs, cam)
    return read_rgb_topdown(rv)
end

"""
    render_mobjects(mobs, cam::Camera; rv = nothing) → Array{UInt8,3} (3×width×height, row 1 on top)

draw_scene! + a synchronous readback. Without an
`rv` the frame is drawn on a render VM of the camera's size kept for the
process (one per size, on the process's GPU); with one, on that VM.
"""
render_mobjects(mobs, cam::Camera; rv = nothing) = render_mobjects_wgpu(mobs, cam; rv)

"""
    setup_render_vm(width, height; samples = 0) → GPURenderVM

A render VM on the PROCESS's GPU (`_shared_gpu`). Nothing has to be opened
first: the GPU is the process's, the VM is yours to `close_render_vm!` (or to
leave to the device, which takes everything with it).
"""
setup_render_vm(width::Int, height::Int; samples::Int = 0) =
    setup_render_vm(_shared_gpu(), width, height; samples)

"Binary PPM, for looking at renders with your eyes."
function save_ppm(path::String, img::Array{UInt8,3})
    open(path, "w") do io
        write(io, "P6\n$(size(img, 2)) $(size(img, 3))\n255\n")
        write(io, img)
    end
    return path
end
