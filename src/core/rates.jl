# Rate functions — a port of manimlib/utils/rate_functions.py.
# `smooth` is GL's quintic (polynomial, exact at 0/1, zero derivatives at
# both ends, AD-friendly) — NOT CE's rescaled sigmoid.

"""
    linear(t) → t

The identity rate function: constant speed, no easing at either end.

A rate function maps the fraction of the run time elapsed (`t`, from 0 to 1) to
the fraction of the animation completed. It belongs to the ANIMATION, never to
[`play!`](@ref) — `play!` decides how long, the animation decides how the
progress is spread over that time:

```julia
play!(scene, Create(c; rate_func = linear); run_time = 2)
```

Use it for anything that should not appear to accelerate: a rotation that has
to loop seamlessly, a value counting up, a tracker driving a plot. Everything
else looks better with the default [`smooth`](@ref).
"""
linear(t::Real) = Float64(t)

"Quintic with zero 1st and 2nd derivatives at t=0 and t=1 (≡ bezier([0,0,0,1,1,1]))."
function smooth(t::Real)
    s = 1 - t
    return t^3 * (10s * s + 5s * t + t * t)
end

"""
    rush_into(t)

Ease IN only: starts from rest and arrives at full speed — the first half of
[`smooth`](@ref), stretched over the whole run.

The right rate for something that leaves and keeps going, and the natural
partner of [`rush_from`](@ref) when one animation hands over to another.
"""
rush_into(t::Real) = 2smooth(0.5t)

"""
    rush_from(t)

Ease OUT only: starts at full speed and glides to a stop — the second half of
[`smooth`](@ref). The mirror of [`rush_into`](@ref), for something that was
already moving when it entered.
"""
rush_from(t::Real) = 2smooth(0.5(t + 1)) - 1

"""
    double_smooth(t)

Two eased halves back to back: it accelerates, slows almost to a stop at the
midpoint, and then does it again.

The pause in the middle is the point — it reads as two movements rather than
one, which is how you show a step happening in two stages without splitting the
`play!`.
"""
function double_smooth(t::Real)
    t < 0.5 ? 0.5smooth(2t) : 0.5(1 + smooth(2t - 1))
end

"""
    there_and_back(t)

Out to 1 and back to 0 within the same run — so the animation ENDS where it
started.

This is what makes an emphasis gesture: `animate(m, (scale!, 1.2))` with this
rate grows the mobject and returns it to its size, leaving nothing to undo. For
a hold at the far end, [`there_and_back_with_pause`](@ref).
"""
function there_and_back(t::Real)
    smooth(t < 0.5 ? 2t : 2(1 - t))
end

"""
    squish_rate_func(f, a=0.4, b=0.6) → g

Compress `f` into the window `[a, b]`: `g` holds `f(0)` before `a`, runs the
whole of `f` inside the window, and holds `f(1)` after `b`.

Manim's composed animations use it INTERNALLY (Flash, the passing-flash
family, ShowCreationThenDestruction). Without it they come out crooked — the
sub-animations start and end at the wrong instants.

The degenerate window `a == b` returns **`a`**, not `f(a)`: that is what
manimlib does (rate_functions.py:squish_rate_func), and it matters because
`squish_rate_func(f, 0.5, 0.5)` is the idiom for "freeze at the midpoint".
"""
function squish_rate_func(f::Function, a::Real = 0.4, b::Real = 0.6)
    return function (t::Real)
        a == b && return Float64(a)
        t < a && return Float64(f(0))
        t > b && return Float64(f(1))
        return Float64(f((t - a) / (b - a)))
    end
end

# ═══════════════════════════════════════════════════════════════════════════
# the rest of the family
# ═══════════════════════════════════════════════════════════════════════════
#
# Two referees, on purpose. Everything that composes `smooth` inside comes
# from ManimGL (our `smooth` IS its quintic; CE's is a rescaled sigmoid and
# would disagree by design). The easings.net family exists only in CE, and
# every one of those is a closed form that touches neither: CE is its referee
# and nothing else's.

"""
    bezier(values) → f(t)

The Bernstein evaluator over a list of control VALUES (manimlib's `bezier`):
`f(t) = Σ C(n,k)·(1−t)^(n−k)·t^k·values[k+1]`. `running_start` and `overshoot`
are nothing but this over hand-picked control values, which is exactly how
manimlib defines them.
"""
function bezier(values::AbstractVector)
    n = length(values) - 1
    return function (t::Real)
        s = 1 - t
        # The zero of the right SHAPE: a point for control points, a
        # number for numbers (this evaluator is also GL's
        # `bezier` over np.arrays, its main use). `0.0 * v` is 0.0 or -0.0,
        # and adding to a signed zero changes no bit of a scalar sum.
        acc = 0.0 * values[1]
        @inbounds for k in 0:n
            acc += binomial(n, k) * s^(n - k) * t^k * values[k+1]
        end
        return acc
    end
end

"√(1 − (1−t)²): starts fast and eases out — the quarter-circle rate."
slow_into(t::Real) = sqrt(1 - (1 - t) * (1 - t))

"""
    there_and_back_with_pause(t, pause_ratio=1/3)

`there_and_back` with a HOLD in the middle: out over the first
`(1−pause_ratio)/2` of the run, frozen at 1 for `pause_ratio`, back over the
rest. The pause is what gives the eye time to read what was emphasised.
"""
function there_and_back_with_pause(t::Real, pause_ratio::Real = 1 / 3)
    a = 2 / (1 - pause_ratio)
    t < 0.5 - pause_ratio / 2 && return smooth(a * t)
    t < 0.5 + pause_ratio / 2 && return 1.0
    return smooth(a - a * t)
end

"""
    running_start(t, pull_factor=-0.5)

Pulls BACK before setting off (the wind-up of a sprinter). `pull_factor < 0`
is what makes it go backwards first; manimlib builds it as a degree-6 Bézier
over `[0, 0, p, p, 1, 1, 1]`.
"""
running_start(t::Real, pull_factor::Real = -0.5) =
    bezier([0, 0, pull_factor, pull_factor, 1, 1, 1])(t)

"""
    overshoot(t, pull_factor=1.5)

Goes PAST the target and settles back — `running_start`'s mirror image, a
degree-5 Bézier over `[0, 0, p, p, 1, 1]`.
"""
overshoot(t::Real, pull_factor::Real = 1.5) =
    bezier([0, 0, pull_factor, pull_factor, 1, 1])(t)

"""
    not_quite_there(f=smooth, proportion=0.7) → g

`g = proportion · f`: the animation stops short of its target. Useful for
"almost, but not yet" gestures, and for stacking a second animation on the
remaining distance.
"""
not_quite_there(f::Function = smooth, proportion::Real = 0.7) =
    (t::Real) -> proportion * f(t)

"""
    wiggle(t, wiggles=2)

`there_and_back(t) · sin(wiggles·π·t)`: an oscillation whose amplitude rises
and falls, so it starts and ends at exactly 0 (unlike a bare sine, which ends
at 0 but with non-zero speed).
"""
wiggle(t::Real, wiggles::Real = 2) = there_and_back(t) * sin(wiggles * PI * t)

"Linear over [0, 0.8] and then HELD: the animation arrives early and waits."
lingering(t::Real) = squish_rate_func(identity, 0, 0.8)(t)

"""
    exponential_decay(t, half_life=0.1)

`1 − e^(−t/half_life)`: the asymptotic approach. It never reaches 1 exactly —
with the default half-life the cut-off error at t=1 is 4.5e-5, which is why
manimlib warns that the half-life should stay small.
"""
exponential_decay(t::Real, half_life::Real = 0.1) = 1 - exp(-t / half_life)

# ── the easings.net family (CE's `ease_*`) ─────────────────────────────────
# Ported one by one from Manim CE, which ports them from easings.net. The
# special cases at t ∈ {0, 1} in the expo and elastic ones are NOT decoration:
# `2^(10·0−10)` is 0.00098, not 0, and an animation that starts 0.1% along its
# way starts with a visible jump.

"""
    ease_in_sine(t)

The gentlest acceleration there is: `1 − cos(πt/2)`.

**The `ease_*` family.** Thirty closed-form curves from easings.net, reached
through Manim CE, named `ease_{in,out,in_out}_{curve}`: `in` starts slow and
ends fast, `out` starts fast and ends slow, `in_out` does both with the fast
part in the middle. The curve name says how PRONOUNCED the effect is, in
increasing order: `sine`, `quad`, `cubic`, `quart`, `quint`, `expo`. Then there
are three that are not just steeper — `circ` (a quarter circle),
`back` (overshoots), `elastic` (springs) and `bounce` (lands and bounces).

They are all `f(0) = 0` and `f(1) = 1`, so any of them can be dropped into a
`rate_func` in place of [`smooth`](@ref).
"""
ease_in_sine(t::Real) = 1 - cos((t * PI) / 2)

"""
    ease_out_sine(t)

The gentlest deceleration: `sin(πt/2)`. See [`ease_in_sine`](@ref).
"""
ease_out_sine(t::Real) = sin((t * PI) / 2)

"""
    ease_in_out_sine(t)

Gentle at both ends. The closest of the family to [`smooth`](@ref), and the
safe substitute when you want a named easing. See [`ease_in_sine`](@ref).
"""
ease_in_out_sine(t::Real) = -(cos(PI * t) - 1) / 2

"""
    ease_in_quad(t)

Quadratic acceleration, `t²` — a clear pull-away without drama. See
[`ease_in_sine`](@ref) for the family.
"""
ease_in_quad(t::Real) = t * t

"""
    ease_out_quad(t)

Quadratic deceleration, `1 − (1−t)²`. See [`ease_in_sine`](@ref).
"""
ease_out_quad(t::Real) = 1 - (1 - t) * (1 - t)

"""
    ease_in_out_quad(t)

Quadratic at both ends. See [`ease_in_sine`](@ref).
"""
ease_in_out_quad(t::Real) = t < 0.5 ? 2t * t : 1 - (-2t + 2)^2 / 2

"""
    ease_in_cubic(t)

Cubic acceleration, `t³`. Noticeably slower off the mark than
[`ease_in_quad`](@ref). See [`ease_in_sine`](@ref).
"""
ease_in_cubic(t::Real) = t * t * t

"""
    ease_out_cubic(t)

Cubic deceleration, `1 − (1−t)³` — the workhorse for something arriving and
settling. See [`ease_in_sine`](@ref).
"""
ease_out_cubic(t::Real) = 1 - (1 - t)^3

"""
    ease_in_out_cubic(t)

Cubic at both ends. See [`ease_in_sine`](@ref).
"""
ease_in_out_cubic(t::Real) = t < 0.5 ? 4t * t * t : 1 - (-2t + 2)^3 / 2

"""
    ease_in_quart(t)

Quartic acceleration, `t⁴` — the mobject barely moves for the first third of
the run. See [`ease_in_sine`](@ref).
"""
ease_in_quart(t::Real) = t^4

"""
    ease_out_quart(t)

Quartic deceleration, `1 − (1−t)⁴`. See [`ease_in_sine`](@ref).
"""
ease_out_quart(t::Real) = 1 - (1 - t)^4

"""
    ease_in_out_quart(t)

Quartic at both ends. See [`ease_in_sine`](@ref).
"""
ease_in_out_quart(t::Real) = t < 0.5 ? 8 * t^4 : 1 - (-2t + 2)^4 / 2

"""
    ease_in_quint(t)

Quintic acceleration, `t⁵` — the steepest of the polynomial eases. See
[`ease_in_sine`](@ref).
"""
ease_in_quint(t::Real) = t^5

"""
    ease_out_quint(t)

Quintic deceleration, `1 − (1−t)⁵`. See [`ease_in_sine`](@ref).
"""
ease_out_quint(t::Real) = 1 - (1 - t)^5

"""
    ease_in_out_quint(t)

Quintic at both ends. See [`ease_in_sine`](@ref).
"""
ease_in_out_quint(t::Real) = t < 0.5 ? 16 * t^5 : 1 - (-2t + 2)^5 / 2

"""
    ease_in_expo(t)

Exponential acceleration, `2^(10t−10)` — the most extreme of the "slow start"
curves; for most of the run nothing appears to happen.

`t = 0` is special-cased to exactly `0`, and that is not decoration:
`2^(10·0−10)` is 0.00098, and an animation that begins 0.1% along its way
begins with a visible jump. See [`ease_in_sine`](@ref).
"""
ease_in_expo(t::Real) = t == 0 ? 0.0 : 2.0^(10t - 10)

"""
    ease_out_expo(t)

Exponential deceleration — almost all of the distance is covered in the first
instant. `t = 1` is special-cased to exactly `1`. See [`ease_in_expo`](@ref).
"""
ease_out_expo(t::Real) = t == 1 ? 1.0 : 1 - 2.0^(-10t)

"""
    ease_in_out_expo(t)

Exponential at both ends, with both endpoints special-cased. See
[`ease_in_expo`](@ref).
"""
function ease_in_out_expo(t::Real)
    t == 0 && return 0.0
    t == 1 && return 1.0
    t < 0.5 && return 2.0^(20t - 10) / 2
    return (2 - 2.0^(-20t + 10)) / 2
end

"""
    ease_in_circ(t)

A quarter circle: it leaves at zero speed and arrives at INFINITE speed, so it
looks like something falling off a ledge. See [`ease_in_sine`](@ref) for the
family.
"""
ease_in_circ(t::Real) = 1 - sqrt(1 - t^2)

"""
    ease_out_circ(t)

The mirror quarter circle — off the mark instantly and then a hard, clean stop.
See [`ease_in_circ`](@ref). Note that [`slow_into`](@ref) is the same curve
under manimlib's name.
"""
ease_out_circ(t::Real) = sqrt(1 - (t - 1)^2)

"""
    ease_in_out_circ(t)

Circular at both ends: barely moving, then a rush through the middle, then a
hard stop. See [`ease_in_circ`](@ref).
"""
ease_in_out_circ(t::Real) = t < 0.5 ? (1 - sqrt(1 - (2t)^2)) / 2 :
                            (sqrt(1 - (-2t + 2)^2) + 1) / 2

const _EASE_C1 = 1.70158          # the overshoot constant of easings.net
const _EASE_C2 = _EASE_C1 * 1.525
const _EASE_C3 = _EASE_C1 + 1
const _EASE_C4 = (2 * PI) / 3
const _EASE_C5 = (2 * PI) / 4.5

"""
    ease_in_back(t)

Pulls BACKWARDS before setting off — the wind-up. The value goes negative
early, so the mobject moves the wrong way first.

That matters when you use it: only animate something that CAN overshoot. On a
`FadeIn` a negative alpha is meaningless. [`running_start`](@ref) is
manimlib's version of the same idea. See [`ease_in_sine`](@ref) for the family.
"""
ease_in_back(t::Real) = _EASE_C3 * t * t * t - _EASE_C1 * t * t

"""
    ease_out_back(t)

Goes PAST the target and settles back onto it — the classic "lands with
authority" arrival, and the one to reach for when something appears. Its value
exceeds 1 in the middle. See [`ease_in_back`](@ref).
"""
ease_out_back(t::Real) = 1 + _EASE_C3 * (t - 1)^3 + _EASE_C1 * (t - 1)^2

"""
    ease_in_out_back(t)

Winds up, goes, overshoots, settles. Leaves `[0, 1]` at BOTH ends. See
[`ease_in_back`](@ref).
"""
ease_in_out_back(t::Real) =
    t < 0.5 ? ((2t)^2 * ((_EASE_C2 + 1) * 2t - _EASE_C2)) / 2 :
    ((2t - 2)^2 * ((_EASE_C2 + 1) * (t * 2 - 2) + _EASE_C2) + 2) / 2

"""
    ease_in_elastic(t)

A spring wound up: several oscillations of growing amplitude before it lets go.
Both endpoints are special-cased to exactly 0 and 1.

Like [`ease_in_back`](@ref) it leaves `[0, 1]`, and much further — use it on
position and scale, not on opacity. See [`ease_in_sine`](@ref) for the family.
"""
function ease_in_elastic(t::Real)
    t == 0 && return 0.0
    t == 1 && return 1.0
    return -2.0^(10t - 10) * sin((t * 10 - 10.75) * _EASE_C4)
end
"""
    ease_out_elastic(t)

Arrives and wobbles to rest — the spring released. The most recognisable of the
whole family, and the one that reads as "springy" without any further work. See
[`ease_in_elastic`](@ref).
"""
function ease_out_elastic(t::Real)
    t == 0 && return 0.0
    t == 1 && return 1.0
    return 2.0^(-10t) * sin((t * 10 - 0.75) * _EASE_C4) + 1
end
"""
    ease_in_out_elastic(t)

Winds up, springs across, wobbles to rest. Elastic at both ends. See
[`ease_in_elastic`](@ref).
"""
function ease_in_out_elastic(t::Real)
    t == 0 && return 0.0
    t == 1 && return 1.0
    t < 0.5 && return -(2.0^(20t - 10) * sin((20t - 11.125) * _EASE_C5)) / 2
    return (2.0^(-20t + 10) * sin((20t - 11.125) * _EASE_C5)) / 2 + 1
end

"""
    ease_out_bounce(t)

Lands on the target and bounces off it — four parabolic arcs of decreasing
height, like a dropped ball.

Unlike [`ease_out_back`](@ref) and [`ease_out_elastic`](@ref) it never leaves
`[0, 1]`: every bounce is on the near side of the target, so this one is safe
on an opacity as well as on a position. See [`ease_in_sine`](@ref) for the
family.
"""
function ease_out_bounce(t::Real)
    n1, d1 = 7.5625, 2.75
    t < 1 / d1 && return n1 * t * t
    t < 2 / d1 && return n1 * (t - 1.5 / d1)^2 + 0.75
    t < 2.5 / d1 && return n1 * (t - 2.25 / d1)^2 + 0.9375
    return n1 * (t - 2.625 / d1)^2 + 0.984375
end
"""
    ease_in_bounce(t)

[`ease_out_bounce`](@ref) played backwards: it bounces where it STARTS and then
leaves, which reads as a ball gathering itself before rolling away.
"""
ease_in_bounce(t::Real) = 1 - ease_out_bounce(1 - t)

"""
    ease_in_out_bounce(t)

Bounces at both ends. See [`ease_out_bounce`](@ref).
"""
ease_in_out_bounce(t::Real) = t < 0.5 ? (1 - ease_out_bounce(1 - 2t)) / 2 :
                              (1 + ease_out_bounce(2t - 1)) / 2
