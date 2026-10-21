# Aligning and interpolating VMobjects — the point surgery that makes
# Transform possible. Port of vectorized_mobject.py:960-1105 and bezier.py.
#
# The idea: to interpolate two paths they must be given the
# SAME number of points by inserting curves that do not change the shape
# (splitting a quadratic in two with partial De Casteljau leaves the stroke
# identical).

const _POINT_ATOL = 1.0f-8    # GL's tolerance_for_point_equality

"""
    integer_interpolate(start, stop, α) → (integer, residue)

E.g. (0, 10, 0.46) → (4, 0.6): position α between start and stop as an integer
index plus the proportion towards the next one (bezier.py).
"""
function integer_interpolate(start::Int, stop::Int, alpha::Real)
    alpha >= 1 && return (stop - 1, 1.0)
    alpha <= 0 && return (start, 0.0)
    value = Int(floor((1 - alpha) * start + alpha * stop))
    residue = ((stop - start) * alpha) % 1
    return (value, residue)
end

"""
    partial_bezier(p0, p1, p2, a, b) → (h0, h1, h2)

The [a,b] portion of a quadratic as ANOTHER exact quadratic
(partial_quadratic_bezier_points, bezier.py:75).
"""
function partial_bezier(p0::Point3f, p1::Point3f, p2::Point3f, a::Real, b::Real)
    a == 1 && return (p2, p2, p2)
    curve_at(t) = Point3f((1 - t)^2 * p0 + 2t * (1 - t) * p1 + t^2 * p2)
    h0 = a > 0 ? curve_at(a) : p0
    h2 = b < 1 ? curve_at(b) : p2
    h1p = Point3f((1 - a) * p1 + a * p2)
    prop = (b - a) / (1 - a)
    h1 = Point3f((1 - prop) * h0 + prop * h1p)
    return (h0, h1, h2)
end

"""
Insert `n` curves into a 2m+1 point list without changing the shape: the
insertions go to the longest curves (insert_n_curves_to_point_list).
"""
function _insert_n_curves(points::Vector{Point3f}, n::Int)
    length(points) == 1 && return fill(points[1], 2n + 1)
    nc = (length(points) - 1) ÷ 2
    norms = zeros(nc)
    for k in 1:nc
        a0, h, a1 = points[2k-1], points[2k], points[2k+1]
        norms[k] = norm(h - a0) < _POINT_ATOL ? 0.0 : norm(a1 - a0)
    end
    ipc = zeros(Int, nc)
    for _ in 1:n
        i = argmax(norms)
        ipc[i] += 1
        norms[i] *= ipc[i] / (ipc[i] + 1)
    end
    new_points = [points[1]]
    for k in 1:nc
        alphas = range(0, 1; length = ipc[k] + 2)
        for (a1, a2) in zip(alphas, alphas[2:end])
            _, h1, h2 = partial_bezier(points[2k-1], points[2k], points[2k+1], a1, a2)
            push!(new_points, h1, h2)
        end
    end
    return new_points
end

# ── VMobject fulfils the interpolation contract ─────────────────────────────
# The four pieces: the trait, copy, interpolate! and become! (further down),
# plus the align_data! hook. Transform never mentions VMobject: it calls these.

is_interpolable(::VMobject) = true

"""
    align_data!(a::VMobject, b::VMobject; padding = :invisible)

Leaves both families interpolable: the same tree of children at every level
(padding the shorter side) and the same number of points per pair. This is
the hook of the contract that Transform calls in `begin!`.

The padding is ManimGL's (`align_family` and `add_n_more_submobjects`,
mobject.py:1779-1823), level by level: a side with NO children against N
grows N null children — copies of itself collapsed to one point at its
centre — and a shorter side repeats its children uniformly
(`repeat_indices`) with INVISIBLE copies, so in the middle of a morph a
glyph travels and its extra partner emerges from nothing where the target
needs one, instead of one glyph splitting into two that travel. `padding =
:visible` keeps the copies visible.
"""
function align_data!(a::VMobject, b::VMobject; padding::Symbol = :invisible)
    _check_padding(padding)
    _align_family!(a, b, padding)
    fa, fb = get_family(a), get_family(b)
    length(fa) == length(fb) || throw(ArgumentError(
        "the families do not match ($(length(fa)) vs $(length(fb)) members) — " *
        "both mobjects must have the same tree of children"))
    for (sa, sb) in zip(fa, fb)
        sa isa VMobject && sb isa VMobject && align_points!(sa, sb)
    end
    return a
end

const _PADDINGS = (:invisible, :visible)
_check_padding(p::Symbol) = p in _PADDINGS || throw(ArgumentError(
    "padding must be :invisible (ManimGL's invisible copies) or :visible " *
    "(visible copies), got :$p"))

"""
The pair hook of `Transform`, with the padding threaded through ONLY where
families are padded — a type of your own with the four-line contract never
sees the keyword.
"""
_align_pair!(a::Mobject, b::Mobject, ::Symbol) = align_data!(a, b)
_align_pair!(a::VMobject, b::VMobject, padding::Symbol) = align_data!(a, b; padding)

"Align the two trees level by level (GL's `align_family`): equalise this pair's child count, then recurse into the paired children."
function _align_family!(a::VMobject, b::VMobject, padding::Symbol)
    na, nb = length(a.submobjects), length(b.submobjects)
    if na != nb
        _add_n_more_submobjects!(a, max(0, nb - na), padding)
        _add_n_more_submobjects!(b, max(0, na - nb), padding)
    end
    for (x, y) in zip(a.submobjects, b.submobjects)
        x isa VMobject && y isa VMobject && _align_family!(x, y, padding)
    end
    return a
end

"""
Grow `m` by `n` children the way GL does (`add_n_more_submobjects`,
mobject.py:1799): a childless parent gets `n` null copies of itself — one
point at its centre, its own style — and a parent with children repeats them
spread uniformly, each original first and then its padding copies.
"""
function _add_n_more_submobjects!(m::VMobject, n::Int, padding::Symbol)
    n == 0 && return m
    if isempty(m.submobjects)
        null = copy(m)
        set_points!(null, [get_center(m)])
        for _ in 1:n
            add!(m, copy(null))
        end
        return m
    end
    _replace_children!(m, _padded_children(m.submobjects, n, padding))
    return m
end

"The children plus `n` padding copies spread as GL's `repeat_indices` — the original first, its copies right after it."
function _padded_children(children::Vector{Mobject}, n::Int, padding::Symbol)
    curr = length(children)
    target = curr + n
    indices = [div(k * curr, target) + 1 for k in 0:target-1]
    out = Mobject[]
    seen = zeros(Int, curr)
    for i in indices
        seen[i] += 1
        push!(out, seen[i] == 1 ? children[i] : _padding_copy(children[i], padding))
    end
    return out
end

_padding_copy(m::Mobject, padding::Symbol) = padding === :visible ? copy(m) : invisible_copy(m)

"""
    invisible_copy(m) → Mobject

A copy at opacity zero (ManimGL's `invisible_copy`, mobject.py:1821): what
family padding is made of.
"""
function invisible_copy(m::Mobject)
    c = copy(m)
    applicable(set_opacity!, c, 0.0) && set_opacity!(c, 0.0)
    return c
end

"Swap `m`'s children for `new` through the family's one door: the ones kept are re-added, the rest forget their parent."
function _replace_children!(m::Mobject, new::Vector{Mobject})
    for old in m.submobjects
        _forget_parent!(old, m)
    end
    empty!(m.submobjects)
    note_changed_family!(m)
    for c in new
        add!(m, c)
    end
    return m
end

"Deep copy: points, style, keys, updaters and children (recursive); no parents, no caches."
function Base.copy(m::VMobject{S}) where {S}
    c = vmob(S)
    c.points = copy(m.points)
    c.stroke_rgba = copy(m.stroke_rgba)
    c.fill_rgba = copy(m.fill_rgba)
    c.stroke_width = copy(m.stroke_width)
    c.default_stroke_rgba = m.default_stroke_rgba
    c.default_fill_rgba = m.default_fill_rgba
    c.default_stroke_width = m.default_stroke_width
    c.shading = m.shading
    c.depth_test = m.depth_test
    c.fixed_in_frame = m.fixed_in_frame
    c.keys = copy(m.keys)          # a key is mobject data: it travels with it
    c.fill_gradient = m.fill_gradient   # shared: the spec is immutable
    c.z_index = m.z_index               # draw order is mobject data too
    c.joint_type = m.joint_type         # how it turns a corner travels too
    c.updaters = copy(m.updaters)       # GL's `list(self.updaters)` (mobject.py:693)
    c.updating_suspended = m.updating_suspended
    for child in m.submobjects
        add!(c, copy(child))
    end
    # AFTER the children: `add!` invalidates the family caches, and this one
    # is a list of child indices, which the copy reproduces exactly. The copy
    # gets its own list so a later `_isolate!` on either side cannot touch the
    # other (the runs themselves are never mutated after construction).
    c.key_runs = m.key_runs === nothing ? nothing : copy(m.key_runs)
    return c
end

"Adopt the point count of `other` by copying its points (GL's match_points)."
function match_points!(m::VMobject, other::VMobject)
    set_points!(m, other.points)
end

"""
    align_points!(m1, m2)

Leaves both with the SAME number of points without deforming them
(vectorized_mobject.py:960): sorts the subpaths by length, pairs them, inserts
curves into the shorter one of each pair, and fills unpaired subpaths with a
collapsed point (see the note on unpaired subpaths below).
"""
function align_points!(m1::VMobject, m2::VMobject)
    # Deliberate departure from Manim: GL's shortcut only compares the
    # NUMBER of points — if two mobjects agree on the total but differ in the
    # subpath structure (e.g. 9+1+33 vs 33+1+9), the lerp pairs them wrongly
    # and the morph tangles. Our shortcut also demands the SAME cuts.
    if get_num_points(m1) == get_num_points(m2) &&
       (has_points(m1) ? get_subpath_end_indices(m1) : Int[]) ==
       (has_points(m2) ? get_subpath_end_indices(m2) : Int[])
        return m1
    end
    for m in (m1, m2)
        has_points(m) || start_new_path!(m, get_center(m))
    end

    sps1 = [collect(sp) for sp in get_subpaths(m1)]
    sps2 = [collect(sp) for sp in get_subpaths(m2)]
    path_length(sp) = sum(norm(sp[i+1] - sp[i]) for i in 1:length(sp)-1; init = 0.0)
    sort!(sps1; by = path_length, rev = true)
    sort!(sps2; by = path_length, rev = true)

    function nth_subpath(list, n)
        n <= length(list) && return list[n]
        # Unpaired: a subpath COLLAPSED at the centre of the main one (it grows
        # from a point, CE style). Unlike GL, whose "there and back"
        # (retracing the main subpath) creates hundreds of ± overlapping
        # triangles whose AA stops cancelling halfway through a morph — the
        # winding fill streaks seen in Tex→Tex. A single point retraces
        # nothing.
        centre = sum(list[1]) / length(list[1])
        return fill(centre, 3)
    end

    new1 = Point3f[]
    new2 = Point3f[]
    for n in 1:max(length(sps1), length(sps2))
        sp1 = nth_subpath(sps1, n)
        sp2 = nth_subpath(sps2, n)
        d1 = max(0, (length(sp2) - length(sp1)) ÷ 2)
        d2 = max(0, (length(sp1) - length(sp2)) ÷ 2)
        sp1 = _insert_n_curves(sp1, d1)
        sp2 = _insert_n_curves(sp2, d2)
        if n > 1   # the pinned handle that separates subpaths
            push!(new1, new1[end])
            push!(new2, new2[end])
        end
        append!(new1, sp1)
        append!(new2, sp2)
    end
    set_points!(m1, new1)
    set_points!(m2, new2)
    return m1
end

"""
    interpolate!(m, m1, m2, α)

Leaves `m` as the state α between m1 and m2: lerp of points AND of style
(Mobject.interpolate — GL interpolates every field of `data`).
"""
function interpolate!(m::VMobject, m1::VMobject, m2::VMobject, alpha::Real)
    n = get_num_points(m1)
    n == get_num_points(m2) || throw(ArgumentError(
        "cannot interpolate mobjects with $n and $(get_num_points(m2)) points — " *
        "call align_points!(m1, m2) first"))
    a = Float32(alpha)
    resize!(m.points, n); _resize_style!(m, n)
    # Exact endpoints: a + 1·(b − a) lands 1 ulp OFF b in Float32, so an
    # animation would end NEAR its target instead of ON it (and a gradient
    # spec, gated on row equality, would die at the finish line). α ∈ {0,1}
    # copies the endpoint literally and restores its spec.
    if a == 0f0 || a == 1f0
        src = a == 0f0 ? m1 : m2
        m.points .= src.points
        m.stroke_rgba .= src.stroke_rgba
        m.fill_rgba .= src.fill_rgba
        m.stroke_width .= src.stroke_width
        m.fill_gradient = src.fill_gradient
    else
        @inbounds for i in 1:n
            m.points[i] = m1.points[i] + a * (m2.points[i] - m1.points[i])
            m.stroke_rgba[i] = m1.stroke_rgba[i] + a * (m2.stroke_rgba[i] - m1.stroke_rgba[i])
            m.fill_rgba[i] = m1.fill_rgba[i] + a * (m2.fill_rgba[i] - m1.fill_rgba[i])
            m.stroke_width[i] = m1.stroke_width[i] + a * (m2.stroke_width[i] - m1.stroke_width[i])
        end
    end
    _expire_subpath_cuts!(m)
    refresh_bounding_box!(m)
    return m
end

"""
    pointwise_become_partial!(m, src, a, b)

`m` becomes the [a,b] portion of `src`'s path — the mechanism behind
ShowCreation/Create (vectorized_mobject.py:1060). It preserves the point
count: whatever is not drawn collapses onto the ends.
"""
function pointwise_become_partial!(m::VMobject, src::VMobject, a::Real, b::Real)
    if a <= 0 && b >= 1
        return set_points!(m, src.points)
    end
    nc = get_num_curves(src)
    nc == 0 && return set_points!(m, fill(Point3f(0, 0, 0), get_num_points(src)))
    vp = src.points
    li, lres = integer_interpolate(0, nc, a)
    ui, ures = integer_interpolate(0, nc, b)
    i1 = 2li; i2 = 2li + 3; i3 = 2ui; i4 = 2ui + 3    # 0-based like GL
    new_points = copy(vp)
    if li == ui
        t = partial_bezier(vp[i1+1], vp[i1+2], vp[i1+3], lres, ures)
        new_points[1:i1] .= Ref(t[1])
        new_points[i1+1:i4] .= (t[1], t[2], t[3])
        new_points[i4+1:end] .= Ref(t[3])
    else
        lower = partial_bezier(vp[i1+1], vp[i1+2], vp[i1+3], lres, 1)
        upper = partial_bezier(vp[i3+1], vp[i3+2], vp[i3+3], 0, ures)
        new_points[1:i1] .= Ref(lower[1])
        new_points[i1+1:i2] .= (lower[1], lower[2], lower[3])
        new_points[i3+1:i4] .= (upper[1], upper[2], upper[3])
        new_points[i4+1:end] .= Ref(upper[3])
    end
    return set_points!(m, new_points)
end

"""
Steal the data of `other` while keeping identity (Manim's become) — RECURSIVE
over the children: a Tex is a parent without points plus one child per glyph,
and become! on the parent alone would leave the glyphs untouched (FadeIn(Tex)
would not fade: its become!(mob, faded) would never reach the children). If the structures differ, it adopts copies of `other`'s children.

What travels (as in ManimGL): the points, the style rows AND the factory
style, the gradient, the joint type and the keys. What stays: the z-index
(`set_z_index!(m, get_z_index(other))` if you want the source's), the
updaters, and the flags (`depth_test`, `fixed_in_frame`, `shading`).
"""
function become!(m::VMobject, other::VMobject)
    if length(m.submobjects) == length(other.submobjects)
        for (a, b) in zip(m.submobjects, other.submobjects)
            a isa VMobject && b isa VMobject && become!(a, b)
        end
    else
        for old in m.submobjects
            _forget_parent!(old, m)     # leave the family THROUGH the door
        end
        empty!(m.submobjects)
        note_changed_family!(m)
        for child in other.submobjects
            add!(m, copy(child))
        end
    end
    set_points!(m, other.points)
    m.stroke_rgba .= other.stroke_rgba
    m.fill_rgba .= other.fill_rgba
    m.stroke_width .= other.stroke_width
    m.fill_gradient = other.fill_gradient   # adopt the spec with the rows
    # The factory style travels with the rows (otherwise a mobject that later
    # grew points would re-stamp the OLD one, and get_opacity would lie), and
    # so does the joint (GL transfers the uniform). The z-index does NOT: GL
    # keeps it as an attribute of the destination, and a fresh always_redraw
    # shape would otherwise reset the user's z.
    m.default_stroke_rgba = other.default_stroke_rgba
    m.default_fill_rgba = other.default_fill_rgba
    m.default_stroke_width = other.default_stroke_width
    m.joint_type = other.joint_type
    m.keys = copy(other.keys)      # the key travels with the data
    # So do the recorded occurrences (what `get_parts_by_tex` answers —
    # otherwise the parts would come back keyless), and the ancestors' key
    # memos are stale now: a group that memoised `g["x"]` before this become!
    # would keep serving the OLD glyph (the memo of `m` itself is dropped
    # below, the ancestors' by the climb)
    m.key_runs = other.key_runs === nothing ? nothing : copy(other.key_runs)
    m.key_group_cache = nothing    # the memo indexed the previous keys
    _expire_key_memos_above!(m)
    return m
end
