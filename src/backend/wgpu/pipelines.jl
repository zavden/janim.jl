# backend/wgpu/pipelines.jl — the WGSL sources and the state table of the
# renderer as render pipelines.
#
# WebGPU bakes blend, depth test, colour mask, depth mask and depth func into
# a RENDER PIPELINE, immutable, so each combination the frame's pass uses is
# one object here, created on first use and cached by
# `(kind, depth, z_pass, sample_count, format)`:
#
#   stroke ×3   flat (no depth) · the depth prepass (colour mask 0, Z_PASS
#               = 1, depth Less + write) · the colour pass (LessEqual, no
#               write)
#   dots ×2, surface ×2, image ×2, textured_surface ×2   with or without
#               the depth test
#   stencil, stencil_grad   the COUNT of a VMobject's fill into the
#               stencil aspect: colour mask 0, no depth test, IncrementWrap
#               on a front face and DecrementWrap on a back face (the
#               nonzero rule, per sample); the module compiled per sample
#               count, and without the zero-alpha cull for a gradient run
#   cover ×2, cover_grad ×2   the PAINT: the same triangles under
#               `NotEqual 0` (zeroed as they pass, and on a depth fail), the
#               pass's blend; with the depth test `Less` + write and the
#               measured slope bias, without it `Always` and no write — a 2D
#               fill does not touch the z-buffer
#
# They are keyed by the PASS's sample count and format too (the scene's
# target at 4 samples, a layer's content in `rgba16float`), since every
# pipeline of a pass must share both. Every pass uses the same separate
# blend — SrcAlpha/OneMinusSrcAlpha for colour, One/OneMinusSrcAlpha for
# alpha, the coverage accumulation that keeps a transparent target
# premultiplied — and declares the depth-stencil state ALWAYS, because every
# target carries `depth24plus-stencil8`: a mobject that does not depth-test
# gets `Always` with writes off.
#
# The sources are `.wgsl` files beside this one, read at include time into
# constants (so they travel in the precompiled image) with their
# `// #INSERT x.wgsl` lines spliced from `shaders/inserts/`.
# `stroke.wgsl` is compiled twice, with `const Z_PASS` substituted (as
# ManimGL compiles its fill border with `IS_FILL_BORDER`); `stencil.wgsl`
# four times, with `SAMPLES` and `CULL_ALPHA`; the six fill modules with
# `THIN_PX`.

const _WGSL_DIR = joinpath(@__DIR__, "shaders")

"""
    _wgsl(name) → String

The WGSL source `shaders/<name>` with every `// #INSERT x.wgsl` line
replaced by `shaders/inserts/x.wgsl`. Inserts do not nest.
"""
function _wgsl(name::String)
    out = IOBuffer()
    for line in eachline(joinpath(_WGSL_DIR, name))
        m = match(r"^// #INSERT (\S+)\s*$", line)
        if m === nothing
            println(out, line)
        else
            println(out, "// ── ", m[1], " ──")
            print(out, read(joinpath(_WGSL_DIR, "inserts", String(m[1])), String))
            println(out)
        end
    end
    return String(take!(out))
end

const STROKE_WGSL = _wgsl("stroke.wgsl")
const _Z_PASS_OFF = "const Z_PASS: f32 = 0.0;"
const _Z_PASS_ON = "const Z_PASS: f32 = 1.0;"
occursin(_Z_PASS_OFF, STROKE_WGSL) || error("stroke.wgsl must declare `$(_Z_PASS_OFF)`: the prepass module is made by substituting it")
const STROKE_ZPASS_WGSL = replace(STROKE_WGSL, _Z_PASS_OFF => _Z_PASS_ON)
# The prepass writes z on the pixel a thin ribbon's centre line crosses
# (stroke.wgsl: the fragment whose centre lies within Z_CORE PIXELS of the
# curve, besides the ink at alpha ≥ 0.8). 0.5 is the pixel the line passes
# through — a screen-space number, not a scene-unit one — and 0 is the
# alpha rule alone. Substituted when the prepass module is compiled, a Ref
# so a sweep can vary it (a fresh VM per setting: the modules are cached per
# VM); it holds the measured value.
const _Z_CORE_DECL = "const Z_CORE: f32 = 0.5;"
occursin(_Z_CORE_DECL, STROKE_WGSL) || error("stroke.wgsl must declare `$(_Z_CORE_DECL)`: the prepass module substitutes it")
const _STROKE_Z_CORE = Ref{Float32}(0.5f0)
_stroke_zpass_source() = replace(STROKE_ZPASS_WGSL, _Z_CORE_DECL => "const Z_CORE: f32 = $(Float64(_STROKE_Z_CORE[]));")
const TRUE_DOT_WGSL = _wgsl("true_dot.wgsl")
const SURFACE_WGSL = _wgsl("surface.wgsl")
const IMAGE_WGSL = _wgsl("image.wgsl")
const TEXTURED_SURFACE_WGSL = _wgsl("textured_surface.wgsl")
const QUAD_WGSL = _wgsl("quad.wgsl")          # the compositor's ten fragments and two vertices
const EFFECTS_WGSL = _wgsl("effects.wgsl")    # the eleven editor effects
const PRESENT_WGSL = _wgsl("present.wgsl")    # the preview's presentation pass
# Stencil-then-cover: the stencil pass compiled per sample count (the
# fragment places the curve test at the SAMPLES standard positions) and, for
# a gradient run, without the zero-alpha cull (the ramp decides); the two
# covers, flat and gradient
const STENCIL_WGSL = _wgsl("stencil.wgsl")
const COVER_WGSL = _wgsl("cover.wgsl")
const COVER_GRAD_WGSL = _wgsl("cover_grad.wgsl")
const _STENCIL_SAMPLES = "const SAMPLES: u32 = 4u;"
const _STENCIL_CULL = "const CULL_ALPHA: f32 = 1.0;"
(occursin(_STENCIL_SAMPLES, STENCIL_WGSL) && occursin(_STENCIL_CULL, STENCIL_WGSL)) ||
    error("stencil.wgsl must declare `$(_STENCIL_SAMPLES)` and `$(_STENCIL_CULL)`: its variants are made by substituting them")
_stencil_source(samples::Int, grad::Bool) =
    replace(STENCIL_WGSL, _STENCIL_SAMPLES => "const SAMPLES: u32 = $(samples)u;",
            _STENCIL_CULL => grad ? "const CULL_ALPHA: f32 = 0.0;" : _STENCIL_CULL)

"Every module by name, inserts spliced: what `_module!` compiles."
const WGSL_SOURCES = (stroke = STROKE_WGSL, stroke_zpass = STROKE_ZPASS_WGSL,
                      true_dot = TRUE_DOT_WGSL, surface = SURFACE_WGSL,
                      image = IMAGE_WGSL, textured_surface = TEXTURED_SURFACE_WGSL,
                      quad = QUAD_WGSL, effects = EFFECTS_WGSL,
                      present = PRESENT_WGSL,                 # the preview's pass
                      stencil_1 = _stencil_source(1, false), stencil_4 = _stencil_source(4, false),
                      stencil_grad_1 = _stencil_source(1, true), stencil_grad_4 = _stencil_source(4, true),
                      cover = COVER_WGSL, cover_grad = COVER_GRAD_WGSL)
# The thin-triangle cull of the fill (inserts/thin_triangle.wgsl): a
# Loop-Blinn triangle thinner than THIN_PX window pixels — the straight side
# of a polygon or a glyph after an f32 transform — collapses in the three
# shaders of the fill, so lavapipe stops fabricating the NaN sample its
# snapped micro-triangle interpolates (the composited route would keep the
# NaN under every effect, the direct route a black sample). 2⁻⁹ px is the
# measured value (NaN = 0 on lavapipe from 2⁻¹¹ up, RADV unmoved at every
# setting); 0 is ManimGL's two culls alone. Substituted when the six fill
# modules are compiled, a Ref so a sweep can vary it (a fresh VM per
# setting: the modules are cached per VM), like `_STROKE_Z_CORE`.
const _THIN_PX_DECL = "const THIN_PX: f32 = 0.001953125;"
(occursin(_THIN_PX_DECL, STENCIL_WGSL) && occursin(_THIN_PX_DECL, COVER_WGSL) && occursin(_THIN_PX_DECL, COVER_GRAD_WGSL)) ||
    error("stencil.wgsl, cover.wgsl and cover_grad.wgsl must include thin_triangle.wgsl, which declares `$(_THIN_PX_DECL)`: the fill modules substitute it")
const _FILL_THIN_PX = Ref{Float32}(2f0^-9)
const _FILL_MODULES = (:stencil_1, :stencil_4, :stencil_grad_1, :stencil_grad_4, :cover, :cover_grad)
_fill_source(name::Symbol) =
    replace(getfield(WGSL_SOURCES, name), _THIN_PX_DECL => "const THIN_PX: f32 = $(Float64(_FILL_THIN_PX[]));")

"The compiled module `name`, made on first use."
function _module!(rv, name::Symbol)
    m = get(rv.modules, name, nothing)
    m === nothing || return m
    src = name === :stroke_zpass ? _stroke_zpass_source() :      # Z_CORE
          name in _FILL_MODULES ? _fill_source(name) :            # THIN_PX
          getfield(WGSL_SOURCES, name)
    m = compile_wgsl(rv.gpu, src; label = String(name))
    rv.modules[name] = m
    return m
end

# ── vertex layouts ──────────────────────────────────────────────────────

const _F32 = sizeof(Float32)
_attr(fmt, off, loc) = WGPUVertexAttribute(fmt, UInt64(off), UInt32(loc))

# Test hatch: swap the offsets that deliver p1 and p2 of the stroke's point
# slot, so the shader receives the end point as the control point and the
# other way round. The pixels must CHANGE — that is the only way to prove the
# three-attributes-per-slot instancing is what hands the triple over, and not
# a coincidence of layout. Test-only; the pipeline cache has to be emptied
# for it to take.
const _STROKE_SWAP_P1P2 = Ref(false)

"""
The vertex buffers of each kind, as (attributes per slot, layouts). The
attribute vectors are returned so the caller can keep them alive while the
descriptor points into them.
"""
function _vertex_layouts(kind::Symbol)
    x1, x2, x3, x4 = WGPUVertexFormat_Float32, WGPUVertexFormat_Float32x2,
                     WGPUVertexFormat_Float32x3, WGPUVertexFormat_Float32x4
    if kind === :stroke
        # instancing: the expanded triple (p0, p1, p2) per instance — SoA
        # slots stepped per INSTANCE with stride 3·elem, three attributes
        # each at 0, elem, 2·elem; the normal's slot consumes only its
        # central element (the trick ManimGL plays with v_unit_normal[1]).
        # The slots are the arena's EIGHT buffers in the arena's order — point, fill_rgba,
        # stroke_rgba, stroke_width, joint_angle, base_normal, grad_uv,
        # grad_uv_base — so the frame's one pass binds the arena once and
        # the stroke and the fill draws of every run alternate without a
        # rebind (`_bind_arena!`, render.jl). A slot this kind does not
        # read declares ONE attribute the shader never consumes (locations
        # 13–15 here): a layout with no attribute is RENUMBERED by this
        # wgpu-native — the fill's base point came out of another buffer and
        # every curve grew a sliver — and an unconsumed attribute is what the
        # spec allows.
        o1, o2 = _STROKE_SWAP_P1P2[] ? (6_F32, 3_F32) : (3_F32, 6_F32)
        attrs = [[_attr(x3, 0, 0), _attr(x3, o1, 1), _attr(x3, o2, 2)],
                 [_attr(x1, 0, 13)],
                 [_attr(x4, 0, 3), _attr(x4, 4_F32, 4), _attr(x4, 8_F32, 5)],
                 [_attr(x1, 0, 6), _attr(x1, _F32, 7), _attr(x1, 2_F32, 8)],
                 [_attr(x1, 0, 9), _attr(x1, _F32, 10), _attr(x1, 2_F32, 11)],
                 [_attr(x3, 3_F32, 12)],
                 [_attr(x1, 0, 14)], [_attr(x1, 0, 15)]]
        strides = [9_F32, 12_F32, 12_F32, 3_F32, 3_F32, 9_F32, 6_F32, 6_F32]
        step = WGPUVertexStepMode_Instance
    elseif kind in (:stencil, :stencil_grad, :cover, :cover_grad)
        # the fill's triple per instance over the same eight slots —
        # point ×3, fill_rgba ×3 (the culls, the cover's colour), and of
        # base_normal the fan base (element 0) and the unit normal (element
        # 1); the gradient cover adds grad_uv ×3 and the fan base's uv; the
        # other slots carry the unconsumed attribute of the note above
        attrs = [[_attr(x3, 0, 0), _attr(x3, 3_F32, 1), _attr(x3, 6_F32, 2)],
                 [_attr(x4, 0, 3), _attr(x4, 4_F32, 4), _attr(x4, 8_F32, 5)],
                 [_attr(x1, 0, 12)], [_attr(x1, 0, 13)], [_attr(x1, 0, 14)],
                 [_attr(x3, 0, 6), _attr(x3, 3_F32, 7)],
                 [_attr(x1, 0, 15)], [_attr(x1, 0, 9)]]
        if kind === :cover_grad
            attrs[7] = [_attr(x2, 0, 8), _attr(x2, 2_F32, 9), _attr(x2, 4_F32, 10)]
            attrs[8] = [_attr(x2, 0, 11)]
        end
        strides = [9_F32, 12_F32, 12_F32, 3_F32, 3_F32, 9_F32, 6_F32, 6_F32]
        step = WGPUVertexStepMode_Instance
    elseif kind === :dots
        attrs = [[_attr(x3, 0, 0)], [_attr(x1, 0, 1)], [_attr(x4, 0, 2)]]
        strides = [3_F32, _F32, 4_F32]
        step = WGPUVertexStepMode_Instance
    elseif kind === :surface
        attrs = [[_attr(x3, 0, 0)], [_attr(x3, 0, 1)], [_attr(x4, 0, 2)]]
        strides = [3_F32, 3_F32, 4_F32]
        step = WGPUVertexStepMode_Vertex
    elseif kind === :image
        attrs = [[_attr(x3, 0, 0)], [_attr(x2, 0, 1)]]
        strides = [3_F32, 2_F32]
        step = WGPUVertexStepMode_Vertex
    elseif kind === :textured_surface
        attrs = [[_attr(x3, 0, 0)], [_attr(x3, 0, 1)], [_attr(x2, 0, 2)]]
        strides = [3_F32, 3_F32, 2_F32]
        step = WGPUVertexStepMode_Vertex
    else
        error("no vertex layout for kind $kind")
    end
    layouts = [WGPUVertexBufferLayout(step, UInt64(strides[k]), length(attrs[k]),
                                      isempty(attrs[k]) ? Ptr{WGPUVertexAttribute}(C_NULL) : pointer(attrs[k]))
               for k in eachindex(attrs)]
    return attrs, layouts
end

"The blend every pass uses: over in rgb, coverage accumulation in alpha."
const _BLEND = WGPUBlendState(
    WGPUBlendComponent(WGPUBlendOperation_Add, WGPUBlendFactor_SrcAlpha, WGPUBlendFactor_OneMinusSrcAlpha),
    WGPUBlendComponent(WGPUBlendOperation_Add, WGPUBlendFactor_One, WGPUBlendFactor_OneMinusSrcAlpha))

const _STENCIL_OFF = WGPUStencilFaceState(WGPUCompareFunction_Always, WGPUStencilOperation_Keep,
                                          WGPUStencilOperation_Keep, WGPUStencilOperation_Keep)

# The stencil fill's three face states: the count (IncrementWrap on a
# front face, DecrementWrap on a back face — the nonzero rule, per sample),
# and the cover's test (NotEqual the reference 0, wgpu's default; Zero on
# pass AND on a depth fail, so no count outlives its mobject; Keep on a
# stencil fail, where it is zero already)
const _STENCIL_COUNT_FRONT = WGPUStencilFaceState(WGPUCompareFunction_Always, WGPUStencilOperation_Keep,
                                                  WGPUStencilOperation_Keep, WGPUStencilOperation_IncrementWrap)
const _STENCIL_COUNT_BACK = WGPUStencilFaceState(WGPUCompareFunction_Always, WGPUStencilOperation_Keep,
                                                 WGPUStencilOperation_Keep, WGPUStencilOperation_DecrementWrap)
const _STENCIL_COVER = WGPUStencilFaceState(WGPUCompareFunction_NotEqual, WGPUStencilOperation_Keep,
                                            WGPUStencilOperation_Zero, WGPUStencilOperation_Zero)

# The strokes win the tie: the depth-tested cover yields by a constant number
# of depth quanta plus a multiple of its own depth slope per pixel (the
# hardware bias, `depthBias` and `depthBiasSlopeScale` of the pipeline
# state), so a stroke on the same plane — its ribbon a billboard whose far half
# lies BEHIND a tilted face by up to the face's slope times the half
# width — passes `LessEqual` whole when drawn after the face, and a
# stroke behind a face by more than the bias stays hidden. The two
# numbers are MEASURED (RADV and lavapipe alike, a tilted face at φ = 40° and
# a face-on one), never guessed:
#
#   K quanta alone (1 … 64): the wire's line after the face 15 → 20 % seen
#     of an ideal 67 % — a constant cannot reach a slope's worth of depth;
#   M = 0.5: 58 %; M = 1: 66.7 % = the ideal, and a 4-wide line 80 % of
#     its 89 % (its outer apron pixel); M = 2: both whole;
#   face-on, any K: the tie already goes to the stroke (after = ideal,
#     before = the core, K moves nothing);
#   the line 0.05 behind: 0 % under every setting.
#
# So K = 0 and M = 1: the smallest push that makes the specimen's own
# line whole. (M = 2 is the next notch, for strokes wider than ~3 px;
# every fill then yields two pixels of its own slope to whatever is drawn
# on it.) What no bias can do — measured too — is protect a line drawn
# BEFORE an opaque face: its antialiasing apron writes no depth (the prepass
# discards below alpha 0.8) and the face paints over it; the order is the
# scene's to give. The Refs exist so a sweep can vary them (a fresh VM per
# setting: the pipelines are cached per VM) and hold the measured values.
const _COVER_DEPTH_BIAS = Ref{Int32}(0)
const _COVER_DEPTH_SLOPE = Ref{Float32}(1f0)

"The depth-stencil attachment of every target: 24-bit depth, the fill's count in the stencil."
const _DS_FORMAT = WGPUTextureFormat_Depth24PlusStencil8

"""
A render pipeline over `shader` (vs_main / fs_main) with the blend, the
target format and the state the caller names; the `depth24plus-stencil8`
attachment always declared, with the stencil face states and the depth
bias the caller names.
"""
function _render_pipeline(gpu::GPU, label::String, layout::WGPUPipelineLayout,
                          shader::WGPUShaderModule, kind::Symbol;
                          topology = WGPUPrimitiveTopology_TriangleList,
                          depth_compare = WGPUCompareFunction_Always,
                          depth_write::Bool = false,
                          write_mask = WGPUColorWriteMask_All,
                          sample_count::Int = 1,
                          format = WGPUTextureFormat_RGBA8Unorm,
                          blend_state::WGPUBlendState = _BLEND,
                          stencil_front::WGPUStencilFaceState = _STENCIL_OFF,
                          stencil_back::WGPUStencilFaceState = _STENCIL_OFF,
                          depth_bias::Integer = 0,
                          depth_bias_slope::Real = 0)
    attrs, layouts = _vertex_layouts(kind)
    blend = Ref(blend_state)
    targets = [WGPUColorTargetState(C_NULL, format,
                                    Base.unsafe_convert(Ptr{WGPUBlendState}, blend), write_mask)]
    frag = Ref(WGPUFragmentState(C_NULL, shader, _sv(_FS_MAIN), 0, C_NULL,
                                 length(targets), pointer(targets)))
    ds = Ref(WGPUDepthStencilState(C_NULL, _DS_FORMAT,
                                   depth_write ? WGPUOptionalBool_True : WGPUOptionalBool_False,
                                   depth_compare, stencil_front, stencil_back,
                                   0xffffffff, 0xffffffff, Int32(depth_bias), Float32(depth_bias_slope), 0f0))
    desc = Ref(WGPURenderPipelineDescriptor(
        C_NULL, _sv(label), layout,
        WGPUVertexState(C_NULL, shader, _sv(_VS_MAIN), 0, C_NULL, length(layouts),
                        isempty(layouts) ? C_NULL : pointer(layouts)),
        WGPUPrimitiveState(C_NULL, topology, WGPUIndexFormat_Undefined, WGPUFrontFace_CCW,
                           WGPUCullMode_None, 0),
        Base.unsafe_convert(Ptr{WGPUDepthStencilState}, ds),
        WGPUMultisampleState(C_NULL, UInt32(sample_count), 0xffffffff, 0),
        Base.unsafe_convert(Ptr{WGPUFragmentState}, frag)))
    pipe = GC.@preserve label attrs layouts blend targets frag ds desc _error_scope(gpu) do
        wgpuDeviceCreateRenderPipeline(gpu.device, desc)
    end
    pipe == C_NULL && throw(GPUValidationError("wgpuDeviceCreateRenderPipeline returned NULL for $label"))
    _GPU_OBJECTS[] += 1
    return pipe
end

const _PIPELINE_LABELS = Dict{Tuple{Symbol,Bool,Bool},String}()
function _pipeline_label(kind, depth, z_pass)
    get!(_PIPELINE_LABELS, (kind, depth, z_pass)) do
        string("Janim ", kind, depth ? " · depth" : "", z_pass ? " · z prepass" : "")
    end
end

"""
The pipeline of `(kind, depth, z_pass)` at the sample count of the PASS
that draws it and onto its `format` (`rgba8unorm` for the scene,
`rgba16float` for a layer's content), made on first use.
"""
function _pipeline!(rv, kind::Symbol, depth::Bool, z_pass::Bool, samples::Int = 1,
                    format = WGPUTextureFormat_RGBA8Unorm)
    key = (kind, depth, z_pass, samples, format)
    p = get(rv.pipelines, key, nothing)
    p === nothing || return p
    label = _pipeline_label(kind, depth, z_pass)
    if kind === :stencil || kind === :stencil_grad
        # The count — no colour, no depth test (the interior is marked
        # whatever occludes it; the cover tests), the stencil ops by face;
        # the module of this pass's sample count
        (depth || z_pass) && error("the stencil pass neither depth-tests nor prepasses: the cover does")
        samples in (1, 4) || error("the stencil module is compiled for 1 or 4 samples, not $samples")
        shader = _module!(rv, Symbol(kind, :_, samples))
        p = _render_pipeline(rv.gpu, label, rv.pipeline_layout, shader, kind; format, sample_count = samples,
                             write_mask = WGPUColorWriteMask_None,
                             stencil_front = _STENCIL_COUNT_FRONT, stencil_back = _STENCIL_COUNT_BACK)
    elseif kind === :cover || kind === :cover_grad
        # The paint — the same triangles under NotEqual 0, zeroed as they
        # pass; the pass's own blend (straight colour, coverage accumulation
        # in alpha); with the depth test Less + write and the slope bias,
        # without it Always and no write (a 2D fill does not touch the
        # z-buffer)
        z_pass && error("z_pass is the stroke's alone")
        layout = kind === :cover_grad ? rv.pipeline_layout_tex : rv.pipeline_layout
        p = _render_pipeline(rv.gpu, label, layout, _module!(rv, kind), kind; format, sample_count = samples,
                             stencil_front = _STENCIL_COVER, stencil_back = _STENCIL_COVER,
                             depth_compare = depth ? WGPUCompareFunction_Less : WGPUCompareFunction_Always,
                             depth_write = depth,
                             depth_bias = depth ? _COVER_DEPTH_BIAS[] : 0,
                             depth_bias_slope = depth ? _COVER_DEPTH_SLOPE[] : 0f0)
    elseif kind === :stroke
        shader = _module!(rv, z_pass ? :stroke_zpass : :stroke)
        p = if !depth
            # flat: no test, no write, colour
            _render_pipeline(rv.gpu, label, rv.pipeline_layout, shader, kind; format, sample_count = samples)
        elseif z_pass
            # the depth-only prepass — colour mask 0, Less + write,
            # and the module whose fragment discards the AA apron
            _render_pipeline(rv.gpu, label, rv.pipeline_layout, shader, kind; format, sample_count = samples,
                             depth_compare = WGPUCompareFunction_Less, depth_write = true,
                             write_mask = WGPUColorWriteMask_None)
        else
            # the colour pass against its own prepass z: LessEqual, no write
            _render_pipeline(rv.gpu, label, rv.pipeline_layout, shader, kind; format, sample_count = samples,
                             depth_compare = WGPUCompareFunction_LessEqual, depth_write = false)
        end
    else
        z_pass && error("z_pass is the stroke's alone")
        shader = _module!(rv, kind === :dots ? :true_dot : kind)
        layout = kind in (:image, :textured_surface) ? rv.pipeline_layout_tex : rv.pipeline_layout
        topology = kind === :image ? WGPUPrimitiveTopology_TriangleStrip : WGPUPrimitiveTopology_TriangleList
        p = _render_pipeline(rv.gpu, label, layout, shader, kind; topology, format, sample_count = samples,
                             depth_compare = depth ? WGPUCompareFunction_Less : WGPUCompareFunction_Always,
                             depth_write = depth)
    end
    rv.pipelines[key] = p
    return p
end
