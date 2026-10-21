# Emphasis animations.
#
# "Look HERE": the family every explanatory video leans on. Not one of them is
# a new mechanism — they are all composition over the existing pieces
# (there_and_back + Transform + ShowCreation + AnimationGroup). That is the
# point: if any of these needed a new primitive, the primitive was missing.

"""
    SurroundingRectangle(m; buff=0.1, color=YELLOW, stroke_width=2)

A rectangle around `m`'s bounding box: four lines over `surround!`, which
`Circumscribe` also uses.
"""
function SurroundingRectangle(m::Mobject; buff::Real = 0.1, color = YELLOW,
                              stroke_width::Real = 2.0)
    r = Rectangle(width = get_width(m) + 2buff, height = get_height(m) + 2buff)
    set_stroke!(r; color, width = stroke_width)
    set_fill!(r; opacity = 0)
    move_to!(r, get_center(m))
    return r
end

"""
    Indicate(m; scale_factor=1.2, color=YELLOW, kw...)

Grow and tint, then come back: a Transform toward a scaled, coloured copy with
`there_and_back`. Manim's numbers exactly (indication.py:Indicate).
"""
function Indicate(m::Mobject; scale_factor::Real = 1.2, color = YELLOW,
                  rate_func::Function = there_and_back, kw...)
    make_target = function ()
        t = copy(m)
        scale!(t, scale_factor)
        set_color!(t; color)
        return t
    end
    return Transform(AnimBase(; mobject = m, rate_func, kw...), nothing, nothing,
                     make_target, nothing, NTuple{3,Mobject}[], Bool[])
end

"""
    FocusOn(point_or_mobject; opacity=0.2, color=GREY, run_time=2)

A huge translucent disc that shrinks onto the target — the "camera iris"
gesture. It is a remover: the scene drops it when it ends.

Manim starts from a disc of radius FRAME_X_RADIUS + FRAME_Y_RADIUS with
opacity 0 and ends at radius 0 with `opacity`; the eye reads the shrinking
edge, not the fill.
"""
function FocusOn(target; opacity::Real = 0.2, color = GREY_C, run_time::Real = 2.0,
                 kw...)
    center = target isa Mobject ? get_center(target) : Point3f(target)
    make_start = function ()
        d = Dot(center; radius = FRAME_X_RADIUS + FRAME_Y_RADIUS)
        set_stroke!(d; width = 0, opacity = 0)
        set_fill!(d; color, opacity = 0)
        return d
    end
    make_target = function ()
        d = Dot(center; radius = 0)
        set_stroke!(d; width = 0, opacity = 0)
        set_fill!(d; color, opacity)
        return d
    end
    return Transform(AnimBase(; mobject = make_start(), run_time, remover = true, kw...),
                     nothing, nothing, make_target, make_start,
                     NTuple{3,Mobject}[], Bool[])
end

"""
    Flash(point_or_mobject; color=YELLOW, line_length=0.2, num_lines=12,
          flash_radius=0.3, line_stroke_width=3, run_time=1)

The radial burst. `num_lines` segments spread over TAU, each drawn outwards
and then erased, so the burst reads as one gesture instead of twelve
overlapping ones.

Each ray is its own [`ShowCreationThenFadeOut`](@ref) — a `Succession` — and
the twelve of them run together in an `AnimationGroup`. That split is
load-bearing; see the note in [`Circumscribe`](@ref) for what happens when
two animations over ONE mobject go into the group instead.
"""
function Flash(target; color = YELLOW, line_length::Real = 0.2,
               num_lines::Int = 12, flash_radius::Real = 0.3,
               line_stroke_width::Real = 3.0, run_time::Real = 1.0, kw...)
    center = target isa Mobject ? get_center(target) : Point3f(target)
    lines = VMobject[]
    for k in 0:(num_lines - 1)
        theta = k * TAU / num_lines
        dir = Point3f(cos(theta), sin(theta), 0)
        ln = Line(center + Float32(flash_radius) * dir,
                  center + Float32(flash_radius + line_length) * dir)
        set_stroke!(ln; color, width = line_stroke_width)
        push!(lines, ln)
    end
    group = VGroup(lines...)
    anims = Animation[ShowCreationThenFadeOut(ln; run_time) for ln in lines]
    g = AnimationGroup(anims...; run_time, kw...)
    g.base.mobject = group
    g.base.remover = true
    return g
end

"""
    Circumscribe(m; shape=:rectangle, buff=0.1, color=YELLOW, run_time=1)

Draw a box (or circle) around `m` and rub it out again: ShowCreation followed
by FadeOut, one per half of the run. A remover.

**Why a `Succession` and not an `AnimationGroup`.** The two halves act on
the SAME outline, and an `AnimationGroup` begins every child at once — as
ManimGL and CE both do. The `FadeOut` would therefore snapshot the outline that
the `ShowCreation` had just collapsed to nothing, and restore that empty state
on every frame: the animation would draw **zero** length at every instant of
its run, while every other property of it (box size, remover, rate windows)
looked correct. `Succession` begins each child when its turn comes, which is
exactly the difference. CE's own `Circumscribe` is a `Succession`, and it is
the reference here — ManimGL has no `Circumscribe`.

**One deliberate divergence from CE.** CE's *default* branch is a single
`ShowPassingFlash` around the shape; create-then-fade is what it does under
`fade_out = True`. Janim keeps create-then-fade as the default gesture, and
CE's flash is one line away when you want it:
`ShowPassingFlash(SurroundingRectangle(m))`.
"""
function Circumscribe(m::Mobject; shape::Symbol = :rectangle, buff::Real = 0.1,
                      color = YELLOW, stroke_width::Real = 2.0,
                      run_time::Real = 1.0, kw...)
    outline = if shape === :rectangle
        SurroundingRectangle(m; buff, color, stroke_width)
    elseif shape === :circle
        c = Circle(radius = 0.5 * hypot(get_width(m), get_height(m)) + buff)
        set_stroke!(c; color, width = stroke_width)
        set_fill!(c; opacity = 0)
        move_to!(c, get_center(m))
        c
    else
        throw(ArgumentError("Circumscribe: shape :$shape is unknown — " *
                            ":rectangle or :circle"))
    end
    g = ShowCreationThenFadeOut(outline; run_time, kw...)
    g.base.mobject = outline
    g.base.remover = true
    return g
end

"""
    Wiggle(m; scale_value=1.1, rotation_angle=0.01·TAU, n_wiggles=6, run_time=2)

Shake to draw the eye without moving anything permanently: the mobject grows
slightly (there_and_back) while rocking `n_wiggles` times. Points come from
the START state every frame, so the wiggle leaves nothing behind.
"""
mutable struct Wiggle <: Animation
    base::AnimBase
    scale_value::Float64
    rotation_angle::Float64
    n_wiggles::Int
    pairs::Vector{NTuple{2,Mobject}}
end

Wiggle(m::Mobject; scale_value::Real = 1.1, rotation_angle::Real = 0.01TAU,
       n_wiggles::Int = 6, run_time::Real = 2.0, rate_func::Function = linear, kw...) =
    Wiggle(AnimBase(; mobject = m, run_time, rate_func, kw...), Float64(scale_value),
           Float64(rotation_angle), n_wiggles, NTuple{2,Mobject}[])

begin!(w::Wiggle) = (w.base.starting_mobject = copy(w.base.mobject);
                     w.pairs = _families(w.base.mobject, w.base.starting_mobject);
                     interpolate!(w, 0.0); w)

"The wiggle's oscillator: |sin(n·π·t)| — n full swings over the run."
_wiggle(t::Real, n::Int) = sin(n * PI * t)

function interpolate!(w::Wiggle, alpha::Real)
    for (sub, from) in w.pairs
        sub isa VMobject && from isa VMobject && set_points!(sub, get_points(from))
    end
    a = w.base.rate_func(clamp(alpha, 0, 1))
    mob = w.base.mobject
    center = get_bounding_box_point(w.base.starting_mobject, ORIGIN)
    scale!(mob, 1 + (w.scale_value - 1) * there_and_back(a); about_point = center)
    rotate!(mob, w.rotation_angle * _wiggle(a, w.n_wiggles); about_point = center)
    return w
end
