# animation/creation.jl — DrawBorderThenFill and Write, the rest of the
# appearance animations and the generic escape valve.
#
# Port of manimlib/animation/{creation,growing,update}.py. Nothing here is a
# new MECHANISM: it is the standard life cycle plus two pieces that already
# exist — `pointwise_become_partial!` (which cuts by subpath) and the
# exact-at-the-ends `interpolate!`. That second one is what makes «it ends
# EXACT» a property of the design instead of a tolerance: at α=1 the style
# rows are COPIED from the snapshot, not lerped towards it.

# ═══════════════════════════════════════════════════════════════════════
# DrawBorderThenFill — the two-half animation (creation.py:69)
# ═══════════════════════════════════════════════════════════════════════
#
# First half: draw the BORDER, an outline of the mobject with no fill and a
# borrowed stroke. Second half: cross-fade that outline into the real thing —
# the fill rises and the borrowed stroke settles back to what it really was.
#
# Both halves come out of ONE number: integer_interpolate(0, 2, α) splits the
# rate function in two and hands back which half we are in plus how far into
# it. That is why the default rate_func is `double_smooth` — a full ease in
# each half, so the two gestures read as two.

mutable struct DrawBorderThenFill <: Animation
    base::AnimBase
    stroke_width::Float64
    stroke_color::Any                   # nothing = each member's own colour
    outline::Union{Nothing,Mobject}     # built in begin!, like every snapshot
    triples::Vector{NTuple{3,Mobject}}  # (live, snapshot, outline) per member
    reverse_lag::Bool                   # Unwrite: the LAST child leaves first
end

"""
    DrawBorderThenFill(m; stroke_width=2, stroke_color=nothing, run_time=2, …)

Draw `m`'s outline and then fill it in — the animation that makes a shape look
DRAWN rather than dropped in.

`stroke_color=nothing` gives each family member its OWN colour (`get_color`:
its fill when it has one, its stroke otherwise), so a two-coloured formula
draws each glyph in its own colour. Manim passes a single colour for the whole
mobject; ours is the same thing when the mobject is one colour, and better
when it is not.
"""
function DrawBorderThenFill(m::VMobject; stroke_width::Real = 2.0,
                            stroke_color = nothing, run_time::Real = 2.0,
                            rate_func::Function = double_smooth,
                            reverse_lag::Bool = false, kw...)
    DrawBorderThenFill(AnimBase(; mobject = m, run_time, rate_func, kw...),
                       Float64(stroke_width), stroke_color, nothing,
                       NTuple{3,Mobject}[], reverse_lag)
end

"""
The outline: same points, no fill, and a stroke BORROWED for the occasion.

Two details that are easy to get wrong. The colours are read from the ORIGINAL
(reading them after switching the fill off would return the stroke's colour —
`get_color` answers "fill if you have one"). And the borrowed stroke forces
opacity 1: manim can leave the opacity alone because its mobjects hide their
stroke with width 0, but ours are entitled to hide it with alpha 0 — a `Tex`
glyph is born `stroke_opacity=0`, and without this the border half would draw
nothing at all.
"""
function _borrowed_outline(m::VMobject, width::Real, color)
    colours = [(sub isa VMobject && has_points(sub)) ? get_color(sub) : nothing
               for sub in get_family(m)]
    o = copy(m)
    set_fill!(o; opacity = 0)
    for (sub, c) in zip(get_family(o), colours)
        (c === nothing || !(sub isa VMobject)) && continue
        set_stroke!(sub; color = color === nothing ? c : color,
                    width = width, opacity = 1, recurse = false)
    end
    return o
end

"Adopt `src`'s style ROW BY ROW (no flattening: per-point style survives)."
function _adopt_style!(dst::VMobject, src::VMobject)
    dst.stroke_rgba .= src.stroke_rgba
    dst.fill_rgba .= src.fill_rgba
    dst.stroke_width .= src.stroke_width
    return dst
end

function begin!(d::DrawBorderThenFill)
    m = d.base.mobject
    m isa VMobject || throw(ArgumentError(
        "DrawBorderThenFill needs vector geometry (a VMobject): a $(typeof(m)) " *
        "has no border to draw. For anything else, FadeIn is the general tool."))
    d.outline = _borrowed_outline(m, d.stroke_width, d.stroke_color)
    d.base.starting_mobject = copy(m)
    # the family pattern, NOT the parent: pointwise_become_partial! works on
    # ONE mobject's points, so on a Tex — a parent with no points — calling it
    # on the parent would draw nothing.
    d.triples = _families(m, d.base.starting_mobject, d.outline)
    interpolate!(d, 0.0)
    return d
end

function interpolate!(d::DrawBorderThenFill, alpha::Real)
    n = length(d.triples)
    for (i, (sub, start, out)) in enumerate(d.triples)
        (sub isa VMobject && start isa VMobject && out isa VMobject) || continue
        idx = d.reverse_lag ? n + 1 - i : i
        a = _sub_alpha(d.base, alpha, idx, n)
        half, sub_a = integer_interpolate(0, 2, a)
        if half == 0
            pointwise_become_partial!(sub, out, 0, sub_a)
            _adopt_style!(sub, out)    # idempotent: survives a rate_func that
                                       # walks backwards (there_and_back)
        else
            # outline → the real thing. The points of both ends are identical
            # (the outline IS a copy), so this is a pure style interpolation —
            # and at sub_a=1 exactly it COPIES the snapshot's rows: the
            # borrowed stroke returns to its true value, zero included.
            interpolate!(sub, out, start, sub_a)
        end
    end
    return d
end

"""
Exact α=1, and — for a remover (Unwrite) — the mobject handed back intact.

A reversed DrawBorderThenFill ends with its points collapsed and its style
borrowed; manim leaves that husk behind. Since the mobject is leaving the
scene anyway, we restore the snapshot: re-adding it later shows the real
thing. The last drawn frame is unaffected — `finish!` runs after it.
"""
function finish!(d::DrawBorderThenFill)
    interpolate!(d, d.base.final_alpha)
    if is_remover(d) && d.base.starting_mobject !== nothing
        become!(d.base.mobject, d.base.starting_mobject)
    end
    return d
end

"Family members that actually carry ink — what Write's numbers are keyed on."
_n_inked(m::Mobject) = count(get_family(m)) do sub
    sub isa VMobject && has_points(sub)
end

"""
    Write(m; run_time=auto, lag_ratio=auto, rate_func=linear, kw...)

`DrawBorderThenFill` with a LAG per family member: the pieces are written one
after another, the way a hand writes. Manim's automatic numbers, measured off
the real thing:

    run_time  = 1 if fewer than 15 inked members, else 2
    lag_ratio = min(4/(n+1), 0.2)

`rate_func=linear`, because the easing that
matters is already inside each member's two halves.
"""
function Write(m::VMobject; run_time::Real = -1, lag_ratio::Real = -1,
               rate_func::Function = linear, kw...)
    n = _n_inked(m)
    DrawBorderThenFill(m;
        run_time = run_time < 0 ? (n < 15 ? 1.0 : 2.0) : Float64(run_time),
        lag_ratio = lag_ratio < 0 ? min(4.0 / (n + 1.0), 0.2) : Float64(lag_ratio),
        rate_func = rate_func, kw...)
end

"""
    Unwrite(m; reverse=true, kw...)

`Write` run backwards: the ink is erased and the mobject leaves the scene.
`reverse=true` (the default) erases the LAST piece first, which is what makes
it read as un-writing rather than as a second, backwards writing.

CE gets that order by inverting the mobject's children in `begin` and putting
them back in `finish`; we remap the lag index instead — same picture, no
structural mutation of the user's mobject (swapping children would orphan
every external reference and every key group).
"""
function Unwrite(m::VMobject; rate_func::Function = linear, reverse::Bool = true,
                 remover::Bool = true, kw...)
    d = Write(m; rate_func = t -> rate_func(1 - t), remover = remover, kw...)
    d.reverse_lag = reverse
    return d
end

"""
    Uncreate(m; kw...)

`ShowCreation` backwards: the stroke retreats along its own path and the
mobject leaves the scene. Like `Unwrite`, it hands the mobject back intact.
"""
Uncreate(m::Mobject; rate_func::Function = smooth, remover::Bool = true, kw...) =
    ShowCreation(m; rate_func = t -> rate_func(1 - t), remover = remover, kw...)

# ═══════════════════════════════════════════════════════════════════════
# The growing family (growing.py) — Transforms with a manufactured START
# ═══════════════════════════════════════════════════════════════════════
#
# Every one of them is the same idea: the animation's target is the mobject as
# it stands, and its START is a copy scaled to nothing at some point. The
# start is built INSIDE begin!, so chaining inside a Succession
# snapshots the state at the right instant.

"""
    GrowFromPoint(m, point; point_color=nothing, path_arc=0, kw...)

`m` grows out of `point`. With `point_color`, the start is also tinted that
colour, so the growth carries a colour change as well.
"""
function GrowFromPoint(m::Mobject, point; point_color = nothing,
                       path_arc::Real = 0.0, path_arc_axis = OUT, kw...)
    make_start = function ()
        s = copy(m)
        scale!(s, 0)
        move_to!(s, Point3f(point))
        point_color === nothing || set_color!(s; color = point_color)
        return s
    end
    t = Transform(AnimBase(; mobject = m, kw...), nothing, nothing,
                  () -> copy(m), make_start, NTuple{3,Mobject}[], Bool[])
    t.path_arc = Float64(path_arc)
    t.path_arc_axis = Point3f(path_arc_axis)
    return t
end

"`m` grows out of its own centre."
GrowFromCenter(m::Mobject; kw...) = GrowFromPoint(m, get_center(m); kw...)

"`m` grows out of one edge of its bounding box: `GrowFromEdge(bar, DOWN)`."
GrowFromEdge(m::Mobject, edge; kw...) =
    GrowFromPoint(m, get_bounding_box_point(m, Point3f(edge)); kw...)

"An arrow that grows from its tail, tip and all — `GrowFromPoint` at `get_start`."
GrowArrow(m::Mobject; kw...) = GrowFromPoint(m, get_start(m); kw...)

"""
    DrawCurvedArrow(start, stop; path_arc=TAU/4, tip_start_scale=0.5,
                    tip_reveal_portion=0.3, run_time, rate_func, lag_ratio,
                    remover, arrow keywords...)

A curved arrow that is DRAWN instead of scaled: the shaft traces its own final
path, and the head rides the leading end at full size, tangent to the curve.

```julia
play!(scene, DrawCurvedArrow(3 * LEFT, 3 * RIGHT; path_arc = TAU / 4,
                             fill_color = YELLOW, run_time = 1.5))
```

**It is the counterpart of [`GrowArrow`](@ref), not a variant of it.**
`GrowArrow` is manim's and manim's is `GrowFromPoint`: the arrow is a shrunk
copy of itself that inflates, head and all. On a straight arrow that reads
fine; on a curved one it reads as a bent shape swelling rather than as an
arrow going somewhere. Both are here and they are different animations.

Neither reference engine has this. They have `CurvedArrow` as a mobject and no
animation for it.

**The head does not pop into existence.** It enters at `tip_start_scale` of
its final size and reaches full size once the shaft has covered
`tip_reveal_portion` of the path. Pass `tip_reveal_portion = 0` for a head
that is full size from the first frame.

**It takes the arrow's ARGUMENTS, not an arrow**, and that is forced rather
than chosen. In Manim CE the tip is a separate submobject, so the original of
this animation could `pointwise_become_partial` the shaft and move the tip by
hand. Janim's [`Arrow`](@ref) is ONE closed contour — shaft, head and belly in
a single path, which is what makes a `Transform` between two arrows pair head
with head — so there is no tip to move, and the honest way to draw a partial
arrow is to build it. Building it needs the arc's true endpoints and angle,
and a built `Arrow` does not remember them: Janim keeps no per-mobject state,
and `get_start` of a curved arrow is a corner of its outline, not the arc's
tail. So the animation constructs the arrow and hands it to the scene through
[`play!`](@ref), which registers an animation's mobject exactly as `self.play`
does.

Every keyword the animation does not use goes to `Arrow` — `thickness`,
`buff`, `fill_color` — so the drawn arrow and the final one are the same
object by construction and cannot drift.

**Colour it with `fill_color`, not `color`.** An arrow is drawn by its FILL
(its `stroke_width` is 0), and the constructor fixes `fill_color` itself, so
`color = YELLOW` sets a stroke nobody draws and leaves the arrow grey. ManimGL
does the same — measured, `Arrow(color=YELLOW)` there has fill `#BBBBBB` and
stroke `#FFFF00` — so this is manim's trap ported faithfully, not one of ours.

Adapted from a `DrawCurvedArrow` helper written for Manim CE scenes. One
thing did not come across: there the head also fades in, because it is its own
mobject with its own opacity. Here it is a stretch of rows in the arrow's
single contour, and singling those rows out means reproducing the
constructor's point layout — brittle, for a touch the size ramp already
covers.
"""
function DrawCurvedArrow(start, stop; path_arc::Real = TAU / 4,
                         tip_start_scale::Real = 0.5,
                         tip_reveal_portion::Real = 0.3,
                         run_time::Real = 1.0, rate_func::Function = smooth,
                         lag_ratio::Real = 0.0, remover::Bool = false,
                         buff::Real = MED_SMALL_BUFF, thickness::Real = 3.0,
                         tip_width_ratio::Real = 5, tip_angle::Real = PI / 3,
                         max_tip_length_to_length_ratio::Real = 0.5,
                         max_width_to_length_ratio::Real = 0.1, kw...)
    theta = Float64(path_arc)
    shape = (; buff, thickness, tip_width_ratio, tip_angle,
             max_tip_length_to_length_ratio, max_width_to_length_ratio)
    arrow = Arrow(start, stop; path_arc = theta, shape..., kw...)

    # The centre line, WITHOUT the buff the arrow trims: the drawing walks the
    # whole arc and the buff is the arrow's own business at each step.
    spine = Line(start, stop; path_arc = theta)

    # NOTE: the head does NOT need propping up to keep its size. Janim sizes
    # it from `thickness`, not from the arrow's length, and the two proportion
    # caps only bind below about 0.39 units — so a half-drawn arrow already
    # carries a full-sized head.

    # A zero-length shaft has no tangent to aim the head along, so the first
    # frame keeps this much of the path (the helper's `min_portion`).
    min_portion = 1e-3

    draw = function (m, alpha)
        a = clamp(Float64(alpha), 0.0, 1.0)
        if a >= 1
            # The end state is the arrow the caller ASKED for, built from its
            # own arguments — not from `point_from_proportion(spine, 1)`, which
            # is the arc's last point and lands a few Float32 bits off `stop`.
            become!(m, Arrow(start, stop; path_arc = theta, shape..., kw...))
            return m
        end
        portion = max(a, min_portion)
        reveal = tip_reveal_portion > 0 ? min(portion / tip_reveal_portion, 1.0) : 1.0
        scale = tip_start_scale + (1 - tip_start_scale) * reveal

        tip = point_from_proportion(spine, portion)
        len = Float64(norm(Point3f(tip) - Point3f(get_start(spine)))) - buff
        if len <= 1e-3
            # Shorter than its own buff: there is no arrow to draw yet, and
            # that is what `buff` MEANS. Collapsed on the tail is what nothing
            # looks like — and it is what GrowArrow shows at α = 0 too.
            become!(m, Arrow(start, stop; path_arc = theta, shape..., kw...))
            scale!(m, 0)
            move_to!(m, Point3f(get_start(spine)))
            return m
        end
        # The reveal rides on `tip_width_ratio`, which is the knob that sizes
        # the HEAD alone: `tip_width = tip_width_ratio × width`, and the head's
        # length follows from its width and `tip_angle`. Everything else is the
        # caller's, so a short shaft behaves exactly as a short Arrow does and
        # no ratio can run away.
        become!(m, Arrow(start, tip; path_arc = portion * theta, buff, thickness,
                         tip_width_ratio = tip_width_ratio * scale, tip_angle,
                         max_tip_length_to_length_ratio, max_width_to_length_ratio,
                         kw...))
        return m
    end
    return UpdateFromAlphaFunc(arrow, draw; run_time, rate_func, lag_ratio, remover)
end

"""
    SpinInFromNothing(m; angle=PI, kw...)

Grow from the centre WHILE spinning: `GrowFromCenter` with a curved path.
There is no other way round it — a start scaled to zero is a single point, and
rotating a point does nothing; the spin has to live in the trajectory, which
is exactly what `path_arc` is (CE builds this class the same way).
"""
SpinInFromNothing(m::Mobject; angle::Real = PI, kw...) =
    GrowFromCenter(m; path_arc = angle, kw...)

"""
    ShrinkToCenter(m; kw...)

The mirror of `GrowFromCenter`: `m` collapses onto its own centre. Manim does
NOT remove it afterwards (it stays as a zero-sized mobject) — pass
`remover=true` if you want it gone.
"""
function ShrinkToCenter(m::Mobject; kw...)
    make_target = function ()
        t = copy(m)
        scale!(t, 0)
        return t
    end
    return Transform(AnimBase(; mobject = m, kw...), nothing, nothing,
                     make_target, nothing, NTuple{3,Mobject}[], Bool[])
end

# ═══════════════════════════════════════════════════════════════════════
# The escape valve (update.py)
# ═══════════════════════════════════════════════════════════════════════

"""
    UpdateFromAlphaFunc(m, f; kw...)

The generic animation: `f(m, α)` is called each frame with the rate function
already applied. Whatever you can write as "the state of `m` at α", this
animates — no new type, no contract to implement.

Unlike every other animation here it takes NO snapshot, which is deliberate:
that is what lets it drive a mobject that cannot interpolate itself (a
`Surface`, a camera frame, something of your own). `f` is the whole authority.
"""
mutable struct UpdateFromAlphaFunc <: Animation
    base::AnimBase
    func::Any
end

UpdateFromAlphaFunc(m::Mobject, f; kw...) =
    UpdateFromAlphaFunc(AnimBase(; mobject = m, kw...), f)

begin!(u::UpdateFromAlphaFunc) = (interpolate!(u, 0.0); u)

function interpolate!(u::UpdateFromAlphaFunc, alpha::Real)
    u.func(u.base.mobject, u.base.rate_func(clamp(alpha, 0, 1)))
    return u
end

"""
    UpdateFromFunc(m, f; kw...)

`f(m)` each frame, with no α at all — for a mobject whose state depends on
ANOTHER mobject being animated at the same time (a label that follows a dot).
The sibling of an updater, but bounded by the animation's run time.
"""
mutable struct UpdateFromFunc <: Animation
    base::AnimBase
    func::Any
end

UpdateFromFunc(m::Mobject, f; kw...) = UpdateFromFunc(AnimBase(; mobject = m, kw...), f)

begin!(u::UpdateFromFunc) = (interpolate!(u, 0.0); u)
interpolate!(u::UpdateFromFunc, ::Real) = (u.func(u.base.mobject); u)

# ── the wrappers (an Axes, a DecimalNumber…) write like a VMobject ──
# Their lines and glyphs ARE VMobjects, one level down: the creation
# animations typed on VMobject take the group they wrap.
Write(w::_Wrapper; kw...) = Write(_inner(w); kw...)
Unwrite(w::_Wrapper; kw...) = Unwrite(_inner(w); kw...)
DrawBorderThenFill(w::_Wrapper; kw...) = DrawBorderThenFill(_inner(w); kw...)
