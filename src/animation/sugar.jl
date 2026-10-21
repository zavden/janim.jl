# animation/sugar.jl — names for animations you can already write.
#
# Not one new mechanism in this file. Every constructor below resolves to a
# `Transform`, an `animate`, a `LaggedStart` or an updater that exist
# already, and its whole value is at the CALL SITE: `FadeToColor(m,
# RED)` says what is happening where `animate(m, (set_color!, RED))` says how
# it is done.
#
# The two that are NOT pure sugar carry their own struct and say so:
# `VFadeIn`, because fading only the STYLE is a different animation from
# fading towards a transparent copy, and `ShowIncreasingSubsets`, because
# revealing children one at a time is about the family and not about points.

# ── over `animate` ──────────────────────────────────────────────────────────

"""
    FadeToColor(m, color; run_time = 1, …)

Animate a mobject to a new colour, leaving everything else alone.

```julia
play!(scene, FadeToColor(square, YELLOW))
```

Both engines have it. It is `animate(m, (set_color!, color))`, and the name is
what it buys.
"""
FadeToColor(m::Mobject, color; kw...) = animate(m, (_recolour!, color); kw...)

"`set_color!` takes its colour as a KEYWORD, so `animate` needs this adapter."
_recolour!(m::Mobject, c) = set_color!(m; color = c)

"""
    ScaleInPlace(m, factor; run_time = 1, …)

Scale about the mobject's own centre, so it grows without drifting.

```julia
play!(scene, ScaleInPlace(logo, 1.4))
```

`scale!` is already about the centre in Janim, so this is `animate(m, (scale!,
factor))` under a name that says the intent — in Manim the distinction matters
more, because there `scale` can be given another origin.
"""
ScaleInPlace(m::Mobject, factor::Real; kw...) = animate(m, (scale!, factor); kw...)

"""
    FadeInFromPoint(m, point; run_time = 1, …)

Fade in while growing out of a point:

```julia
play!(scene, FadeInFromPoint(label, get_center(source)))
```

The mobject appears to come FROM somewhere, which is what makes it read as
caused by the thing it came from rather than as appearing on its own.
"""
function FadeInFromPoint(m::Mobject, point; kw...)
    start = copy(m)
    scale!(start, 1e-3)
    move_to!(start, Point3f(point))
    set_stroke!(start; opacity = 0)
    set_fill!(start; opacity = 0)
    return Transform(AnimBase(; mobject = m, kw...), nothing, nothing,
                     () -> copy(m), () -> start, NTuple{3,Mobject}[], Bool[])
end

"""
    FadeOutToPoint(m, point; run_time = 1, …)

The reverse of [`FadeInFromPoint`](@ref): shrink into a point and vanish. The
mobject leaves the scene when it finishes, like [`FadeOut`](@ref).
"""
function FadeOutToPoint(m::Mobject, point; kw...)
    make_target = function ()
        t = copy(m)
        scale!(t, 1e-3)
        move_to!(t, Point3f(point))
        set_stroke!(t; opacity = 0)
        set_fill!(t; opacity = 0)
        return t
    end
    return Transform(AnimBase(; mobject = m, remover = true, final_alpha = 0.0, kw...),
                     nothing, nothing, make_target, nothing, NTuple{3,Mobject}[], Bool[])
end

# ── over Transform ──────────────────────────────────────────────────────────

"""
    CyclicReplace(mobs...; path_arc = TAU/4, run_time = 1, …)

Rotate a set of mobjects through each other's places: the last one takes the
first one's spot and everything else shifts along.

```julia
play!(scene, CyclicReplace(a, b, c))      # a→b's place, b→c's, c→a's
```

`path_arc` makes them travel along an arc instead of in straight lines, which
is what keeps them from passing through each other. 90° is both engines'
default.

[`Swap`](@ref) is the same animation under Manim's other name.
"""
function CyclicReplace(mobs::Mobject...; path_arc::Real = TAU / 4, kw...)
    length(mobs) >= 2 || throw(ArgumentError(
        "CyclicReplace needs at least two mobjects to swap round (got $(length(mobs)))"))
    group = VGroup(mobs...)
    make_target = function ()
        t = copy(group)
        centres = [get_center(m) for m in mobs]
        cycled = [centres[end], centres[1:end-1]...]
        for (child, dest) in zip(t.submobjects, cycled)
            move_to!(child, dest)
        end
        return t
    end
    # The 7-argument form takes no keywords; `path_arc` is the 10th field,
    # so the full constructor is the way to bend the paths.
    return Transform(AnimBase(; mobject = group, kw...), nothing, nothing,
                     make_target, nothing, NTuple{3,Mobject}[], Bool[],
                     false, Float64(path_arc), Point3f(OUT))
end

"""
    Swap(a, b; …)

Manim's other name for [`CyclicReplace`](@ref) — the same animation. With two
mobjects a cycle IS a swap, which is where the second name comes from.
"""
Swap(mobs::Mobject...; kw...) = CyclicReplace(mobs...; kw...)

"""
    CircleIndicate(m; color = YELLOW, run_time = 1, …)

Flash a circle around a mobject and let it fade:

```julia
play!(scene, CircleIndicate(answer))
```

Where [`Indicate`](@ref) grows the mobject ITSELF, this leaves it alone and
draws attention beside it — the one to use when the thing being pointed at
must not move (a cell in a table, a term in a formula).
"""
function CircleIndicate(m::Mobject; color = YELLOW, scale_factor::Real = 1.2,
                        run_time::Real = 1.0, kw...)
    c = Circle(; radius = 0.5 * sqrt(Float64(get_width(m))^2 +
                                     Float64(get_height(m))^2) * scale_factor)
    set_stroke!(c; color, width = 3.0)
    set_fill!(c; opacity = 0.0)
    move_to!(c, get_center(m))
    return Succession(ShowCreation(c; run_time = run_time / 2),
                      FadeOut(c; run_time = run_time / 2); kw...)
end

# ── over LaggedStart ────────────────────────────────────────────────────────

# `f` is any callable, as GL's `anim_func` is — an animation TYPE
# (`LaggedStartMap(ShowCreation, tree)`, the literal translation of the .py)
# is not a `Function` in Julia, so `f::Function` would refuse it.
"""
    LaggedStartMap(f, group; lag_ratio = 0.05, run_time = 2.0, kw...)

Apply the same animation to every child of a group, starting each a little
after the last:

```julia
play!(scene, LaggedStartMap(FadeIn, dots))
play!(scene, LaggedStartMap(m -> Indicate(m; color = RED), row))
play!(scene, LaggedStartMap(FadeIn, dots; shift = UP, rate_func = linear))
```

`f` takes a mobject and returns an animation. It is `LaggedStart(f.(children)...)`
with the loop written for you, and it is the shape most "reveal a list" moments
want. Every other keyword goes to EACH child animation — `f(child;
kw...)` — as in ManimGL (composition.py:175); only `lag_ratio` and `run_time`
belong to the group.

`run_time` is **2.0** because that is what ManimGL puts in the
signature (`composition.py:171`), not something it computes — a cascade over
a long row reads too fast at the 1.05 the lag arithmetic gives. Ask for
`run_time = -1` to get that computed duration back.
"""
function LaggedStartMap(f, group::Mobject; lag_ratio::Real = 0.05,
                        run_time::Real = 2.0, kw...)
    children = collect(group)
    isempty(children) && throw(ArgumentError(
        "LaggedStartMap over a group with no children — there is nothing to animate"))
    return LaggedStart([f(c; kw...) for c in children]...; lag_ratio, run_time)
end

"""
    BroadcastRipple(m; focal_point = ORIGIN, n = 5, run_time = 3, …)

Rings spreading out from a point, like a drop hitting water:

```julia
play!(scene, BroadcastRipple(Circle(; radius = 2); focal_point = get_center(dot)))
```

`n` copies of the mobject, each starting collapsed at the focal point and
growing to full size while it fades, staggered so they read as one wave.

**The name**: Manim calls this `Broadcast`, and `Broadcast` is a MODULE in
`Base` — `Base.Broadcast`, the machinery behind every `f.(x)` in Julia.
Shadowing it is not an option, and unlike `Text`/`Vector`/`Matrix` there is no
mobject to suffix, so this one takes a descriptive name instead. See
`docs/naming.md`.
"""
function BroadcastRipple(m::Mobject; focal_point = ORIGIN, n::Int = 5,
                         initial_width::Real = 0.0, final_opacity::Real = 0.0,
                         lag_ratio::Real = 0.2, run_time::Real = 3.0, kw...)
    n >= 1 || throw(ArgumentError("BroadcastRipple needs at least one ring, got $n"))
    anims = Animation[]
    for _ in 1:n
        ring = copy(m)
        move_to!(ring, Point3f(focal_point))
        target = copy(ring)
        set_stroke!(target; opacity = final_opacity)
        set_fill!(target; opacity = final_opacity)
        initial_width > 0 ? set_width!(ring, initial_width) : scale!(ring, 1e-3)
        push!(anims, Transform(AnimBase(; mobject = ring, remover = true,
                                        run_time = run_time / 2),
                               nothing, nothing, () -> target, nothing,
                               NTuple{3,Mobject}[], Bool[]))
    end
    return LaggedStart(anims...; lag_ratio, run_time, kw...)
end

"""
    Blink(m; times = 1, run_time = 1, …)

Make a mobject blink: out and back in, `times` times.

```julia
play!(scene, Blink(cursor; times = 3))
```

Manim CE's. It is a [`Succession`](@ref) of fades, so the mobject is left
exactly as it was found — on stage and visible (the `VFadeOut` inside
restores the opacity when it ends and is told NOT to remove).
"""
function Blink(m::Mobject; times::Int = 1, run_time::Real = 1.0, kw...)
    times >= 1 || throw(ArgumentError("Blink needs at least one blink, got $times"))
    each = Float64(run_time) / (2 * times)
    anims = Animation[]
    for _ in 1:times
        push!(anims, VFadeOut(m; run_time = each, remover = false))
        push!(anims, VFadeIn(m; run_time = each))
    end
    return Succession(anims...; kw...)
end

# ── animations with their own struct ────────────────────────────────────────

"""
    VFadeIn(m; run_time = 1, …)

Fade a mobject in by its OPACITY alone — no movement, no scaling, nothing but
the alpha climbing from zero to whatever it already was.

```julia
play!(scene, VFadeIn(overlay))
```

The difference from [`FadeIn`](@ref) matters more than it sounds. `FadeIn`
transforms towards a copy, so it interpolates every attribute; this touches
stroke and fill opacity and leaves the points alone. On a mobject whose points
are being written by an updater — a `TracedPath`, a plot that is still
growing — `FadeIn` fights the updater and this does not.

ManimGL's, and the reason its docstring there says "only work for VMobjects".
"""
mutable struct VFadeIn <: Animation
    base::AnimBase
    out::Bool
    pairs::Vector{NTuple{2,Mobject}}
end

VFadeIn(m::Mobject; kw...) =
    VFadeIn(AnimBase(; mobject = m, kw...), false, NTuple{2,Mobject}[])

"""
    VFadeOut(m; run_time = 1, …)

[`VFadeIn`](@ref) backwards: the opacity falls to zero and the scene drops the
mobject when it finishes — handing it back at its opacity, like
[`FadeOut`](@ref) (fading.py:180).
"""
VFadeOut(m::Mobject; kw...) =
    VFadeIn(AnimBase(; mobject = m, remover = true, final_alpha = 0.0, kw...), true,
            NTuple{2,Mobject}[])

function begin!(v::VFadeIn)
    v.base.starting_mobject = copy(v.base.mobject)
    v.pairs = _families(v.base.mobject, v.base.starting_mobject)
    interpolate!(v, 0.0)
    return v
end

function interpolate!(v::VFadeIn, alpha::Real)
    n = length(v.pairs)
    for (i, (sub, from)) in enumerate(v.pairs)
        (sub isa VMobject && from isa VMobject) || continue
        a = _sub_alpha(v.base, alpha, i, n)
        v.out && (a = 1 - a)
        # The TARGET opacities are the ones the mobject had when it started,
        # so a half-transparent shape fades in to half-transparent and not to
        # opaque — which is what "fade in what is there" has to mean.
        for k in eachindex(sub.stroke_rgba)
            c = from.stroke_rgba[k]
            sub.stroke_rgba[k] = Vec4f(c[1], c[2], c[3], Float32(a) * c[4])
        end
        for k in eachindex(sub.fill_rgba)
            c = from.fill_rgba[k]
            sub.fill_rgba[k] = Vec4f(c[1], c[2], c[3], Float32(a) * c[4])
        end
    end
    return v
end

"""
    VFadeInThenOut(m; run_time = 1, remover = true, …)

Fade in and back out again — a flash. ManimGL's, with its ending
(fading.py:199): the mobject is handed back at its opacity (`final_alpha =
0.5`, the top of `there_and_back`) and REMOVED from the stage; `remover =
false` keeps it there, visible.
"""
VFadeInThenOut(m::Mobject; rate_func::Function = there_and_back,
               remover::Bool = true, final_alpha::Real = 0.5, kw...) =
    VFadeIn(m; rate_func, remover, final_alpha = Float64(final_alpha), kw...)

"""
    ShowIncreasingSubsets(group; run_time = 1, …)

Reveal a group's children one at a time, in order:

```julia
play!(scene, ShowIncreasingSubsets(bullet_points))
play!(scene, ShowIncreasingSubsets(dots; run_time = 3))
```

Nothing fades and nothing is drawn stroke by stroke — children simply APPEAR,
which is the right gesture for a list, a series of steps or a scatter filling
in. Present in both engines.

It is about the FAMILY, not about points: at α there are `round(α · n)`
children on stage. [`ShowSubmobjectsOneByOne`](@ref) shows one at a time
instead of accumulating.
"""
mutable struct ShowIncreasingSubsets <: Animation
    base::AnimBase
    one_at_a_time::Bool
    children::Vector{Mobject}
    # The opacities each child had when the animation began, so hiding and
    # showing restores what was there instead of forcing everything opaque.
    saved::Vector{Mobject}
end

# `rate_func = linear` on purpose, and it is not a detail. With the default
# `smooth` the reveal eases in and out, which on a COUNT means the middle
# children flash past while the first and last linger — measured on three
# children, α = 0.67 already showed all three and the second was never alone.
# Each child gets the same slice of time, which is what "one at a time" means.
function ShowIncreasingSubsets(group::Mobject; one_at_a_time::Bool = false,
                               rate_func::Function = linear, kw...)
    kids = collect(group)
    isempty(kids) && throw(ArgumentError(
        "ShowIncreasingSubsets over a group with no children — nothing to reveal"))
    return ShowIncreasingSubsets(AnimBase(; mobject = group, rate_func, kw...),
                                 one_at_a_time, Vector{Mobject}(kids), Mobject[])
end

"""
    ShowSubmobjectsOneByOne(group; …)

[`ShowIncreasingSubsets`](@ref) showing ONE child at a time rather than
accumulating them — a flip-book instead of a list filling in.
"""
ShowSubmobjectsOneByOne(group::Mobject; kw...) =
    ShowIncreasingSubsets(group; one_at_a_time = true, kw...)

function begin!(s::ShowIncreasingSubsets)
    s.base.starting_mobject = copy(s.base.mobject)
    s.saved = Mobject[copy(c) for c in s.children]
    interpolate!(s, 0.0)
    return s
end

function interpolate!(s::ShowIncreasingSubsets, alpha::Real)
    n = length(s.children)
    a = s.base.rate_func(clamp(Float64(alpha), 0.0, 1.0))
    shown = clamp(ceil(Int, a * n), 0, n)
    for (i, child) in enumerate(s.children)
        visible = s.one_at_a_time ? (i == max(shown, 1)) : (i <= shown)
        _set_visible!(child, visible, get(s.saved, i, nothing))
    end
    return s
end

finish!(s::ShowIncreasingSubsets) = (interpolate!(s, s.base.final_alpha); s)

"""
Show or hide one child by its opacity, restoring what it had from `saved`.

BOTH stroke AND fill, and that is not belt-and-braces: text and formulas are
drawn by their FILL and have no stroke at all, so an earlier version of this
that touched only the stroke left every glyph visible from the first frame.
It passed its own lock, because the lock used squares and circles — which do
have a stroke. Caught in a render of `AddTextLetterByLetter`.

Restoring FROM the saved copy rather than forcing 1.0 is the other half: a
half-transparent child has to come back half-transparent.
"""
function _set_visible!(m::Mobject, visible::Bool, saved)
    m isa VMobject || return m
    fam = collect(get_family(m))
    ref = saved isa VMobject ? collect(get_family(saved)) : nothing
    for (i, sub) in enumerate(fam)
        sub isa VMobject || continue
        src = (ref !== nothing && i <= length(ref) && ref[i] isa VMobject) ? ref[i] : sub
        for k in eachindex(sub.stroke_rgba)
            c = sub.stroke_rgba[k]
            a = visible ? (k <= length(src.stroke_rgba) ? src.stroke_rgba[k][4] : c[4]) :
                zero(Float32)
            sub.stroke_rgba[k] = Vec4f(c[1], c[2], c[3], a)
        end
        for k in eachindex(sub.fill_rgba)
            c = sub.fill_rgba[k]
            a = visible ? (k <= length(src.fill_rgba) ? src.fill_rgba[k][4] : c[4]) :
                zero(Float32)
            sub.fill_rgba[k] = Vec4f(c[1], c[2], c[3], a)
        end
    end
    return m
end

"""
    MaintainPositionRelativeTo(m, other; run_time = 1, …)

Keep `m` at the offset it currently has from `other`, whatever `other` does:

```julia
play!(scene, animate(planet, (shift!, 4 * RIGHT)),
             MaintainPositionRelativeTo(moon, planet))
```

It is an updater expressed as an animation, so it composes in a `play!` beside
the animation that is moving the other mobject. For a permanent link, use
[`add_updater!`](@ref) directly — this one lasts as long as the play.

Present in both engines.
"""
function MaintainPositionRelativeTo(m::Mobject, other::Mobject; kw...)
    offset = get_center(m) - get_center(other)
    return UpdateFromAlphaFunc(m, (mob, _) -> move_to!(mob, get_center(other) + offset);
                               kw...)
end
