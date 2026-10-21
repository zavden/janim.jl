# ValueTracker · DecimalNumber · always_redraw.
#
# The trio behind every parametric scene in CE/GL: a number you can animate, a
# mobject that displays it, and the glue that rebuilds the display each frame.
#
# The interpolation contract means this file needs NO changes to
# animation/animations.jl. ValueTracker becomes animatable by writing the four
# lines of the interpolation contract, and Transform (and therefore `animate`)
# picks it up by dispatch. If you find yourself editing Transform to support a
# new type, something went wrong.

# ═══════════════════════════════════════════════════════════════════════
# ValueTracker — a mobject with no points whose state is one number
# ═══════════════════════════════════════════════════════════════════════

"""
    ValueTracker(value = 0.0)

A pointless (literally: no points) mobject holding one `Float64`. It lives in
the scene like anything else, and it is animatable:

    vt = ValueTracker(0.0)
    add!(scene, vt)
    play!(scene, animate(vt, (set_value!, 10.0)); run_time = 2)

Read it with `get_value(vt)` from an updater to drive anything else.
"""
mutable struct ValueTracker <: Mobject
    value::Float64
    updaters::Vector{Updater}
    parents::Vector{Mobject}        # the node contract — it can live in a Group
end
ValueTracker(value::Real = 0.0) = ValueTracker(Float64(value), Updater[], Mobject[])

"""
    get_value(x) → Float64

The number a [`ValueTracker`](@ref) or a [`DecimalNumber`](@ref) currently
holds. This is what an updater reads to follow the animated quantity:

```julia
add_updater!(dot, m -> move_to!(m, c2p(ax, get_value(vt), f(get_value(vt)))))
```
"""
get_value(v::ValueTracker) = v.value

"""
    set_value!(vt, x)

Write a new number into a [`ValueTracker`](@ref), and return the tracker.

Animating it is the point: `animate(vt, (set_value!, 10.0))` interpolates the
number over the run time, and everything reading it through
[`get_value`](@ref) follows.
"""
set_value!(v::ValueTracker, x::Real) = (v.value = Float64(x); v)

"""
    increment_value!(vt, dx)

Add `dx` to the tracker's value. `set_value!(vt, get_value(vt) + dx)`, written
the way it is meant.
"""
increment_value!(v::ValueTracker, dx::Real) = set_value!(v, v.value + dx)

# ── the four lines of the contract ──────────────────────────────────
is_interpolable(::ValueTracker) = true
Base.copy(v::ValueTracker) = ValueTracker(v.value, copy(v.updaters), Mobject[])   # updaters travel
interpolate!(dst::ValueTracker, a::ValueTracker, b::ValueTracker, alpha::Real) =
    (dst.value = a.value + alpha * (b.value - a.value); dst)
become!(dst::ValueTracker, src::ValueTracker) = (dst.value = src.value; dst)

# ── the minimum to live in a scene ─────────────────────────────────────────
# The generic Mobject fallbacks (interpolable.jl) cover get_family and the
# no-updater case; a ValueTracker DOES carry updaters (that is how CE drives
# one tracker from another), so those three are specialised.
has_updaters(v::ValueTracker) = !isempty(v.updaters)
get_updaters(v::ValueTracker) = v.updaters
add_updater!(v::ValueTracker, f; call::Bool = true, parallel::Bool = false) =
    (push!(v.updaters, Updater(f; parallel)); call && update!(v, 0.0); v)

function update!(v::ValueTracker, dt::Real = 0.0; recurse::Bool = true)
    for u in v.updaters
        u(v, dt)
    end
    return v
end

# A ValueTracker draws nothing. The renderer walks families and asks each
# member for its points; declaring zero points is what keeps it invisible
# without a single `if` in the backend.
get_num_points(::ValueTracker) = 0
has_points(::ValueTracker) = false

"""
    ComplexValueTracker(z = 0im)

A [`ValueTracker`](@ref) that holds a COMPLEX number (`value_tracker.py:65`,
where GL swaps the tracker's `value_type` for `complex128`). Everything else is
the same: read it with [`get_value`](@ref), write it with [`set_value!`](@ref),
animate it with `animate(z, (set_value!, 2 + 3im))`.

```julia
z = ComplexValueTracker(1 + 0im)
add_updater!(dot, m -> move_to!(m, complex_to_R3(get_value(z))))
play!(scene, animate(z, (set_value!, exp(im * TAU / 3))))
```

Interpolation is BY COMPONENT, which is GL's (its uniform is an array of two
floats): a quarter of the way from `0` to `2 + 4i` is `0.5 + 1i`, not a point
on some arc. Rotating a number is `animate` over the ANGLE, not over `z`.

It is a separate type rather than a keyword because a `ValueTracker` stores a
`Float64` — Julia's fields are typed, and one number's type is not a runtime
option here as it is in Python.
"""
mutable struct ComplexValueTracker <: Mobject
    value::ComplexF64
    updaters::Vector{Updater}
    parents::Vector{Mobject}
end
ComplexValueTracker(value::Number = 0im) = ComplexValueTracker(ComplexF64(value), Updater[], Mobject[])

get_value(v::ComplexValueTracker) = v.value
set_value!(v::ComplexValueTracker, z::Number) = (v.value = ComplexF64(z); v)
increment_value!(v::ComplexValueTracker, dz::Number) = set_value!(v, v.value + dz)

is_interpolable(::ComplexValueTracker) = true
Base.copy(v::ComplexValueTracker) = ComplexValueTracker(v.value, copy(v.updaters), Mobject[])
interpolate!(dst::ComplexValueTracker, a::ComplexValueTracker, b::ComplexValueTracker, alpha::Real) =
    (dst.value = a.value + alpha * (b.value - a.value); dst)
become!(dst::ComplexValueTracker, src::ComplexValueTracker) = (dst.value = src.value; dst)

has_updaters(v::ComplexValueTracker) = !isempty(v.updaters)
get_updaters(v::ComplexValueTracker) = v.updaters
add_updater!(v::ComplexValueTracker, f; call::Bool = true, parallel::Bool = false) =
    (push!(v.updaters, Updater(f; parallel)); call && update!(v, 0.0); v)
function update!(v::ComplexValueTracker, dt::Real = 0.0; recurse::Bool = true)
    for u in v.updaters
        u(v, dt)
    end
    return v
end
get_num_points(::ComplexValueTracker) = 0
has_points(::ComplexValueTracker) = false

# ═══════════════════════════════════════════════════════════════════════
# Group — the container that is NOT vector-specific
# ═══════════════════════════════════════════════════════════════════════
#
# `VGroup` is a VMobject, so its children must be VMobjects too: `add!` writes
# into `mob.parents`, a field a ValueTracker does not have. That was fine
# while everything animatable was a VMobject — which stops being true,
# because `AnimationGroup` builds a group out of the mobjects it
# animates and one of them may now be a tracker or a camera frame.
#
# Manim has had both containers forever (Group vs VGroup) for this reason.
# This is Group: it holds ANY Mobject, draws nothing itself, and exists so
# that composition does not have to care what it is composing.

"""
    Group(mobs...)

A container for ANY mobjects: VMobjects, ValueTrackers, a CameraFrame, a
Surface. Use `VGroup` when everything is vector geometry and you want the
group to accept transforms and style; use `Group` when the members only need
to live and update together.
"""
mutable struct Group <: Mobject
    submobjects::Vector{Mobject}
    parents::Vector{Mobject}            # the node contract, like every mobject
    updaters::Vector{Updater}           # a Group has its own updaters (GL)
    updating_suspended::Bool
    z_index::Float64                    # a Group used as a root sorts in the scene
    family::Union{Nothing,Vector{Mobject}}       # DFS cache, like VMobject's
    draw_family::Union{Nothing,Vector{Mobject}}  # z per level, like VMobject's
    has_updaters_cache::Union{Nothing,Bool}
end
Group(mobs::Vector{Mobject}; z_index::Real = 0.0) =
    _add_children!(Group(Mobject[], Mobject[], Updater[], false, Float64(z_index),
                         nothing, nothing, nothing), mobs)
Group(mobs::Mobject...; kw...) = Group(collect(Mobject, mobs); kw...)

# the tree, through the same door as a VMobject (mobject.jl)
function get_family(g::Group)
    if g.family === nothing
        fam = Mobject[g]
        for sm in g.submobjects
            append!(fam, get_family(sm))
        end
        g.family = fam
    end
    return g.family::Vector{Mobject}
end
function note_changed_family!(g::Group)
    g.family = nothing
    g.draw_family = nothing
    refresh_has_updater_status!(g)
    for p in g.parents
        note_changed_family!(p)
    end
    return g
end
function _draw_family(g::Group)
    g.draw_family === nothing || return g.draw_family::Vector{Mobject}
    fam = get_family(g)
    if !any(x -> get_z_index(x) != 0.0, fam)
        g.draw_family = fam
        return fam
    end
    out = Mobject[g]
    for child in _by_z(g.submobjects)
        append!(out, _draw_family(child))
    end
    g.draw_family = out
    return out
end
add!(g::Group, mobs::Mobject...) = _add_children!(g, mobs)
remove!(g::Group, mobs::Mobject...) = _remove_children!(g, mobs)
get_num_points(::Group) = 0
has_points(::Group) = false

function bring_to_front!(parent::Group, child::Mobject)
    i = findfirst(x -> x === child, parent.submobjects)
    i === nothing && throw(ArgumentError("bring_to_front!: that mobject is not a child of this Group"))
    deleteat!(parent.submobjects, i)
    push!(parent.submobjects, child)
    note_changed_family!(parent)
    return parent
end
function bring_to_back!(parent::Group, child::Mobject)
    i = findfirst(x -> x === child, parent.submobjects)
    i === nothing && throw(ArgumentError("bring_to_back!: that mobject is not a child of this Group"))
    deleteat!(parent.submobjects, i)
    pushfirst!(parent.submobjects, child)
    note_changed_family!(parent)
    return parent
end

# updaters: the group's own run AFTER its members' (GL's update walks
# the submobjects first), and the family status is cached like a VMobject's
function has_updaters(g::Group)
    if g.has_updaters_cache === nothing
        g.has_updaters_cache = !isempty(g.updaters) || any(has_updaters, g.submobjects)
    end
    return g.has_updaters_cache::Bool
end
function refresh_has_updater_status!(g::Group)
    g.has_updaters_cache = nothing
    for p in g.parents
        refresh_has_updater_status!(p)
    end
    return g
end
get_updaters(g::Group) = g.updaters
function update!(g::Group, dt::Real = 0.0; recurse::Bool = true)
    (has_updaters(g) && !g.updating_suspended) || return g
    if recurse
        for sm in g.submobjects
            update!(sm, dt)
        end
    end
    _run_updaters!(g, g.updaters, dt)
    return g
end
function add_updater!(g::Group, f; call::Bool = true, parallel::Bool = false)
    push!(g.updaters, Updater(f; parallel))
    refresh_has_updater_status!(g)
    call && update!(g, 0.0)
    return g
end
add_updater!(f, g::Group; kw...) = add_updater!(g, f; kw...)
remove_updater!(g::Group, f) =
    (filter!(u -> !_is_func(u, f), g.updaters); refresh_has_updater_status!(g); g)
function clear_updaters!(g::Group; recurse::Bool = true)
    for mob in (recurse ? get_family(g) : Mobject[g])
        _clear_own_updaters!(mob)
    end
    refresh_has_updater_status!(g)
    return g
end
has_time_based_updaters(g::Group) = any(get_family(g)) do mob
    u = _updaters(mob)
    u !== nothing && any(x -> x.takes_dt, u)
end

# the per-mobject flags and the opacity reach the members that answer
# (a ValueTracker inside is along for the ride, as for the transforms below)
function set_opacity!(g::Group, op::Real)
    for m in g.submobjects
        _can(set_opacity!, m, op) && set_opacity!(m, op)
    end
    return g
end

"See [`fade!`](@ref). A Group holds no style of its own, so it always reaches its members."
fade!(g::Group, darkness::Real = 0.5) = set_opacity!(g, 1.0 - Float64(darkness))

"See [`set_style!`](@ref) — the members that carry a style get it; the rest are skipped."
function set_style!(g::Group; kw...)
    for m in g.submobjects
        _can(set_style!, m) && set_style!(m; kw...)
    end
    return g
end
function fix_in_frame!(g::Group; value::Bool = true)
    for m in g.submobjects
        applicable(fix_in_frame!, m) && fix_in_frame!(m; value)
    end
    return g
end
function apply_depth_test!(g::Group; value::Bool = true)
    for m in g.submobjects
        applicable(apply_depth_test!, m) && apply_depth_test!(m; value)
    end
    return g
end
function set_shading!(g::Group; kw...)
    for m in g.submobjects
        applicable(set_shading!, m) && set_shading!(m; kw...)
    end
    return g
end

# a `Cube` is a Group of meshes, so the colour verb has to reach them.
# `set_color!` is the one a Surface answers to, and the one GL
# calls on its SGroup cube.
function set_color!(g::Group; color = nothing, opacity = nothing)
    for m in g.submobjects
        _can(set_color!, m) && set_color!(m; color, opacity)
    end
    return g
end

"""
A `Group` has no fill of its own: the members do, and only the ones made of
vector geometry. This forwards to those and REFUSES when none of them has a
fill to set — a `Cube` of meshes lands there, and being told to use
`set_color!` is worth more than a silent no-op.
"""
function set_fill!(g::Group; kw...)
    any = false
    for m in g.submobjects
        if _can(set_fill!, m)
            set_fill!(m; kw...)
            any = true
        end
    end
    any || throw(ArgumentError(
        "no member of this Group has a fill — a mesh (a Surface, and so a " *
        "`Cube`) carries ONE colour. Use `set_color!(g; color, " *
        "opacity)`, or build it with `VCube`/`VPrism` if you need fill and stroke."))
    return g
end

"See [`set_fill!`](@ref) — the stroke half, with the same refusal."
function set_stroke!(g::Group; kw...)
    any = false
    for m in g.submobjects
        if _can(set_stroke!, m)
            set_stroke!(m; kw...)
            any = true
        end
    end
    any || throw(ArgumentError(
        "no member of this Group has a stroke — a mesh (a Surface, and so a " *
        "`Cube`) carries ONE colour. Use `set_color!(g; color, " *
        "opacity)`, or build it with `VCube`/`VPrism` if you need fill and stroke."))
    return g
end

# A Group is as much a collection as a VGroup: same measured CE/GL
# semantics (len/iter = the submobjects), same indexing surface.
Base.length(g::Group) = length(g.submobjects)
Base.iterate(g::Group, state::Int = 1) =
    state > length(g.submobjects) ? nothing : (g.submobjects[state], state + 1)
Base.eltype(::Type{Group}) = Mobject
Base.keys(g::Group) = Base.OneTo(length(g.submobjects))
Base.getindex(g::Group, i::Integer) = g.submobjects[i]
Base.firstindex(::Group) = 1
Base.lastindex(g::Group) = length(g.submobjects)

# ── a Group moves, like manim's ────────────────────────────────────────────
#
# MEASURED, `Group(...).shift(UP).scale(0.5).move_to(ORIGIN)` works in Manim
# CE and in ManimGL, because their `Group` is a `Mobject` subclass and the
# transforms recurse into the submobjects.
#
# Janim's `Group` is also the container that may hold a `ValueTracker` or a
# `CameraFrame`, and "shift a tracker by UP" means nothing. The answer is
# manim's — apply to the members that can be applied to
# — but WITHOUT manim's silence: a member that cannot move is skipped because
# there is no method for it, which `applicable` asks about explicitly instead
# of swallowing an error.

"Members that answer to `f` — the rest are along for the ride, not moved."
_can(f::F, m, args...) where {F} = applicable(f, m, args...)

get_bounding_box(g::Group) = _group_bounding_box(g)

"Does anything in `m`'s family carry points? (The box of a member without any is the origin, not a measurement.)"
_family_has_points(m::Mobject) = any(get_family(m)) do x
    _can(has_points, x) && has_points(x)
end

function _group_bounding_box(g::Group)
    lo = Point3f(Inf32, Inf32, Inf32)
    hi = Point3f(-Inf32, -Inf32, -Inf32)
    seen = false
    for m in g.submobjects
        _can(get_bounding_box, m) || continue
        # a member with no points reports a degenerate box; skipping it keeps
        # an empty label from dragging the group's corner to the origin. (A
        # family always holds the mobject itself, so testing it for emptiness
        # would never skip an empty VGroup.)
        _family_has_points(m) || continue
        bb = get_bounding_box(m)
        lo = Point3f(min.(lo, bb[1]))
        hi = Point3f(max.(hi, bb[3]))
        seen = true
    end
    seen || return Point3f[ORIGIN, ORIGIN, ORIGIN]
    return Point3f[lo, (lo + hi) / 2, hi]
end

get_bounding_box_point(g::Group, direction) =
    _bbox_point(get_bounding_box(g), direction)
get_center(g::Group) = get_bounding_box(g)[2]
get_left(g::Group)   = get_bounding_box_point(g, LEFT)
get_right(g::Group)  = get_bounding_box_point(g, RIGHT)
get_top(g::Group)    = get_bounding_box_point(g, UP)
get_bottom(g::Group) = get_bounding_box_point(g, DOWN)
length_over_dim(g::Group, dim::Int) =
    (bb = get_bounding_box(g); Float64(bb[3][dim] - bb[1][dim]))
get_width(g::Group)  = length_over_dim(g, 1)
get_height(g::Group) = length_over_dim(g, 2)
get_depth(g::Group)  = length_over_dim(g, 3)

# The transforms that need a pivot take the GROUP's pivot and hand it down as
# an explicit `about_point`, or each member would turn about its own centre
# and the group would come apart.
function shift!(g::Group, vector)
    v = Point3f(vector)
    for m in g.submobjects
        _can(shift!, m, v) && shift!(m, v)
    end
    return g
end

function scale!(g::Group, factor; about_point = nothing, about_edge = ORIGIN, kw...)
    p = about_point === nothing ? get_bounding_box_point(g, about_edge) :
        Point3f(about_point)
    for m in g.submobjects
        _can(scale!, m, factor) && scale!(m, factor; about_point = p, kw...)
    end
    return g
end
_side_effect_children(g::Group) = g.submobjects     # a Group inside a VGroup is walked too

function rotate!(g::Group, angle::Real; axis = OUT, about_point = nothing,
                 about_edge = ORIGIN, kw...)
    p = about_point === nothing ? get_bounding_box_point(g, about_edge) :
        Point3f(about_point)
    for m in g.submobjects
        _can(rotate!, m, angle) && rotate!(m, angle; axis, about_point = p, kw...)
    end
    return g
end

function stretch!(g::Group, factor::Real, dim::Int; about_point = nothing,
                  about_edge = ORIGIN)
    p = about_point === nothing ? get_bounding_box_point(g, about_edge) :
        Point3f(about_point)
    for m in g.submobjects
        _can(stretch!, m, factor, dim) && stretch!(m, factor, dim; about_point = p)
    end
    return g
end

flip!(g::Group; axis = UP, about_point = nothing, about_edge = ORIGIN) =
    rotate!(g, PI; axis, about_point, about_edge)

# rescale_to_fit!: the one Mobject method of transforms.jl
set_width!(g::Group, w::Real; kw...)  = rescale_to_fit!(g, w, 1; kw...)
set_height!(g::Group, h::Real; kw...) = rescale_to_fit!(g, h, 2; kw...)
set_depth!(g::Group, d::Real; kw...)  = rescale_to_fit!(g, d, 3; kw...)

# ── and it interpolates, so `animate` and Transform work on it ─────────────
#
# "Method animations" — in Julia, animations of FUNCTIONS:
# `animate(g, (shift!, RIGHT))` copies the group, applies the calls to the
# copy and transforms towards it. That needs the interpolation contract, which
# for a container is the pairwise one: each member against its own.

is_interpolable(::Group) = true

function Base.copy(g::Group)
    c = Group(Mobject[copy(m) for m in g.submobjects])
    c.updaters = copy(g.updaters)       # like a VMobject's copy
    c.updating_suspended = g.updating_suspended
    c.z_index = g.z_index
    return c
end

# A container of N against one of M pads the shorter with invisible
# copies of its members, as GL's align_family does for any Mobject; an EMPTY
# one still refuses — GL pads it with null mobjects that draw nothing, and a
# member that morphs from nothing is what a VGroup already does.
function align_data!(a::Group, b::Group; padding::Symbol = :invisible)
    _check_padding(padding)
    na, nb = length(a.submobjects), length(b.submobjects)
    if na != nb
        (na == 0 || nb == 0) && throw(ArgumentError(
            "cannot align an empty Group with one of $(max(na, nb)) members: " *
            "ManimGL pads it with null mobjects that draw nothing, so there " *
            "is nothing to imitate — hold the members in a VGroup, whose " *
            "padding grows from a point"))
        short = na < nb ? a : b
        _replace_children!(short, _padded_children(short.submobjects, abs(na - nb), padding))
    end
    for (x, y) in zip(a.submobjects, b.submobjects)
        _align_pair!(x, y, padding)
    end
    return a
end
_align_pair!(a::Group, b::Group, padding::Symbol) = align_data!(a, b; padding)

function interpolate!(dst::Group, a::Group, b::Group, alpha::Real)
    for (d, x, y) in zip(dst.submobjects, a.submobjects, b.submobjects)
        interpolate!(d, x, y, alpha)
    end
    return dst
end

function become!(dst::Group, src::Group)
    if length(dst.submobjects) != length(src.submobjects)
        for old in dst.submobjects
            _forget_parent!(old, dst)   # leave the family THROUGH the door
        end
        empty!(dst.submobjects)
        _add_children!(dst, Mobject[copy(m) for m in src.submobjects])
        return dst
    end
    for (d, s) in zip(dst.submobjects, src.submobjects)
        become!(d, s)
    end
    return dst
end

# ═══════════════════════════════════════════════════════════════════════
# always_redraw — the updater that rebuilds and adopts
# ═══════════════════════════════════════════════════════════════════════

"""
    always_redraw(f) → mobject

`f()` builds a mobject from scratch; the result is rebuilt EVERY frame and
adopted by the returned mobject via `become!`.

    vt = ValueTracker(1.0)
    circle = always_redraw(() -> Circle(radius = get_value(vt)))

Why `become!` and not "replace the object": the scene, the compositor and any
group holding it keep the SAME identity across frames — no re-adding, no
dangling references.

This helper is also the right place to enforce the gallery's rule (a mobject
whose points are created by an updater must be born with its final style):
here it is automatic, because each frame's mobject is built by the user's own
`f`, styling included.
"""
function always_redraw(f)
    m = f()
    add_updater!(m, mob -> become!(mob, f()); call = false)
    return m
end

# ═══════════════════════════════════════════════════════════════════════
# DecimalNumber — a number rendered as glyphs, redrawn as it changes
# ═══════════════════════════════════════════════════════════════════════

"""
    DecimalNumber(value; num_decimal_places=2, size=1.0, color=WHITE,
                  include_sign=false, unit=nothing)

The number as a text mobject, built with the same pipeline as `TextMobject`.

    counter = DecimalNumber(0.0; num_decimal_places = 1)
    add_updater!(counter, m -> set_number!(m, get_value(vt)))

`set_number!` rebuilds the glyphs and keeps the LEFT edge where it was, so a
counter running 9.9 → 10.0 grows to the right instead of pushing its own
digits outwards. That is ManimGL's `edge_to_fix = LEFT` (`numbers.py:51`),
the default here: a number that keeps growing — a counter, a running total —
reads as one that gains digits, not as one that slides. Pass
`edge_to_fix = ORIGIN` for re-centring (CE's, and the right choice for a number centred under something), or `RIGHT` for a
countdown that grows leftwards.

`unit` follows ManimGL's rule (`numbers.py:25-31`): plain text (`" m"`,
`"%"`) is written with the digits, in their face; a unit with a `\\`, or one
that starts with `^`, is a formula, typeset by [`Tex`](@ref) (`via = :math`)
at the number's font size and set right after the last digit, bottom to
bottom — a `^…` superscript top to top with the digits instead:

    DecimalNumber(90.0; unit = raw"^\\circ")   # 90.00°, the ring at the top
    DecimalNumber(1.0; unit = raw"\\pi")       # 1.00π, on the line
"""
mutable struct DecimalNumber <: Mobject
    group::VMobject                 # the glyphs (a VGroup)
    value::Float64
    num_decimal_places::Int
    size::Float64
    color::Any
    include_sign::Bool
    unit::Union{Nothing,String}
    edge_to_fix::Point3f            # which edge survives a rebuild (GL numbers.py:51)
    integer::Bool                   # reads back as an Int (GL's `Integer`)
    parents::Vector{Mobject}        # the node contract (the glyphs live in `group`)
end
# the old-arity constructor links the number as the parent of its glyphs
# (wrappers.jl), so an invalidation climbs group → number → the real parent
DecimalNumber(g::VMobject, value, places, size, color, include_sign, unit,
              edge_to_fix = LEFT, integer::Bool = false) =
    _link_wrapper!(DecimalNumber(g, Float64(value), Int(places), Float64(size),
                                 color, Bool(include_sign), unit,
                                 Point3f(edge_to_fix), integer, Mobject[]))

function _decimal_string(x::Real, places::Int, include_sign::Bool,
                         unit::Union{Nothing,String})
    # `@sprintf("%.*f")` and not `round` + zero padding. `round(1.7e-9;
    # digits=9)` stringifies as "2.0e-9", and padding that to nine decimals
    # gives «2.0e-900000» — the exponent eats the padding.
    # Fixed-point formatting has no exponent to corrupt, keeps the width
    # stable by construction, and is exact for integers and any value inside
    # the plain-decimal range. Zero places go through `_whole` (an Int, or a
    # BigInt past Int64); NaN and ±Inf are spelled like GL's Python `format`.
    s = places <= 0 ? string(_whole(x)) :
        isfinite(x) ? Printf.format(Printf.Format("%.$(places)f"), Float64(x)) :
        isnan(x) ? "nan" : x > 0 ? "inf" : "-inf"
    # GL's rule (numbers.py:139-144): a value whose rounded
    # digits are all zero shows no minus sign — "-0.00" reads "0.00" and,
    # with the sign, "+0.00" (never "+-0.00"). Decided on the STRING, which
    # is what the reader sees; `-0.5` at zero places is "0" too.
    if startswith(s, '-') && all(c -> c == '0' || c == '.', SubString(s, 2))
        s = String(SubString(s, 2))
    end
    include_sign && !startswith(s, '-') && (s = "+" * s)
    # a Tex unit is glyphs of its own (`_decimal_glyphs`)
    unit === nothing || _tex_unit(unit) || (s = s * unit)
    return s
end

"""
A whole number the way GL's `int(number)` reads it: an `Int`
while it fits one, a `BigInt` past ±9.0e18 (`round(Int, 1e19)` threw an
InexactError). NaN and ±Inf still refuse, as `int(nan)` does in GL.
"""
_whole(x::Real) = abs(x) < 9.0e18 ? round(Int, x) : BigInt(round(x))

"A unit GL typesets with Tex (`numbers.py:25-31`): one with a `\\`, or a superscript."
_tex_unit(unit) = unit !== nothing && (occursin('\\', unit) || startswith(unit, '^'))

"""
    _decimal_glyphs(txt, unit, size, color) → VMobject

The glyphs of a number: `txt` through `TextMobject`, and a Tex unit (see
`_tex_unit`) as glyphs of its own, appended flat to the digits' group. GL's placement (`numbers.py:107-118`): right after the
last digit, bottom to bottom, and a `^…` unit then lifted to the digits'
top, GL's `digit_buff` (0.001 × font_size) before it; the whole number
centred, unit included, as GL's `arrange` leaves it.
A plain unit is already in `txt`, and nothing else happens to it.
"""
function _decimal_glyphs(txt::AbstractString, unit, size::Real, color)
    g = TextMobject(txt; size, color)
    _tex_unit(unit) || return g
    sup = startswith(unit, '^')
    # GL's `Tex(unit)` at the number's font_size: `size` is TextMobject's
    # unit, so it goes back through the two calibrations
    u = Tex(
        sup ? "{}" * unit : unit;
        via = :math,
        size = size * _GL_SIZE.text / _GL_SIZE.math,
        color,
    )
    # GL arranges digits and unit with `digit_buff_per_font_unit = 0.001` of
    # its font_size between INK boxes (numbers.py:107-113); the digits here
    # keep FreeType's advances, and the unit — a box of its own — takes GL's
    # gap, so the ring of «90.00°» does not touch the last zero
    buff = 0.001 * size * DEFAULT_FONT_SIZE * _GL_SIZE.text
    next_to!(u, g.submobjects[end], RIGHT; buff, aligned_edge = DOWN)
    sup && align_to!(u, g, UP)
    glyphs = copy(u.submobjects)
    remove!(u, glyphs...)
    add!(g, glyphs...)
    move_to!(g, ORIGIN)
    return g
end

function DecimalNumber(value::Real = 0.0; num_decimal_places::Int = 2,
                       size = nothing, font_size = nothing, color = WHITE,
                       include_sign::Bool = false,
                       unit::Union{Nothing,String} = nothing,
                       edge_to_fix = LEFT, integer::Bool = false)
    # It draws with TextMobject, so it takes TextMobject's
    # calibration — resolved HERE and stored, because `set_number!` rebuilds
    # the glyphs from `d.size` on every digit change.
    size = _text_size(size, font_size, _GL_SIZE.text, "DecimalNumber")
    txt = _decimal_string(value, num_decimal_places, include_sign, unit)
    g = _decimal_glyphs(txt, unit, size, color)
    return DecimalNumber(g, Float64(value), num_decimal_places, Float64(size),
                         color, include_sign, unit, edge_to_fix, integer)
end

"""
    IntegerMobject(n = 0; size, color, include_sign, unit, edge_to_fix)

A whole number on screen — ManimGL's `Integer` (`numbers.py:229`), which is a
[`DecimalNumber`](@ref) with no decimal places whose [`get_value`](@ref) reads
back an `Int`:

```julia
counter = IntegerMobject(0)
add_updater!(counter, m -> set_value!(m, floor(Int, 10 * get_value(clock))))
get_value(counter) isa Int      # true — not 7.0
```

**Why the name is not `Integer`.** `Base.Integer` is the abstract type
every whole number in Julia is one of, and exporting a second `Integer` from
`Janim` would make the bare name ambiguous for everyone doing `using Janim` —
`x::Integer` in their own code would stop compiling. Same reason `Text` is
[`TextMobject`](@ref) and `Matrix` is [`MatrixMobject`](@ref).

Like [`UnitInterval`](@ref), it is a CONSTRUCTOR, not a type: what it returns
is a `DecimalNumber`, so it transforms, interpolates and animates with exactly
the same methods. Rounding is Julia's `round`, which breaks ties to even —
`numpy.round`'s rule, so `IntegerMobject(2.5)` reads 2 in both engines. Past
±9.0e18, where an `Int` no longer holds it, it reads back a `BigInt`.
"""
IntegerMobject(n::Real = 0; num_decimal_places::Int = 0, kw...) =
    DecimalNumber(n; num_decimal_places, integer = true, kw...)

"""
    get_value(d) → Float64, or Int for an [`IntegerMobject`](@ref)

The number a [`DecimalNumber`](@ref) is showing. An `IntegerMobject` reads
back an `Int` while it fits one and a `BigInt` beyond ±9.0e18 — GL's `int`
has no ceiling, whereas `round(Int, 1e19)` would throw.
"""
get_value(d::DecimalNumber) = d.integer ? _whole(d.value) : d.value

"Rebuild the glyphs for a new value, keeping `edge_to_fix` where it was."
function set_number!(d::DecimalNumber, x::Real)
    old = d.group
    # GL numbers.py:208-211: read the edge BEFORE the rebuild and put the
    # fresh glyphs back on it. With `edge_to_fix = ORIGIN` this is a plain
    # re-centring, since the bounding-box point of ORIGIN IS the centre.
    anchor = has_points(old) || !isempty(old.submobjects) ?
             get_bounding_box_point(old, d.edge_to_fix) : ORIGIN
    # the style survives the rebuild (numbers.py:207-215: GL saves the first
    # glyph's style and re-applies it, then copies its uniforms down): a
    # number set to opacity 0 stays at 0 when an updater changes a digit
    ref = _first_with_points(old)
    txt = _decimal_string(x, d.num_decimal_places, d.include_sign, d.unit)
    fresh = _decimal_glyphs(txt, d.unit, d.size, d.color) 
    ref === nothing || match_style!(fresh, ref)
    move_to!(fresh, anchor; aligned_edge = d.edge_to_fix)
    # the group's OWN keys say what the number is (a table's "(i,j)"), not
    # what it reads: `become!` carries the fresh group's keys, none, so they
    # are set again or a counter in a table would stop being its cell
    isempty(old.keys) || set_key!(fresh, old.keys...)
    become!(old, fresh)
    for sub in get_family(old)
        sub isa VMobject || continue
        sub.fixed_in_frame = old.fixed_in_frame
        sub.depth_test = old.depth_test
    end
    d.value = Float64(x)
    return d
end

"The first family member with points — where GL reads the style to keep."
function _first_with_points(m::VMobject)
    for sub in get_family(m)
        sub isa VMobject && has_points(sub) && return sub
    end
    return nothing
end

"""
    set_value!(d, x) · increment_value!(d, dx)

The [`ValueTracker`](@ref) verbs on a [`DecimalNumber`](@ref) — the same
names ManimGL uses for both, so `animate(d, (set_value!, 5.0))` reads the same
whichever holds the number. `set_value!` IS [`set_number!`](@ref).
"""
set_value!(d::DecimalNumber, x::Real) = set_number!(d, x)
increment_value!(d::DecimalNumber, dx::Real) = set_number!(d, d.value + dx)

# A DecimalNumber IS its glyphs as far as the scene and the renderer are
# concerned: the family, the updaters, the box and the transforms are the
# group's — delegated ONCE for every wrapped type in wrappers.jl.
# What is the number's own is the interpolation contract: the glyphs morph
# and the value lerps, so `animate(d, (set_number!, 15.0))` is
# ChangeDecimalToValue.
is_interpolable(::DecimalNumber) = true
function Base.copy(d::DecimalNumber)
    c = DecimalNumber(copy(d.group), d.value, d.num_decimal_places, d.size, d.color,
                      d.include_sign, d.unit, d.edge_to_fix, d.integer)
    # the group's copy carries the updaters, and a wrapper's updater closes over the WRAPPER: re-aimed at the copy, or
    # `update!(copy)` keeps changing the original's value
    _rebind_wrapper_calls!(c.group, d, c)
    return c
end
align_data!(a::DecimalNumber, b::DecimalNumber) = (align_data!(a.group, b.group); a)
_align_pair!(a::DecimalNumber, b::DecimalNumber, padding::Symbol) =
    (align_data!(a.group, b.group; padding); a)
function interpolate!(dst::DecimalNumber, a::DecimalNumber, b::DecimalNumber, α::Real)
    interpolate!(dst.group, a.group, b.group, α)
    dst.value = a.value + Float64(α) * (b.value - a.value)
    dst.size = a.size + Float64(α) * (b.size - a.size)     # GL's DecimalNumber.interpolate
    return dst
end
# A number morphs into any VMobject and back (GL numbers.py:
# 151-160 guards `font_size` with `hasattr`): the glyph group is what aligns
# and travels — it is the first member of the number's family, so the pair
# of groups does the moving — and `value`/`size` only travel between numbers.
align_data!(a::DecimalNumber, b::VMobject) = (align_data!(a.group, b); a)
align_data!(a::VMobject, b::DecimalNumber) = (align_data!(a, b.group); a)
_align_pair!(a::DecimalNumber, b::VMobject, padding::Symbol) =
    (align_data!(a.group, b; padding); a)
_align_pair!(a::VMobject, b::DecimalNumber, padding::Symbol) =
    (align_data!(a, b.group; padding); a)
interpolate!(dst::DecimalNumber, ::DecimalNumber, ::VMobject, ::Real) = dst
# GL's `font_size` semantics (numbers.py; mobject.py:949-977):
# a scale moves the glyphs AND the size the next rebuild draws at, by the
# same clamped, f32-rounded factor that moved the points — a number scaled
# ×1.7 and then set to another value stays ×1.7, by every route (direct,
# VGroup, Group, animate). `stretch!` and a vector scale leave `size` alone, as GL does.
function scale!(d::DecimalNumber, factor::Real; min_scale_factor::Real = 1e-8, kw...)
    scale!(d.group, factor; min_scale_factor, kw...)
    d.size *= Float64(Float32(max(factor, min_scale_factor)))
    return d
end
_scale_side_effects!(d::DecimalNumber, s::Float64) = (d.size *= s; nothing)
function become!(dst::DecimalNumber, src::DecimalNumber)
    become!(dst.group, src.group)
    dst.value = src.value
    dst.num_decimal_places = src.num_decimal_places
    dst.size = src.size
    dst.color = src.color
    dst.include_sign = src.include_sign
    dst.unit = src.unit
    dst.edge_to_fix = src.edge_to_fix
    dst.integer = src.integer          # how it reads back travels too
    return dst
end

# ═══════════════════════════════════════════════════════════════════════
# TracedPath — the trail of a moving point
# ═══════════════════════════════════════════════════════════════════════
#
# Drawing an orbit or a pendulum needs this trail. Here it is as a mobject: an updater that
# samples a point each frame and re-draws the polyline it has seen.
#
# It is ALSO the canonical example of the updater rule from the gallery: a
# mobject whose points are created inside an updater must be born with its
# final style, because new points re-stamp the factory style. Being born from
# `vmob(...)` with the stroke already set is what guarantees it here — the
# user never has to know the rule.

"""
    TracedPath(point_func; stroke_color=WHITE, stroke_width=2, time_traced=Inf,
               smooth=false)

The trail of a moving point. `point_func()` is sampled once per frame (a
`Dot`'s centre, an integrator's state, anything); with `time_traced` the trail
only keeps the last seconds and the tail dissolves behind the head.

    dot = Dot(); add!(scene, dot, TracedPath(() -> get_center(dot)))

**Add it AFTER whatever it follows.** `add!` fixes the update order as well as
the draw order, so a trail added first samples the PREVIOUS frame's position
and sits exactly one frame behind — 0.618 scene units for a point crossing a
circle of radius 2 at 20 fps, which is plainly visible. The same trap exists in
ManimCE and ManimGL.

To draw the trail UNDERNEATH what it follows, use `set_z_index!(trail, -1)`,
which changes the drawing and not the updater order. `bring_to_back!` would
also put it behind — and would silently bring the one-frame lag back with it,
because it moves the mobject to the front of the scene's list.

`smooth=true` rounds the trail with `make_smooth!` instead of leaving it
a polyline. It costs one pass over the samples per frame and moves no anchor —
the curve still goes through every point the object visited. Worth it when the
sampling is coarse relative to the curvature, which is exactly the case for a
fast orbit or a chaotic pendulum at 30 fps.
"""
const TracedPath = VMobject{:TracedPath}
function (::Type{TracedPath})(point_func; stroke_color = WHITE,
                              stroke_width::Real = 2.0, stroke_opacity::Real = 1.0,
                              time_traced::Real = Inf, smooth::Bool = false, kw...)
    m = vmob(:TracedPath; stroke_color, stroke_width, stroke_opacity, kw...)
    set_fill!(m; opacity = 0)
    seen = Point3f[]
    add_updater!(m, function (mob, dt)
        dt == 0 && return mob          # the registration call traces nothing
        push!(seen, Point3f(point_func()))
        pts = seen
        if isfinite(time_traced)
            n_rel = max(2, round(Int, time_traced / dt))
            if length(seen) > n_rel
                length(seen) > 10n_rel && deleteat!(seen, 1:length(seen)-n_rel)
                pts = @view seen[max(1, end - n_rel + 1):end]
            end
        end
        if length(pts) >= 2
            set_points_as_corners!(mob, pts)
            # rounding happens AFTER the corners are set, on the same
            # anchors — the trail never invents a point the object did not
            # visit, it only changes how the visits are joined up.
            smooth && make_smooth!(mob)
        else
            set_points!(mob, (pts[1], pts[1], pts[1]))
        end
        return mob
    end)
    return m
end

# ═══════════════════════════════════════════════════════════════════════
# Two verbs over the children, written once Group exists
# ═══════════════════════════════════════════════════════════════════════

"""
    add_to_back!(parent, mobs...)

Add `mobs` as the FIRST children of `parent`, in the order given, so they draw
underneath the rest (GL's `add_to_back`, mobject.py:491). One that is already
a child stays where it is — GL merges the two lists keeping the LAST
occurrence (`list_update`), measured: `add_to_back(b)` on `[a, b]` leaves
`[a, b]`. To move an existing child underneath, [`bring_to_back!`](@ref).
"""
function add_to_back!(parent::Union{VMobject,Group}, mobs::Mobject...)
    fresh = Mobject[]
    for m in mobs
        any(x -> x === m, parent.submobjects) && continue
        any(x -> x === m, fresh) && continue
        push!(fresh, m)
    end
    isempty(fresh) && return parent
    add!(parent, fresh...)
    for m in Iterators.reverse(fresh)
        bring_to_back!(parent, m)
    end
    return parent
end

"""
    space_out_submobjects!(m, factor = 1.5; about_point = nothing, about_edge = ORIGIN)

Push the children apart without growing them (GL's `space_out_submobjects`,
mobject.py:1265): the whole is scaled by `factor` — about its centre, or as
`about_point`/`about_edge` say, the way [`scale!`](@ref) takes them — and
each child is then scaled back by `1/factor` about its own centre.
"""
function space_out_submobjects!(m::Union{VMobject,Group}, factor::Real = 1.5; kw...)
    scale!(m, factor; kw...)
    for sub in m.submobjects
        scale!(sub, 1 / factor)
    end
    return m
end
