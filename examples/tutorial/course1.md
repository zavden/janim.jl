# Course 1 — Foundations

Thirty-three lessons. If you know Manim, this is the syllabus you already know; what
changes is the dialect and, in a few places, the design.

Run any of them with
`julia --project=. examples/tutorial/<chapter>/<lesson>.jl`.

---

## 1 · [`c1_01_basics`](c1_01_basics) — the elements

| Lesson | What it teaches | The thing worth remembering |
|---|---|---|
| `01_how_janim_works.jl` | `construct(scene)` as a contract; frames as steps of a fixed clock | the αs are the MIDPOINTS `(k+½)/n` — no frame ever sees α = 0 or 1 |
| `02_mobjects_and_animations.jl` | `add!` vs `play!`; the four basic animations | `play!` adds the mobject for you; a remover takes it back out |
| `03_setters_and_getters.jl` | style, placement, size, and the bounding-box getters | `set_fill!(m; opacity = …)` with no colour keeps each row's colour |
| `04_animation_properties.jl` | `run_time`, `rate_func`, `lag_ratio`, `remover` | `lag_ratio` staggers a FAMILY on one animation, and ANIMATIONS on a group |
| `05_copies.jl` | `copy` is deep; where copies appear whether you ask or not | `Transform(a, b)` never mutates `b`, and leaves you holding `a` |
| `06_layers.jl` | draw order, `set_z_index!`, `bring_to_front!/back!` | `bring_to_back!` also moves the UPDATE order — one frame of lag |

## 2 · [`c1_02_config_and_assets`](c1_02_config_and_assets) — configuration and files

| Lesson | What it teaches | The thing worth remembering |
|---|---|---|
| `01_configuration.jl` | there is no config file, and why | `CLI flag > Scene kwargs > engine defaults`, resolved by building the scene |
| `02_cli.jl` | `bin/janim`: render, frame, preview, states, the farm | `-n X,Y` gates the DRAWING; `--from label` skips the SIMULATION |
| `03_config_dict.jl` | Manim's `config` dict as a `NamedTuple` you splat | `encoder_threads = 1` for a byte-reproducible render |
| `04_svg_import.jl` | `SVGMobject` from a file or a string; ids become keys | `clipPath`s need `clip_layers` (course 3) to have any effect |
| `05_image_import.jl` | `ImageMobject`, `TexturedSurface`, images computed in Julia | no `get_bounding_box_point`, so relative layout does not work on them |
| `06_audio_import.jl` | `add_sound`, and a wav written by hand | the audio is MUXED at close, so the video stays deterministic |
| `07_multiscene.jl` | several scenes in one file: `file.jl:name` on every verb, and mixing by plain calls | no suffix = `construct`; the default output gains the name (`x.jl:intro` → `x_intro.mp4`) |

## 3 · [`c1_03_groups_and_text`](c1_03_groups_and_text) — groups, text and formulas

| Lesson | What it teaches | The thing worth remembering |
|---|---|---|
| `01_groups_vs_vgroups.jl` | `VGroup` (vector geometry) vs `Group` (anything) | `AnimationGroup` picks for you, and that is why `Group` exists |
| `02_comprehensions.jl` | building many mobjects, and splatting them | a NESTED Julia comprehension is a MATRIX, not a flat list |
| `03_text.jl` | `TextMobject`, fonts, `t2c`, `t2w` | a missing weight is an ERROR, not a silent fallback |
| `04_latex.jl` | `Tex` without LaTeX, in 0.2–0.4 ms | a `Tex` is a parent plus ONE CHILD PER GLYPH, and that is load-bearing |
| `05_latex_config.jl` | `via = :math / :latex / :typst / :auto`, `config_tex!` | the three routes share x-height and baseline — not syntax |
| `06_tex_transformations.jl` | `TransformMatchingTex` | when it ends the scene holds the TARGET; carry on with that one |
| `07_symbol_by_symbol.jl` | `tex[3]`, `tex["x"]`, `isolate = ["x^2"]` | groups are memoised: `tex["x"] === tex["x"]` |

## 4 · [`c1_04_animations`](c1_04_animations) — animations

| Lesson | What it teaches | The thing worth remembering |
|---|---|---|
| `01_rate_functions.jl` | the whole family, drawn and raced side by side | `rate_func` belongs to the ANIMATION, never to `play!` |
| `02_class_animations.jl` | an animation is a value; the three-act life cycle | `Rotating` is not a `Transform` — chords vs arcs |
| `03_method_animations.jl` | `animate(m, (f, args...))`, the `.animate` idiom | calls are POSITIONAL; a keyword setter needs a one-line adapter |
| `04_animation_group.jl` | `AnimationGroup`, `LaggedStart`, `Succession` | `Succession` begins each animation LATE, which is why it is a type |

## 5 · [`c1_05_utilities`](c1_05_utilities) — the utility belt

| Lesson | What it teaches | The thing worth remembering |
|---|---|---|
| `01_useful_methods.jl` | `next_to!`, `align_to!`, `arrange!`, `arrange_in_grid!`, `surround!` | `to_edge!` uses the NOMINAL frame, so zooming does not move it |
| `02_useful_mobjects.jl` | the shape zoo, annotations, matrices and tables | `Brace` is a native path, not `Tex("\\underbrace")` |
| `03_useful_animations.jl` | `Indicate`, `Flash`, `Circumscribe`, `FocusOn`, `Wiggle`, the growers | `Uncreate`/`Unwrite` hand the mobject back INTACT |
| `04_extending_janim.jl` | the four extension seams — Manim's "plugins" | there is no plugin registry: a plugin is a package that adds methods |

## 6 · [`c1_06_plots_and_updaters`](c1_06_plots_and_updaters) — plots and updaters

| Lesson | What it teaches | The thing worth remembering |
|---|---|---|
| `01_plots_2d.jl` | `Axes`, `c2p`/`p2c`, `plot`, `get_area`, `NumberPlane`, `PolarPlane` | the map is DERIVED from the live geometry, so it survives transforms |
| `02_plots_3d.jl` | `ThreeDAxes`, `Surface`, `reorient!`, `apply_depth_test!` | `fix_in_frame!` is how a HUD ignores the camera |
| `03_basic_updaters.jl` | `add_updater!`, `always_redraw`, `ValueTracker`, `DecimalNumber` | a mobject whose points are made in an updater must be BORN styled |
| `04_vector_fields.jl` | `VectorField`, `TimeVaryingVectorField`, `StreamLines`, `AnimatedStreamLines` | a whole field is ONE mobject, and its seeds are hashed — same bytes in any process |
| `05_particles.jl` | `DotCloud`, `GlowDots`, `make_3d!`, the in-place updater idiom | glow per fragment for sparse clouds; a Bloom layer when overlap saturates it |

---

## Where course 1 differs from Manim, in one page

| Manim | Janim | Why |
|---|---|---|
| `self.play(…)` | `play!(scene, …)` | no class to inherit from; `scene` is an argument |
| `m.set_fill(BLUE, opacity=0.5)` | `set_fill!(m; color = BLUE, opacity = 0.5)` | Julia convention: `!` mutates, the object comes first, style is keyword |
| `m.animate.shift(RIGHT).rotate(PI)` | `animate(m, (shift!, RIGHT), (rotate!, PI))` | no chainable proxy; the tuples are applied in order |
| `Text` / `MathTex` | `TextMobject` / `Tex` | Julia's `Text` and `Matrix` are taken |
| `Tex` runs LaTeX | `Tex` runs MathTeXEngine (`via = :latex` opts in) | milliseconds instead of a subprocess |
| `manim.cfg`, `config`, `tempconfig` | `Scene` kwargs; the CLI's `janim.cfg` is only a flag shortener | nothing global reaches the engine, and the cfg announces itself |
| `-ql / -qm / -qh` | `-r 854x480 --fps 30` | opaque aliases replaced by what they mean |
| `ZoomedScene`, `MovingCameraScene`, `ThreeDScene` | one `Scene`; `scene.frame` is animatable, and a `Layer` can carry a second camera | the camera is a mobject (course 2, chapter 3) |
| plugins via entry points | Julia packages adding methods | dispatch is the extension mechanism |
