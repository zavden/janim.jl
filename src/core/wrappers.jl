# core/wrappers.jl — the mobjects that WRAP a group of vector geometry.
#
# Five types are not VMobjects and yet are made of them: the coordinate
# objects (a `NumberLine` IS a group plus a map read off it), `DecimalNumber`
# (a group of glyphs plus a value), `VectorField` (one batched VMobject),
# `StreamLines` and `AnimatedStreamLines`. They share ONE set of delegating
# methods over a Union, never five copies, because `rotate!` is a keyword
# function and five more keyword methods would push `rotate!(circle, θ)` from 0
# to 272 bytes of allocation.
#
# The shape of the delegation: the wrapper is the NODE (it has `parents`, it
# is what a parent lists in `submobjects`); the group it wraps holds the
# geometry, the updaters and the z-index. `get_family(wrapper)` is the
# group's family — the wrapper itself never appears in a family, so the
# renderer, `Transform` and the key machinery only ever meet VMobjects. The
# group names the wrapper as ITS parent (`_link_wrapper!`, called by the
# wrapper constructors), which is what lets an invalidation climb
# group → wrapper → the real parent. The generic `note_changed_family!`,
# `refresh_bounding_box!`, `refresh_has_updater_status!` and
# `_note_changed_order!` of a node without caches do exactly that climb.

const _Wrapper = Union{CoordinateObject,DecimalNumber,VectorField,StreamLines,
                       AnimatedStreamLines}

"The mobject a wrapper is made of."
_inner(m::CoordinateObject) = m.group
_inner(d::DecimalNumber) = d.group
_inner(v::VectorField) = v.mob
_inner(s::StreamLines) = s.group
_inner(a::AnimatedStreamLines) = a.group

"Register `w` as a parent of the group it wraps, so invalidations climb through it."
function _link_wrapper!(w::_Wrapper)
    ps = _inner(w).parents
    any(x -> x === w, ps) || push!(ps, w)
    return w
end

# A scale's side effects walk INTO a wrapper (a NumberLine's
# labels, a DecimalNumber's glyphs), the way they walk into any node
_side_effect_children(w::_Wrapper) = _inner(w).submobjects

"""
GL's copy carries its updaters (`list(self.updaters)`,
mobject.py:693) and so does ours — but a wrapper's updater is a
`_WrapperCall` closing over the WRAPPER, so a copied group's calls would still
point at the original: `update!(copy)` would change the ORIGINAL's value.
After copying the group, every call aimed at `old` is re-aimed at `new`.
"""
function _rebind_wrapper_calls!(g::VMobject, old, new)
    us = g.updaters
    for i in eachindex(us)
        f = us[i].func
        (f isa _WrapperCall && f.w === old) || continue
        us[i] = Updater(_WrapperCall(new, f.f, f.takes_dt), us[i].takes_dt, us[i].parallel)
    end
    return g
end

# ── the family and the tree ─────────────────────────────────────────────────
get_family(w::_Wrapper) = get_family(_inner(w))
_draw_family(w::_Wrapper) = _draw_family(_inner(w))
add!(w::_Wrapper, mobs::Mobject...) = (add!(_inner(w), mobs...); w)   # GL's axes.add(graph)
remove!(w::_Wrapper, mobs::Mobject...) = (remove!(_inner(w), mobs...); w)
has_points(w::_Wrapper) = has_points(_inner(w))
get_num_points(w::_Wrapper) = get_num_points(_inner(w))

# ── updaters: they live in the group, the function receives the WRAPPER ────
has_updaters(w::_Wrapper) = has_updaters(_inner(w))
get_updaters(w::_Wrapper) = get_updaters(_inner(w))
has_time_based_updaters(w::_Wrapper) = has_time_based_updaters(_inner(w))
update!(w::_Wrapper, dt::Real = 0.0; recurse::Bool = true) =
    (update!(_inner(w), dt; recurse); w)
function add_updater!(w::_Wrapper, f; call::Bool = true, parallel::Bool = false)
    u = Updater(f; parallel)              # the arity of `f`, detected once
    add_updater!(_inner(w), _WrapperCall(w, f, u.takes_dt); call, parallel)
    return w
end
add_updater!(f, w::_Wrapper; kw...) = add_updater!(w, f; kw...)   # do-block form
remove_updater!(w::_Wrapper, f) = (remove_updater!(_inner(w), f); w)
clear_updaters!(w::_Wrapper; recurse::Bool = true) = (clear_updaters!(_inner(w); recurse); w)
suspend_updating!(w::_Wrapper; recurse::Bool = true) = (suspend_updating!(_inner(w); recurse); w)
resume_updating!(w::_Wrapper; recurse::Bool = true, call_updater::Bool = true) =
    (resume_updating!(_inner(w); recurse, call_updater); w)

# ── the box and the transforms ─────────────────────────────────────────────
# (for a coordinate object this is what makes the derived map follow the
# object: they move the very geometry the map is READ FROM)
get_bounding_box(w::_Wrapper) = get_bounding_box(_inner(w))
get_bounding_box_point(w::_Wrapper, direction) = get_bounding_box_point(_inner(w), direction)
apply_points_function!(f, w::_Wrapper; kw...) = (apply_points_function!(f, _inner(w); kw...); w)
shift!(w::_Wrapper, d) = (shift!(_inner(w), d); w)
scale!(w::_Wrapper, f::Real; kw...) = (scale!(_inner(w), f; kw...); w)
rotate!(w::_Wrapper, θ::Real; kw...) = (rotate!(_inner(w), θ; kw...); w)
move_to!(w::_Wrapper, p; kw...) = (move_to!(_inner(w), p; kw...); w)
stretch!(w::_Wrapper, f::Real, dim::Int; kw...) = (stretch!(_inner(w), f, dim; kw...); w)
get_center(w::_Wrapper) = get_center(_inner(w))
get_left(w::_Wrapper)   = get_left(_inner(w))
get_right(w::_Wrapper)  = get_right(_inner(w))
get_top(w::_Wrapper)    = get_top(_inner(w))
get_bottom(w::_Wrapper) = get_bottom(_inner(w))
length_over_dim(w::_Wrapper, dim::Int) = length_over_dim(_inner(w), dim)
get_width(w::_Wrapper)  = get_width(_inner(w))
get_height(w::_Wrapper) = get_height(_inner(w))
get_depth(w::_Wrapper)  = get_depth(_inner(w))

# The size verbs GL defines on every Mobject. They go through
# `rescale_to_fit!` on the WRAPPER, not on its group, so a uniform resize ends
# in the wrapper's own `scale!(w, ::Real)` — where a DecimalNumber keeps its
# `size` in step (GL: rescale_to_fit → scale → font_size) — and a
# stretch ends in `stretch!`, which leaves it alone.
set_width!(w::_Wrapper, x::Real; stretch::Bool = false, kw...) =
    rescale_to_fit!(w, x, 1; stretch, kw...)
set_height!(w::_Wrapper, x::Real; stretch::Bool = false, kw...) =
    rescale_to_fit!(w, x, 2; stretch, kw...)
set_depth!(w::_Wrapper, x::Real; stretch::Bool = false, kw...) =
    rescale_to_fit!(w, x, 3; stretch, kw...)
stretch_to_fit_width!(w::_Wrapper, x::Real; kw...) =
    rescale_to_fit!(w, x, 1; stretch = true, kw...)
stretch_to_fit_height!(w::_Wrapper, x::Real; kw...) =
    rescale_to_fit!(w, x, 2; stretch = true, kw...)
stretch_to_fit_depth!(w::_Wrapper, x::Real; kw...) =
    rescale_to_fit!(w, x, 3; stretch = true, kw...)

# A vector factor is a stretch: the points move and `size`, one number, stays
# (GL multiplies its font_size by the vector here, numbers.py:217-219 — a
# deliberate divergence)
scale!(w::_Wrapper, f::Union{AbstractVector,Tuple}; kw...) = (scale!(_inner(w), f; kw...); w)
flip!(w::_Wrapper; axis = UP, kw...) = (flip!(_inner(w); axis, kw...); w)

# layout.jl's `replace!`/`surround!` run on the WRAPPER, not
# delegated to the group: their uniform rescale must reach `scale!(w, ::Real)`
# for `size` to follow, exactly as `set_width!` above
function Base.replace!(
    w::_Wrapper,
    other::VMobject;
    dim_to_match::Int = 1,
    stretch::Bool = false,
)
    if !has_points(other) && isempty(other.submobjects)
        return scale!(w, 0)
    end
    if stretch
        for i in 1:3
            rescale_to_fit!(w, length_over_dim(other, i), i; stretch = true)
        end
    else
        rescale_to_fit!(
            w,
            length_over_dim(other, dim_to_match),
            dim_to_match;
            stretch = false,
        )
    end
    return shift!(w, get_center(other) - get_center(w))
end

function surround!(
    w::_Wrapper,
    other::VMobject;
    dim_to_match::Int = 1,
    stretch::Bool = false,
    buff::Real = MED_SMALL_BUFF,
)
    replace!(w, other; dim_to_match, stretch)
    len = length_over_dim(other, dim_to_match)
    len == 0 && return w
    return scale!(w, (len + buff) / len)
end

# ── style and the per-mobject flags ────────────────────────────────────────
set_color!(w::_Wrapper; kw...) = (set_color!(_inner(w); kw...); w)
set_stroke!(w::_Wrapper; kw...) = (set_stroke!(_inner(w); kw...); w)
set_fill!(w::_Wrapper; kw...) = (set_fill!(_inner(w); kw...); w)
set_opacity!(w::_Wrapper, op::Real; kw...) = (set_opacity!(_inner(w), op; kw...); w)
fade!(w::_Wrapper, darkness::Real = 0.5; kw...) = (fade!(_inner(w), darkness; kw...); w)
set_style!(w::_Wrapper; kw...) = (set_style!(_inner(w); kw...); w)
get_opacity(w::_Wrapper) = get_opacity(_inner(w))
fix_in_frame!(w::_Wrapper; kw...) = (fix_in_frame!(_inner(w); kw...); w)
apply_depth_test!(w::_Wrapper; kw...) = (apply_depth_test!(_inner(w); kw...); w)
set_shading!(w::_Wrapper; kw...) = (set_shading!(_inner(w); kw...); w)

# ── draw order ──────────────────────────────────────────────────────────────
get_z_index(w::_Wrapper) = get_z_index(_inner(w))
_set_z!(w::_Wrapper, z::Float64) = _set_z!(_inner(w), z)
set_z_index!(w::_Wrapper, z::Real; recurse::Bool = true) =
    (set_z_index!(_inner(w), z; recurse); w)

# ── keys ────────────────────────────────────────────────────────────────────
# A wrapper is keyed through its group, the member of its family
# that `find_by_key` meets (`get_cell` climbs from there back to the wrapper)
set_key!(w::_Wrapper, keys::AbstractString...) = (set_key!(_inner(w), keys...); w)
add_key!(w::_Wrapper, key::AbstractString) = (add_key!(_inner(w), key); w)
get_keys(w::_Wrapper) = get_keys(_inner(w))         # so `has_key(cell, "(1,2)")` answers

# ══════════════════════════════════════════════════════════════════════════
# A stage's list with ManimGL's `remove` semantics (scene.py:374-386,
# recursive_mobject_remove): removing a mobject removes its whole family from
# the roots, and a root that CONTAINED it is replaced, in its place, by its
# remaining children — ungrouped, recursively. Shared by Scene, Timeline and
# the compositor's layers.
# ══════════════════════════════════════════════════════════════════════════

"The children a root exposes to the stage: its submobjects, or the wrapped group's."
_stage_children(m::Mobject) =
    hasfield(typeof(m), :submobjects) ? (getfield(m, :submobjects)::Vector{Mobject}) : Mobject[]
_stage_children(w::_Wrapper) = _inner(w).submobjects

"Every mobject in `mobs` and their families, keyed by identity (looked up, never iterated)."
function _family_set(mobs)
    gone = IdDict{Mobject,Nothing}()
    for m in mobs
        gone[m] = nothing
        for x in get_family(m)
            gone[x] = nothing
        end
    end
    return gone
end

"GL's `recursive_mobject_remove`: the list without `gone`, and whether anything left."
function _without(list::Vector{Mobject}, gone::IdDict{Mobject,Nothing})
    out = Mobject[]
    found = false
    for m in list
        if haskey(gone, m)
            found = true
        elseif any(x -> x !== m && haskey(gone, x), get_family(m))
            sub, _ = _without(_stage_children(m), gone)
            append!(out, sub)
            found = true
        else
            push!(out, m)
        end
    end
    # A root is never listed twice. Ungrouping puts a container's remaining
    # children among the roots, and one of them may already BE a root
    # (`add!(scene, c; recurse = false)`): `[g, c]` minus `d` would come back
    # as `[c, c]`, drawn twice and updated twice per frame. First occurrence
    # wins, by identity. GL never reaches this shape because its `add`
    # removes first.
    found && _unique_by_identity!(out)
    return out, found
end

"Keep the first occurrence of each mobject, by identity, in order."
function _unique_by_identity!(list::Vector{Mobject})
    seen = IdDict{Mobject,Nothing}()
    return filter!(list) do m
        haskey(seen, m) && return false
        seen[m] = nothing
        return true
    end
end

"Apply `_without` to a stage's list IN PLACE; true when something left."
function _remove_from_list!(list::Vector{Mobject}, gone::IdDict{Mobject,Nothing})
    out, found = _without(list, gone)
    if found
        empty!(list)
        append!(list, out)
    end
    return found
end

"""
    _add_animated!(stage, mobs)

ManimGL's `begin_animations` guard (`scene.py:545-556`): an animated mobject
joins the stage only when it is NOWHERE on it yet — the test is against
`get_mobject_family_members()`, every root AND everything inside them, not
just the roots.

Without the guard `play!` would register every animated leaf as a root, so
animating a CHILD of something already on stage would draw that child twice:
once inside its parent and once as a root of its own (measured on a red
square at α ½ — `[190, 74, 64]` against `[127, 49, 43]`). With it, the child is left where it lives and the list is
not restructured at all. The restructuring `add!` does is for the other case,
the one GL's comment describes: a mobject arriving from outside whose family
overlaps something on screen.
"""
function _add_animated!(stage, mobs)
    # `_see!` and not `get_family` alone: GL's `get_family` always contains
    # the mobject itself, and Janim's does NOT for the five WRAPPED types
    # (a NumberPlane is not in its own family, only its group's is).
    # Seeding from the family alone would leave every wrapper root looking
    # absent, so `play!` would re-add it and `add!` would move it to the top.
    seen = IdDict{Mobject,Nothing}()
    _see!(d, m) = (d[m] = nothing; for x in get_family(m); d[x] = nothing; end; d)
    for r in _stage_list(stage)
        _see!(seen, r)
    end
    # One `add!` per BATCH of disjoint families, not one per leaf (a
    # LaggedStartMap over 3000 leaves would otherwise cost 593 ms, ×32 the 500
    # case: every add! walks the whole list again). Disjoint additions commute
    # with the removal of their families, so `add!(stage, a, b)` is
    # `add!(a); add!(b)`; an overlap (a leaf whose family touches a pending
    # one) flushes the batch first, which keeps the sequential order, the
    # promotion and the flattening exactly as they would be one by one.
    pending = Mobject[]
    pending_family = IdDict{Mobject,Nothing}()
    for m in mobs
        haskey(seen, m) && continue
        if haskey(pending_family, m) || any(x -> haskey(pending_family, x), get_family(m))
            add!(stage, pending...)
            empty!(pending); empty!(pending_family)
        end
        push!(pending, m)
        _see!(pending_family, m)
        _see!(seen, m)
    end
    isempty(pending) || add!(stage, pending...)
    return stage
end

"""
    _add_gl!(list, mobs)

ManimGL's `Scene.add` (`scene.py:331-337`), the list half: `remove` first, so
the family of what is arriving leaves the roots — a container that held part
of it is replaced in place by its remaining children — and then append, which
puts it on top. Shared by `Scene` and `Timeline`; the compositor's layers are
NOT touched, because under a composition the roots are only what `play!`
registers and the drawing lives in the layers.
"""
function _add_gl!(list::Vector{Mobject}, mobs)
    _remove_from_list!(list, _family_set(mobs))
    listed = IdDict{Mobject,Nothing}(m => nothing for m in list)   # O(1), not a scan per push
    for m in mobs                      # by identity: GL appends the tuple as
        haskey(listed, m) && continue  # given, we refuse to draw one twice
        push!(list, m)
        listed[m] = nothing
    end
    return list
end

"""
    _prepend_gl!(list, mobs)

ManimGL's `Scene.bring_to_back` (`scene.py:397-400`), the list half: `remove`
first — the family of what arrives leaves the roots, and a container that
held part of it is replaced in place by its remaining children — and then
PREPEND, in the order given, which puts it underneath everything. The mirror
of `_add_gl!`, and under the same rule: the compositor's layers are not
touched, because a full `remove!` would take a layered mobject out of the
layer that draws it, and under a composition the roots are not drawn.
"""
function _prepend_gl!(list::Vector{Mobject}, mobs)
    _remove_from_list!(list, _family_set(mobs))
    front = Mobject[]
    fronted = IdDict{Mobject,Nothing}()
    for m in mobs                      # by identity, as `_add_gl!`: GL prepends
        haskey(fronted, m) && continue # the tuple as given
        push!(front, m)
        fronted[m] = nothing
    end
    prepend!(list, front)
    return list
end

"Swap `old` for `new` in place; false when `old` is not a member."
function _replace_in_list!(list::Vector{Mobject}, old::Mobject, new::Mobject)
    i = findfirst(x -> x === old, list)
    i === nothing && return false
    list[i] = new
    return true
end
