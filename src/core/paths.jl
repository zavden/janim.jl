# Quadratic bézier paths — a port of GL (vectorized_mobject.py:481-815).
#
# Interleaved 2n+1 layout: [a₀,h₀,a₁,h₁,…,aₙ] — curve k is points 2k+1:2k+3
# (1-based). Subpaths are separated with GL's trick: a "handle" pinned EXACTLY
# on the previous anchor marks the cut.

"""
    set_anchors_and_handles!(m, anchors, handles)

Replace `m`'s path with the curve through `anchors`, bending through
`handles` — one handle BETWEEN each pair of anchors, so `n + 1` anchors need
`n` handles (any other count throws).

The two lists are interleaved into the `a, h, a, h, …, a` layout the engine
stores. For a polyline there is [`set_points_as_corners!`](@ref) (which puts
each handle at the midpoint) and for a smooth curve through given points,
[`set_points_smoothly!`](@ref).
"""
function set_anchors_and_handles!(m::VMobject, anchors, handles)
    isempty(anchors) && return clear_points!(m)
    length(anchors) == length(handles) + 1 || throw(ArgumentError(
        "n+1 anchors are needed for n handles " *
        "(got $(length(anchors)) and $(length(handles)))"))
    pts = Vector{Point3f}(undef, 2length(anchors) - 1)
    pts[1:2:end] .= Point3f.(anchors)
    pts[2:2:end] .= Point3f.(handles)
    set_points!(m, pts)
end

"A polyline as degenerate béziers: each handle is the midpoint of its side."
function set_points_as_corners!(m::VMobject, corners)
    anchors = Point3f.(corners)
    handles = [(anchors[i] + anchors[i+1]) / 2 for i in 1:length(anchors)-1]
    set_anchors_and_handles!(m, anchors, handles)
end

"""
    start_new_path!(m, point)

GL's subpath cut (vectorized_mobject.py:496): if there are already points, it
appends [last_anchor, point] — that first point is the handle pinned on the
previous anchor that get_subpaths() will detect as the end of a path.
"""
function start_new_path!(m::VMobject, point)
    if has_points(m)
        append_points!(m, (m.points[end], Point3f(point)))
    else
        set_points!(m, (Point3f(point),))
    end
    return m
end

"A 'line' is 3 collinear points: a degenerate quadratic bézier."
function add_line_to!(m::VMobject, point)
    has_points(m) || throw(ArgumentError(
        "add_line_to! needs a starting point — call " *
        "start_new_path!(m, first_point) first"))
    a, b = m.points[end], Point3f(point)
    append_points!(m, ((a + b) / 2, b))
    return m
end

"""
    add_quadratic_bezier_to!(m, handle, anchor)

Extend the current path with one quadratic Bézier that bends towards `handle`
and ends at `anchor`.

```julia
v = VMobject()
start_new_path!(v, ORIGIN)
add_quadratic_bezier_to!(v, UP, UP + RIGHT)     # a curve
add_line_to!(v, 2 * RIGHT)                      # a straight piece
```

The pen has to be down: with no points at all it throws, since there is no
point to curve FROM — [`start_new_path!`](@ref) is what puts it down.
"""
function add_quadratic_bezier_to!(m::VMobject, handle, anchor)
    has_points(m) || throw(ArgumentError(
        "add_quadratic_bezier_to! needs a starting point — call " *
        "start_new_path!(m, first_point) first"))
    append_points!(m, (Point3f(handle), Point3f(anchor)))
    return m
end

# ── cubic → 2 quadratics (shared by fonts and the SVG importer) ───────

"""
Split the cubic at t=½ and approximate each half with the quadratic whose
handle is H = (3(p₁+p₂) − p₀ − p₃)/4 (same endpoints, averaged tangents) — the
same scheme as manimlib's get_quadratic_approximation_of_cubic. Error measured
at 0.0012 em on CFF glyphs. Returns (h₁, mid, h₂): two
add_quadratic_bezier_to! calls.
"""
function _cubic_to_two_quadratics(a0, c1, c2, a1)
    m01 = (a0 + c1) / 2; m12 = (c1 + c2) / 2; m23 = (c2 + a1) / 2
    m012 = (m01 + m12) / 2; m123 = (m12 + m23) / 2
    mid = (m012 + m123) / 2
    h1 = (3 * (m01 + m012) - a0 - mid) / 4
    h2 = (3 * (m123 + m23) - mid - a1) / 4
    return h1, mid, h2
end

# ── reading the structure ───────────────────────────────────────────────────

"""
    get_num_curves(m) → Int

How many quadratic pieces `m`'s path is made of: `get_num_points(m) ÷ 2`, since
the layout is `a, h, a, h, …, a`. A full [`Circle`](@ref) has 16.
"""
get_num_curves(m::VMobject) = get_num_points(m) ÷ 2

"""
    get_anchors(m) → view

The points the curve actually PASSES THROUGH — the odd positions of the point
array, as a view, not a copy. Writing into it moves the curve, and leaves the
cached bounding box stale: prefer [`set_points!`](@ref) or
[`apply_points_function!`](@ref), which keep the box honest.

For a closed polygon the first anchor is repeated at the end;
[`get_vertices`](@ref) drops it.
"""
get_anchors(m::VMobject) = @view m.points[1:2:end]

"""
    get_handles(m) → view

The control points the curve bends TOWARDS but does not reach — the even
positions, as a view. One per curve, so there is exactly one fewer of them than
there are anchors, per subpath.

A handle sitting exactly on the previous anchor is not a bend: it is the mark
that a subpath ENDS there ([`get_subpath_end_indices`](@ref)).
"""
get_handles(m::VMobject) = @view m.points[2:2:end]

"""
    get_nth_curve_points(m, n) → view

The three points `(anchor, handle, anchor)` of curve `n`, one-based, as a view.
Out of range throws rather than returning something empty.
"""
function get_nth_curve_points(m::VMobject, n::Int)
    1 <= n <= get_num_curves(m) || throw(ArgumentError(
        "curve $n does not exist — the mobject has $(get_num_curves(m)) curves"))
    return @view m.points[2n-1:2n+1]
end

"""
    get_subpath_end_indices(m) → Vector{Int} (1-based indices of final anchors)

An exact port of GL (vectorized_mobject.py:784): an anchor ends a subpath when
the handle after it is pinned on top of it (EXACT equality — they are bit-for-
bit copies) and the anchor that follows is genuinely different (atol 1e-4).
"""
function get_subpath_end_indices(m::VMobject)
    if m.subpath_end_indices === nothing
        m.subpath_end_indices = _subpath_end_indices(m.points)
    end
    return m.subpath_end_indices::Vector{Int}
end

function _subpath_end_indices(points::Vector{Point3f})
    atol = 1.0f-4
    ends = Int[]
    @inbounds for k in 1:(length(points)-1)÷2
        a0, h, a1 = points[2k-1], points[2k], points[2k+1]
        if a0 == h && any(abs.(h - a1) .> atol)
            push!(ends, 2k - 1)
        end
    end
    push!(ends, length(points))
    return ends
end

"The subpaths as views over `points` (no copying)."
function get_subpaths(m::VMobject)
    has_points(m) || return SubArray{Point3f,1}[]
    ends = get_subpath_end_indices(m)
    starts = [1; ends[1:end-1] .+ 2]
    return [@view m.points[i1:i2] for (i1, i2) in zip(starts, ends)]
end

# ═══════════════════════════════════════════════════════════════════════
# Anchor modes: make_smooth! / make_jagged! (as in GL)
# ═══════════════════════════════════════════════════════════════════════
#
# A port of GL's `change_anchor_mode` (vectorized_mobject.py:704) and the
# closed-form solver behind it (`approx_smooth_quadratic_bezier_handles`,
# bezier.py:184). Numbers verified point by point against manimlib.
#
# The idea, which is GL's and is worth restating because it is not a spline
# solve: for three successive anchors P₀, P₁, P₂ the handle
# h = ¼P₀ + P₁ − ¼P₂ makes the quadratic (P₀, h, P₁) pass through P₂. So for
# the handle BETWEEN P₁ and P₂ there are two natural choices — the one whose
# parabola continues on to P₃, and the one whose parabola came from P₀ — and
# the answer is their midpoint. No linear system, no iteration.
#
# GL calls this `approx_smooth`, and the name is honest: it does NOT achieve
# exact C¹ continuity, so `is_smooth` STAYS FALSE on a sharp zigzag after
# smoothing it. That is manimlib's own behaviour, checked rather than
# assumed. (GL's exact mode fits cubics and re-approximates them with
# fontTools, changing the point count and adding a font dependency; it is not
# ported and the docstring says so.)

using LinearAlgebra: dot, norm

# The endpoints count as "the same" at this scale. GL asks numpy's isclose,
# whose effective threshold here is ~1e-5; ours is the same order, chosen in
# Float32 terms rather than inherited.
@inline _same_point(a, b) = maximum(abs.(a - b)) <= 1.0f-5

"""
    smooth_quadratic_handles(anchors) → Vector{Point3f}

The n handles that most smoothly join n+1 anchors, in closed form (GL's
`approx_smooth_quadratic_bezier_handles`). When the first and last anchor
coincide the path is treated as CLOSED and the two end handles wrap around the
seam, so a loop has no corner where it joins.
"""
function smooth_quadratic_handles(anchors::AbstractVector{<:AbstractVector})
    n = length(anchors)
    n <= 1 && return Point3f[]
    n == 2 && return [Point3f((anchors[1] + anchors[2]) / 2)]
    a = Point3f.(anchors)
    closed = _same_point(a[1], a[n])
    q = 0.25f0
    h = Vector{Point3f}(undef, n - 1)
    for k in 1:n-1
        # …the parabola that carries on to the NEXT anchor…
        str = k <= n - 2 ? q * a[k] + a[k+1] - q * a[k+2] :
              closed     ? q * a[n-1] + a[n] - q * a[2] :      # wraps the seam
                           q * a[n] + a[n-1] - q * a[n-2]      # mirror at the end
        # …and the one that came from the PREVIOUS anchor.
        stl = k >= 2 ? q * a[k+1] + a[k] - q * a[k-1] :
              closed  ? q * a[2] + a[1] - q * a[n-1] :         # wraps the seam
                        q * a[1] + a[2] - q * a[3]             # mirror at the start
        h[k] = (str + stl) / 2
    end
    return h
end

"The turn between two tangents, in radians. A zero-length tangent says nothing."
@inline function _turn_angle(u, v)
    nu, nv = norm(u), norm(v)
    (nu < 1.0f-8 || nv < 1.0f-8) && return 0.0
    return acos(clamp(dot(u, v) / (nu * nv), -1.0, 1.0))
end

"""
    is_smooth(m; angle_tol = 1°) → Bool

Does the path pass through its anchors without corners? Measured as GL does:
the angle between the tangent arriving at each anchor and the one leaving it,
against a 1° tolerance. A closed subpath is also checked at its seam.

Used by `make_smooth!` to leave an already-smooth path ALONE — which is what
keeps a `Circle`'s exact arc handles from being replaced by an approximation.
"""
function is_smooth(m::VMobject; angle_tol::Real = π / 180)
    has_points(m) || return true
    for sp in get_subpaths(m)
        ncurves = (length(sp) - 1) ÷ 2
        ncurves >= 2 || continue
        for k in 1:ncurves-1                       # the interior joints
            _turn_angle(sp[2k+1] - sp[2k], sp[2k+2] - sp[2k+1]) < angle_tol ||
                return false
        end
        if _same_point(sp[1], sp[end])             # …and the seam of a loop
            _turn_angle(sp[end] - sp[end-1], sp[2] - sp[1]) < angle_tol ||
                return false
        end
    end
    return true
end

"Rewrite every subpath's handles under `mode`, preserving the subpath cuts."
function _set_anchor_mode!(m::VMobject, mode::Symbol)
    has_points(m) || return m
    subs = [collect(sp) for sp in get_subpaths(m)]   # copied: we rewrite m.points
    out = Point3f[]
    for (i, sp) in enumerate(subs)
        anchors = @view sp[1:2:end]
        newh = mode === :jagged ?
               [(anchors[k] + anchors[k+1]) / 2 for k in 1:length(anchors)-1] :
               smooth_quadratic_handles(anchors)
        np = copy(sp)
        for k in eachindex(newh)
            a0, a1, h = np[2k-1], np[2k+1], newh[k]
            # A handle landing exactly on the PREVIOUS anchor would be read as
            # a subpath cut (that is how cuts are encoded), and one landing on
            # the NEXT anchor is GL's documented visual bug. Both fall back to
            # the midpoint — i.e. to a straight segment, which is honest.
            np[2k] = (h == a0 || h == a1) ? (a0 + a1) / 2 : h
        end
        i == 1 || push!(out, out[end])              # re-create the cut marker
        append!(out, np)
    end
    return set_points!(m, out)
end

_vmobjects_of(m::VMobject) = (sub for sub in get_family(m) if sub isa VMobject)

"""
    make_smooth!(m; recurse=true)

Edit the path so it passes smoothly through its current anchors, without
moving any of them (GL's `make_smooth`, approx mode). Subpaths are smoothed
one by one and a subpath that is already smooth is left untouched.

    set_points_as_corners!(p, trail); make_smooth!(p)

**It is an approximation**, and deliberately the same one GL ships: on a sharp
zigzag `is_smooth` still reports `false` afterwards. What it buys is a curve
through the same points with no visible corners, in closed form and with the
point count unchanged.
"""
function make_smooth!(m::VMobject; recurse::Bool = true)
    for sub in (recurse ? _vmobjects_of(m) : (m,))
        has_points(sub) && !is_smooth(sub) && _set_anchor_mode!(sub, :smooth)
    end
    return m
end

"""
    make_jagged!(m; recurse=true)

The inverse: every handle back to the midpoint of its side, so the path
becomes the polyline through its anchors (GL's `make_jagged`).
"""
function make_jagged!(m::VMobject; recurse::Bool = true)
    for sub in (recurse ? _vmobjects_of(m) : (m,))
        has_points(sub) && _set_anchor_mode!(sub, :jagged)
    end
    return m
end

"""
    set_points_smoothly!(m, points)

`set_points_as_corners!` followed by `make_smooth!` — the one-liner for
building a curve that passes through a list of points.
"""
set_points_smoothly!(m::VMobject, points) =
    make_smooth!(set_points_as_corners!(m, points))

# ═══════════════════════════════════════════════════════════════════════
# The curve tools ManimGL has
# ═══════════════════════════════════════════════════════════════════════
#
# Their numbers match what ManimGL itself prints.

"""
    reverse_points!(m; recurse = true)

Run every path of `m` backwards — last point first — keeping each subpath a
subpath (GL's `VMobject.reverse_points`, vectorized_mobject.py:1258). A filled
path flips its winding, which is what a hole drawn the other way round relies
on.

The line that matters is the first one in the loop. A subpath ends where an
anchor is followed by a handle sitting on top of it, and a bare `reverse!`
turns that pair the wrong way round and welds every subpath into one (a
five-subpath logo would come back as one and lose its holes). So before
reversing, the handle after each inner end is moved onto the anchor that
starts the next subpath — `vectorized_mobject.py:1264-1265`, literally — and
the style rows travel with their points, as GL's `data[::-1]` does.
"""
function reverse_points!(m::VMobject; recurse::Bool = true)
    for sub in (recurse ? _vmobjects_of(m) : (m,))
        has_points(sub) || continue
        ends = get_subpath_end_indices(sub)
        pts = sub.points
        @inbounds for e in ends[1:end-1]
            pts[e + 1] = pts[e + 2]
        end
        reverse!(pts)
        reverse!(sub.stroke_rgba)
        reverse!(sub.fill_rgba)
        reverse!(sub.stroke_width)
        _note_data_changed!(sub)
    end
    return m
end

"""
    insert_n_curves!(m, n; recurse = true)

Add `n` curves to every path of `m` without moving it (GL's `insert_n_curves`,
vectorized_mobject.py:1026-1058). Each insertion splits the currently longest
curve — longest by chord, and a curve whose handle sits on its anchor (the
mark of a subpath break) is never split — so a line becomes shorter lines and
a circle stays a circle. What it buys is POINTS for a function of the points
to bend: a square with four curves cannot curve under
[`apply_points_function!`](@ref), one with fifty can. An empty mobject and a
one-point one are left alone, as in GL.

The style rows are resized the way GL resizes them (`resize_preserving_order`:
the new row `i` takes the old row at `i·old ÷ new`), so a gradient stretches
along the path instead of ending in a run of its last colour.
"""
function insert_n_curves!(m::VMobject, n::Integer; recurse::Bool = true)
    n >= 0 || throw(ArgumentError("insert_n_curves!: n must be ≥ 0, got $n"))
    for sub in (recurse ? _vmobjects_of(m) : (m,))
        get_num_curves(sub) > 0 || continue
        new_points = _insert_n_curves_to_point_list(n, sub.points)
        k = length(new_points)
        _resize_preserving_order!(sub.stroke_rgba, k)
        _resize_preserving_order!(sub.fill_rgba, k)
        _resize_preserving_order!(sub.stroke_width, k)
        set_points!(sub, new_points)
    end
    return m
end

"GL's `resize_preserving_order` (iterables.py:99), in place: row `i` of the result is old row `i·n ÷ k`."
function _resize_preserving_order!(rows::Vector, k::Int)
    n = length(rows)
    (n == k || n == 0) && return rows
    src = copy(rows)
    resize!(rows, k)
    @inbounds for i in 1:k
        rows[i] = src[((i - 1) * n) ÷ k + 1]
    end
    return rows
end

"GL's `insert_n_curves_to_point_list` (vectorized_mobject.py:1033), point for point."
function _insert_n_curves_to_point_list(n::Integer, points::Vector{Point3f})
    length(points) == 1 && return repeat(points, 2n + 1)
    nc = (length(points) - 1) ÷ 2
    atol = 1.0f-8                       # GL's tolerance_for_point_equality
    norms = Vector{Float64}(undef, nc)
    @inbounds for c in 1:nc
        a0, h, a1 = points[2c-1], points[2c], points[2c+1]
        norms[c] = norm(h - a0) < atol ? 0.0 : Float64(norm(a1 - a0))
    end
    ipc = zeros(Int, nc)                # insertions per curve
    for _ in 1:n
        i = argmax(norms)               # the FIRST of the longest, like np.argmax
        ipc[i] += 1
        norms[i] *= ipc[i] / (ipc[i] + 1)
    end
    out = Point3f[points[1]]
    @inbounds for c in 1:nc
        a0, h, a1 = points[2c-1], points[2c], points[2c+1]
        alphas = range(0.0, 1.0; length = ipc[c] + 2)
        for j in 1:(ipc[c] + 1)
            t = partial_bezier(a0, h, a1, alphas[j], alphas[j+1])
            push!(out, t[2], t[3])
        end
    end
    return out
end

"""
    get_subcurve(m, a, b) → VMobject

A copy of `m` reduced to the part of its path between proportions `a` and `b`
(GL's `get_subcurve`, vectorized_mobject.py:1103). The point count is kept —
what lies outside `[a, b]` collapses onto the two ends, as
[`pointwise_become_partial!`](@ref) leaves it — so the piece can still be
paired with the whole.
"""
function get_subcurve(m::VMobject, a::Real, b::Real)
    piece = copy(m)
    pointwise_become_partial!(piece, m, a, b)
    return piece
end

"""
    CurvesAsSubmobjects(m; kw...) → VGroup

One child per curve of `m`'s path, each a three-point VMobject in `m`'s style
(GL's `CurvesAsSubmobjects`, vectorized_mobject.py:1386) — the way one path
gets a colour per segment, or a piece-by-piece fade. A function that builds a
`VGroup`, like [`PGroup`](@ref).
"""
function CurvesAsSubmobjects(m::VMobject; kw...)
    g = VGroup(; kw...)
    for c in 1:get_num_curves(m)
        part = VMobject()
        set_points!(part, collect(get_nth_curve_points(m, c)))
        match_style!(part, m)
        add!(g, part)
    end
    return g
end
