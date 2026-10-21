# Cached bounding box — a port of GL (mobject.py:339-393).
#
# The box lives in the mobject as 3 rows [mins, mids, maxs] with a dirty flag.
# Affine transforms that preserve it (shift/scale/stretch) update it IN PLACE
# (works_on_bounding_box=true); rotate invalidates it. Invalidation travels up
# through `parents` (a group's box contains its children).

function get_bounding_box(m::VMobject)
    if m.needs_new_bounding_box
        mins, mids, maxs = compute_bounding_box(m)
        m.bounding_box[1] = mins
        m.bounding_box[2] = mids
        m.bounding_box[3] = maxs
        m.needs_new_bounding_box = false
    end
    return m.bounding_box
end

function compute_bounding_box(m::VMobject)
    mins = Point3f(Inf32, Inf32, Inf32)
    maxs = Point3f(-Inf32, -Inf32, -Inf32)
    any_points = false
    @inbounds for p in m.points
        mins = min.(mins, p)
        maxs = max.(maxs, p)
        any_points = true
    end
    for mob in Iterators.drop(get_family(m), 1)
        if mob isa VMobject
            has_points(mob) || continue
            # The ANNOTATION is load-bearing: `get_bounding_box` has four
            # methods, and four is past Julia's `max_methods` for
            # union-splitting — without it inference gives up on the return
            # type here and this loop boxes, so `rotate!(circle)` allocates
            # 272 bytes instead of 0. Every method returns [mins, mids, maxs].
            bb = get_bounding_box(mob)::Vector{Point3f}
        else
            # An image, a mesh or a cloud inside a VGroup counts too —
            # `_leaf_bounding_box` is `nothing` for what has no box or points
            lb = _leaf_bounding_box(mob)
            lb === nothing && continue
            bb = lb::Vector{Point3f}
        end
        mins = min.(mins, bb[1])
        maxs = max.(maxs, bb[3])
        any_points = true
    end
    any_points || return (ORIGIN, ORIGIN, ORIGIN)  # GL: zeros when there are no points
    return (mins, (mins + maxs) / 2, maxs)
end

function refresh_bounding_box!(m::VMobject; recurse_down::Bool = false,
                               recurse_up::Bool = true)
    if recurse_down
        for mob in get_family(m)
            mob isa VMobject && (mob.needs_new_bounding_box = true)
        end
    else
        m.needs_new_bounding_box = true
    end
    if recurse_up
        for p in m.parents
            refresh_bounding_box!(p)
        end
    end
    return m
end

"""
The box of a family member that is not a VMobject (an ImageMobject, a
Surface, a DotCloud…), or `nothing` when the type has none or holds no
points. Each raster type adds its method next to its `get_bounding_box`.
"""
_leaf_bounding_box(::Mobject) = nothing

"A node without a box cache (a wrapper, a raster mobject) only passes the news upwards."
function refresh_bounding_box!(m::Mobject; recurse_down::Bool = false,
                               recurse_up::Bool = true)
    if recurse_up
        for p in _parents(m)
            refresh_bounding_box!(p)
        end
    end
    return m
end

"""
    _refresh_shared_parents!(m)

Dirties the boxes of parents OUTSIDE the family that has just been
transformed. A child can have more than one parent — key groups
(`tex["x"]`) share children with the real parent, and a hand-built VGroup does
too: their box depends on points that just moved, but they are not in the
family and nobody else would tell them (without this, `shift!(tex, …)` would
leave `get_center(tex["x"])` frozen where it used to be; GL has that hole).

The common case — a single parent, always inside the family — leaves through
the `continue` without paying anything: zero cost for 99% of mobjects.
"""
function _refresh_shared_parents!(m::VMobject)
    fam = get_family(m)
    for mob in fam
        (mob isa VMobject && length(mob.parents) > 1) || continue
        for p in mob.parents
            any(x -> x === p, fam) || refresh_bounding_box!(p)
        end
    end
    return m
end

"""
    get_bounding_box_point(m, direction) → Point3f

Per dimension: sign(dir) −1/0/+1 picks the mins/mids/maxs row. With this, the
9+ critical points (get_center, get_left, corners…) are ONE function.
"""
_bbox_point(bb, direction) = Point3f(ntuple(3) do i
    bb[Int(sign(direction[i]))+2][i]
end)

# TYPED ON VMobject, not on Mobject: with an abstract signature the call to
# `get_bounding_box` inside stops being resolved statically and `rotate!` on a
# Circle went from 0 to 272 bytes — the same allocation trap as above. Other
# mobject types get their own two-line method instead; Surface has one in surface.jl.
"""
    get_bounding_box_point(m, direction) → Point3f

The point of `m`'s bounding box that lies furthest in `direction` — the general
form of which [`get_left`](@ref), [`get_top`](@ref) and the corners are special
cases.

```julia
get_bounding_box_point(m, UR)     # the top-right corner of the box
get_bounding_box_point(m, ORIGIN) # the centre — the same as get_center
```

Each axis is read independently from the sign of the direction, so any of the
27 combinations works. The box covers the whole FAMILY and is axis-aligned, so
a rotated square reports a bigger box than its side.
"""
get_bounding_box_point(m::VMobject, direction) = _bbox_point(get_bounding_box(m), direction)

"""
    get_center(m) → Point3f

The centre of `m`'s bounding box — the midpoint of its extent, not a centroid
of its points or its mass.

It covers the whole family, so a group's centre is the centre of everything it
holds. This is the point [`rotate!`](@ref) and [`scale!`](@ref) work about by
default, and the one [`move_to!`](@ref) places.
"""
get_center(m::VMobject) = get_bounding_box(m)[2]

"""
    get_center_of_mass(m) → Point3f

The MEAN of every point in `m`'s family — manim's `get_center_of_mass`, which
in both engines is exactly `get_all_points().mean(0)`.

```julia
get_center(m)             # the middle of the bounding box
get_center_of_mass(m)     # where the points crowd
```

**It is not the centroid of the area, and it is not the centre of the bounding
box.** It is the average of the CONTROL POINTS of the path, handles included,
so it follows wherever the description of the curve happens to be dense. On a
[`Star`](@ref) the spikes carry as many points as the body and pull the mean
towards them; on a shape whose left half is drawn with more curves than its
right, the mean drifts left although nothing moved.

That makes it the wrong tool for "where does this look like it balances" —
[`get_real_center_of_mass`](@ref) is the one that answers that — and a rough
"where is the detail" at best.

Neither engine leans on it, which is worth knowing before trusting the name:
ManimGL defines it and never calls it, and Manim CE calls it exactly once, in
`SpiralIn` (`creation.py:487`). It is here for a scene that asks for it by
name, and because a scene translated from Manim may look for it.

Because it averages control points, it also depends on HOW a shape is built,
and the two reference engines answer differently for the same outline. Janim
reproduces **ManimGL** exactly and departs from Manim CE, for one structural
reason: Janim and GL close a polygon by REPEATING the first vertex as the
last, so a [`Triangle`](@ref) is 7 points with one vertex counted twice and
its mean sits at `y = 1/7`; CE stores 12 cubic points with no repeat and lands
on the centroid, `y = 0`. Same for a [`Star`](@ref), where the closed form is
`outer_radius / get_num_points(m)` — `Star()` gives `(0, 1/21)` and CE gives
`(0, 0)`.

An empty mobject has no points to average and answers [`ORIGIN`](@ref), like
both engines' `mean` of an empty family would not.
"""
function get_center_of_mass(m::VMobject)
    n = 0
    sx = sy = sz = 0.0                       # 64 bits to add, 32 to store
    for mob in get_family(m)
        mob isa VMobject || continue
        @inbounds for p in mob.points
            sx += p[1]; sy += p[2]; sz += p[3]
            n += 1
        end
    end
    n == 0 && return Point3f(ORIGIN)
    return Point3f(sx / n, sy / n, sz / n)
end

# ── the area centroid ──────────────────────────────────────────────────────
#
# Neither reference engine has this. `get_center_of_mass` in both is the mean
# of the CONTROL POINTS, which is not a centre of mass and, in ManimGL's case,
# not even a property of the shape: it moves when you rotate the list of
# vertices. What follows is the real thing, and it is exact
# rather than sampled.
#
# Green's theorem turns the area integrals into contour integrals:
#
#     A    = ½ ∮ (x ẏ − y ẋ) dt
#     A·Cx = ½ ∮ x² ẏ dt
#     A·Cy = −½ ∮ y² ẋ dt
#
# Over a quadratic Bézier x(t) and y(t) are polynomials of degree 2, so those
# integrands are of degree 3, 5 and 5. Three-point Gauss–Legendre integrates
# every polynomial up to degree 5 EXACTLY — so three evaluations per curve give
# the integral itself, not an approximation of it. That is the whole reason
# this is cheap: a quadratic engine is exactly the case where the closed form
# is short.

"Gauss–Legendre on [0,1], 3 nodes: exact for polynomials up to degree 5."
const _GAUSS3_T = (0.5 - 0.5 * sqrt(0.6), 0.5, 0.5 + 0.5 * sqrt(0.6))
const _GAUSS3_W = (5 / 18, 8 / 18, 5 / 18)

"""
The three Green integrals over ONE quadratic Bézier, un-halved:
`(∮(xẏ − yẋ), ∮x²ẏ, ∮y²ẋ)`. In `Float64` — the points are `Float32`, but the
moments are differences of similar-sized products and lose digits fast.
"""
@inline function _green_segment(p0, p1, p2)
    x0, y0 = Float64(p0[1]), Float64(p0[2])
    x1, y1 = Float64(p1[1]), Float64(p1[2])
    x2, y2 = Float64(p2[1]), Float64(p2[2])
    # P(t) = a0 + a1 t + a2 t²
    a1x, a1y = 2(x1 - x0), 2(y1 - y0)
    a2x, a2y = x0 - 2x1 + x2, y0 - 2y1 + y2
    ia = ix = iy = 0.0
    @inbounds for k in 1:3
        t, w = _GAUSS3_T[k], _GAUSS3_W[k]
        x = x0 + a1x * t + a2x * t * t
        y = y0 + a1y * t + a2y * t * t
        dx = a1x + 2 * a2x * t
        dy = a1y + 2 * a2y * t
        ia += w * (x * dy - y * dx)
        ix += w * (x * x * dy)
        iy += w * (y * y * dx)
    end
    return (ia, ix, iy)
end

"""
    get_real_center_of_mass(m) → Point3f

The CENTRE OF MASS of the filled shape: the centroid of its area, taking the
region as a uniform lamina. Computed exactly, not sampled.

```julia
get_center(m)                  # the middle of the bounding box
get_center_of_mass(m)          # manim's: the mean of the control points
get_real_center_of_mass(m)     # where it would balance on a pin
```

This is the one of the three that answers "where does this shape balance",
and the only one that is a property of the SHAPE rather than of how it was
written down. Rotate the list of vertices of a polygon and this does not move;
[`get_center_of_mass`](@ref) does, because ManimGL's formula counts the first
vertex twice. Neither reference engine offers this, which is why the name is
not manim's.

For a triangle it is the familiar `(v₁+v₂+v₃)/3`; for a trapezoid, a concave
polygon or a circular sector it is NOT the average of the vertices, and that
is exactly where manim's function stops being usable.

Holes work. The integral is signed, so a subpath wound the other way — the
inside of an `O`, the hole of an [`Annulus`](@ref) — subtracts its own area
and its own moment, and the answer is the centroid of what is actually
painted. A subpath that does not close is closed with a straight chord, which
is what the renderer fills anyway.

Two limits worth knowing:

  * **It is planar, in xy.** The integrals are the 2D ones; `z` comes from the
    bounding box, which is right for the flat paths a `VMobject` holds and
    meaningless for a path bent out of the plane.
  * **Overlap counts twice.** Over a family, the areas are summed, so two
    children lying on top of each other weigh double in the overlap. The true
    centroid of a union needs boolean geometry, which this is not.

A shape with no area — a [`Line`](@ref), an open arc, a figure that cancels
itself out — has no centre of mass, and this throws `ArgumentError` rather
than dividing by a number that is only accidentally not zero.
"""
function get_real_center_of_mass(m::VMobject)
    ia = ix = iy = 0.0
    for mob in get_family(m)
        mob isa VMobject || continue
        for sub in get_subpaths(mob)
            n = length(sub)
            n >= 3 || continue
            @inbounds for k in 1:(n-1)÷2
                a, b, c = _green_segment(sub[2k-1], sub[2k], sub[2k+1])
                ia += a; ix += b; iy += c
            end
            # Close it. A subpath that already closes has last == first and
            # this contributes nothing, so there is no special case to get
            # wrong — and an open one gets the chord the fill would draw.
            q, p = sub[end], sub[1]
            a, b, c = _green_segment(q, (q + p) / 2, p)
            ia += a; ix += b; iy += c
        end
    end

    area = ia / 2
    lo, mid, hi = get_bounding_box(m)
    span = Float64(hi[1] - lo[1]) + Float64(hi[2] - lo[2])
    # A tolerance in the units of the answer: the area of a shape this wide.
    # Absolute epsilons cannot work here — a scene is 14 units across and a
    # glyph is 0.1.
    if abs(area) <= 1e-9 * span^2
        throw(ArgumentError(
            "get_real_center_of_mass: this shape encloses no area (computed " *
            "$(area)), so it has no centre of mass. A Line, an open arc or a " *
            "path that cancels itself out lands here — get_center or " *
            "get_center_of_mass answer for those."))
    end
    return Point3f(ix / (2 * area), -iy / (2 * area), mid[3])
end

"""
    get_left(m) → Point3f

The middle of the left edge of `m`'s bounding box. Handy as an anchor:
`next_to!(label, m, LEFT)` does this arithmetic for you, but a raw point is
sometimes what a [`Line`](@ref) wants. See [`get_bounding_box_point`](@ref).
"""
get_left(m::VMobject)   = get_bounding_box_point(m, LEFT)

"""
    get_right(m) → Point3f

The middle of the right edge of `m`'s bounding box. See [`get_left`](@ref).
"""
get_right(m::VMobject)  = get_bounding_box_point(m, RIGHT)

"""
    get_top(m) → Point3f

The middle of the top edge of `m`'s bounding box. See [`get_left`](@ref).
"""
get_top(m::VMobject)    = get_bounding_box_point(m, UP)

"""
    get_bottom(m) → Point3f

The middle of the bottom edge of `m`'s bounding box. See [`get_left`](@ref).
"""
get_bottom(m::VMobject) = get_bounding_box_point(m, DOWN)

_dim_length(bb, dim::Int) = abs(bb[3][dim] - bb[1][dim])

"""
    length_over_dim(m, dim) → Float32

How far `m` extends along axis `dim` (1 = x, 2 = y, 3 = z), in scene units.
[`get_width`](@ref), [`get_height`](@ref) and [`get_depth`](@ref) are this with
the axis named.
"""
function length_over_dim(m::VMobject, dim::Int)
    1 <= dim <= 3 || throw(ArgumentError(
        "dim=$dim does not exist: 1=width(x), 2=height(y), 3=depth(z)"))
    bb = get_bounding_box(m)
    return abs(bb[3][dim] - bb[1][dim])
end

"""
    get_width(m) → Float32

How wide `m` is, in scene units — the bounding box of the whole family, so a
group is as wide as everything in it.

Axis-aligned, so a rotated rectangle is wider than its side; and measured from
the POINTS, so a thick stroke sticking out is not counted.
"""
get_width(m::VMobject)  = length_over_dim(m, 1)

"""
    get_height(m) → Float32

How tall `m` is, in scene units. See [`get_width`](@ref).
"""
get_height(m::VMobject) = length_over_dim(m, 2)

"""
    get_depth(m) → Float32

How deep `m` is along z, in scene units — zero for anything flat. See
[`get_width`](@ref).
"""
get_depth(m::VMobject)  = length_over_dim(m, 3)
