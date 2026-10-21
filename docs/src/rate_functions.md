# Rate functions

A rate function maps the fraction of the run time elapsed to the fraction of
the animation completed. It is what makes movement look like movement instead
of like linear interpolation.

```julia
play!(scene, Create(c; rate_func = linear); run_time = 2)
play!(scene, animate(m, (scale!, 1.2); rate_func = there_and_back))
```

**It belongs to the ANIMATION, never to `play!`.** `play!` decides how long;
how progress is spread over that time is the animation's business. That split
is what makes an animation behave identically under `play!`, under a
[`Timeline`](@ref) and under [`render_frame`](@ref).

The default is [`smooth`](@ref).

## The manimlib family

| | |
|---|---|
| [`linear`](@ref) | constant speed |
| [`smooth`](@ref) | eased at both ends — the default |
| [`rush_into`](@ref) | starts from rest, ends at full speed |
| [`rush_from`](@ref) | starts at full speed, glides to a stop |
| [`slow_into`](@ref) | a quarter circle: fast start, eased finish |
| [`double_smooth`](@ref) | two eased halves, almost stopping in the middle |
| [`there_and_back`](@ref) | out and back — ends where it started |
| [`there_and_back_with_pause`](@ref) | …with a hold at the far end |
| [`running_start`](@ref) | pulls back before setting off |
| [`overshoot`](@ref) | goes past and settles back |
| [`not_quite_there`](@ref) | stops short of the target |
| [`wiggle`](@ref) | an oscillation that starts and ends at 0 |
| [`lingering`](@ref) | arrives early and waits |
| [`exponential_decay`](@ref) | the asymptotic approach |

[`smooth`](@ref) is ManimGL's quintic — a polynomial, exact at 0 and 1, with
zero first and second derivatives at both ends. It is NOT Manim CE's rescaled
sigmoid, so the two disagree by design.

`there_and_back` is the one that makes an emphasis gesture safe: the animation
returns to where it began, so there is nothing to undo.

## The easings.net family

Thirty closed forms, named `ease_{in,out,in_out}_{curve}`. `in` starts slow,
`out` ends slow, `in_out` does both.

The curves, in increasing sharpness: `sine`, `quad`, `cubic`, `quart`,
`quint`, `expo`. Then four that are not merely steeper — `circ` (a quarter
circle, arriving at infinite speed), `back` (overshoots), `elastic` (springs)
and `bounce` (lands and bounces).

```julia
play!(scene, FadeIn(m; rate_func = ease_out_cubic))
play!(scene, animate(m, (shift!, 3RIGHT); rate_func = ease_out_elastic))
```

**Three of them leave the interval `[0, 1]`**: `back` and `elastic` overshoot,
and `elastic` by a long way. That is fine on a position or a scale and wrong on
an opacity, where a value above 1 or below 0 is meaningless.
[`ease_out_bounce`](@ref) is the exception among the dramatic ones — every
bounce stays on the near side of the target, so it is safe anywhere.

## Composing them

```julia
squish_rate_func(smooth, 0.4, 0.6)      # run the whole of it in that window
squish_rate_func(f, 0.5, 0.5)           # freeze at the midpoint
not_quite_there(smooth, 0.7)            # only 70% of the way
bezier([0, 0, 1.5, 1.5, 1, 1])          # your own, from control values
```

[`squish_rate_func`](@ref) compresses a rate into a window, holding `f(0)`
before it and `f(1)` after. Manim's composed animations use it internally, so
porting one of them without it comes out crooked.

A rate function is just a function of one number, so writing one takes no
ceremony:

```julia
staircase(t) = floor(t * 4) / 4
play!(scene, animate(m, (shift!, 4RIGHT); rate_func = staircase))
```

## Seeing the shape

Every one of them is pure and cheap, so the fastest way to understand one is to
evaluate it:

```@example rates
using Janim
[round(smooth(t); digits = 3) for t in 0:0.25:1]
```

```@example rates
[round(there_and_back(t); digits = 3) for t in 0:0.25:1]
```

```@example rates
round(ease_out_back(0.6); digits = 3)     # above 1: it has overshot
```

## Reference

All of them are in [the animation reference](api_animation.md).
