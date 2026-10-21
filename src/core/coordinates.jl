# Line · Arrow · Dot.
#
# The three primitives everything annotational hangs from: the ticks and axes
# of Axes/NumberLine, braces and underlines, the arrows of diagrams, the dots
# of a plot. That is why they live here and not inside Axes: if they were
# born inside Axes, Brace would reinvent them.
#
# Port of manimlib/mobject/geometry.py with GL's exact geometry:
#   · Line = one subpath (straight or arc) with an optional buff trimmed by
#     arc length.
#   · Arrow = ONE VMobject: shaft, tip and belly form a SINGLE closed contour
#     (verified: 1 subpath, 0 children). That is what makes a Transform
#     between arrows pair tip with tip. (CE keeps the tip as a submobject and
#     its morphs look wrong; GL master already does it like this.)
#   · Dot = a filled Circle of radius 0.08.

# ── arc length and arcs between points ─────────────────────────────────────

"Length of the polyline through `pts` (GL's poly_line_length)."
_poly_line_length(pts) = sum(norm(pts[i+1] - pts[i]) for i in 1:length(pts)-1; init = 0.0)

"""
    quick_point_from_proportion(m, alpha) → Point3f

The point at `alpha` along the path COUNTING CURVES: α is split equally between
the curves, whatever they measure (GL's `quick_point_from_proportion`).

The cheap one, and the one the engine itself uses —
[`MoveAlongPath`](@ref) rests on it because manimlib's does too. Exact whenever
every curve is the same length, which covers a straight [`Line`](@ref), an
[`Arc`](@ref), a [`Circle`](@ref) and any regular polygon. On a path of uneven
pieces it reads ahead or behind; [`point_from_proportion`](@ref) is the one
that weighs them.
"""
function quick_point_from_proportion(m::VMobject, alpha::Real)
    nc = get_num_curves(m)
    nc == 0 && throw(ArgumentError("a path without curves has no points by proportion"))
    n, residue = integer_interpolate(0, nc, alpha)
    c = get_nth_curve_points(m, n + 1)
    t = Float32(residue)
    return Point3f((1 - t)^2 * c[1] + 2t * (1 - t) * c[2] + t^2 * c[3])
end

"""
    curve_and_prop_of_partial_point(m, alpha) → (n, residue)

Which curve of `m` carries the point at proportion `alpha`, and how far along
it — `n` counted from 1, the way [`get_nth_curve_points`](@ref) wants it.

The weighing is manimlib's, and it is worth knowing exactly what it is: each
curve counts for its CHORD, the straight line from its first anchor to its
last. Not its arc length — no sampling happens anywhere here, it is one
subtraction and one norm per curve. Manim CE measures the real arc instead, by
sampling each curve; the two agree wherever the pieces are straight and part
company on curved ones.

A NULL curve (first anchor equal to its handle, within
`Janim._POINT_ATOL`) counts zero. That is the marker of a jump between
subpaths, so the gap between the two rings of an `O` is not travelled — which
is what makes this work on a [`Tex`](@ref) glyph or a shape with a hole.
"""
function curve_and_prop_of_partial_point(m::VMobject, alpha::Real)
    nc = get_num_curves(m)
    nc == 0 && throw(ArgumentError("a path without curves has no points by proportion"))
    alpha <= 0 && return (1, 0.0)

    partials = Vector{Float64}(undef, nc + 1)     # a leading 0, then one per curve
    partials[1] = 0.0
    @inbounds for k in 1:nc
        c = get_nth_curve_points(m, k)
        null = abs(c[2][1] - c[1][1]) < _POINT_ATOL &&
               abs(c[2][2] - c[1][2]) < _POINT_ATOL &&
               abs(c[2][3] - c[1][3]) < _POINT_ATOL
        partials[k+1] = partials[k] + (null ? 0.0 : Float64(norm(c[3] - c[1])))
    end

    full = partials[end]
    full == 0 && return (nc, 1.0)                 # every curve null: a path that is a point

    # The first partial that reaches α of the total. `findfirst` cannot come
    # back empty for 0 < α ≤ 1 (the last partial IS the total), but α can
    # underflow to a target of exactly 0, and then the answer is the start.
    i = something(findfirst(>=(full * alpha), partials), nc + 1)
    i == 1 && return (1, 0.0)
    return (i - 1, inverse_interpolate(partials[i-1] / full, partials[i] / full, alpha))
end

"""
    point_from_proportion(m, alpha) → Point3f

The point at proportion `alpha` along the path, WEIGHING each curve by its
length (manimlib's `point_from_proportion`). `alpha` runs 0 → 1 from
[`get_start`](@ref) to [`get_end`](@ref).

```julia
l = Line(3 * LEFT, 3 * RIGHT)
point_from_proportion(l, 0.25)          # a quarter of the way along
```

Use it to lay things out along a curve without knowing its equation:

```julia
dots = VGroup((Dot(point_from_proportion(path, a); fill_color = c)
               for (a, c) in zip(range(0, 1; length = 10),
                                 color_gradient([RED, BLUE], 10)))...)
```

**Against [`quick_point_from_proportion`](@ref)**, which is the one the engine
uses internally: the quick one splits α equally between the curves without
measuring them, this one weighs each by its chord
([`curve_and_prop_of_partial_point`](@ref) says exactly how). On a path whose
pieces are all the same length the two agree — a `Line`, an `Arc`, a `Circle`,
a regular polygon. On a 4×1 [`Rectangle`](@ref) they are 1.5 scene units apart
at α = 0.25: the quick one thinks a quarter of the path is a whole side,
because it counts sides rather than distance.

Neither gives constant SPEED inside a curve: both hand the leftover proportion
straight to the Bézier as its parameter, and a quadratic does not travel its
parameter uniformly. Manim is the same in both engines. The weighing fixes the
share BETWEEN curves, which is where the visible error lives.

An empty path throws, like its sibling. (Manimlib answers the centre here for
`0 < α < 1` and raises at the ends, which is not a rule worth reproducing.)
"""
function point_from_proportion(m::VMobject, alpha::Real)
    get_num_curves(m) == 0 &&
        throw(ArgumentError("a path without curves has no points by proportion"))
    alpha <= 0 && return get_start(m)
    alpha >= 1 && return get_end(m)
    n, residue = curve_and_prop_of_partial_point(m, alpha)
    c = get_nth_curve_points(m, n)
    t = Float32(residue)
    return Point3f((1 - t)^2 * c[1] + 2t * (1 - t) * c[2] + t^2 * c[3])
end

"""
    get_arc_length(m; n_sample_points=nothing) → Float64

Length of the path. With no arguments it uses GL's estimate
(vectorized_mobject.py:896): ⅔ of the anchor polyline plus ⅓ of the one that
also goes through the handles — cheap and sampling-free. With
`n_sample_points` (at least 2) it samples by proportion.

CAREFUL (difference from `Line`): manimlib gives Line its OWN closed formula
— chord × arc/chord — because it knows its `path_arc`. Janim keeps no
per-mobject state, so that formula lives where the arc IS known: inside
`set_points_by_ends!`. What stays here is the generic one, valid for any path.
"""
function get_arc_length(m::VMobject; n_sample_points::Union{Nothing,Int} = nothing)
    # one sample is no polyline: refused by name rather than dying inside
    # `range` («endpoints differ»), which names the symptom, not the cause
    n_sample_points === nothing || n_sample_points >= 2 || throw(ArgumentError(
        "get_arc_length: n_sample_points must be at least 2 (a polyline needs two samples), got $n_sample_points"))
    if n_sample_points !== nothing
        return _poly_line_length([quick_point_from_proportion(m, a)
                                  for a in range(0, 1; length = n_sample_points)])
    end
    inner = _poly_line_length(get_anchors(m))
    outer = _poly_line_length(get_points(m))
    return inner + (outer - inner) / 3
end

"Line's closed formula: chord × (arc/chord) — exact for a circular arc."
_arc_length_from_chord(chord::Real, path_arc::Real) =
    path_arc > 0 ? chord * path_arc / (2 * sin(path_arc / 2)) : Float64(chord)

"""
    add_arc_to!(m, point, angle; n_components=nothing, threshold=1e-3)

Continue the path up to `point` along an arc subtending `angle`
(vectorized_mobject.py:584). With angle ~0 it is a straight line.
"""
function add_arc_to!(m::VMobject, point, angle::Real;
                     n_components = nothing, threshold::Real = 1e-3)
    has_points(m) || throw(ArgumentError(
        "add_arc_to! needs a starting point — call start_new_path! first"))
    abs(angle) < threshold && return add_line_to!(m, point)
    nc = n_components === nothing ? Int(ceil(8 * abs(angle) / TAU)) : Int(n_components)
    pts = quadratic_bezier_points_for_arc(angle; n_components = nc)
    tail = m.points[end]
    target_vect = Point3f(point) - tail
    current_vect = pts[end] - pts[1]
    R = rotation_between_vectors(current_vect, target_vect)
    scale = norm(target_vect) / norm(current_vect)
    rotated = [Point3f(scale * (R * SVector{3,Float64}(p[1], p[2], p[3]))) for p in pts]
    delta = tail - rotated[1]
    append_points!(m, [p + delta for p in rotated[2:end]])
    return m
end

"""
    add_subpath!(m, pts)

GL's add_subpath (vectorized_mobject.py:756): continue the path with another
one. If `pts[1]` is already where we are it does NOT open a new subpath — it
keeps the same contour. That detail is what makes the arrow ONE closed
contour instead of two pieces with a seam.
"""
function add_subpath!(m::VMobject, pts)
    isempty(pts) && return m
    P = Point3f[Point3f(p) for p in pts]
    has_points(m) || return set_points!(m, P)
    all(abs.(P[1] - m.points[end]) .<= _POINT_ATOL) || start_new_path!(m, P[1])
    append_points!(m, P[2:end])
    return m
end

"""
    append_vectorized_mobject!(m, other)

Continue `m`'s path with `other`'s, style included (GL's
`append_vectorized_mobject`, vectorized_mobject.py:766): the points go in as
a new subpath through [`add_subpath!`](@ref), and `other`'s per-point rows —
stroke colour, fill colour, width — are copied onto them, so a red square
joined by a blue circle is red where it was red and blue where it is new. The
point that marks the seam keeps `m`'s style, as in GL.
`add_subpath!(m, other::VMobject)` is the same verb.
"""
function append_vectorized_mobject!(m::VMobject, other::VMobject)
    add_subpath!(m, other.points)
    n = length(other.points)
    n == 0 && return m
    N = length(m.points)
    @inbounds for i in 1:n
        m.stroke_rgba[N - n + i] = other.stroke_rgba[i]
        m.fill_rgba[N - n + i] = other.fill_rgba[i]
        m.stroke_width[N - n + i] = other.stroke_width[i]
    end
    return m
end
add_subpath!(m::VMobject, other::VMobject) = append_vectorized_mobject!(m, other)

# ── endpoints ───────────────────────────────────────────────────────────────

"""
    get_start(m) → Point3f

Where `m`'s path begins — its first point.

An [`Arrow`](@ref) answers with the middle of its tail rather than a literal
first point, because its outline starts at one side of the shaft; that is the
end you drew it from, which is what you meant to ask.
"""
get_start(m::VMobject) = m.points[begin]

"""
    get_end(m) → Point3f

Where `m`'s path ends — its last point, or the TIP of an [`Arrow`](@ref). See
[`get_start`](@ref).
"""
get_end(m::VMobject) = m.points[end]

"""
    get_start_and_end(m) → (Point3f, Point3f)

Both endpoints at once, so they can be destructured:
`a, b = get_start_and_end(line)`.
"""
get_start_and_end(m::VMobject) = (get_start(m), get_end(m))

"""
    get_vector(m) → Point3f

End minus start — the displacement the line covers, direction and length
together. `norm(get_vector(line))` is its length as the crow flies (for the arc
length of a curve, [`get_arc_length`](@ref)).
"""
get_vector(m::VMobject) = get_end(m) - get_start(m)

"""
    get_unit_vector(m) → Point3f

[`get_vector`](@ref) normalised to length 1 — the direction alone. Useful for
offsetting along a line: `shift!(label, 0.3 * get_unit_vector(line))`.
"""
get_unit_vector(m::VMobject) = Point3f(normalize(SVector{3,Float64}(get_vector(m))))

"""
    get_angle(m) → Float64

The angle of [`get_vector`](@ref) in the xy plane, in radians, measured
counter-clockwise from the positive x axis.

The natural way to align something with a line: `rotate!(label, get_angle(l))`.
"""
get_angle(m::VMobject) = angle_of_vector(get_vector(m))

"""
    get_length(m) → Float64

The straight distance from `m`'s start to its end (GL's `get_length`,
geometry.py:200): a line's length, an arrow's from tail to tip, and 0 for a
closed path. For the distance ALONG a curve, [`get_arc_length`](@ref).
"""
get_length(m::VMobject) = norm(SVector{3,Float64}(get_vector(m)))

"""
    set_length!(m, length; about_point = nothing, about_edge = ORIGIN)

Scale `m` until [`get_length`](@ref) is `length` (GL's `set_length`,
geometry.py:788) — about its centre unless told otherwise, the way
[`scale!`](@ref) takes it.
"""
function set_length!(m::VMobject, len::Real; kw...)
    L = get_length(m)
    # GL would scale a closed path by `len / 2e-16` and hand back a giant one;
    # a path whose ends sit within the point-equality tolerance has no length
    # to set, and saying so beats the giant
    L > _POINT_ATOL || throw(ArgumentError(
        "set_length!: this $(tag(m)) has no length to scale (start == end)"))
    return scale!(m, len / L; kw...)
end

"""
    set_angle!(m, angle; about_point = get_start(m))

Turn `m` in the plane until [`get_angle`](@ref) is `angle` (GL's `set_angle`,
geometry.py:779). GL pivots on the START by default — the line swings like a
clock hand — and `about_point` moves the pivot.
"""
function set_angle!(m::VMobject, angle::Real; about_point = nothing)
    pivot = about_point === nothing ? get_start(m) : Point3f(about_point)
    return rotate!(m, angle - get_angle(m); about_point = pivot)
end

"""
    put_start_and_end_on!(m, start, stop)

Scale, rotate and shift `m` so its endpoints land on `start` and `stop` (GL's
put_start_and_end_on). On an Arrow it also scales the tip — a deliberate
difference from GL, which rebuilds it: here an arrow keeps no parameters of
its own (no hidden per-mobject state), and scaling the tip is what CE does and
what you want when an arrow is a Transform target.
"""
function put_start_and_end_on!(m::VMobject, start, stop)
    p0, p1 = get_start_and_end(m)
    current = p1 - p0
    # within GL's point-equality tolerance, not exactly zero: a Circle's
    # ends differ by 2e-16 of float noise, and `== 0` let it through to be
    # scaled by 1e16 (GL has the same hole, `np.all(curr_vect == 0)`)
    norm(current) <= _POINT_ATOL && throw(ArgumentError(
        "cannot reposition the endpoints of a closed path (start == end)"))
    target = Point3f(stop) - Point3f(start)
    scale!(m, norm(target) / norm(current); about_point = p0)
    axis = cross(SVector{3,Float64}(current), SVector{3,Float64}(target))
    rotate!(m, angle_between_vectors(current, target);
            axis = norm(axis) < 1e-8 ? OUT : Point3f(axis), about_point = p0)
    return shift!(m, Point3f(start) - get_start(m))
end

# GL's `Line.put_start_and_end_on` (geometry.py:751) handles the NULL
# line: a Line whose two ends coincide has no direction to scale and rotate,
# so it is rebuilt between the new ends instead of raising. Janim's Line
# keeps no `path_arc` of its own, so the rebuilt line is straight where GL
# rebuilds the arc it remembers. A closed path of any
# other kind still raises above.
function put_start_and_end_on!(m::VMobject{:Line}, start, stop)
    p0, p1 = get_start_and_end(m)
    if all(abs.(p1 - p0) .<= _POINT_ATOL)
        return set_points_by_ends!(m, Point3f(start), Point3f(stop); buff = 0, path_arc = 0)
    end
    return invoke(put_start_and_end_on!, Tuple{VMobject,Any,Any}, m, start, stop)
end

# ── Line ────────────────────────────────────────────────────────────────────

_rough_point(x::Mobject) = get_center(x)
_rough_point(x) = Point3f(x)
_point_toward(x::Mobject, dir) = get_bounding_box_point(x, dir)
_point_toward(x, _) = Point3f(x)

"Real endpoints: when they are mobjects, the border points facing each other (GL)."
function _endpoints(a, b)
    ra, rb = _rough_point(a), _rough_point(b)
    v = SVector{3,Float64}(rb - ra)
    u = norm(v) == 0 ? Point3f(0, 0, 0) : Point3f(normalize(v))
    return (_point_toward(a, u), _point_toward(b, -u))
end

"""
    set_points_by_ends!(m, start, stop; buff=0, path_arc=0)

Rebuild `m`'s path as a segment (or arc) between two points, trimming `buff`
off each end.
"""
function set_points_by_ends!(m::VMobject, start, stop; buff::Real = 0.0,
                             path_arc::Real = 0.0)
    clear_points!(m)
    start_new_path!(m, Point3f(start))
    add_arc_to!(m, Point3f(stop), path_arc)
    if buff > 0
        # Line's closed formula (exact for an arc), not the generic estimate:
        # it is the one GL uses here and where the trim lands depends on it.
        len = _arc_length_from_chord(norm(Point3f(stop) - Point3f(start)), path_arc)
        if len > 0
            alpha = min(buff / len, 0.5)
            pointwise_become_partial!(m, m, alpha, 1 - alpha)
        end
    end
    return m
end

"""
    Line(start=LEFT, stop=RIGHT; buff=0, path_arc=0, kw...)

Segment between two points (or between two mobjects: it uses the borders
facing each other). `buff` leaves air at the ends; `path_arc` curves it.
"""
const Line = VMobject{:Line}

function (::Type{Line})(start = LEFT, stop = RIGHT; buff::Real = 0.0,
                        path_arc::Real = 0.0, kw...)
    m = vmob(:Line; kw...)
    p0, p1 = _endpoints(start, stop)
    return set_points_by_ends!(m, p0, p1; buff, path_arc)
end

# ── Dot ─────────────────────────────────────────────────────────────────────

"""
    Dot(point=ORIGIN; radius=0.08, kw...)

A filled circle with no stroke — Manim's point marker.
"""
const Dot = VMobject{:Dot}

# The literal 0.08, not DEFAULT_DOT_RADIUS — which is the
# 0.05 ManimGL exports from dot_cloud.py. `geometry.py:442` reads its own
# module-local 0.08 for exactly the same reason.
function (::Type{Dot})(point = ORIGIN; radius::Real = 0.08,
                       fill_color = WHITE, fill_opacity = 1.0,
                       stroke_color = BLACK, stroke_width = 0.0, kw...)
    m = vmob(:Dot; fill_color, fill_opacity, stroke_color, stroke_width, kw...)
    return _init_arc!(m, 0.0, TAU, radius, nothing, Point3f(point))
end
# `Dot(mobject)` marks the mobject's centre (instead of a conversion error
# from `Point3f(square)`).
(::Type{Dot})(m::Mobject; kw...) = Dot(get_center(m); kw...)

"""
    SmallDot(point=ORIGIN; radius=DEFAULT_SMALL_DOT_RADIUS, kw...)

A [`Dot`](@ref) at half the radius — `0.04` scene units, so `0.08` across.

```julia
SmallDot(2 * RIGHT)
VGroup((SmallDot(p) for p in points)...)   # a scatter that does not shout
```

It exists for the same reason Manim has it: on a plot with many markers the
default dot is loud, and scaling one down by hand every time invites the
`0.01`-that-is-a-third-of-a-pixel mistake. Measured on ManimGL 1.7.2: exactly
half a `Dot`'s width, same white fill, same absent stroke.
"""
const SmallDot = VMobject{:SmallDot}

function (::Type{SmallDot})(point = ORIGIN;
                            radius::Real = DEFAULT_SMALL_DOT_RADIUS,
                            fill_color = WHITE, fill_opacity = 1.0,
                            stroke_color = BLACK, stroke_width = 0.0, kw...)
    m = vmob(:SmallDot; fill_color, fill_opacity, stroke_color, stroke_width, kw...)
    return _init_arc!(m, 0.0, TAU, radius, nothing, Point3f(point))
end

# ── Arrow ───────────────────────────────────────────────────────────────────

"""
    Arrow(start=LEFT, stop=RIGHT; buff=0.25, path_arc=0, thickness=3.0, …)

A filled arrow: shaft, tip and belly are ONE path of the SAME mobject — the
tip is not a child. `thickness` is the shaft width in GL's units (×0.015 scene
units); the caps `max_width_to_length_ratio` and
`max_tip_length_to_length_ratio` keep short arrows from turning fat.
"""
const Arrow = VMobject{:Arrow}
const _THICKNESS_TO_WIDTH = 0.015          # GL's tickness_multiplier (sic)

"The arrow's three measurements, with GL's proportion caps."
function _arrow_dimensions(len, thickness, tip_width_ratio, tip_angle,
                           max_tip_length_to_length_ratio, max_width_to_length_ratio)
    width = thickness * _THICKNESS_TO_WIDTH
    w_ratio = max_width_to_length_ratio / (width / len)
    w_ratio < 1 && (width *= w_ratio)
    tip_width = tip_width_ratio * width
    tip_length = tip_width / (2 * tan(tip_angle / 2))
    t_ratio = max_tip_length_to_length_ratio / (tip_length / len)
    if t_ratio < 1
        tip_length *= t_ratio
        tip_width *= t_ratio
    end
    return (width, tip_width, tip_length)
end

function (::Type{Arrow})(start = LEFT, stop = RIGHT;
                         buff::Real = MED_SMALL_BUFF, path_arc::Real = 0.0,
                         fill_color = GREY_B, fill_opacity = 1.0,
                         stroke_width = 0.0, thickness::Real = 3.0,
                         tip_width_ratio::Real = 5, tip_angle::Real = PI / 3,
                         max_tip_length_to_length_ratio::Real = 0.5,
                         max_width_to_length_ratio::Real = 0.1, kw...)
    m = vmob(:Arrow; fill_color, fill_opacity, stroke_width, kw...)
    p0, p1 = _endpoints(start, stop)
    return _set_arrow_points!(m, p0, p1, Float64(buff), Float64(path_arc),
                              Float64(thickness), Float64(tip_width_ratio),
                              Float64(tip_angle),
                              Float64(max_tip_length_to_length_ratio),
                              Float64(max_width_to_length_ratio))
end

function _set_arrow_points!(m::VMobject, start::Point3f, stop::Point3f, buff, path_arc,
                            thickness, tip_width_ratio, tip_angle,
                            max_tip_length_to_length_ratio, max_width_to_length_ratio)
    v = SVector{3,Float64}(stop - start)
    len = max(norm(v), 1e-8)
    unit = Point3f(v / len)
    width, tip_width, tip_length = _arrow_dimensions(
        len - buff, thickness, tip_width_ratio, tip_angle,
        max_tip_length_to_length_ratio, max_width_to_length_ratio)

    R = 0.0
    if path_arc == 0
        start = start + Float32(buff) * unit
        stop = stop - Float32(buff) * unit
    else
        R = len / 2 / sin(path_arc / 2)
        mid = Point3f(0.5 * (start + stop))
        centre = mid + rotate_vector(Point3f(0.5 * v), PI / 2) / tan(path_arc / 2)
        start = centre + rotate_vector(start - centre, buff / R)
        stop = centre + rotate_vector(stop - centre, -buff / R)
        path_arc -= (2buff + tip_length) / R
    end
    v = SVector{3,Float64}(stop - start)
    len = norm(v)

    # the arrow is built pointing LEFT and then oriented
    if path_arc == 0
        base = Point3f[(len - tip_length) * RIGHT,
                       0.5 * (len - tip_length) * RIGHT, ORIGIN]
        points1 = [p + Float32(width / 2) * UP for p in base]
        points2 = [p + Float32(width) * DOWN for p in reverse(points1)]
    else
        arc = quadratic_bezier_points_for_arc(path_arc)
        rot = rotation_matrix(PI / 2 - path_arc, OUT)
        place(p, r) = Point3f(rot * SVector{3,Float64}(r * p[1], r * p[2], r * p[3])) +
                      Float32(R) * DOWN
        points1 = [place(p, R + width / 2) for p in arc]
        points2 = [place(p, R - width / 2) for p in reverse(arc)]
    end

    set_points!(m, points1)
    add_line_to!(m, Float32(tip_width / 2) * UP)
    add_line_to!(m, Float32(tip_length) * LEFT)      # the tip vertex
    add_line_to!(m, Float32(tip_width / 2) * DOWN)
    add_line_to!(m, points2[1])
    add_subpath!(m, points2)
    add_line_to!(m, points1[1])

    rotate!(m, angle_of_vector(v) - get_angle(m))
    rotate!(m, PI / 2 - acos(clamp(normalize(v)[3], -1.0, 1.0));
            axis = rotate_vector(get_unit_vector(m), -PI / 2))
    return shift!(m, start - get_start(m))
end

# An arrow's endpoints are not the endpoints of its path: the start is the
# centre of the shaft and the end is the tip VERTEX. Both follow from the
# construction invariant (n = 2·n_shaft + 9 points, vertex at n_shaft+4), so
# there is no need to store the index in the mobject as GL does.
_tip_index(m::VMobject) = (get_num_points(m) - 9) ÷ 2 + 4
get_start(m::VMobject{:Arrow}) = Point3f(0.5 * (m.points[begin] + m.points[end-2]))
get_end(m::VMobject{:Arrow}) = m.points[_tip_index(m)]

# ═══════════════════════════════════════════════════════════════════════
# Arrow and line variants
# ═══════════════════════════════════════════════════════════════════════
# Compositions over the Arrow and Line this file already builds. What is NOT
# here, and why: ManimGL's `ArrowTip` and Manim CE's tip zoo (`StealthTip`,
# `ArrowTriangleTip`, `ArrowCircleTip`, `ArrowSquareTip`) are interchangeable
# tip MOBJECTS attached as children. Janim's arrow has no such seam — shaft,
# tip and belly are ONE contour of ONE mobject, on purpose (it is what keeps
# an arrow a single fillable path). Porting the tip zoo means building that
# seam first, which is a mechanism and not a composition.

"""
    VectorMobject(direction = RIGHT; buff = 0, kw...)

An arrow from the ORIGIN to `direction` — the arrow you draw when the arrow IS
the quantity:

```julia
v = VectorMobject(2 * RIGHT + UP)
w = VectorMobject([1, 2, 0]; fill_color = YELLOW)
```

Manim calls this `Vector`, and that name is taken: Julia's `Vector` is
`Array{T,1}` and shadowing it would break every `Vector{Float64}` in the
caller's code. Same reason, same treatment as [`TextMobject`](@ref) and
[`MatrixMobject`](@ref) — see `docs/naming.md`.

Note the `buff = 0`: unlike a plain [`Arrow`](@ref) between two mobjects, a
vector starts exactly at the origin, because a vector that does not start
where it starts is a different vector.
"""
const VectorMobject = VMobject{:Vector}

function (::Type{VectorMobject})(direction = RIGHT; buff::Real = 0.0, kw...)
    d = length(direction) == 2 ? Point3f(direction[1], direction[2], 0) :
        Point3f(direction)
    return Arrow(ORIGIN, d; buff, kw...)
end

"""
    DoubleArrow(start = LEFT, stop = RIGHT; buff = 0.25, path_arc = 0, kw...)

An arrow with a head at BOTH ends — the one that says "these two are related"
rather than "this one becomes that one":

```julia
DoubleArrow(square.get_left, square.get_right)
DoubleArrow(a, b; path_arc = TAU / 8)
```

It is a [`VGroup`](@ref) of two arrows meeting in the middle, and that is a
real difference from Manim: there a double arrow is one mobject carrying two
tip children. Janim's arrow is a single contour with its head built in, so two
heads means two arrows. What follows from it: `get_start`/`get_end` describe
the group's box rather than the shaft, and a `Transform` pairs the two halves
with the target's children. Everything visual is the same.
"""
function DoubleArrow(start = LEFT, stop = RIGHT; buff::Real = MED_SMALL_BUFF,
                     path_arc::Real = 0.0, kw...)
    # The buff belongs to the OUTER ends only. Building each half as
    # `Arrow(mid, end; buff)` trims it at BOTH of its ends, which opens a gap
    # down the middle — visible immediately in a render, invisible in every
    # number. So the spine is trimmed once, and the halves are drawn from its
    # midpoint outwards with no buff of their own.
    spine = Line(start, stop; buff, path_arc)
    a, b = get_start(spine), get_end(spine)
    mid = point_from_proportion(spine, 0.5)
    return VGroup(Arrow(mid, b; buff = 0.0, path_arc = path_arc / 2, kw...),
                  Arrow(mid, a; buff = 0.0, path_arc = -path_arc / 2, kw...))
end

"""
    CurvedArrow(start, stop; angle = TAU/4, kw...)

An arrow that travels along an arc instead of a straight line:

```julia
CurvedArrow(2 * LEFT, 2 * RIGHT)                  # bulging up
CurvedArrow(a, b; angle = -TAU / 6, fill_color = YELLOW)
```

`angle` is the arc's central angle, positive counter-clockwise — the same
convention as [`ArcBetweenPoints`](@ref). It is [`Arrow`](@ref) with
`path_arc`, spelled the way both reference engines spell it, so a scene
translated from either one reads unchanged.

For the arrow being DRAWN along its arc, see [`DrawCurvedArrow`](@ref).
"""
CurvedArrow(start, stop; angle::Real = TAU / 4, kw...) =
    Arrow(start, stop; path_arc = angle, kw...)

"""
    CurvedDoubleArrow(start, stop; angle = TAU/4, kw...)

[`CurvedArrow`](@ref) with a head at both ends — a [`DoubleArrow`](@ref) along
an arc. Present in both engines with this name.
"""
CurvedDoubleArrow(start, stop; angle::Real = TAU / 4, kw...) =
    DoubleArrow(start, stop; path_arc = angle, kw...)

"""
    TangentLine(mob, alpha; length = 1, d_alpha = 1e-6, kw...)

The tangent to a shape at the point `alpha` of the way along its path:

```julia
c = Circle(; radius = 2)
TangentLine(c, 0.0; length = 4)        # at the rightmost point
TangentLine(c, 0.4; length = 4, color = GREEN)
```

`alpha` runs 0 → 1 along the path, the same parameter
[`point_from_proportion`](@ref) takes. The direction is a numerical
derivative over `d_alpha`, which is what both engines do — there is no
analytic tangent to ask for once a shape is a chain of Béziers.

The line is CENTRED on the point of tangency, so `length` is split either
side of it.
"""
function TangentLine(mob::VMobject, alpha::Real; length::Real = 1.0,
                     d_alpha::Real = 1e-6, kw...)
    a = Float64(alpha)
    # Step INWARDS at the ends so the pair never falls off the path.
    a1 = clamp(a - d_alpha, 0.0, 1.0)
    a2 = clamp(a + d_alpha, 0.0, 1.0)
    a1 == a2 && throw(ArgumentError(
        "d_alpha = $d_alpha is too small to take a derivative at alpha = $a"))
    p1, p2 = point_from_proportion(mob, a1), point_from_proportion(mob, a2)
    v = p2 - p1
    n = sqrt(sum(abs2, v))
    n > 0 || throw(ArgumentError(
        "the path does not move between alpha = $a1 and $a2, so it has no " *
        "tangent there — try a larger d_alpha"))
    u = v ./ Float32(n)
    centre = point_from_proportion(mob, a)
    half = Float32(length) / 2
    return Line(centre - half * u, centre + half * u; buff = 0.0, kw...)
end

"""
    StrokeArrow(start = LEFT, stop = RIGHT; stroke_width = 5, buff = 0.25, kw...)

An arrow drawn with a STROKE rather than a fill: the shaft is a stroked line
and only the head is filled.

```julia
StrokeArrow(a, b; stroke_width = 8, color = YELLOW)
```

The difference from [`Arrow`](@ref) is what happens under a zoom or a scale.
A filled arrow is geometry, so it grows with the scene; a stroked one keeps
its shaft width in screen terms, which is what you want for a pointer that
must stay legible while the camera moves. ManimGL's; Manim CE has no
equivalent.

It is a [`VGroup`](@ref) of shaft and head, for the reason
[`DoubleArrow`](@ref) is: this engine's arrow has no detachable tip.
"""
function StrokeArrow(start = LEFT, stop = RIGHT; stroke_width::Real = 5.0,
                     buff::Real = MED_SMALL_BUFF, color = GREY_A,
                     tip_length::Real = 0.25, tip_width_ratio::Real = 1.2, kw...)
    p0, p1 = _endpoints(start, stop)
    v = p1 - p0
    n = sqrt(sum(abs2, v))
    n > 2 * buff || throw(ArgumentError(
        "the two ends are $(round(n; digits = 4)) apart and the buff trims " *
        "$(2 * buff) — there is no arrow left to draw"))
    u = v ./ Float32(n)
    a = p0 + Float32(buff) * u
    b = p1 - Float32(buff) * u
    tl = min(Float64(tip_length), 0.5 * (n - 2 * buff))
    base = b - Float32(tl) * u
    perp = Point3f(-u[2], u[1], 0) * Float32(tl * tip_width_ratio / 2)
    shaft = Line(a, base; buff = 0.0)
    set_stroke!(shaft; color, width = stroke_width)
    head = Polygon(b, base + perp, base - perp)
    set_fill!(head; color, opacity = 1.0)
    set_stroke!(head; width = 0.0)
    return VGroup(shaft, head; kw...)
end
