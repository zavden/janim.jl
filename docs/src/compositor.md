# The compositor

A stack of layers, each rendered to its own buffer, each with its own effects
and mask, blended into the one below. This has no Manim equivalent — it is
what makes an effect apply to PART of the picture rather than to all of it.

```julia
function construct(scene)
    use_composition!(scene, Composition(
        Layer(backdrop),
        Layer(glow; blend = :add, effects = [Bloom(; threshold = 0.6)]),
        Layer(formula; opacity = 0.9);
        background = (0, 0, 0, 1)))

    play!(scene, Write(formula))
end
```

**A mounted composition REPLACES `scene.mobjects` as what gets drawn.** If you
mount one and see nothing, that is why. Put anything that must be simulated —
a physics updater, a tracker — in a scene-level mobject: `scene.mobjects` is
updated BEFORE the layers' contents are drawn.

## Layers

```julia
Layer(mobjects...; blend = :normal, opacity = 1.0, effects = [],
                   mask = nothing, matte = nothing,
                   camera = nothing, window = nothing)
Layer(comp; …)        # a nested Composition: a precomp
```

Blend modes: `:normal`, `:add`, `:multiply`, `:screen`, `:overlay` — the W3C
definitions. `:add` is the one that makes light behave like light instead of
like paint.

A `Layer` with no mobjects is an empty one, useful as a ground. A `Layer`
holding a [`Composition`](@ref) is a precomp, which is why the default
background is TRANSPARENT: a nested composition has to let what is below show
through.

## A camera per layer

A layer can carry its own [`CameraFrame`](@ref) and a `window` — and that one
mechanism is the magnifier, the picture-in-picture, the minimap, the split
screen and the 3D multicam. Each such layer is a REAL second render, not a
scaled copy: stroke widths stay put under the zoom, and 3D content occludes
per view, in each layer's own z-buffer.

```julia
zoom = CameraFrame()                    # aim it like scene.frame
set_frame_height!(zoom, 1.5)            # capture 1.5 scene units tall
move_to!(zoom, focus)

display = Rectangle(width = 4.0, height = 2.25)   # 16:9, the frame's shape
to_corner!(display, UR)

use_composition!(scene, Composition(
    Layer(world),                                  # the scene, as always
    Layer(world; camera = zoom, window = display), # the inset: a second render
    Layer(display)))                               # its border, on top
```

The split of responsibilities, each half of which you can lean on:

- **`camera` is what the layer SEES.** It defaults to the scene's camera, it
  animates like `scene.frame` (it IS a `CameraFrame`), it can carry updaters
  — `add_updater!(zoom, f -> move_to!(f, get_center(target)))` is the chase
  camera — and a precomp under a layer with a camera composes entirely under
  it, inner layers overriding at will. An inner camera is SOVEREIGN: the
  parent pastes the precomp's finished picture 1:1 rather than re-projecting
  it, so nested zooms do not multiply — After Effects' rule, and the window
  is what places a finished picture somewhere else.
- **`window` is where the picture SHOWS.** The mobject's bounding box,
  projected through the PARENT camera; the layer draws the largest centred
  cut of its view that matches the window's aspect, so nothing is ever
  stretched — a window shaped like the camera frame shows exactly the
  camera's view, and a square one shows the central square. The window
  mobject itself is not drawn: give it a stroke in a layer above for the
  border, `fix_in_frame!` it when the parent camera flies and the HUD must
  not.
- **Effects run in the layer's world** — a `Blur(σ)` measures scene units as
  that camera sees them — and the window then scales the finished picture,
  effects included. Masks and mattes stay in the PARENT's space: the mask is
  the window's shape on screen, applied after the placement, which is what a
  round magnifier is.

The same world can sit in several layers at once; updaters still run once per
frame (the live list deduplicates by identity). Worked material:
lesson 2.3.2 (the magnifier), `examples/scenes/11_multicam_views.jl` (four views of
one 3D world) and `examples/scenes/12_chase_camera.jl` (chase + minimap + pinned
HUD).

## Masks

```julia
Mask(mobjects...; invert = false, feather = 0.0, hard = false, luma = false)

Layer(content; mask = Mask(window; feather = 0.1))
```

A real per-pixel cut-out, not a stencil of rectangles. `feather` softens the
edge, `invert` cuts the hole instead of keeping it, `luma` uses the mask's
brightness rather than its coverage.

The sugar for the common cases:

```julia
crop(content; inside = window, feather = 0.1)     # keep what is inside
crop(content; minus = hole)                       # cut it out
```

`matte` is the After Effects idea: the layer above stops being drawn and acts
as the track matte for this one.

## Blur and glow

```julia
Blur(σ; in_pixels = false)                  # Gaussian, σ in scene units
BoxBlur(radius)                             # one H+V pass; 3 chained ≈ Gaussian
DirectionalBlur(sigma, angle)               # along one direction
RadialBlur(strength)                        # outwards from the centre
Bloom(; threshold = 0.6, intensity, sigma)  # what is bright, spilled
Dof(focus; aperture = 0.4, max_sigma = 4.0) # depth of field, per layer
```

[`Bloom`](@ref) is the difference between "a yellow circle" and "a light".
[`Dof`](@ref) measures the layer's distance from the focal plane every frame —
see [3D and the camera](three_d.md).

## Editor effects

```julia
Glitch(; intensity = 0.5, seed = 1, rate = 3, rgb_shift = 0.05, slices = 12, block = 0.3)
CRT(; scanlines = 240, scan_depth = 0.35, mask = 0.3, curvature, vignette, roll)
VHS(; chroma_bleed = 0.15, jitter = 0.04, noise, head_switch)
ColorAdjust(; brightness = 1.0, contrast = 1.0, saturation = 1.0, hue = 0.0)
Pixelate(size = 0.2)
Vignette(; amount = 0.5, radius = 0.5, feather = 0.4)
Grain(; amount = 0.15, seed = 1, rate = 1, levels = 8)
ChromaticAberration(amount = 0.1)
Sharpen(amount = 0.6; sigma = 0.05)
Wave(; amplitude = 0.1, wavelength = 1.5, angle = 0.0, phase = 0.0)
EdgeDetect(; amount, color)
```

Four rules hold across all of them, and they are worth knowing because they
make the dials predictable:

- **Every dial's zero is an exact no-op** — the pass is skipped entirely, not
  applied with a neutral parameter.
- **`rate` counts FRAMES**, not seconds. A `rate = 3` glitch changes its
  pattern every third frame regardless of the frame rate.
- **Geometric sizes are in SCENE UNITS**, like everything else, so an effect
  looks the same at every resolution.
- **The pattern comes from the frame number, never from `rand`.** That is what
  keeps a noisy render byte-reproducible.

Two of them reward being animated from an updater: `CRT`'s `roll` is a
television losing sync, and `Wave`'s `phase` is a travelling wave.

## Determinism with high-frequency content

Noise effects and fine textures render the same frames in every process. The
WebGPU drivers compile their pipelines at creation and have no shader
variant to swap in later, so there is no driver knob to set ([`strict_gl_status`](@ref)
says so): six cold processes writing the same file give one file, in RADV and
in lavapipe.

For a byte-reproducible mp4 of blurred or high-contrast content also pass
`encoder_threads = 1` when the mp4's bytes (not just its frames) must repeat: x264's
multithreaded default is bit-stable on one machine but not a promise.

The CPU route (`JANIM_HEADLESS=1`, lavapipe) needs one more guard that the GPU
adapter does not: a straight edge of a filled shape could fabricate a NaN
texel — the Loop-Blinn triangle of a straight side is 10⁻⁶ px thin
after an f32 transform, lavapipe rasterises it on its 1/256 px grid and
interpolates it with a float area of 0. The layers are rgba16float, so the
NaN would survive the resolve and every effect (under `Sharpen` it would open
a hole the size of the kernel). The fill therefore culls any
triangle thinner than `THIN_PX = 2⁻⁹` window pixels in its three shaders
(`shaders/inserts/thin_triangle.wgsl`); a pure-black `(0, 0, 0)` pixel in a
composited frame over a non-black background is the signature of a NaN texel.

## Writing your own effect

A layer effect is a mutable struct, a WGSL fragment registered once, and
one method:

```julia
effect_shader!(:my_effect, """
@fragment
fn fs_my_effect(in: QuadOut) -> @location(0) vec4<f32> {
    let c = sample_a(in.uv);
    return vec4<f32>(unpremult(c) * P.f0.x * c.a, c.a);
}
""")
_apply_effect!(cg::GPUCompositor, rv, ef::MyEffect, src::Int) =
    _quad!(cg, rv, :my_effect, _scratch(cg, src); a = src,
           params = QuadParams(f0 = (Float32(ef.gain),)))
```

`RadialBlur` in `src/backend/wgpu/compositor.jl` is the smallest complete
example. The layer's CURRENT texture travels as a slot index — the method
writes into `_scratch(cg, src)` and returns the slot it wrote, never writing
`src`, and there is no copy back. The fragment runs over the shared quad
(`quad_common.wgsl`, spliced in front of it by [`effect_shader!`](@ref)
together with the noise and the straight-alpha helpers): its parameters
are read from `P.f0`, `P.f1`, `P.i0` (four floats, four more, four ints)
and it samples through `sample_a(uv)` / `sample_b(uv)`
(`textureSampleLevel`, nearest, repeat). If it needs randomness or a
per-frame pattern it must NOT call `rand`: declare a field
`current_frame::Int` (that field alone is what makes the engine fill it in)
and pass `Int32(ef.current_frame)` and `_noise_seed(ef, ef.seed)` in
`P.i0`, where the seed is an `i32` the shader reads with `bitcast<u32>`
(`janim_noise_px(in.position.xy, frame, seed)`) and offsets with
`seed_plus(seed, k)`. The seed is mixed with the effect's type name, so two
effects given the same user seed do not draw the same pattern.

See [Extending the engine](extending.md).

## Reference

[`Composition`](@ref) · [`Layer`](@ref) · [`use_composition!`](@ref) ·
[`Mask`](@ref) · [`crop`](@ref) · [`Bloom`](@ref) · [`Dof`](@ref) ·
[`Glitch`](@ref) · [`render_composition`](@ref) — in
[the backend reference](api_backend.md).
