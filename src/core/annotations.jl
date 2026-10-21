# Annotations — Brace, BraceLabel, BackgroundRectangle, Underline, Cross,
# DashedLine / DashedVMobject.
#
# All of it is composition over Line and the relative layout. One deliberate
# divergence:
#
#   manimlib's Brace is `Tex("\\underbrace{\\qquad}")` — a LaTeX call to draw
#   a bracket. We build it as a NATIVE STRETCHABLE PATH (fixed tips, scalable
#   body). Two reasons: it removes a LaTeX dependency from something that is
#   pure geometry, and a stretched glyph thins its strokes while a built path
#   keeps them even.

"""
    Brace(m, direction=DOWN; buff=0.2, color=WHITE, stroke_width=0,
          thickness=0.18, tip_length=0.3)

A curly brace spanning `m`'s extent along `direction`.

Built as a path in five pieces: two end curls, two straight arms and a middle
spike. Only the ARMS grow with the span, so the curls keep their shape at any
width — the thing a stretched LaTeX glyph gets wrong.
"""
function Brace(m::Mobject, direction = DOWN; buff::Real = 0.2, color = WHITE,
               thickness::Real = 0.18, tip_length::Real = 0.3,
               stroke_width::Real = 0.0)
    d = Point3f(direction)
    # the span is measured PERPENDICULAR to the brace's direction
    perp = Point3f(-d[2], d[1], 0)
    span = abs(get_width(m) * perp[1]) + abs(get_height(m) * perp[2])
    span = max(Float64(span), 4 * Float64(tip_length))

    t = Float64(thickness)
    tip = Float64(tip_length)
    half = 0.5 * span
    arm = half - tip                       # what is left for the straight part

    # profile in a local frame: x along the span, y away from the mobject
    outer = Point3f[
        Point3f(-half, 0, 0),
        Point3f(-half + tip, -t, 0),
        Point3f(-tip, -t, 0),
        Point3f(0, -2t, 0),                # the spike
        Point3f(tip, -t, 0),
        Point3f(half - tip, -t, 0),
        Point3f(half, 0, 0),
    ]
    br = vmob(:Brace)          # tagged, so get_tip/get_tex dispatch on it
    set_points_as_corners!(br, outer)
    set_stroke!(br; color, width = max(stroke_width, 3.0))
    set_fill!(br; opacity = 0)

    # into place: rotate the local frame onto `direction`, then push it out
    θ = atan(d[2], d[1]) + PI / 2
    rotate!(br, θ)
    move_to!(br, get_bounding_box_point(m, d))
    shift!(br, Float32(buff + 2t) * d)
    return br
end

"""
The label of `Title`, `BraceLabel` and `get_graph_label`, by the route its
`via` names: `:text` is a `TextMobject`; `:math`, `:latex`, `:typst` and
`:auto` are a `Tex` BY THAT ROUTE, the same four words `Tex` takes. A
misspelt route is an error.
"""
function _label_via(text, via::Symbol; size, color)
    via === :text && return TextMobject(String(text); size, color)
    via in (:math, :latex, :typst, :auto) && return Tex(String(text); via, size, color)
    throw(
        ArgumentError(
            "via = :$via is not a route — :text (FreeType), :math (MathTeXEngine, " *
            "the default of Tex), :latex, :typst or :auto",
        ),
    )
end

"""
    BraceLabel(m, text, direction=DOWN; buff=0.2, label_buff=0.15, via=:text, …)

A `Brace` with its label already placed outside it. Returns a VGroup, so
`brace_label[1]` is the brace and `[2]` the text. `via` is the label's route:
`:text` (FreeType), or `:math`, `:latex`, `:typst`, `:auto` for a [`Tex`](@ref)
by that route.
"""
function BraceLabel(m::Mobject, text::AbstractString, direction = DOWN;
                    buff::Real = 0.2, label_buff::Real = 0.15,
                    size::Real = 0.5, color = WHITE, via::Symbol = :text, kw...)
    br = Brace(m, direction; buff, color, kw...)
    lab = _label_via(text, via; size, color)
    next_to!(lab, br, direction; buff = label_buff)
    return VGroup(br, lab)
end

"""
    get_tip(br) → Point3f

The point of the brace — the spike, wherever the brace was turned to.

ManimGL reads it by index too, with the comment that it is "very specific to
the LaTeX representation of a brace, but it's the only way I can think of"
(`brace.py:81`). Ours is not LaTeX but seven corners, and the spike is the
middle one by construction, so the middle POINT of the path is it — an index
that survives every rotation, shift and scale, which is what the question
needs.
"""
function get_tip(br::VMobject{:Brace})
    has_points(br) || throw(ArgumentError("get_tip: this brace has no points"))
    return br.points[(length(br.points) + 1) ÷ 2]
end

"""
    get_direction(br) → Point3f

The unit vector from the brace's centre to its tip (`brace.py:87`) — which way
it is pointing, whatever it was constructed with.
"""
get_direction(br::VMobject{:Brace}) =
    Point3f(normalize(SVector{3,Float64}(get_tip(br) - get_center(br))))

"""
    get_tex(br, strings...; buff=SMALL_BUFF, kw...)

A [`Tex`](@ref) built and placed just beyond the brace's tip (`brace.py:93`):

```julia
br = Brace(bar, DOWN)
lab = get_tex(br, raw"n - 1")
add!(scene, br, lab)
```

The direction is the brace's own, ROUNDED as GL rounds it, so a brace at a
slight angle still puts its label squarely below or beside it. Every other
keyword goes to `Tex`. [`BraceLabel`](@ref) is the one-call version that
returns both.
"""
function get_tex(br::VMobject{:Brace}, texts::AbstractString...;
                 buff::Real = SMALL_BUFF, kw...)
    t = Tex(texts...; kw...)
    next_to!(t, get_tip(br), Point3f(round.(get_direction(br))); buff)
    return t
end

"""
    BackgroundRectangle(m; color=BLACK, opacity=0.75, buff=0.1)

An opaque rectangle behind `m` — the standard trick for putting text over a
busy background. Add it BEFORE `m` so it draws underneath.
"""
function BackgroundRectangle(m::Mobject; color = BLACK, opacity::Real = 0.75,
                             buff::Real = 0.1)
    r = Rectangle(width = get_width(m) + 2buff, height = get_height(m) + 2buff)
    set_fill!(r; color, opacity)
    set_stroke!(r; width = 0, opacity = 0)
    move_to!(r, get_center(m))
    return r
end

"""
    add_background_rectangle!(m; color=BLACK, opacity=0.75, buff=0.1) → m

Put a [`BackgroundRectangle`](@ref) behind `m`, as its first child
(`mobject.py:1507`) — the one-call form of the trick above, and what a ported
`.py` writes.

```julia
add_background_rectangle!(label)        # now it reads over anything
```

Two measured differences from ManimGL's, both recorded in
`docs/divergences.md`: GL's verb forces `fill_opacity = 1.0` (its own
`BackgroundRectangle` defaults to 0.75, so the two disagree inside GL), and
GL's rectangle hugs the mobject with `buff = 0` where Janim's leaves 0.1. This
keeps ONE rule here — the verb is the constructor plus [`add_to_back!`](@ref)
— and both keywords are one word away.
"""
add_background_rectangle!(m::Union{VMobject,Group}; kw...) =
    add_to_back!(m, BackgroundRectangle(m; kw...))

"""
    Underline(m; buff=0.1, color=WHITE, stroke_width=3.0)

A line under `m`, as wide as it is.
"""
function Underline(m::Mobject; buff::Real = 0.1, color = WHITE,
                   stroke_width::Real = 3.0)
    w = get_width(m) / 2
    c = get_bounding_box_point(m, DOWN)
    l = Line(c + Point3f(-w, -buff, 0), c + Point3f(w, -buff, 0))
    set_stroke!(l; color, width = stroke_width)
    return l
end

"""
    DimensionLine(start, stop; color=GREY_A, stroke_width=1.5, tip_length=0.11,
                  tip_width=0.11, max_tip_length_ratio=0.28)

The measurement line of a technical drawing: a thin shaft between two points
with a dart at each end, both pointing INWARDS.

```julia
d = DimensionLine(Point3f(-2, -1, 0), Point3f(2, -1, 0))
lab = TextMobject("4.00"; size = 0.3)
next_to!(lab, d, UP; buff = 0.08)
```

It is not [`Arrow`](@ref) twice over, and the difference is the point of it.
An arrow's head is sized as a FRACTION of its length, so a dimension line
across a short gap grows heads that swallow it, and its tips stick out past
the extension lines they are supposed to meet. Here the tips have an absolute
size — `tip_length` in scene units, not a ratio — the shaft is trimmed to end
where they begin, and both darts live INSIDE the measured segment. What you
measure is the distance between the two points you named, with nothing
overhanging.

`max_tip_length_ratio` is the one concession to proportion: on a segment
shorter than about `tip_length / 0.28` the darts would meet in the middle, so
they shrink with it.

Each dart is a four-cornered concave polygon — apex, shoulder, waist,
shoulder — which is what gives a dimension line its flat-backed look instead
of a triangle's.

Modelled on a `DimensionLine` helper for Manim CE, which exists because
`Line.add_tip(at_start=true)` overshoots exactly this way. Neither reference
engine has it.

Returns a [`VGroup`](@ref) of `(shaft, start dart, end dart)`, so
`d.submobjects[1]` is the line if you want to restyle it alone.
"""
function DimensionLine(start, stop; color = GREY_A, stroke_width::Real = 1.5,
                       tip_length::Real = 0.11, tip_width::Real = 0.11,
                       max_tip_length_ratio::Real = 0.28)
    p0, p1 = Point3f(start), Point3f(stop)
    v = SVector{3,Float64}(p1 - p0)
    len = norm(v)
    # Two coincident points describe no direction: an empty group is the
    # honest answer, and it still composes (next_to!, add!) like a full one.
    len < 1e-8 && return VGroup()

    unit = Point3f(v / len)
    normal = Point3f(-unit[2], unit[1], 0)          # in the xy plane, like CE's
    tl = Float32(min(tip_length, max_tip_length_ratio * len))
    half = Float32(tip_width / 2)

    inner0 = p0 + tl * unit
    inner1 = p1 - tl * unit

    shaft = Line(inner0, inner1)
    set_stroke!(shaft; color, width = stroke_width)

    darts = map(((apex, waist),) -> begin
                    d = Polygon(apex, waist + half * normal, waist,
                                waist - half * normal)
                    set_fill!(d; color, opacity = 1.0)
                    set_stroke!(d; color, width = 0.0)
                    d
                end, ((p0, inner0), (p1, inner1)))

    return VGroup(shaft, darts...)
end

"""
    Cross(m; color=RED, stroke_width=6.0, scale_factor=1.0)

Two diagonals over `m`: the "this is wrong" gesture.
"""
function Cross(m::Mobject; color = RED, stroke_width::Real = 6.0,
               scale_factor::Real = 1.0)
    w = 0.5 * get_width(m) * scale_factor
    h = 0.5 * get_height(m) * scale_factor
    c = get_center(m)
    a = Line(c + Point3f(-w, -h, 0), c + Point3f(w, h, 0))
    b = Line(c + Point3f(-w, h, 0), c + Point3f(w, -h, 0))
    for l in (a, b)
        set_stroke!(l; color, width = stroke_width)
    end
    return VGroup(a, b)
end

"""
    DashedVMobject(m; num_dashes=15, positive_space_ratio=0.5, kw...)

Chop `m`'s path into dashes BY ARC LENGTH, so the dashes stay evenly spaced
along a curve instead of bunching where the parametrisation is dense — which
is what a naive split by parameter does on a circle.
"""
function DashedVMobject(m::VMobject; num_dashes::Int = 15,
                        positive_space_ratio::Real = 0.5, color = nothing,
                        stroke_width = nothing)
    num_dashes < 1 && throw(ArgumentError("DashedVMobject: num_dashes must be ≥ 1"))
    r = Float64(positive_space_ratio)
    (0 < r <= 1) || throw(ArgumentError(
        "DashedVMobject: positive_space_ratio must be in (0, 1], got $r"))
    # a parent WITHOUT points and one child per dash, like GL's
    # DashedVMobject(VMobject): the parent keeps the base's style (GL's
    # `match_style(vmobject, recurse=False)`) and answers get_start/get_end
    # from its dashes (below).
    g = vmob(:DashedVMobject)
    match_style!(g, m)
    add!(g, _dash_pieces(m, num_dashes, r; color, stroke_width)...)
    return g
end

"""
The dashes themselves. The alphas are GL's: a period per dash, the dash `r`
of it, and the whole ladder rescaled by `1 − 1/n + r/n` so the last dash ENDS
where the path ends (vectorized_mobject.py, DashedVMobject), so `get_end` of a
dashed line is the end of the path.
"""
function _dash_pieces(m::VMobject, num_dashes::Int, r::Float64; color, stroke_width)
    period = 1.0 / num_dashes
    partial = r * period
    ladder = 1.0 - period + partial
    pieces = VMobject[]
    for k in 0:(num_dashes - 1)
        a = (k * period) / ladder
        b = min(a + partial, 1.0)
        piece = VMobject()
        match_points!(piece, m)
        pointwise_become_partial!(piece, m, a, b)
        match_style!(piece, m)
        color === nothing || set_color!(piece; color)
        stroke_width === nothing || set_stroke!(piece; width = stroke_width)
        push!(pieces, piece)
    end
    return pieces
end

"""
    DashedLine(p1, p2; dash_length=0.05, positive_space_ratio=0.5, kw...)

A dashed segment. The dash count comes from the LENGTH, so two lines of
different lengths get dashes of the same size — the thing that makes a dashed
grid look regular.

`dash_length` is ManimGL's `DEFAULT_DASH_LENGTH = 0.05` (`geometry.py:40`),
so a 3-unit line gets 30 dashes, and the count is GL's
`ceil(length / (dash_length / positive_space_ratio))` (`geometry.py:847`).
Ask for `dash_length = 0.1` for coarser dashes.
"""
function DashedLine(p1, p2; dash_length::Real = 0.05,
                    positive_space_ratio::Real = 0.5, kw...)
    base = Line(p1, p2; kw...)
    ratio = Float64(positive_space_ratio)
    # the same door as DashedVMobject's: a ratio of 0 has no dash to draw
    # (`_dash_pieces` would divide 0/0 and die in `Int64(NaN)` three calls
    # later). GL dies the same way, in `get_subcurve`, after
    # `calculate_num_dashes` has caught the division and answered 1 dash.
    # Say it here, with the argument's name.
    (0 < ratio <= 1) || throw(ArgumentError(
        "DashedLine: positive_space_ratio must be in (0, 1], got $ratio"))
    full = Float64(dash_length) / ratio
    # the `ceil` is GL's, and so is the RELATIVE slack in front of it, which
    # GL does not need: its points are float64, ours are Point3f, so a line
    # asked for at 0.4 units measures 0.4000000059 and a bare `ceil` turns
    # 6e-9 into a whole extra dash (30 dashes in 3 units is exact, 4 in 0.4
    # was not). 1e-6 is four orders below any dash boundary a scene can mean
    # and six above the f32 residue.
    n = max(1, ceil(Int, (get_arc_length(base) / full) * (1 - 1e-6)))
    # a Line-shaped parent without points of its own: `get_start`, `get_end`
    # and `get_angle` answer from the dashes, as GL's `DashedLine(Line)` does.
    # (A ratio of 0 is refused above: GL's `calculate_num_dashes` catches the
    # division and answers 1 dash, and then its `get_subcurve` dies on NaN
    # alphas.)
    m = vmob(:DashedLine)
    match_style!(m, base)
    add!(m, _dash_pieces(base, n, Float64(positive_space_ratio);
                         color = nothing, stroke_width = nothing)...)
    return m
end

# a dashed line answers like a Line (geometry.py, DashedLine): the first
# dash's start and the last dash's end, and `get_angle` follows through
# `get_vector`. With no dashes (an empty parent) it falls back to its points.
const _Dashed = Union{VMobject{:DashedLine},VMobject{:DashedVMobject}}
get_start(m::_Dashed) =
    isempty(m.submobjects) ? m.points[begin] : get_start(m.submobjects[1]::VMobject)
get_end(m::_Dashed) =
    isempty(m.submobjects) ? m.points[end] : get_end(m.submobjects[end]::VMobject)

# ═══════════════════════════════════════════════════════════════════════
# Angle and RightAngle — the mark between two lines
# ═══════════════════════════════════════════════════════════════════════

"""
    line_intersection(p1, p2, q1, q2) → Point3f

Where the INFINITE lines through (p1,p2) and (q1,q2) cross, in the z=0 plane
(Cramer's rule, as in manim). Parallel lines are an error with a message that
says so, because that is a modelling mistake, not a numerical one.
"""
function line_intersection(p1, p2, q1, q2)
    a, b = Point3f(p1), Point3f(p2)
    c, d = Point3f(q1), Point3f(q2)
    xd = (a[1] - b[1], c[1] - d[1])
    yd = (a[2] - b[2], c[2] - d[2])
    det(u, v) = u[1] * v[2] - u[2] * v[1]
    div = det(xd, yd)
    div == 0 && throw(ArgumentError(
        "the two lines are parallel: they have no intersection to draw an " *
        "angle at"))
    dd = (det((a[1], a[2]), (b[1], b[2])), det((c[1], c[2]), (d[1], d[2])))
    return Point3f(det(dd, xd) / div, det(dd, yd) / div, 0)
end

"""
    line_intersection(line1, line2) → Point3f

GL's form (space_ops.py:274): each line as a PAIR of points —
`line_intersection([a, b], [c, d])` — which is what a translated scene
writes. The four-point form above is the same computation.
"""
line_intersection(line1, line2) = line_intersection(line1[1], line1[2], line2[1], line2[2])

"The corner, the two anchors and the signed angle between them (CE's rules)."
function _angle_geometry(line1::VMobject, line2::VMobject; radius = nothing,
                         quadrant = (1, 1), other_angle::Bool = false)
    inter = line_intersection(get_start(line1), get_end(line1),
                              get_start(line2), get_end(line2))
    if radius === nothing
        d1 = norm((quadrant[1] == 1 ? get_end(line1) : get_start(line1)) - inter)
        d2 = norm((quadrant[2] == 1 ? get_end(line2) : get_start(line2)) - inter)
        short = min(d1, d2)
        radius = short < 0.6 ? (2 / 3) * short : 0.4
    end
    r = Float32(radius)
    a1 = inter + Float32(quadrant[1]) * r * get_unit_vector(line1)
    a2 = inter + Float32(quadrant[2]) * r * get_unit_vector(line2)
    θ1 = angle_of_vector(a1 - inter)
    θ2 = angle_of_vector(a2 - inter)
    value = if !other_angle
        θ2 > θ1 ? θ2 - θ1 : TAU - (θ1 - θ2)
    else
        θ2 < θ1 ? θ2 - θ1 : (θ2 - θ1) - TAU
    end
    return (; inter, radius = Float64(radius), a1, a2, start_angle = θ1, value)
end

"""
    angle_value(line1, line2; quadrant=(1,1), other_angle=false) → radians

The number the `Angle` mark stands for. It is a FUNCTION and not a field of
the mobject on purpose: a mobject in this engine is geometry plus style, and
nothing else — feed this straight into a `DecimalNumber` when you want the
angle written on screen.
"""
angle_value(line1::VMobject, line2::VMobject; kw...) =
    _angle_geometry(line1, line2; kw...).value

"""
    Angle(line1, line2; radius=nothing, quadrant=(1,1), other_angle=false,
          elbow=false)

The arc that marks the angle between two lines. `quadrant` picks WHICH of the
four angles (the signs multiply each line's direction), `other_angle` takes
the reflex one, and `elbow=true` draws the square corner instead.

With no `radius` it uses manim's rule: two thirds of the shortest arm when
that is under 0.6, and 0.4 otherwise.

Born `GREY_A` (`#DDDDDD`) at width `4.0`. ManimGL has no `Angle` at all —
only `Elbow` — so the mark inherits its `VMobject` default, and that is the
one an arc drawn beside a GL scene has to match. Pass `color = WHITE,
stroke_width = 3.0` for a brighter, thinner mark.
"""
const Angle = VMobject{:Angle}
function (::Type{Angle})(line1::VMobject, line2::VMobject; radius = nothing,
                         quadrant = (1, 1), other_angle::Bool = false,
                         elbow::Bool = false, color = GREY_A,
                         stroke_width::Real = 4.0, dot::Bool = false,
                         dot_radius = nothing, dot_distance::Real = 0.55,
                         dot_color = WHITE, kw...)
    g = _angle_geometry(line1, line2; radius, quadrant, other_angle)
    m = vmob(:Angle; kw...)
    if elbow
        middle = g.inter + Float32(quadrant[1] * g.radius) * get_unit_vector(line1) +
                 Float32(quadrant[2] * g.radius) * get_unit_vector(line2)
        set_points_as_corners!(m, (g.a1, middle, g.a2))
    else
        _init_arc!(m, g.start_angle, g.value, g.radius, nothing, g.inter)
    end
    set_stroke!(m; color, width = stroke_width)
    set_fill!(m; opacity = 0)
    # CE's dot inside the angle (`geometry/line.py`, the `if dot` block):
    # a Dot of radius/10 at `radius · dot_distance` from the vertex, along the
    # direction of the ARC's centre. CE puts it inside the arc branch only, so
    # `elbow = true` ignores it — measured, not read (probe: 0 children).
    if dot && !elbow
        r = dot_radius === nothing ? g.radius / 10 : Float64(dot_radius)
        d = Dot(ORIGIN; radius = r, fill_color = dot_color)   # `Dot(color=…)` is swallowed, as in GL
        v = SVector{3,Float64}(get_center(m)) - SVector{3,Float64}(g.inter)
        move_to!(d, Point3f(SVector{3,Float64}(g.inter) +
                            normalize(v) * g.radius * Float64(dot_distance)))
        add!(m, d)
    end
    return m
end

"""
    RightAngle(line1, line2; length=0.4)

The square corner — `Angle(…; elbow=true)`, the way a right angle is drawn.
"""
RightAngle(line1::VMobject, line2::VMobject; length = nothing, kw...) =
    Angle(line1, line2; radius = length, elbow = true, kw...)

# ═══════════════════════════════════════════════════════════════════════
# Labels, braces between things, and the title
# ═══════════════════════════════════════════════════════════════════════
# Compositions over the Brace, Line, Dot and text already defined. Every one
# of them PLACES something, so every one of them goes through the relative
# layout: nothing is positioned before the layout exists, and no coordinates
# are written by hand.

"""
    AnnotationDot(point = ORIGIN; radius = 1.3 × 0.08, …)

A [`Dot`](@ref) that is meant to be SEEN: 30% wider, filled blue and ringed in
white.

```julia
AnnotationDot(c2p(axes, 2.0, 3.0))
```

The plain `Dot` is a marker — it says "a point is here" and stays out of the
way. This one is a pointer: it says "look at this point", and the white ring
is what keeps it visible over a filled shape. Manim CE's exact proportions,
measured: 0.208 units across against a `Dot`'s 0.16.
"""
const AnnotationDot = VMobject{:AnnotationDot}

function (::Type{AnnotationDot})(point = ORIGIN;
                                 radius::Real = 1.3 * 0.08,   # a Dot's radius, not the constant
                                 fill_color = BLUE, fill_opacity::Real = 1.0,
                                 stroke_color = WHITE, stroke_width::Real = 5.0,
                                 kw...)
    m = vmob(:AnnotationDot; fill_color, fill_opacity, stroke_color,
             stroke_width, kw...)
    return _init_arc!(m, 0.0, TAU, radius, nothing, Point3f(point))
end

"""
    LabeledDot(label; point = ORIGIN, buff = 0.2, …)

A filled circle with a label INSIDE it — the node of a graph, the step of a
diagram:

```julia
LabeledDot("1")
LabeledDot(Tex(raw"x_0"); fill_color = MAROON)
LabeledDot(TextMobject("A"); point = 2 * RIGHT)
```

The radius is computed from the label plus `buff`, so a wide label gives a
wide dot instead of spilling out — measured in CE, `"4"` gives 0.60 units and
`"4444"` gives 1.22. Pass `radius` explicitly to fix it yourself, and then
`buff` is ignored.

A `String` is typeset with [`Tex`](@ref), as CE does; pass a mobject to choose
the route (`TextMobject` for words, `Tex(...; via = :latex)` for the full
engine).
"""
function LabeledDot(label; point = ORIGIN, buff::Real = 0.2,
                    radius = nothing, size::Real = 0.5,
                    fill_color = BLUE, fill_opacity::Real = 1.0,
                    stroke_color = WHITE, stroke_width::Real = 0.0, kw...)
    # a non-string label (`LabeledDot(7)`) goes through `string`
    lab = label isa Mobject ? label :
          Tex(label isa AbstractString ? String(label) : string(label); size)
    r = radius === nothing ?
        sqrt((Float64(get_width(lab)) / 2)^2 + (Float64(get_height(lab)) / 2)^2) + buff :
        Float64(radius)
    disc = vmob(:LabeledDot; fill_color, fill_opacity, stroke_color, stroke_width)
    _init_arc!(disc, 0.0, TAU, r, nothing, ORIGIN)
    move_to!(lab, ORIGIN)
    g = VGroup(disc, lab; kw...)
    move_to!(g, Point3f(point))
    return g
end

"""
    BraceBetweenPoints(p1, p2; direction = nothing, …)

A [`Brace`](@ref) spanning two points, wherever they are:

```julia
BraceBetweenPoints(2 * LEFT, 2 * RIGHT)              # under the segment
BraceBetweenPoints(get_corner(sq, UL), get_corner(sq, UR); direction = UP)
```

`Brace` measures a MOBJECT's bounding box, which is the wrong tool when what
you want to measure is a distance between two places. This one spans exactly
`p1` to `p2` at any angle.

With no `direction` the brace sits on the side the segment's normal points to
— the line vector turned a quarter turn clockwise, which is Manim CE's rule
and puts the brace below a left-to-right segment.
"""
function BraceBetweenPoints(p1, p2; direction = nothing, kw...)
    a, b = Point3f(p1), Point3f(p2)
    v = b - a
    d = direction === nothing ? Point3f(v[2], -v[1], 0) : Point3f(direction)
    n = sqrt(sum(abs2, d))
    n > 0 || throw(ArgumentError(
        "the two points coincide, so there is no segment to brace"))
    return Brace(Line(a, b; buff = 0.0), d ./ Float32(n); kw...)
end

"""
    LineBrace(line; direction = nothing, …)

A [`Brace`](@ref) alongside a [`Line`](@ref), following its direction however
the line is turned. ManimGL's.

```julia
l = Line(ORIGIN, 3 * RIGHT + 2 * UP)
LineBrace(l)
```

It is [`BraceBetweenPoints`](@ref) reading the line's own ends, which is the
whole difference from bracing the line's bounding BOX: a diagonal line has a
box much larger than itself, and a plain `Brace` would measure the box.
"""
LineBrace(line::VMobject; kw...) =
    BraceBetweenPoints(get_start(line), get_end(line); kw...)

"""
    BraceText(m, text, direction = DOWN; …)

[`BraceLabel`](@ref) with the label typeset as a FORMULA rather than as text —
Manim's `BraceText`, and the spelling to reach for when the label is `n - 1`
rather than a word.

```julia
BraceText(group, raw"n - 1")
BraceLabel(group, "n - 1")        # the same brace, label as plain text
```

It is `BraceLabel(...; via = :math)`, so everything that constructor takes
still applies.
"""
BraceText(m::Mobject, text::AbstractString, direction = DOWN; kw...) =
    BraceLabel(m, text, direction; via = :math, kw...)

# ArcBrace (Manim CE) is NOT here, and the reason is the render, not the maths.
#
# It can be built and it WORKS by every number: a straight brace as long as the
# arc, bent by mapping x to arc length and y to distance from the centre, with
# every point landing between r + buff and r + buff + thickness — measured,
# 2.38 to 2.74 around a radius-2 arc. It hugs the arc from outside, exactly as
# asked.
#
# It just does not LOOK like a brace. A brace is seven anchors (two curls, two
# arms, the spike), and seven points spread over a quarter circle read as a
# polygon. Subdividing to 31 points before bending helps and is still not
# enough: the curls flatten and the spike disappears, so what arrives on
# screen is an irregular outline rather than a curly brace. It fails the only
# question no numeric check asks: can you see it?
#
# What it would take: build the brace's profile
# DIRECTLY in polar coordinates instead of bending a straight one, so the
# curls keep their shape at any sweep — the same reasoning that made Janim's
# Brace a five-piece path instead of a stretched LaTeX glyph (see the note at
# the top of this file). That is a new construction, not a composition.
#
# Two things worth knowing if it is attempted:
#   · `apply_points_function!` applies f RELATIVE to the mobject's own centre
#     by default (`about_edge = ORIGIN` resolves to its bounding-box centre).
#     An absolute map needs `about_point = ORIGIN` spelled out, or the shape
#     arrives pre-shifted. It cost a render that looked plausibly wrong.
#   · `_insert_n_curves(get_points(m), n)` is how a path gets more control
#     points before being deformed. It is in `core/alignment.jl`.

"""
    Label(text; buff = 0.15, box_color = WHITE, background = BLACK, …)

Text in a box, ready to be dropped on top of anything:

```julia
Label("v = 3")
Label(Tex(raw"\\theta"); box_color = YELLOW)
```

Three pieces in one group: an opaque backdrop, the text, and the outline —
which is exactly Manim CE's `Label`, measured. The backdrop is what makes it
readable over a plot or an image; without it the outline would frame something
you still cannot read.

`[`LabeledLine`](@ref)` and [`LabeledArrow`](@ref) place one of these on a
line for you.
"""
function Label(text; buff::Real = 0.15, size::Real = 0.5,
               color = WHITE, box_color = WHITE, background = BLACK,
               background_opacity::Real = 0.85, stroke_width::Real = 2.0, kw...)
    # a non-string label (`Label(3)`) goes through `string`
    lab = text isa Mobject ? text :
          TextMobject(text isa AbstractString ? String(text) : string(text); size, color)
    fondo = Rectangle(; width = get_width(lab) + 2buff,
                      height = get_height(lab) + 2buff)
    set_fill!(fondo; color = background, opacity = background_opacity)
    set_stroke!(fondo; width = 0.0, opacity = 0.0)
    marco = Rectangle(; width = get_width(lab) + 2buff,
                      height = get_height(lab) + 2buff)
    set_fill!(marco; opacity = 0.0)
    set_stroke!(marco; color = box_color, width = stroke_width)
    move_to!(fondo, get_center(lab))
    move_to!(marco, get_center(lab))
    return VGroup(fondo, lab, marco; kw...)
end

"""
Place a Label at `alpha` of the way from `a` to `b`, and return shaft + label.

The anchor is interpolated between the ENDS the caller asked for, not taken
from `point_from_proportion`. On a `Line` the two agree; on an `Arrow` they do
not, because an arrow is a CLOSED contour — shaft, head and belly — so walking
its path by proportion goes up one side and back down the other, and α = 0.5
lands at the tip instead of the middle. Caught in a render: the label sat on
the arrowhead.
"""
function _labelled(shaft::VMobject, text, a::Point3f, b::Point3f, alpha::Real, kw)
    lab = Label(text; kw...)
    t = Float32(clamp(Float64(alpha), 0.0, 1.0))
    move_to!(lab, a + t * (b - a))
    return VGroup(shaft, lab)
end

"""
    LabeledLine(text, start = LEFT, stop = RIGHT; alpha = 0.5, …)

A line with a boxed label sitting ON it:

```julia
LabeledLine("3 cm", a, b)
LabeledLine(Tex(raw"\\ell"), a, b; alpha = 0.25)
```

`alpha` says where along the line the label goes, 0 → 1 from `start` to `stop`.
The label's opaque backdrop is what lets it sit on the line without the line
crossing the text.

Returns a group: `[1]` is the line, `[2]` the label.
"""
function LabeledLine(text, start = LEFT, stop = RIGHT; alpha::Real = 0.5,
                     buff::Real = 0.0, path_arc::Real = 0.0, kw...)
    l = Line(start, stop; buff, path_arc)
    return _labelled(l, text, get_start(l), get_end(l), alpha, kw)
end

"""
    LabeledArrow(text, start = LEFT, stop = RIGHT; alpha = 0.5, …)

[`LabeledLine`](@ref) with a head — the labelled arrow of a diagram.

```julia
LabeledArrow("f", a, b)
```
"""
function LabeledArrow(text, start = LEFT, stop = RIGHT; alpha::Real = 0.5,
                      buff::Real = MED_SMALL_BUFF, path_arc::Real = 0.0, kw...)
    arr = Arrow(start, stop; buff, path_arc)
    # An arrow's own start/end come from its CONTOUR, so the ends are taken
    # from the segment the caller named instead.
    p0, p1 = Janim._endpoints(start, stop)
    return _labelled(arr, text, p0, p1, alpha, kw)
end

"""
    Title(text; underline = true, underline_width = FRAME_WIDTH - 2, …)

A heading: the text at the top of the frame with a rule under it.

```julia
add!(scene, Title("Teorema de Pitágoras"))
Title(raw"\\int_0^1 f"; via = :math, match_underline_width = true)
```

Both engines place it the same way and this reproduces it: `to_edge!(UP)` with
`MED_SMALL_BUFF`, the rule `SMALL_BUFF` below the text and as wide as the
frame less 2 units. `match_underline_width = true` makes the rule as wide as
the text instead, which reads better for a short title.

Returns a group of text and rule, so `t[1]` is the words and `t[2]` the line.
With `underline = false` it is a group of one, so a scene that toggles the
rule does not have to change how it indexes.

`via` is the words' route: `:text` (the default), or `:math`, `:latex`,
`:typst`, `:auto` for a [`Tex`](@ref) by that route; a mobject is used as it
comes.
"""
function Title(text; underline::Bool = true, size::Real = 0.8,
               color = WHITE, via::Symbol = :text,
               underline_width::Real = FRAME_WIDTH - 2,
               match_underline_width::Bool = false,
               underline_buff::Real = SMALL_BUFF,
               underline_color = GREY_C, underline_stroke::Real = 2.0, kw...)
    words = text isa Mobject ? text : _label_via(text, via; size, color)
    to_edge!(words, UP; buff = MED_SMALL_BUFF)
    underline || return VGroup(words; kw...)
    regla = Line(LEFT, RIGHT)
    set_stroke!(regla; color = underline_color, width = underline_stroke)
    set_width!(regla, match_underline_width ? get_width(words) : underline_width;
               stretch = true)
    next_to!(regla, words, DOWN; buff = underline_buff)
    return VGroup(words, regla; kw...)
end
