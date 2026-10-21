# Animations

An animation is a PLAN. Building one changes nothing; [`play!`](@ref) runs it.

```julia
play!(scene, FadeIn(c; shift = 0.5 * UP); run_time = 0.8)
play!(scene, a, b, c)                       # three at once
```

## The life cycle

Every animation goes through the same three calls, and `play!` makes them:

```
begin!(a)                 snapshot the starting state, align, jump to α = 0
interpolate!(a, α) × N    once per frame
finish!(a)                land on exactly α = 1 and clean up
```

The snapshot is why ORDER matters: everything the animation reads off the
mobject is read in `begin!`, so styling it after that changes the target rather
than the starting point.

You can drive the cycle yourself when you want a frame at a particular α — that
is exactly what [`render_frame`](@ref) and the live window do.

Shared keywords, on every constructor: `run_time`, `rate_func`, `lag_ratio`,
`remover`. See [`Animation`](@ref).

## Transforming

```julia
Transform(m, target)                    # m becomes target; the scene keeps m
ReplacementTransform(m, target)         # …and the scene keeps TARGET
TransformFromCopy(m, target)            # m stays put, a copy flies over
FadeTransform(m, target)                # cross-fade rather than morph
Transform(m, target; path_arc = TAU/4)  # a curved trajectory
```

The difference between the first two is a classic source of confusion, and it
is about what you are left holding. After `Transform`, the scene holds `m`
wearing the target's shape. After `ReplacementTransform`, it holds `target`.
Use the second when the target is the thing you will keep manipulating.

[`Transform`](@ref) speaks only the interpolation contract, never `VMobject` —
which is why it works on a [`ValueTracker`](@ref), on a [`Surface`](@ref) and
on any type of your own that fulfils it. See [Extending the
engine](extending.md).

### `.animate`, without the proxy

Manim's `m.animate.shift(RIGHT).rotate(PI)` is a chainable proxy. Julia has no
such thing, so the same idea is spelled as a list of calls:

```julia
play!(scene, animate(m, (shift!, 2 * RIGHT), (rotate!, TAU / 4)))
play!(scene, animate(m, center!))                  # a bare function
play!(scene, animate(vt, (set_value!, 10.0)); run_time = 2)
```

Each tuple is `(function, args...)`, applied in order to a COPY, and the result
becomes the target of a `Transform`.

**Tuple arguments are positional.** Julia has no `;` inside a tuple —
`(to_edge!, RIGHT; buff = 1)` is a syntax error, not a runtime one — so
anything with a KEYWORD is written as a function of the mobject instead:

```julia
play!(scene, animate(c, m -> to_edge!(m, RIGHT; buff = 1)))
play!(scene, animate(m, m -> set_fill!(m; color = RED, opacity = 1)))
```

That form takes any signature at all, chains as many calls as you like, and
mixes freely with the tuples:

```julia
play!(scene, animate(c, (shift!, UP), m -> to_edge!(m, RIGHT; buff = 1)))

play!(scene, animate(c, m -> begin
    to_edge!(m, RIGHT; buff = 1)
    scale!(m, 1.5; about_edge = RIGHT)
end))
```

A named adapter is worth it only when the same call repeats across a scene:

```julia
paint!(m, c) = set_color!(m; color = c)
play!(scene, animate(m, (paint!, RED)))
```

## Appearing and disappearing

```julia
FadeIn(m; shift = 0.5 * UP)
FadeOut(m; shift = 0.5 * DOWN)
ShowCreation(m)            # Create(m) — the same object
Uncreate(m)
Write(m)                   # for text and formulas
Unwrite(m)
DrawBorderThenFill(m)
GrowFromCenter(m)
GrowFromPoint(m, p)
GrowFromEdge(m, LEFT)
GrowArrow(arrow)
SpinInFromNothing(m; angle = PI)
ShrinkToCenter(m)
```

[`ShowCreation`](@ref) draws the path as if with a pen and depends on where the
path starts. [`Write`](@ref) is the text version, drawing glyph by glyph.
[`Uncreate`](@ref) and [`Unwrite`](@ref) hand the mobject back INTACT rather
than leaving an empty husk, so `add!` after one of them shows something.

**`FadeIn` fades towards the CURRENT state.** To reveal something that is
already hidden, `Transform` it towards a copy carrying the target opacity —
otherwise you are fading towards invisible.

The removers ([`FadeOut`](@ref), [`Uncreate`](@ref), [`Unwrite`](@ref)) take
the mobject off stage when they finish; [`is_remover`](@ref) is how the scene
knows. Leaving something at opacity zero is not the same thing.

## Emphasis

```julia
Indicate(m; scale_factor = 1.2, color = YELLOW)
Flash(point_or_mobject; line_length = 0.2, num_lines = 12)
Circumscribe(m; shape = :rectangle, buff = 0.1)
FocusOn(point_or_mobject; opacity = 0.2)
Wiggle(m; scale_value = 1.1, n_wiggles = 6)
```

These end where they started, so nothing needs undoing afterwards.

## Motion

```julia
Rotate(m, PI; axis = OUT, about_point = nothing)
Rotating(m, TAU; run_time = 4, rate_func = linear)
MoveAlongPath(m, path; run_time = 3, rate_func = linear)
```

[`Rotate`](@ref) is a fixed turn; [`Rotating`](@ref) keeps going. For
[`MoveAlongPath`](@ref) the default rate is [`smooth`](@ref), like manimlib's —
say `linear` if you want a steady pace.

## Text

```julia
Write(formula)
TransformMatchingTex(a, b; key_map = Dict("x" => "y"))
```

[`TransformMatchingTex`](@ref) pairs glyphs by KEY instead of by position.
**When it ends the scene holds the TARGET** — carry on with `b`, not with `a`.
See [Text and formulas](text.md).

## The generic escape valve

When nothing in the catalogue fits, drive the mobject from α directly:

```julia
play!(scene, UpdateFromAlphaFunc(surface, (m, α) -> begin
    set_shading!(m; reflectiveness = α)
end); run_time = 2)

play!(scene, UpdateFromFunc(label, m -> set_number!(m, get_value(vt))))
```

[`UpdateFromAlphaFunc`](@ref) takes no snapshot, which is why it can drive a
[`Surface`](@ref) and other things a morph cannot. This is almost always the
right answer before writing a new `Animation` type.

## Composing

```julia
AnimationGroup(a, b, c)                       # all at once
AnimationGroup(a, b; lag_ratio = 0.3)         # overlapping
LaggedStart(anims...; lag_ratio = 0.05)       # a cascade
Succession(a, b, c)                           # strictly one after another
```

The three are the same time algebra with different lags: `0` is simultaneous,
`1` is sequential, in between overlaps.

But [`Succession`](@ref) is NOT just `lag_ratio = 1`: it begins each animation
LAZILY, when its turn arrives. That is what makes chaining several animations
over the SAME mobject correct, because the second one snapshots what the first
one left rather than the state everything had at the start.

`lag_ratio` also works on the CHILDREN of a single animation, which is what
turns "draw these five things" into a ripple:

```julia
play!(scene, ShowCreation(g; lag_ratio = 0.2))
```

## Timing

`run_time` on the animation is its natural length; `run_time` on `play!`
overrides it for that call. `rate_func` never goes on `play!` — see [Rate
functions](rate_functions.md).

To lay animations out on a timeline without a scene, there is
[`Timeline`](@ref), which is what the precompilation workload and the tests
use.

## Reference

[The animation reference](api_animation.md) lists all of them.
Starting points: [`Animation`](@ref), [`Transform`](@ref), [`animate`](@ref),
[`FadeIn`](@ref), [`ShowCreation`](@ref), [`Write`](@ref),
[`AnimationGroup`](@ref), [`UpdateFromAlphaFunc`](@ref).
