# animation/passing.jl — animations made of PARTIAL strokes.
#
# Everything here rides on `pointwise_become_partial!(dst, src, a, b)`, which
# gives you the stretch of a path between two proportions. `ShowCreation`
# already uses it with `a = 0`; what this file adds is a MOVING WINDOW —
# a → b travelling along the path — and the animations that fall out of it.
#
# THE THING TO KNOW BEFORE READING ON, because it decides how each of these
# behaves on a Tex or on a group: `pointwise_become_partial!` is NOT
# recursive. On a mobject with children and no points of its own it does
# nothing at all. So every animation here walks the family itself and applies
# the window to each child that HAS points — which also means each child gets
# the window over ITS OWN path, not over a share of the whole. On a formula
# that reads as every glyph flashing together, which is the right gesture; if
# you want one glyph after another, that is what `lag_ratio` is for.

"""
    VShowPassingFlash(m; time_width = 0.3, run_time = 1, …)

A bright stretch of the mobject's own outline, travelling along it:

```julia
play!(scene, VShowPassingFlash(circle))
play!(scene, VShowPassingFlash(path; time_width = 0.15, run_time = 2))
```

`time_width` is how much of the path is lit at once, as a fraction. The window
enters at one end and leaves at the other, so the animation begins and ends
with nothing showing.

It is a REMOVER, as in ManimGL (`indication.py:170,200`). The
window ends empty either way, so what the flag decides is whether the mobject
stays on the stage afterwards — and GL takes it off, which is what a flash
over something already drawn wants. `remover = false` leaves it there,
for a flash that IS the mobject's entrance.

Use it to trace a route, to show a current running through a wire, or to point
at a shape without moving it. ManimGL's; CE calls the same idea
`ShowPassingFlash`, and that name is here too.

**On a group or a formula** every child gets the window over its own outline
at the same time. `lag_ratio` staggers them if you want the flash to travel
across the children instead.
"""
mutable struct VShowPassingFlash <: Animation
    base::AnimBase
    time_width::Float64
    pairs::Vector{NTuple{2,Mobject}}
end

function VShowPassingFlash(m::Mobject; time_width::Real = 0.3, kw...)
    0 < time_width <= 1 || throw(ArgumentError(
        "time_width is a fraction of the path and must be in (0, 1], got $time_width"))
    return VShowPassingFlash(AnimBase(; mobject = m, remover = true, kw...),
                             Float64(time_width), NTuple{2,Mobject}[])
end

"CE's name for the same animation."
ShowPassingFlash(m::Mobject; kw...) = VShowPassingFlash(m; kw...)

function begin!(v::VShowPassingFlash)
    v.base.starting_mobject = copy(v.base.mobject)
    v.pairs = _families(v.base.mobject, v.base.starting_mobject)
    interpolate!(v, 0.0)
    return v
end

function interpolate!(v::VShowPassingFlash, alpha::Real)
    n = length(v.pairs)
    tw = v.time_width
    for (i, (sub, from)) in enumerate(v.pairs)
        (sub isa VMobject && from isa VMobject) || continue
        has_points(from) || continue
        a = _sub_alpha(v.base, alpha, i, n)
        # The window slides from entirely before the path to entirely after
        # it, so both ends of the animation show nothing. Clamping is what
        # makes it enter and leave instead of wrapping round.
        upper = a * (1 + tw)
        pointwise_become_partial!(sub, from, clamp(upper - tw, 0, 1), clamp(upper, 0, 1))
    end
    return v
end

"Put the mobject back the way it was: the flash is a gesture, not a change."
function finish!(v::VShowPassingFlash)
    v.base.starting_mobject === nothing ||
        become!(v.base.mobject, v.base.starting_mobject)
    return v
end

"""
    FlashAround(m; buff = 0.05, color = YELLOW, run_time = 1, …)

Run a flash around the OUTLINE of a rectangle enclosing the mobject:

```julia
play!(scene, FlashAround(answer))
```

The mobject itself is untouched — nothing moves, nothing changes colour — so
it is the emphasis to use on a term inside a formula or a cell inside a table,
where growing the thing would push its neighbours around.

[`FlashUnder`](@ref) does the same along a line beneath it instead.
"""
function FlashAround(m::Mobject; buff::Real = 0.05, color = YELLOW,
                     stroke_width::Real = 4.0, time_width::Real = 0.4, kw...)
    box = SurroundingRectangle(m; buff)
    set_stroke!(box; color, width = stroke_width)
    set_fill!(box; opacity = 0.0)
    return VShowPassingFlash(box; time_width, kw...)
end

"""
    FlashUnder(m; buff = 0.1, color = YELLOW, run_time = 1, …)

A flash travelling along a line under the mobject — an underline that draws
itself and leaves. Manim CE's `FlashUnder`.
"""
function FlashUnder(m::Mobject; buff::Real = 0.1, color = YELLOW,
                    stroke_width::Real = 4.0, time_width::Real = 0.4, kw...)
    line = Underline(m; buff, color, stroke_width)
    return VShowPassingFlash(line; time_width, kw...)
end

"""
    ShowCreationThenDestruction(m; run_time = 1, …)

Draw the mobject and then undraw it, in one animation:

```julia
play!(scene, ShowCreationThenDestruction(arrow))
```

It is [`ShowCreation`](@ref) with `there_and_back`, which is the whole trick —
the rate function goes 0 → 1 → 0 and the partial-stroke machinery does the
rest. The mobject is left as it was found.
"""
ShowCreationThenDestruction(m::Mobject; kw...) =
    ShowCreation(m; rate_func = there_and_back, kw...)

"""
    ShowCreationThenFadeOut(m; run_time = 1, …)

Draw the mobject, then fade the whole thing out — and take it off stage.
Unlike [`ShowCreationThenDestruction`](@ref), which undraws it stroke by
stroke, this one lets the finished shape dissolve.
"""
function ShowCreationThenFadeOut(m::Mobject; run_time::Real = 1.0, kw...)
    half = Float64(run_time) / 2
    return Succession(ShowCreation(m; run_time = half),
                      FadeOut(m; run_time = half); kw...)
end

"""
    TurnInsideOut(m; run_time = 1, …)

Turn a shape through itself: every point travels to the point diametrically
opposite along its path, so the outline passes through its own middle and
comes back inverted.

```julia
play!(scene, TurnInsideOut(square))
```

ManimGL's. It is a `Transform` towards the same shape with its points
REVERSED, and what makes it worth having is the middle of the animation, not
the ends: the winding flips on the way through, so a filled shape empties and
re-fills. Look at α = 0.5 before using it on something with a hole.
"""
function TurnInsideOut(m::VMobject; kw...)
    make_target = function ()
        t = copy(m)
        set_points!(t, reverse(get_points(m)))
        return t
    end
    return Transform(AnimBase(; mobject = m, kw...), nothing, nothing,
                     make_target, nothing, NTuple{3,Mobject}[], Bool[])
end

"""
    AddTextLetterByLetter(text; run_time = -1, …)

Type a text out, one glyph at a time:

```julia
play!(scene, AddTextLetterByLetter(TextMobject("hola mundo")))
```

Where [`Write`](@ref) draws every glyph's outline (a handwriting gesture),
this one makes whole glyphs APPEAR in order — a typewriter. On a long line the
difference is large: `Write` is calligraphy and this is typing.

With `run_time = -1` (the default) the duration is picked from the number of
glyphs, as `Write` does, so a long line takes longer than a short one.

It is [`ShowIncreasingSubsets`](@ref) over the glyphs, which is exactly what
Manim's is.
"""
function AddTextLetterByLetter(text::VMobject; run_time::Real = -1,
                               time_per_char::Real = 0.06, kw...)
    n = length(text)
    n > 0 || throw(ArgumentError(
        "that mobject has no glyphs to type — AddTextLetterByLetter wants a " *
        "TextMobject or a Tex, whose children are the glyphs"))
    rt = run_time < 0 ? max(0.5, n * Float64(time_per_char)) : Float64(run_time)
    return ShowIncreasingSubsets(text; run_time = rt, kw...)
end

"""
    TypeWithCursor(text, cursor; run_time = -1, …)

[`AddTextLetterByLetter`](@ref) with a cursor that follows the last glyph
typed:

```julia
cursor = Rectangle(; width = 0.06, height = 0.5)
set_fill!(cursor; color = WHITE, opacity = 1.0)
play!(scene, TypeWithCursor(line, cursor))
```

The cursor is a mobject you provide, so it can be a bar, a block or an
underscore. Add it to the scene yourself before playing, and use
[`Blink`](@ref) on it afterwards if you want it to keep blinking.

Manim CE's.
"""
function TypeWithCursor(text::VMobject, cursor::Mobject; run_time::Real = -1,
                        time_per_char::Real = 0.06, buff::Real = 0.1, kw...)
    n = length(text)
    n > 0 || throw(ArgumentError("that mobject has no glyphs to type"))
    rt = run_time < 0 ? max(0.5, n * Float64(time_per_char)) : Float64(run_time)
    typing = AddTextLetterByLetter(text; run_time = rt, time_per_char, kw...)
    # NOT a do-block: `UpdateFromAlphaFunc` takes the MOBJECT first, and the
    # do-block syntax passes the function as the first argument.
    chase = function (c, a)
        k = clamp(ceil(Int, a * n), 1, n)
        next_to!(c, text[k], RIGHT; buff)
        return c
    end
    follow = UpdateFromAlphaFunc(cursor, chase; run_time = rt, rate_func = linear)
    return AnimationGroup(typing, follow; run_time = rt)
end
