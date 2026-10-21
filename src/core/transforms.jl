# Affine transforms — a port of GL (mobject.py:283-1010).
#
# EVERY transform goes through a single function: apply_points_function!
# with the affine conjugation p' = f(p − c) + c. The hot loop does not
# allocate — f arrives as a type parameter
# (forced specialisation) and the conjugation happens point by point in place.

"""
The points of a family member that is not a VMobject. Each raster type
adds its method (an image moves its corners, a mesh its vertices AND its
normal points, a cloud its centres); the default does nothing, which is what
a ValueTracker inside a Group wants.
"""
_apply_leaf_points!(f, ::Mobject, ap) = nothing

"""
    apply_points_function!(f, m; about_point = nothing, about_edge = ORIGIN,
                           works_on_bounding_box = false)

Apply `f` to every point of `m`'s whole family — the one door every transform
in the engine goes through, and the escape hatch for the ones that do not
exist.

`f` takes a point and returns a point. It is applied CONJUGATED about a centre:
the point is moved to the origin, transformed, and moved back, which is what
makes `about_edge = LEFT` keep the left edge nailed down. Pass
`about_edge = nothing` for a raw application with no centre (that is what
[`shift!`](@ref) does, since a translation needs no pivot).

```julia
apply_points_function!(p -> Point3f(p[1], p[2] + 0.3sin(3p[1]), p[3]), m)
```

`works_on_bounding_box = true` says `f` is affine enough that the cached box
can be transformed too instead of being recomputed. If that is not true, leave
it `false` and the box is simply invalidated.

The subpath cut cache of every member whose points move is expired here too.
The cuts are a property of the points (GL decides them with a
1e-4 tolerance), so `scale!(m, 4)` on two subpaths 5e-5 apart must answer two
subpaths whether or not anyone asked before the scale. Lazy, like the other
expiries: the next `get_subpath_end_indices` rebuilds it.

Function-barrier: `f` arrives as a type parameter, so the point loop
specialises on it and does not allocate.
"""
function apply_points_function!(f::F, m::VMobject;
                                about_point = nothing,
                                about_edge = ORIGIN,
                                works_on_bounding_box::Bool = false) where {F}
    ap = if about_point === nothing && about_edge !== nothing
        get_bounding_box_point(m, about_edge)
    elseif about_point === nothing
        nothing
    else
        Point3f(about_point)
    end
    for mob in get_family(m)
        if mob isa VMobject
            if has_points(mob)
                _apply!(f, mob.points, ap)
                _expire_subpath_cuts!(mob)   # the cuts follow the points
            end
            works_on_bounding_box && _apply!(f, mob.bounding_box, ap)
        else
            _apply_leaf_points!(f, mob, ap)   # an image or a mesh child moves too
        end
    end
    if works_on_bounding_box
        for p in m.parents          # my box is up to date; my parents' is not
            refresh_bounding_box!(p)
        end
    else
        refresh_bounding_box!(m; recurse_down = true)
    end
    _refresh_shared_parents!(m)   # key groups and overlapping VGroups
    return m
end

_apply!(f::F, pts::Vector{Point3f}, ::Nothing) where {F} = (map!(f, pts, pts); nothing)
function _apply!(f::F, pts::Vector{Point3f}, c::Point3f) where {F}
    @inbounds for i in eachindex(pts)
        pts[i] = f(pts[i] - c) + c
    end
    nothing
end

# ── the four basics ─────────────────────────────────────────────────────────

"Translate. Updates the bbox in place (works_on_bounding_box, mobject.py:941)."
function shift!(m::VMobject, vector)
    v = Point3f(vector)
    apply_points_function!(p -> p + v, m;
                           about_edge = nothing, works_on_bounding_box = true)
end

"""
    scale!(m, factor; about_point=nothing, about_edge=ORIGIN)

Scales about the center by default; `about_edge=LEFT` keeps the left edge
fixed; `about_point` wins when given. `factor` may be a scalar or a vector.
"""
function scale!(m::VMobject, factor::Real; min_scale_factor::Real = 1e-8,
                about_point = nothing, about_edge = ORIGIN)
    s = Float32(max(factor, min_scale_factor))
    apply_points_function!(p -> s * p, m;
                           about_point, about_edge, works_on_bounding_box = true)
    # GL's `_handle_scale_side_effects` (mobject.py:949-977):
    # after the points moved, every member of the tree hears the CLAMPED
    # factor — a DecimalNumber keeps it in `size`, so its next rebuild draws
    # at the size it has now, not at the one it was born with.
    _scale_side_effects_walk!(m, Float64(s))
    return m
end

# The hook every mobject has and only a DecimalNumber fills (trackers.jl):
# nothing, by default. The walk goes by `submobjects`, not by `get_family` — a
# wrapper is a node of its parent but never a member of a family, and the number inside a scaled VGroup is exactly the case.
_scale_side_effects!(::Mobject, ::Float64) = nothing
const _NO_CHILDREN = Mobject[]
_side_effect_children(m::VMobject) = m.submobjects
_side_effect_children(::Mobject) = _NO_CHILDREN
function _scale_side_effects_walk!(m::Mobject, s::Float64)
    for child in _side_effect_children(m)
        _scale_side_effects!(child, s)
        _scale_side_effects_walk!(child, s)
    end
    return nothing
end
function scale!(m::VMobject, factor::Union{AbstractVector,Tuple};
                min_scale_factor::Real = 1e-8,
                about_point = nothing, about_edge = ORIGIN)
    s = Point3f(max.(Float32.(Tuple(factor)), Float32(min_scale_factor)))
    apply_points_function!(p -> s .* p, m;
                           about_point, about_edge, works_on_bounding_box = true)
end

"Anisotropic scaling along ONE dimension (dim: 1=x, 2=y, 3=z)."
function stretch!(m::VMobject, factor::Real, dim::Int; kw...)
    1 <= dim <= 3 || throw(ArgumentError(
        "dim=$dim does not exist: 1=x, 2=y, 3=z"))
    s = Point3f(ntuple(i -> i == dim ? Float32(factor) : 1.0f0, 3))
    apply_points_function!(p -> s .* p, m; works_on_bounding_box = true, kw...)
end

"""
    rotate!(m, angle; axis=OUT, about_point=nothing)

Rotates about the center by default. Invalidates the bbox (a rotated box is no
longer the box of the content — the dirty flag does the rest).
"""
function rotate!(m::VMobject, angle::Real; axis = OUT,
                 about_point = nothing, kw...)
    R = rotation_matrix(angle, axis)
    apply_points_function!(p -> Point3f(R * p), m; about_point, kw...)
end

# ── derived ─────────────────────────────────────────────────────────────────

"""
    move_to!(m, target; aligned_edge = ORIGIN, coor_mask = (1, 1, 1))

Move `m` so that its centre lands on `target`, which may be a point or another
mobject (in which case its centre is used).

```julia
move_to!(m, ORIGIN)
move_to!(label, dot)                             # both centres coincide
move_to!(m, box; aligned_edge = LEFT)            # left edges coincide instead
move_to!(m, target; coor_mask = (1, 0, 0))       # only the x moves
```

`aligned_edge` changes WHICH point of each is matched; `coor_mask` switches
axes off. It is a translation — nothing is resized. For "put it beside that
one" use [`next_to!`](@ref), and for absolute coordinates prefer the relative
layout over writing numbers by hand.
"""
function move_to!(m::Mobject, target; aligned_edge = ORIGIN, coor_mask = (1, 1, 1))
    dest = target isa Mobject ? get_bounding_box_point(target, aligned_edge) :
              Point3f(target)
    anchor = get_bounding_box_point(m, aligned_edge)
    shift!(m, (dest - anchor) .* Point3f(coor_mask))
end

"""
    rescale_to_fit!(m, length, dim; stretch = false, about_point, about_edge)

Resize `m` until its extent along axis `dim` (1 = x, 2 = y, 3 = z) is exactly
`length` scene units.

Uniform by default, so the other two axes follow and the shape is preserved;
`stretch = true` squashes the one axis only. A mobject with zero extent along
that axis is returned untouched — there is no factor that would grow it.

[`set_width!`](@ref), [`set_height!`](@ref) and [`set_depth!`](@ref) are this
with the axis named, and [`match_width!`](@ref) is this with the length taken
from another mobject.
"""
function rescale_to_fit!(m::Mobject, length::Real, dim::Int;
                         stretch::Bool = false, kw...)
    current = length_over_dim(m, dim)
    current == 0 && return m
    stretch ? stretch!(m, length / current, dim; kw...) :
              scale!(m, length / current; kw...)
end

"""
    set_width!(m, w; stretch = false, about_point, about_edge)

Scale `m` until it is `w` scene units wide.

```julia
set_width!(logo, 2)                                 # keeps the proportions
set_width!(bar, 5; stretch = true)                  # only the width moves
get_width(g) > FRAME_WIDTH - 1 && set_width!(g, FRAME_WIDTH - 1)
```

That last line is the standard guard against a group overflowing the screen.
See [`rescale_to_fit!`](@ref).
"""
set_width!(m::VMobject, w::Real; stretch::Bool = false, kw...) =
    rescale_to_fit!(m, w, 1; stretch, kw...)

"""
    set_height!(m, h; stretch = false, about_point, about_edge)

Scale `m` until it is `h` scene units tall. See [`set_width!`](@ref).
"""
set_height!(m::VMobject, h::Real; stretch::Bool = false, kw...) =
    rescale_to_fit!(m, h, 2; stretch, kw...)

"""
    set_depth!(m, d; stretch = false, about_point, about_edge)

Scale `m` until it is `d` scene units deep. Only meaningful for something with
extent in z — a [`Surface`](@ref), a 3D group. See [`set_width!`](@ref).
"""
set_depth!(m::VMobject, d::Real; stretch::Bool = false, kw...) =
    rescale_to_fit!(m, d, 3; stretch, kw...)

"""
    stretch_to_fit_width!(m, w; about_point, about_edge)
    stretch_to_fit_height!(m, h; …)
    stretch_to_fit_depth!(m, d; …)

Resize `m` along ONE dimension and leave the others where they are
(`mobject.py:1181-1189`) — `set_width!(m, w; stretch = true)` written the way
Manim writes it, which is the form a ported `.py` uses.

```julia
stretch_to_fit_width!(Square(), 6.0)    # 6 wide and still 2 tall
```

A dimension the mobject has no extent in is left alone rather than blown up:
[`rescale_to_fit!`](@ref) returns early on a length of zero, so asking a flat
square for depth 3 does nothing (measured in ManimGL: the same).
"""
stretch_to_fit_width!(m::VMobject, w::Real; kw...) = rescale_to_fit!(m, w, 1; stretch = true, kw...)

"See [`stretch_to_fit_width!`](@ref)."
stretch_to_fit_height!(m::VMobject, h::Real; kw...) = rescale_to_fit!(m, h, 2; stretch = true, kw...)

"See [`stretch_to_fit_width!`](@ref)."
stretch_to_fit_depth!(m::VMobject, d::Real; kw...) = rescale_to_fit!(m, d, 3; stretch = true, kw...)

"""
    flip!(m; axis = UP, about_point, about_edge)

Mirror `m` — implemented as a half turn about `axis`, which is what makes it
exact rather than a sign flip on the points.

The default `axis = UP` mirrors LEFT↔RIGHT (the vertical axis is the mirror);
`axis = RIGHT` mirrors up and down. It rotates about the mobject's centre
unless you name another `about_point`.
"""
flip!(m::VMobject; axis = UP, kw...) = rotate!(m, TAU / 2; axis, kw...)
