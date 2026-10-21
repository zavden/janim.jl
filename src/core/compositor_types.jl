# core/compositor_types.jl — the After Effects-style compositor,
# the half that is TYPES and GEOMETRY: `Layer`, `Composition`, `Mask`, the
# five blurs, `crop`, the blend modes, the Gaussian weights, the Dof focus
# pass, the per-layer cameras and windows. The passes — the surfaces, the
# quads, the effects' shaders — are the backend's (`backend/wgpu/compositor.jl`).
#
# The design's single primitive: a layer = a texture + its compositing
# parameters. Every Layer renders its mobjects into its own transparent
# offscreen surface in PREMULTIPLIED convention; a Composition is the
# ordered list of layers, and the final pass blends them bottom-up with a
# fullscreen quad and the compositors' standard equation
# (W3C compositing / PDF / SVG):
#
#   C = (1−αs)·Cb_premult + (1−αb)·Cs_premult + αs·αb·B(Cb, Cs)
#   α = αs + αb·(1−αs)
#
# where B is the blend mode over NON-premultiplied colour:
#   normal: Cs · multiply: Cb·Cs · screen: Cb+Cs−Cb·Cs
#   overlay: 2CbCs if Cb≤½, 1−2(1−Cb)(1−Cs) otherwise    (:add is `plus`:
#   a sum of premultiplied values, the classic additive mode of glows)
#
# With B=Cs the equation collapses to Porter-Duff's over.
#
# Colour space: everything BETWEEN the borders is LINEAR premultiplied light,
# and the sRGB encoding exists only at those borders. A one-line specimen
# anchors it: red at 50% over black ends at byte 188 = round(255·OETF(0.5));
# composing raw sRGB says 128. Concretely:
#
#   entry   one decode pass right after every content draw (layer, mask,
#           matte) — mobjects still PAINT through the exact same programs as
#           the direct path, so a layer's picture matches the scene's
#           byte-for-byte before it enters the linear world. For content
#           whose pixels have one owner the pass equals painting in linear
#           outright; where mobjects overlap INSIDE one layer they mix in
#           sRGB exactly like the direct path mixes them. Precomps skip the
#           pass: they come out of _compose_into! already linear.
#   middle  the maths below runs unchanged on linear values — that is the
#           point. The bright-pass thresholds on STRAIGHT colour. Alpha never
#           sees a transfer function: coverage is coverage in every space.
#   exit    one final pass (draw_composition! / read_layer_rgba): the over
#           with the DECODED camera background happens inside the shader,
#           then a single OETF. The scene target keeps its convention
#           (encoded straight × α), so every reader downstream is untouched.
#
# The layer targets are RGBA16F. An f16 linear store costs no output
# precision: max byte error ≈ 2⁻¹¹·slope(OETF)·lin < 0.06 across the range.
#
# Why Manim cannot do any of this: it draws EVERYTHING to the final
# framebuffer in z order; there are no intermediate textures on which to
# apply a mode or a per-group effect. Here it is the initial design.
#
# Adjustment layers: a Layer with no content — its effects apply to whatever
# is already composited below. Precomps: a Composition as a Layer's content,
# rendered to a texture = just another layer (natural recursion). The first
# real effect is Blur (a separable Gaussian in 2 ping-pong passes).
#
# Per-layer cameras. A Layer may carry its own CameraFrame (`camera`)
# and an on-screen placement (`window`) — picture-in-picture, magnifiers,
# minimaps, split screens and 3D multicam are all this one mechanism. The
# division of responsibilities:
#
#   camera   LAYER space   what the content SEES; nothing = the parent's;
#                          inherits down into precomps, inner layers override
#   window   PARENT space  where the finished picture SHOWS: the mobject's
#                          bbox projected through the PARENT camera, with a
#                          central crop to the window's pixel aspect
#   effects  LAYER space   σ in scene units converts through the LAYER's
#                          camera; the window then scales the finished
#                          picture, effects included (AE semantics)
#   mask     PARENT space  the window's shape ON SCREEN — drawn with the
#                          parent camera, applied AFTER the window pass
#   matte    its own       a matte layer's content draws with ITS camera if
#                          it has one, the parent's otherwise
#   light    the WORLD's   light_position comes from the ambient camera for
#                          every view; per-view speculars use camera_position
#
# The layer target carries a real depth attachment: without one,
# apply_depth_test! inside a composition would silently never occlude (no
# depth buffer ⇒ the test always passes): with two spheres, the far one drawn
# last, the scene path shows the near one and a layer would show the far one.

# ── user-facing types ────────────────────────────

"""
    Blur(σ; in_pixels=false)

Separable Gaussian (2 passes). σ is in SCENE UNITS by default (converted
through the camera: the same look at any resolution); mutable → ANIMATABLE by
mutating `sigma` from an updater (the weights are recomputed per frame and are
continuous in σ — no jumps).
"""
mutable struct Blur
    sigma::Float64
    in_pixels::Bool
end
Blur(σ::Real; in_pixels::Bool = false) = Blur(Float64(σ), in_pixels)

"""
    Dof(focus=nothing; aperture=0.4, max_sigma=4.0)

PER-LAYER depth of field: the blur's σ is modulated every frame by the
layer's distance to the camera's focal plane —
σ = min(aperture·|d − focus|, max_sigma), where d is the camera→layer-centre
distance measured along the view axis. `focus=nothing` means the camera's own
focal distance (so with the default camera the plane through the origin is in
focus). It is resolved by `draw_composition!`/`render_composition` (it needs
the 3D Camera).
"""
mutable struct Dof
    focus::Union{Nothing,Float64}
    aperture::Float64
    max_sigma::Float64
    current_sigma::Float64          # recomputed per frame in _focus!
end
Dof(focus = nothing; aperture::Real = 0.4, max_sigma::Real = 4.0) =
    Dof(focus === nothing ? nothing : Float64(focus), Float64(aperture),
        Float64(max_sigma), 0.0)

"Box blur (1 H+V pass with uniform weights). 3 chained ≈ Gaussian (CLT)."
mutable struct BoxBlur
    radius::Float64                 # scene units
end

"Directional blur: a 1D Gaussian along an angle (rad)."
mutable struct DirectionalBlur
    sigma::Float64                  # scene units
    angle::Float64
end

"Radial/zoom blur towards `center_point` (scene coords); strength ∈ [0,1)."
mutable struct RadialBlur
    strength::Float64
    center_point::NTuple{2,Float64}
end
RadialBlur(strength::Real; center_point = (0.0, 0.0)) = RadialBlur(Float64(strength), Float64.(Tuple(center_point)))

"Bright-pass → a pyramid of blurs (σ, 2σ, 4σ) → add."
mutable struct Bloom
    threshold::Float64
    intensity::Float64
    sigma::Float64                  # scene units
end
Bloom(; threshold::Real = 0.6, intensity::Real = 1.0, sigma::Real = 0.15) =
    Bloom(Float64(threshold), Float64(intensity), Float64(sigma))

"""
    Mask(mobjects...; invert=false, feather=0.0, hard=false, luma=false)

A Layer's clipping mask — any VMobject rendered into the alpha channel;
compositing multiplies by it. `feather` = a blur (σ in scene units) OF THE
MASK; `invert` flips it; `hard` thresholds it to a crisp edge; `luma` uses
luminance instead of alpha.
"""
mutable struct Mask
    content::Vector{Mobject}
    invert::Bool
    feather::Float64
    hard::Bool
    luma::Bool
end
Mask(mobs::Mobject...; invert::Bool = false, feather::Real = 0.0,
     hard::Bool = false, luma::Bool = false) =
    Mask(collect(Mobject, mobs), invert, Float64(feather), hard, luma)

mutable struct Layer
    content::Any                    # Vector{Mobject} | Composition | nothing
    blend::Symbol
    opacity::Float64
    effects::Vector{Any}
    mask::Union{Nothing,Mask}
    matte::Union{Nothing,Symbol}    # :alpha/:luma/:alpha_inv/:luma_inv → layer i+1
    # The layer's own point of view and its on-screen placement. The
    # camera field is a CameraFrame, but camera_frame.jl loads AFTER this
    # file, so the field is typed Mobject and the check goes by dispatch
    # (_validate_layer_camera) instead of by annotation.
    camera::Union{Nothing,Mobject}  # CameraFrame: what the content SEES
    window::Union{Nothing,Mobject}  # its projected bbox: where the picture SHOWS
end

# The check an annotation cannot do (load order): nothing passes, a
# CameraFrame passes (the method lives in animation/camera_frame.jl),
# anything else fails saying what to build instead.
_validate_layer_camera(::Nothing) = nothing
_validate_layer_camera(x) = throw(ArgumentError(
    "camera must be a CameraFrame — build one with CameraFrame() and aim it " *
    "with move_to!/set_frame_height!/reorient! (got $(typeof(x)))"))

"""
    Layer(mobjects...; blend=:normal, opacity=1.0, effects=[], mask=nothing,
          matte=nothing, camera=nothing, window=nothing)

Modes: :normal, :add, :multiply, :screen, :overlay. With no mobjects it is an
**adjustment layer** (its effects apply to whatever is composited below) and
it carries nothing but `effects`: a `mask`, an `opacity`, a `blend`, a
`matte`, a `camera` or a `window` on it is an `ArgumentError`.
`matte=:luma|:alpha|:luma_inv|:alpha_inv` consumes the NEXT layer in the list
as a track matte (AE style: the one above, which stops being drawn).

`camera` is a [`CameraFrame`](@ref) of the layer's own — the content renders
through IT instead of the scene camera, which is what a picture-in-picture, a
magnifier, a minimap or a second view of the same 3D world are. `window` is a
mobject whose projected bounding box says where ON SCREEN the finished picture
lands (its largest central crop matching the window's aspect); without one the
layer covers the whole frame, as always. The window mobject is not drawn by
the layer — give it a stroke and put it in a layer above for the border:

```julia
zoom = CameraFrame()
set_frame_height!(zoom, 1.5)                # capture 1.5 scene units tall
move_to!(zoom, focus_point)
display = Rectangle(width = 4.0, height = 2.25)   # 16:9, like the camera frame
to_corner!(display, UR)
Composition(Layer(world),
            Layer(world; camera = zoom, window = display),
            Layer(display))                 # the border on top
```
"""
function Layer(mobs::Mobject...; blend::Symbol = :normal, opacity::Real = 1.0,
               effects = Any[], mask::Union{Nothing,Mask} = nothing,
               matte::Union{Nothing,Symbol} = nothing,
               camera = nothing, window::Union{Nothing,Mobject} = nothing)
    _validate_layer_camera(camera)
    isempty(mobs) && (camera !== nothing || window !== nothing) && throw(ArgumentError(
        "an adjustment layer (no content) cannot carry a camera or a window — " *
        "its effects apply to whatever is already composited below"))
    isempty(mobs) && _check_adjustment(mask, opacity, blend, matte)
    Layer(isempty(mobs) ? nothing : collect(Mobject, mobs),
          blend, Float64(opacity), collect(Any, effects), mask, matte,
          camera, window)
end

# An adjustment layer is its effects and nothing else: the compositor runs
# them over what is below and never reads its mask, opacity, blend or matte
# (`_compose_into!`; `_validate_composition` skips the layer), so carrying one
# would be a silent no-op. Refused by name — the first found, with its value.
function _check_adjustment(mask, opacity, blend, matte)
    field, value = mask !== nothing ? ("mask", "Mask($(length(mask.content)) mobjects)") :
                   opacity != 1 ? ("opacity", repr(opacity)) :
                   blend !== :normal ? ("blend", repr(blend)) :
                   matte !== nothing ? ("matte", repr(matte)) : ("", "")
    isempty(field) && return nothing
    throw(ArgumentError("an adjustment layer (no content) cannot carry $field = $value — " *
                        "its effects apply to what is composited below"))
end

"""
    Composition(layers...; background = (0, 0, 0, 0))

An ordered stack of [`Layer`](@ref)s, composited bottom to top — the editing
timeline the renderer draws instead of one flat list of mobjects.

```julia
use_composition!(scene, Composition(
    Layer(backdrop),
    Layer(glow; blend = :add, effects = [Bloom(; threshold = 0.6)]),
    Layer(formula; opacity = 0.9);
    background = (0, 0, 0, 1)))
```

Each layer is rendered to its own buffer, gets its own effects and mask, and is
then blended into the one below with a W3C blend mode. That is what a plain
scene cannot do: an effect over PART of the picture, a mask with feathered
edges, a glow that adds instead of covering.

The default background is TRANSPARENT, which is what makes a Composition
usable as a precomp — a `Layer(comp)` nests one inside another, and a
transparent ground lets the layers below show through.

With a composition mounted, put your simulation in a scene-level mobject:
`scene.mobjects` is updated BEFORE the layers' contents are drawn.
"""
mutable struct Composition
    layers::Vector{Layer}
    background::NTuple{4,Float32}   # transparent by default (precomp-friendly)
end
Composition(layers::Layer...; background = (0, 0, 0, 0)) =
    Composition(collect(layers), Float32.(Tuple(background)))

"Precomp: a nested Composition as a layer's content."
function Layer(comp::Composition; blend::Symbol = :normal, opacity::Real = 1.0,
               effects = Any[], mask::Union{Nothing,Mask} = nothing,
               matte::Union{Nothing,Symbol} = nothing,
               camera = nothing, window::Union{Nothing,Mobject} = nothing)
    _validate_layer_camera(camera)
    Layer(comp, blend, Float64(opacity), collect(Any, effects), mask, matte,
          camera, window)
end

"""
    crop(base...; minus=nothing, inside=nothing, feather=0.0, hard=false, kw...)

Sugar for building a cut-out from two ordinary
VMobjects. `minus=circle` REMOVES the circle from the base (an inverted mask);
`inside=shape` keeps only what is inside it. Returns a Layer.
"""
function crop(base::Mobject...; minus = nothing, inside = nothing,
              feather::Real = 0.0, hard::Bool = false, kw...)
    (minus === nothing) == (inside === nothing) && throw(ArgumentError(
        "crop needs exactly one of `minus=` (remove) or `inside=` (keep)"))
    shape = something(minus, inside)
    mobs = shape isa Mobject ? [shape] : collect(Mobject, shape)
    Layer(base...; mask = Mask(mobs...; invert = minus !== nothing,
                               feather = Float64(feather), hard), kw...)
end

const _BLEND_MODES = Dict{Symbol,Int32}(:normal => 0, :add => 1, :multiply => 2,
                                  :screen => 3, :overlay => 4)

_sigma_px(cg, σ::Float64, in_pixels::Bool) =                # any compositor with a `ppu`
    in_pixels ? σ : σ * cg.ppu

function _gauss_weights(sigma::Float64)
    # `uniform float weights[64]` in the blur shader is the hard wall, so the
    # truncation is announced rather than silent. The boundary: σ = 21 px asks
    # for exactly 63 and stays quiet; 21.01 px speaks. The weights keep the
    # TRUE σ, renormalised over the radius that fits — a truncated-but-right
    # Gaussian, not a different one.
    requested = max(ceil(Int, 3sigma), 1)
    radius = min(requested, 63)
    requested > 63 && @warn(
        "gaussian-kernel-radius-limit: σ = $(round(sigma; digits = 2)) px asks for " *
        "radius $requested, the shader's weights[64] caps it at 63 — the blur " *
        "will be narrower than requested",
        maxlog = 1)
    weights = Float32[exp(-0.5 * (i / sigma)^2) for i in 0:radius]
    # The normaliser is summed LEFT TO RIGHT (`foldl`), never with `sum`:
    # `sum` reassociates under `@simd`, and from 16 weights on its bits depend
    # on the vector width the compiler picks (measured: σ = 7.3, 21 and
    # 21.01 px give other kernels under `-C haswell`). One order on every
    # machine keeps the kernel identical everywhere.
    weights ./= (weights[1] + 2 * foldl(+, @view(weights[2:end]); init = 0.0f0))
    return radius, weights
end

"""
Pre-pass: resolves the σ of every Dof in the layer tree using the frame's
camera — the LAYER's own when it carries one (a Dof focuses with the
camera that renders it), the ambient otherwise. A layer's depth = the
camera→content-centre distance projected onto the view axis (−R·ẑ).
"""
function _focus!(comp::Composition, cam::Camera)
    for layer in comp.layers
        lcam = layer.camera === nothing ? cam : _resolved_camera(layer, cam)
        layer.content isa Composition && _focus!(layer.content, lcam)
        any(ef -> ef isa Dof, layer.effects) || continue
        cam_pos = get_implied_camera_location(lcam)
        R = quat_to_matrix(lcam.orientation)
        view_dir = -R[:, 3]                    # from the camera into the scene
        for ef in layer.effects
            ef isa Dof || continue
            layer.content isa Vector || (ef.current_sigma = 0.0; continue)
            centers = [SVector{3,Float64}(get_center(m)) for m in layer.content]
            isempty(centers) && (ef.current_sigma = 0.0; continue)
            center_point = sum(centers) / length(centers)
            d = sum((center_point - cam_pos) .* view_dir)
            focus = something(ef.focus, focal_distance(lcam))
            ef.current_sigma = clamp(ef.aperture * abs(d - focus), 0.0, ef.max_sigma)
        end
    end
    return comp
end

"""
The Camera a layer's content renders with: its own frame geometry when it
carries a `camera`, the ambient one otherwise. Pixels and light come from the
AMBIENT — the layer renders at the compositor's resolution whatever the
CameraFrame's `width` says, and light is a property of the world, not of the
view (two views of one 3D scene must agree on where the sun is). Per-view
speculars still differ, because `camera_position` derives from each camera.
"""
function _resolved_camera(layer::Layer, ambient::Camera)
    layer.camera === nothing && return ambient
    lc = layer.camera.camera        # the CameraFrame's live Camera (see field note)
    return Camera(; width = ambient.width, height = ambient.height,
                  frame_width = lc.frame_width, frame_height = lc.frame_height,
                  fovy = lc.fovy, background = ambient.background,
                  light_position = ambient.light_position,
                  orientation = lc.orientation, center_point = lc.center_point)
end

"""
A world point in NDC, with `emit_gl_Position`'s exact arithmetic: view →
frame rescale → perspective divide by w = 1 − z. `fixed` skips the view
matrix, mirroring `is_fixed_in_frame` in the shader.
"""
function _project_ndc(cam::Camera, p::SVector{3,Float64}; flip_y::Bool, fixed::Bool)
    v = if fixed
        p
    else
        V = get_view_matrix(cam)
        SVector{3,Float64}(V[1, 1] * p[1] + V[1, 2] * p[2] + V[1, 3] * p[3] + V[1, 4],
                           V[2, 1] * p[1] + V[2, 2] * p[2] + V[2, 3] * p[3] + V[2, 4],
                           V[3, 1] * p[1] + V[3, 2] * p[2] + V[3, 3] * p[3] + V[3, 4])
    end
    sy = flip_y ? -1.0 : 1.0
    z = v[3] * get_scale(cam) / focal_distance(cam)
    w = 1.0 - z
    return SVector{2,Float64}(v[1] * 2 / FRAME_WIDTH_DEF / w,
                              v[2] * sy * 2 / FRAME_HEIGHT_DEF / w)
end

"""
The window's destination rect in NDC: the mobject's bounding box, projected
corner by corner through the PARENT camera (a 3D parent view still lands the
window somewhere on screen) and enclosed axis-aligned. `nothing` when the
projection is degenerate — a window scaled to nothing shows nothing.
"""
function _window_dst(cam::Camera, win; flip_y::Bool)
    fixed = hasfield(typeof(win), :fixed_in_frame) ? win.fixed_in_frame : false
    bb = get_bounding_box(win)
    lo, hi = bb[1], bb[3]
    x0 = y0 = Inf
    x1 = y1 = -Inf
    for x in (lo[1], hi[1]), y in (lo[2], hi[2]), z in (lo[3], hi[3])
        q = _project_ndc(cam, SVector{3,Float64}(x, y, z); flip_y, fixed)
        x0 = min(x0, q[1]); x1 = max(x1, q[1])
        y0 = min(y0, q[2]); y1 = max(y1, q[2])
    end
    (isfinite(x0) && isfinite(y1) && x1 - x0 > 1e-6 && y1 - y0 > 1e-6) ||
        return nothing
    return (x0, y0, x1, y1)
end

"""
The source crop in uv: the largest CENTRED sub-rect of the layer's view whose
scene-unit aspect matches the window's pixel aspect — so the picture is never
stretched, and a window shaped like the camera frame shows exactly the
camera's full view.
"""
function _window_src(cg, lcam::Camera, dst)                  # any compositor with a size
    dw = (dst[3] - dst[1]) / 2 * cg.width       # window size in pixels
    dh = (abs(dst[4] - dst[2])) / 2 * cg.height
    a = dw / dh
    if lcam.frame_width / lcam.frame_height >= a
        h_r = lcam.frame_height
        w_r = a * h_r
    else
        w_r = lcam.frame_width
        h_r = w_r / a
    end
    su = w_r / lcam.frame_width / 2
    sv = h_r / lcam.frame_height / 2
    return (0.5 - su, 0.5 - sv, 0.5 + su, 0.5 + sv)
end

"""
    render_composition(comp, cam; rv, cg = nothing, flip_y = false, frame = 0)
        → Array{UInt8,3}

Draw a [`Composition`](@ref) and read the result back as an RGB array of
`(3, width, height)`.

The low-level door, for when you are driving the renderer yourself. In a scene
you do not call it: [`use_composition!`](@ref) mounts the composition and the
frame loop takes it from there.

`rv` is the render VM to draw into and `cg` the compositor state (built on
demand if you do not pass one). `frame` is the frame NUMBER, which the
deterministic noise effects need — they derive their pattern from it instead of
calling `rand`, which is what keeps two renders byte-identical.
"""
render_composition(comp::Composition, cam::Camera; rv, cg = nothing, flip_y::Bool = false, frame::Int = 0) =
    _render_composition(rv, comp, cam, cg; flip_y, frame)   # the backend by the rv's type, positionally
