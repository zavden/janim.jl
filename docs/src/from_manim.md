# Coming from Manim

The API is deliberately the same narrated English, so most of a scene
translates literally. This page is about the places where it does not.

## The shape of a scene

```python
class Demo(Scene):
    def construct(self):
        c = Circle()
        self.play(Create(c), run_time=2)
        self.wait()
```

```julia
function construct(scene)
    c = Circle()
    play!(scene, Create(c); run_time = 2)
    wait!(scene)
end
```

There is no class, so there is nothing to name a scene after: **the FILE is the
unit of address**, one scene per file, and the function must be called
`construct`.

## The table

| Manim CE / GL | Janim |
|---|---|
| `class S(Scene): def construct(self):` | `function construct(scene)` |
| `self.play(a, b)` | `play!(scene, a, b)` |
| `self.play(a, run_time=2, rate_func=linear)` | `play!(scene, a; run_time = 2)` — `rate_func` on the ANIMATION |
| `self.wait(2)` | `wait!(scene, 2)` |
| `self.add(m)` / `self.remove(m)` | `add!(scene, m)` / `remove!(scene, m)` |
| `m.set_fill(BLUE, opacity=0.5)` | `set_fill!(m; color = BLUE, opacity = 0.5)` |
| `BLUE_E`, `GRAY_B`, `LOGO_RED`, `PURE_CYAN` | the same names — the palette is both engines' union |
| `from manim.utils.color.XKCD import *` | `using Janim.XKCD` (six catalogues, as submodules) |
| `m.next_to(o, RIGHT, buff=0.2)` | `next_to!(m, o, RIGHT; buff = 0.2)` |
| `m.get_center()`, `m.get_width()` | `get_center(m)`, `get_width(m)` |
| `VGroup(*mobs)` / `Group(*any)` | `VGroup(mobs...)` / `Group(any...)` |
| `Text("hi", font_size=48)` | `TextMobject("hi"; size = 0.6)` |
| `MathTex(r"x^2")` / `Tex(...)` | `Tex(raw"x^2")` |
| `t2c={"w": YELLOW}` | `t2c = Dict("w" => YELLOW)` |
| `Matrix([[1,2],[3,4]])` | `MatrixMobject([1 2; 3 4])` |
| `Axes(x_range=[-3,3,1])` | `Axes((-3.0, 3.0, 1.0), …)` |
| `axes.plot(f)` / `axes.c2p(x,y)` | `plot(ax, f)` / `c2p(ax, x, y)` |
| `m.copy()` / `m.become(o)` | `copy(m)` / `become!(m, o)` |
| `m.set_z_index(1)` | `set_z_index!(m, 1)` |
| `self.camera.frame` (GL: `self.frame`) | `scene.frame` |
| `self.embed()` | `live("scene.jl")` |
| `checkpoint_paste()` | `checkpoint!(scene, "label")` + `--from label` |
| `config.frame_rate = 60` | `Scene(construct; fps = 60, …)` |
| `manim -pql scene.py S` | `janim render scene.jl -ql -p` |
| `manimgl scene.py` (a window) | `janim scene.jl` — no verb = preview |
| `manimgl scene.py -w` | `janim scene.jl -w` |
| `m.add_updater(lambda m, dt: …)` | `add_updater!(m, (m, dt) -> …)` |
| `always_redraw(lambda: …)` | `always_redraw(() -> …)` |
| `ValueTracker(0).animate.set_value(5)` | `animate(vt, (set_value!, 5.0))` |

Animation names carry over unchanged: `Create`/`ShowCreation` (the same
object), `Write`, `Unwrite`, `FadeIn(m; shift = UP)`, `Transform`,
`ReplacementTransform`, `TransformMatchingTex`, `AnimationGroup(a...;
lag_ratio = 0.1)`, `LaggedStart`, `Succession`, `UpdateFromAlphaFunc`.

## Five things that are not a literal translation

**1 · `.animate` has no chainable proxy.**

```python
self.play(m.animate.shift(RIGHT).rotate(PI))
```
```julia
play!(scene, animate(m, (shift!, RIGHT), (rotate!, PI)))
```

One tuple per call, applied in order — and TUPLE ARGUMENTS ARE POSITIONAL,
because Julia has no `;` inside a tuple. Anything carrying a keyword is written
as a function of the mobject, which accepts any signature at all:

```python
self.play(c.animate.to_edge(RIGHT, buff=1))
```
```julia
play!(scene, animate(c, m -> to_edge!(m, RIGHT; buff = 1)))
```

The two forms mix in one call, so a chain of Manim's is a list here:
`animate(c, (shift!, UP), m -> to_edge!(m, RIGHT; buff = 1))`.

**2 · Mutating functions carry `!` and take the mobject FIRST**, and colour
and opacity are KEYWORDS rather than positional. `m.set_fill(BLUE, 0.5)` is
`set_fill!(m; color = BLUE, opacity = 0.5)`. Keywords do not take part in
dispatch, which is exactly why the mobject is first: it is the argument that
decides which method runs.

**3 · `Text` → `TextMobject`, `MathTex`/`Tex` → `Tex`**, because Julia's `Text`
and `Matrix` are taken. And Janim's `Tex` does not run LaTeX unless you ask for
`via = :latex`.

**4 · The engine reads no config file.** No `manim.cfg`, no `config`, no
`tempconfig`. Settings are `Scene` keywords, and precedence is `CLI flag >
Scene kwargs > engine defaults`, resolved by BUILDING the scene. What does
exist is a CLIENT-side shortener: the CLI takes a `janim.cfg` of flag lines
(announced on every use, user flags win) and a panel on a TTY — see
[the CLI](cli.md). The engine never sees either.

**5 · A nested comprehension gives a MATRIX.** `[Dot() for i in 1:3, j in 1:3]`
is 3×3, not a flat list of 9, and `VGroup` will reject it. Two separate `for`
clauses give the flat one, or `vec(...)` flattens what you have.

## What has no equivalent

| Manim | Status in Janim |
|---|---|
| `manim.cfg` / `config` / `tempconfig` | absent in the ENGINE — kwargs instead; the CLI takes a `janim.cfg` of flag lines as an announced shortener |
| plugin registry / entry points | absent: extension IS adding methods |
| `ZoomedScene` | **surpassed**: a [`Layer`](@ref) takes `camera =` and `window =` — a real second render, and as many of them as you like |
| `MovingCameraScene`, `ThreeDScene` | not needed: every scene's camera is animatable |
| `Code`, `BarChart` | not ported; [`Table`](@ref) covers the grid |
| `config.disable_caching` | **nothing to disable** — see below |
| a scene with no `self.play` → an image | **the same rule, ported** |

### There is no cache to disable

Janim re-simulates the whole scene every time. There are no partial movie files
keyed by an argument hash that can go stale behind your back, so there is
nothing to turn off. The two caches that DO exist are explicit
([`checkpoint!`](@ref)) or keyed by mtime (the daemon's frame cache).

### The empty-scene rule, ported

If `construct` never calls `play!` or `wait!` there is no video to make, so
`x.png` is written instead of `x.mp4`. CE checks `num_plays == 0`; Janim checks
`scene.frames == 0`, which counts SIMULATED frames — so an empty `-n` or
`--from` selection stays an error rather than silently becoming a still.

## Where the two references disagree

Janim ports ManimGL, so a difference from CE is usually CE departing from GL.
Measured on the four basic constructors, default stroke:

| | CE 0.20.1 | GL 1.7.2 | Janim |
|---|---|---|---|
| `Square` | `#FFFFFF` | `#DDDDDD` | `#DDDDDD` |
| `Circle` | `#FC6255` | `#FC6255` | `#FC6255` |
| `Triangle` | **`#58C4DD`** (blue) | `#DDDDDD` | `#DDDDDD` |
| `Rectangle` | `#FFFFFF` | `#DDDDDD` | `#DDDDDD` |

GL and Janim agree on all four; CE differs on three. CE's `Triangle` is blue
because it descends from `Polygram`, whose default is `BLUE` — the one
difference big enough to see across a room.

The palette diverges in exactly three places, and the same policy applies:

| | ManimGL | Manim CE | Janim |
|---|---|---|---|
| [`YELLOW`](@ref) / [`YELLOW_C`](@ref) | `#FFFF00` | `#F7D96F` | `#FFFF00` |
| [`BLUE_E`](@ref) | `#1C758A` | `#236B8E` | `#1C758A` |

So a CE scene ported here comes out with brighter yellows than it had. Neither
CE value is lost: `#236B8E` is [`DARK_BLUE`](@ref) (CE's own second name for
it), and CE's whole palette lives at CE's values in `Janim.ManimCE`, which is
what to reach for when a scene has to match a CE render:

```julia
set_fill!(m; color = Janim.ManimCE.YELLOW)     # "#F7D96F", not "#FFFF00"
```

Everything else in the palette agrees. All 70 of GL's names and all 89 of
CE's are exported, at the engines' own hex, with both spellings of every grey
— see [the palette](api_palette.md).

Everything geometric matches exactly, checked numerically rather than assumed:
`FRAME_HEIGHT = 8.0`, `FRAME_WIDTH = 8·16/9 = 14.222222`, the edge buff `0.5`,
and the four `to_corner` centres agree to six decimals across all three
engines. Constructor defaults match too: `Square(side_length = 2)`,
`Circle(radius = 1)`, `Rectangle(width = 4, height = 2)`,
`Triangle(radius = 1)` → 1.7321 × 1.5, pointing up.

Careful with one constant's NAME: it is `DEFAULT_MOBJECT_TO_EDGE_BUFF` in GL
and in Janim, and CE renamed it to `…_BUFFER`.

A residue that is nobody's bug: with identical stroke colours the two renderers
still differ on ANTIALIASED edge pixels. Compare hues and geometry, not exact
bytes.

## Julia, if you are coming from Python

The library differences above are the small half. The language ones: the `!`
suffix (which is part of the name, NOT a macro), `,` versus `;` in a signature,
dispatch instead of `self`, `end` instead of indentation, 1-based inclusive
ranges, broadcasting with `.`, and strings. Julia's own manual covers each of
them.

## A worked pair

`examples/tutorial/c2_05_from_manim/` holds two runnable translations:

| file | what is in it |
|---|---|
| `01_from_manim_ce.jl` | a ManimCE scene translated line by line, with the original in the comments |
| `02_from_manimgl.jl` | a ManimGL scene, and what `embed()` / `checkpoint_paste()` become |

Each carries the prose: every line of the original with its equivalent, or
with the reason there is none — and the lines that translate to nothing get
the most space, since that is where the design difference lives.
