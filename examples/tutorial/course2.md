# Course 2 — Going deeper

Fourteen lessons: the mechanisms behind the API, and how to add your own.

---

## 1 · [`c2_01_updaters_and_custom_mobjects`](c2_01_updaters_and_custom_mobjects)

| Lesson | What it teaches | The thing worth remembering |
|---|---|---|
| `01_alpha_updaters.jl` | `UpdateFromAlphaFunc`, `UpdateFromFunc` | it takes NO snapshot, so it drives a `Surface` or a type of your own |
| `02_dt_updaters.jl` | the dt form, and its four traps | registration calls the updater once with `dt = 0` |
| `03_custom_mobjects.jl` | seam A (a shape) and seam B (the contract) | `ValueTracker` and `CameraFrame` are four lines each — copy them |

## 2 · [`c2_02_custom_animations`](c2_02_custom_animations)

| Lesson | What it teaches | The thing worth remembering |
|---|---|---|
| `01_anatomy.jl` | `begin!` / `interpolate!` / `finish!` over an `AnimBase` | snapshot in `begin!`, and apply the rate function yourself |
| `02_a_real_one.jl` | one animation driving three mobjects | make `base.mobject` a `Group` of everything it touches |

## 3 · [`c2_03_camera`](c2_03_camera)

| Lesson | What it teaches | The thing worth remembering |
|---|---|---|
| `01_moving_camera.jl` | `scene.frame` is a mobject; zoom, pan, reset | `to_edge!` speaks the NOMINAL frame and does not follow the zoom |
| `02_zoomed_camera.jl` | the magnifier: a `Layer` with its own `camera =` and `window =` | a REAL second render — strokes keep their width, and the camera can chase with an updater |
| `03_camera_3d.jl` | `reorient!`, `apply_depth_test!`, `fix_in_frame!` | 2D mobjects do not join the z-buffer by default, and should not |

## 4 · [`c2_04_simulations`](c2_04_simulations)

| Lesson | What it teaches | The thing worth remembering |
|---|---|---|
| `01_ode_pendulum.jl` | a SciML integrator inside an updater | keep the integrator outside, guard with `dt > 0`, use ONE for everything |
| `02_gradient_descent.jl` | `ForwardDiff` through the whole drawing | the animation is an optimiser running, not a scripted path |

## 5 · [`c2_05_from_manim`](c2_05_from_manim)

| Lesson | What it teaches |
|---|---|
| `01_from_manim_ce.jl` | a CE scene translated line by line, with the original in the comments |
| `02_from_manimgl.jl` | a ManimGL scene, and what `embed()` / `checkpoint_paste()` become |

## 6 · [`c2_06_shaders`](c2_06_shaders)

| Lesson | What it teaches | The thing worth remembering |
|---|---|---|
| `01_write_a_layer_effect.jl` | a mutable struct, a fragment shader, one method | the texture is PREMULTIPLIED, and the zero must be an exact no-op |
| `02_noise_and_determinism.jl` | `janim_noise_px` (WGSL), `current_frame`, `_noise_seed` | never `rand()`: A2 is what scrubbing and the render farm are built on |

---

## The translation table

### Scenes and rendering

| Manim CE / GL | Janim |
|---|---|
| `class S(Scene): def construct(self):` | `function construct(scene)` — or any name, addressed as `file.jl:name` |
| `OtherScene.construct(self)` (scene mixing) | `otra_escena(scene)` — a scene IS a function, the call is the mix |
| `self.play(a, b)` | `play!(scene, a, b)` |
| `self.play(a, run_time=2, rate_func=linear)` | `play!(scene, a; run_time = 2)` with `rate_func` on the ANIMATION |
| `self.wait(2)` | `wait!(scene, 2)` |
| `self.add(m)` / `self.remove(m)` | `add!(scene, m)` / `remove!(scene, m)` |
| `manim -pql scene.py S` | `janim render scene.jl -ql`; several scenes per file: `janim render scene.jl:S -ql` |
| `manimgl scene.py` / `manimgl scene.py -w` | `janim scene.jl` / `janim scene.jl -w` — no verb = preview |
| `manim -s scene.py S` (save_last_frame) | `janim render scene.jl -s`; `-s --to X` picks frame X |
| a `Scene` with no `self.play` → an image | the same: no `play!`/`wait!` → `x.png`, not an empty `x.mp4` |
| `config.frame_rate = 60` | `Scene(construct; fps = 60, …)` |
| `self.camera.frame` (GL: `self.frame`) | `scene.frame` |
| `self.embed()` | `live("scene.jl")` |
| `checkpoint_paste()` | `checkpoint!(scene, "label")` + `janim render --from label` |

### Mobjects

| Manim | Janim |
|---|---|
| `Circle(radius=1).set_fill(BLUE, opacity=1)` | `Circle(radius = 1)` + `set_fill!(c; color = BLUE, opacity = 1)` |
| `Square().rotate(PI/4).shift(2*LEFT)` | `Square()`, then `rotate!(s, PI/4)`, `shift!(s, 2*LEFT)` |
| `VGroup(*mobs)` | `VGroup(mobs...)` |
| `Group(*anything)` | `Group(anything...)` |
| `Text("hi", font_size=48)` | `TextMobject("hi"; size = 0.6)` |
| `MathTex(r"x^2")` / `Tex(...)` | `Tex(raw"x^2")` |
| `t2c={"word": YELLOW}` | `t2c = Dict("word" => YELLOW)` |
| `Matrix([[1,2],[3,4]])` | `MatrixMobject([1 2; 3 4])` |
| `Axes(x_range=[-3,3,1])` | `Axes((-3.0, 3.0, 1.0), …)` |
| `axes.plot(f)` / `axes.c2p(x, y)` | `plot(ax, f)` / `c2p(ax, x, y)` |
| `ImageMobject("f.png")` | `ImageMobject("f.png")` — or from a Julia matrix |
| `SVGMobject("f.svg")` | `SVGMobject("f.svg")` — or from an SVG string |
| `m.get_center()`, `m.get_width()` | `get_center(m)`, `get_width(m)` |
| `m.next_to(o, RIGHT, buff=0.2)` | `next_to!(m, o, RIGHT; buff = 0.2)` |
| `m.copy()` | `copy(m)` |
| `m.become(o)` | `become!(m, o)` |
| `m.set_z_index(1)` | `set_z_index!(m, 1)` |
| `class Gear(VMobject): def __init__(self, **kw): super().__init__(**kw)` | `const Gear = VMobject{:Gear}` + a keyword constructor that starts from `VMobject(:Gear; kw...)` (1.3) |

### Animations

| Manim | Janim |
|---|---|
| `Create` / `ShowCreation` | `Create` / `ShowCreation` (the same object) |
| `Write(t)`, `Unwrite(t)` | `Write(t)`, `Unwrite(t)` |
| `FadeIn(m, shift=UP)` | `FadeIn(m; shift = UP)` |
| `Transform`, `ReplacementTransform` | the same, with `!`-free names |
| `TransformMatchingTex(a, b)` | `TransformMatchingTex(a, b)` |
| `m.animate.shift(RIGHT)` | `animate(m, (shift!, RIGHT))` |
| `AnimationGroup(*a, lag_ratio=0.1)` | `AnimationGroup(a...; lag_ratio = 0.1)` |
| `LaggedStart`, `Succession` | the same |
| `UpdateFromAlphaFunc(m, f)` | `UpdateFromAlphaFunc(m, f)` |
| `always_redraw(lambda: …)` | `always_redraw(() -> …)` |
| `ValueTracker(0).animate.set_value(5)` | `animate(vt, (set_value!, 5.0))` |
| `m.add_updater(lambda m, dt: …)` | `add_updater!(m, (m, dt) -> …)` |

### What has no equivalent

| Manim | Status in Janim |
|---|---|
| `manim.cfg`, `config`, `tempconfig` | absent in the ENGINE — kwargs instead (1.2.1); the CLI's `janim.cfg` is an announced flag shortener |
| plugin registry / `plugins = [...]` | absent: extension is by adding methods (course 1, lesson 5.4) |
| `ZoomedScene` | **surpassed**: `Layer(…; camera = zoom, window = display)` is a real second render (2.3.2) |
| `MovingCameraScene`, `ThreeDScene` | not needed: every `Scene`'s camera is animatable |
| `TransformMatchingShapes` | not provided — a fuzzy shape matcher is a project of its own |
| `Code`, `Table.get_highlighted_cell`, `BarChart` | not ported; `Table` covers the grid, the rest is composition |

### Names that collide — yours shadow Janim's, silently

Janim exports ~720 names and Julia raises no warning when a top-level
definition of yours takes one of them: `get_angle(x) = 42` next to `using
Janim` compiles without a word and wins, and the failure arrives later as a
`MethodError` on some anonymous function. The three that actually bit while
porting the seventeen batches: `get_cell` (the `Table` reader), `get_angle`,
and `vmob` — manimlib's own variable name for a `VMobject`, so a literal
`def __init__(self, vmob, …)` shadowed the base constructor. The way out is to
qualify (`Janim.get_angle(l)`), or to ask `isdefined(Janim, :name)` before
naming a helper; the public base constructor is `VMobject(:Tag; kw...)`, which
no parameter can shadow. One more, from the same family: a custom shape's
constructor written as `(::Type{Gear})(args...; kw...)` intercepts the
positional field constructor `VMobject(:Gear)` ends in and recurses forever
— use keywords or a typed positional argument (1.3).

### What Janim has and Manim does not

| Janim | Where |
|---|---|
| a layer compositor with blend modes, masks, mattes and per-layer effects | course 3 |
| real motion blur with the state advanced between exposures | course 3, chapter 5 |
| frame-deterministic output (same code → same frames, byte for byte; same mp4 with `encoder_threads = 1`) | course 1, lesson 1.1 |
| a TCP daemon and a pure-bash CLI with ~17 ms warm frames | course 1, lesson 2.2 |
| checkpoints that INVALIDATE themselves when the prefix changes | course 1, lesson 2.2 |
| SciML integrators and ForwardDiff inside updaters | course 2, chapter 4 |
| a render farm across processes (`-j 4`) | course 1, lesson 2.2 |
| `Tex` in 0.2–0.4 ms with no LaTeX installed | course 1, lesson 3.4 |
