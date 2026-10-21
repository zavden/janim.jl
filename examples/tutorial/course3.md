# Course 3 — Only in Janim

Forty lessons on the part with no Manim equivalent.

Manim draws everything into the final framebuffer in z order. There are no
intermediate textures, so there is nowhere to apply a blend mode, a mask or an
effect "to this group and not that one". It is not a missing feature — it
follows from the architecture. Janim's compositing primitive is the LAYER: a
texture plus its compositing parameters. Everything here is a consequence.

---

## 1 · [`c3_01_layers`](c3_01_layers) — the compositor

| Lesson | What it teaches |
|---|---|
| `01_one_layer.jl` | `Layer`, `Composition`, `use_composition!` — and that a mounted composition replaces `scene.mobjects` as what gets drawn |
| `02_blend_modes.jl` | `:normal :add :multiply :screen :overlay`, and the W3C equation behind them |
| `03_layer_opacity.jl` | layer opacity vs mobject opacity: the seams |
| `04_adjustment_layer.jl` | a layer with NO content grades everything below it |
| `05_precomp.jl` | a `Composition` as a layer's content: blurring the RESULT of a blend |
| `06_track_matte.jl` | `matte = :alpha / :luma / …` consumes the next layer as coverage |
| `07_layers_vs_zindex.jl` | z-index for ORDER, a layer for TREATMENT |
| `08_animated_composition.jl` | every layer parameter and effect dial is a mutable field |

## 2 · [`c3_02_blur_and_glow`](c3_02_blur_and_glow) — blur and glow

| Lesson | What it teaches |
|---|---|
| `01_blur_basics.jl` | `Blur(σ)`; σ in SCENE UNITS so the look survives the resolution |
| `02_blur_animated.jl` | the dream transition: blur up, swap, blur down |
| `03_box_blur.jl` | `BoxBlur`, its hard cut-off, and why three chained ≈ a Gaussian |
| `04_directional_blur.jl` | `DirectionalBlur`, and why it is not motion blur |
| `05_radial_blur.jl` | `RadialBlur`: the centre stays sharp |
| `06_bloom.jl` | `Bloom` as bright-pass → pyramid → add, and how to tune each dial |
| `07_depth_of_field.jl` | `Dof`: σ from the layer's distance to the focal plane; rack focus |
| `08_glow_pipeline.jl` | the neon recipe: `:add` + `Bloom` + a dark background + a dim tube |

## 3 · [`c3_03_masks`](c3_03_masks) — clipping masks

| Lesson | What it teaches |
|---|---|
| `01_mask_basics.jl` | `Mask(shapes…)`: coverage per pixel, and the shapes are never drawn |
| `02_crop_inside_minus.jl` | `crop(base; inside = …)` vs `crop(base; minus = …)` |
| `03_feather.jl` | feather blurs the MASK, not the layer — and the difference is visible |
| `04_invert_and_hard.jl` | `invert`, and `hard` as a threshold over a feathered stencil |
| `05_luma_mask.jl` | brightness as coverage: gradients and wipes |
| `06_animated_spotlight.jl` | a mask that FOLLOWS; parking it off screen to start |
| `07_text_as_mask.jl` | the world seen through the letters, and punched out of them |
| `08_svg_clip_layers.jl` | `clip_layers(svg)`: an SVG's own `clipPath`s, honoured per pixel |

## 4 · [`c3_04_glitch`](c3_04_glitch) — glitch and the editor family

| Lesson | What it teaches |
|---|---|
| `01_glitch_basics.jl` | `Glitch`: bands, blocks, RGB split; `rate` in FRAMES; 0 is an exact no-op |
| `02_glitch_animated.jl` | a spike, not a swell — and deterministic irregularity |
| `03_crt.jl` | `CRT`: scanlines as a COUNT, curvature as a fraction of the frame |
| `04_crt_roll.jl` | `roll`: a television losing sync, with no internal clock |
| `05_vhs.jl` | `VHS`: the chroma smear takes colour and never luma |
| `06_cheap_family.jl` | `ColorAdjust`, `Pixelate`, `Vignette`, `Grain` |
| `07_chromatic_and_sharpen.jl` | radial split, and the unsharp mask that is exactly identity on flats |
| `08_wave.jl` | `Wave`: animate the phase, and why it is reduced mod 2π |
| `09_edge_detect.jl` | Sobel over luma: a line drawing, or outlines added over the solid |

## 5 · [`c3_05_motion_blur`](c3_05_motion_blur) — motion blur

| Lesson | What it teaches |
|---|---|
| `01_motion_blur_basics.jl` | `motion_blur = n`: the average of n exposures with the state ADVANCED |
| `02_shutter_angle.jl` | `shutter` as the 180° convention, and strobing vs mush |
| `03_updater_motion.jl` | updaters and `always_redraw` smear too — that is the difference |
| `04_render_frame_motion.jl` | check a still before committing to n× the render |
| `05_physics_warning.jl` | MEASURED: 7.5e-11 at 2 s → 6.7e-2 at 20 s on a chaotic system |
| `06_cli_and_farm.jl` | `--motion-blur N[,SHUTTER]`, and the combination the farm refuses |

## 6 · [`c3_06_capstone`](c3_06_capstone) — the capstone

`01_pendulum_smooth_masked.jl` — the field and the chaos with the words taken
away. One double pendulum, a trail rounded by `make_smooth!`, a spotlight mask
following the bob, the trail glowing on an `:add` layer, the streamlines behind
a per-layer `Dof`, and an adjustment layer's blur closing it. No text on
screen at all.

It exists to teach one thing the other lessons cannot:

> **With a composition mounted, put the simulation in a scene-level mobject.**

`_update_all!` updates `scene.mobjects` FIRST and the layers' contents
afterwards, in layer order. A trail that reads the pendulum's state must be
updated after the pendulum writes it — but the trail's layer has to sit BELOW
the pendulum's to be drawn behind it, and those are the same list. Driving the
integrator from an invisible mobject added straight to the scene breaks the
tie.

```bash
julia --project=. examples/tutorial/c3_06_capstone/01_pendulum_smooth_masked.jl
```

---

## The parts list

```julia
Layer(mobjects...; blend, opacity, effects, mask, matte)
Layer(composition; …)                       # a precomp
Layer(; effects = [...])                    # an adjustment layer
Composition(layers...; background = (r, g, b, a))
use_composition!(scene, comp)
crop(base...; inside = shape | minus = shape, feather, hard)
Mask(shapes...; invert, feather, hard, luma)
clip_layers(svg) → Vector{Layer}
```

| Effect | Dials | Units |
|---|---|---|
| `Blur` | `sigma`, `in_pixels` | scene units |
| `BoxBlur` | `radius` | scene units |
| `DirectionalBlur` | `sigma`, `angle` | scene units, radians |
| `RadialBlur` | `strength`, `center_point` | fraction, scene coords |
| `Bloom` | `threshold`, `intensity`, `sigma` | colour, gain, scene units |
| `Dof` | `focus`, `aperture`, `max_sigma` | distance along the view axis |
| `Glitch` | `intensity`, `seed`, `rate`, `rgb_shift`, `slices`, `block` | frames, scene units |
| `CRT` | `intensity`, `scanlines`, `scan_depth`, `mask`, `curvature`, `vignette`, `roll` | counts and fractions of the frame |
| `VHS` | `intensity`, `seed`, `rate`, `chroma_bleed`, `jitter`, `noise`, `head_switch` | scene units, fraction |
| `ColorAdjust` | `brightness`, `contrast`, `saturation`, `hue` | factors, radians |
| `Pixelate` | `size` | scene units |
| `Vignette` | `amount`, `radius`, `feather` | fractions of the half-diagonal |
| `Grain` | `amount`, `seed`, `rate`, `levels` | frames, steps |
| `ChromaticAberration` | `amount` | scene units, at the corner |
| `Sharpen` | `amount`, `sigma` | gain, scene units |
| `Wave` | `amplitude`, `wavelength`, `angle`, `phase` | scene units, radians |
| `EdgeDetect` | `amount`, `color`, `thickness` | gain, colour, pixels |

Three rules that hold for all of them:

1. **Every dial's zero is an exact no-op** — the pass is skipped, and the
   layer comes out bit for bit as it went in.
2. **`rate` counts FRAMES**, not seconds.
3. **Geometric sizes are in scene units**, so a preview at 480p tells the
   truth about a film at 1080p.
