# core/implicit.jl — ImplicitFunction (functions.py:87).
#
# The curve f(x, y) = 0 over a box, traced the way ManimGL traces it: GL
# leans on the `isosurfaces` package (Manson & Schaefer, "Isosurfaces over
# simplicial partitions of multiresolution grids", CGF 2010), and this file is
# a short port of that package rather than a dependency. The
# algorithm, in the same order as the original so the two engines produce the
# same polylines from the same function:
#
#   1. an adaptive QUADTREE over the box: every cell splits down to
#      `min_depth`, and past it only where the corner signs disagree (or the
#      function is undefined on some corners), until `max_quads` leaves;
#   2. every pair of neighbouring leaves is joined by FOUR triangles fanning
#      from the shared edge's dual point to the two face duals — a simplicial
#      partition that works across resolution changes;
#   3. on every triangle edge that crosses zero, a BINARY SEARCH lands the
#      crossing within `tol` = (box size)/1000, and links the triangle to the
#      next one along the curve;
#   4. a tracer walks the links into polylines, closing loops.
#
# Nothing here touches the renderer: the result is an ordinary VMobject of
# corner points, one subpath per connected curve.

mutable struct _IsoPoint
    pos::SVector{2,Float64}
    val::Float64
end

_iso(fn, pos::SVector{2,Float64}) = _IsoPoint(pos, fn(pos))
_iso_mid(a::_IsoPoint, b::_IsoPoint, fn) = _iso(fn, (a.pos + b.pos) / 2)

"The point on the segment a–b whose linearly interpolated value is 0."
function _iso_zero(a::_IsoPoint, b::_IsoPoint, fn)
    denom = a.val - b.val
    k1 = -b.val / denom
    k2 = a.val / denom
    return _iso(fn, k1 * a.pos + k2 * b.pos)
end

"""
Binary search for the zero between `a` and `b`, down to `tol` per axis.
Returns `(point, is_zero)`: the flag rejects an asymptote (1/(xy) − 1 at
x = 0 changes sign without ever being zero).
"""
function _binary_search_zero(a::_IsoPoint, b::_IsoPoint, fn, tol::SVector{2,Float64})
    if all(abs.(b.pos - a.pos) .< tol)
        pt = _iso_zero(a, b, fn)
        is_zero = pt.val == 0 || sign(pt.val - a.val) == sign(b.val - pt.val)
        return pt, is_zero
    end
    mid = _iso_mid(a, b, fn)
    mid.val == 0 && return mid, true
    return (mid.val > 0) == (a.val > 0) ? _binary_search_zero(mid, b, fn, tol) :
                                         _binary_search_zero(a, mid, fn, tol)
end

# ── the quadtree ─────────────────────────────────────────────────────────

mutable struct _IsoCell
    vertices::Vector{_IsoPoint}     # bottom-left, bottom-right, top-left, top-right
    depth::Int
    children::Vector{_IsoCell}      # same order as the vertices
    parent::Union{Nothing,_IsoCell}
    child_direction::Int            # 0-based index among the parent's children
end

function _iso_vertices(pmin::SVector{2,Float64}, pmax::SVector{2,Float64}, fn)
    w = pmax - pmin
    return [_iso(fn, SVector(pmin[1] + (i & 1) * w[1], pmin[2] + ((i >> 1) & 1) * w[2]))
            for i in 0:3]
end

function _iso_split!(cell::_IsoCell, fn)
    for (i, vertex) in enumerate(cell.vertices)
        pmin = (cell.vertices[1].pos + vertex.pos) / 2
        pmax = (cell.vertices[end].pos + vertex.pos) / 2
        push!(cell.children,
              _IsoCell(_iso_vertices(pmin, pmax, fn), cell.depth + 1, _IsoCell[], cell, i - 1))
    end
    return cell
end

"Descend only where the isoline may cross: a sign change, or a corner where f is undefined."
function _iso_should_descend(cell::_IsoCell, tol::SVector{2,Float64})
    all(cell.vertices[end].pos - cell.vertices[1].pos .< 10 * tol) && return false
    all(isnan(v.val) for v in cell.vertices) && return false
    any(isnan(v.val) for v in cell.vertices) && return true
    s0 = sign(cell.vertices[1].val)
    return any(sign(v.val) != s0 for v in @view cell.vertices[2:end])
end

function _iso_build_tree(fn, pmin, pmax, min_depth::Int, max_cells::Int, tol)
    max_cells = max(4^min_depth, max_cells)        # min_depth takes precedence
    root = _IsoCell(_iso_vertices(pmin, pmax, fn), 0, _IsoCell[], nothing, 0)
    queue = _IsoCell[root]
    head = 1
    leaves = 1
    while head <= length(queue) && leaves < max_cells
        cell = queue[head]
        head += 1
        if cell.depth < min_depth || _iso_should_descend(cell, tol)
            _iso_split!(cell, fn)
            append!(queue, cell.children)
            leaves += 3                            # four new leaves, one fewer
        end
    end
    return root
end

# ── the triangulation, and the curve links it computes on the way ────────

mutable struct _IsoTriangle
    vertices::NTuple{3,_IsoPoint}
    next::Union{Nothing,_IsoTriangle}
    next_bisect::Union{Nothing,_IsoPoint}
    prev::Union{Nothing,_IsoTriangle}
    visited::Bool
end

_iso_tri(a, b, c) = _IsoTriangle((a, b, c), nothing, nothing, nothing, false)

"Four triangles from `center` to the (clockwise) quad a, b, c, d."
_iso_four(a, b, c, d, center) =
    (_iso_tri(a, b, center), _iso_tri(b, c, center), _iso_tri(c, d, center), _iso_tri(d, a, center))

mutable struct _IsoTriangulator
    triangles::Vector{_IsoTriangle}
    hanging::Dict{NTuple{2,Float64},_IsoTriangle}   # keyed by the hanging edge's midpoint ×2
    fn::Function
    tol::SVector{2,Float64}
end

function _iso_triangulate_inside!(t::_IsoTriangulator, quad::_IsoCell)
    isempty(quad.children) && return
    for child in quad.children
        _iso_triangulate_inside!(t, child)
    end
    c = quad.children
    _iso_crossing_row!(t, c[1], c[2])
    _iso_crossing_row!(t, c[3], c[4])
    _iso_crossing_col!(t, c[1], c[3])
    _iso_crossing_col!(t, c[2], c[4])
    return
end

"Quad `b` is to the right of quad `a`."
function _iso_crossing_row!(t::_IsoTriangulator, a::_IsoCell, b::_IsoCell)
    if !isempty(a.children) && !isempty(b.children)
        _iso_crossing_row!(t, a.children[2], b.children[1])
        _iso_crossing_row!(t, a.children[4], b.children[3])
    elseif !isempty(a.children)
        _iso_crossing_row!(t, a.children[2], b)
        _iso_crossing_row!(t, a.children[4], b)
    elseif !isempty(b.children)
        _iso_crossing_row!(t, a, b.children[1])
        _iso_crossing_row!(t, a, b.children[3])
    else
        face_a = _iso_face_dual(t, a)
        face_b = _iso_face_dual(t, b)
        if a.depth < b.depth                     # b is the smaller quad
            edge = _iso_edge_dual(t, b.vertices[3], b.vertices[1])
            _iso_add_four!(t, _iso_four(b.vertices[3], face_b, b.vertices[1], face_a, edge))
        else
            edge = _iso_edge_dual(t, a.vertices[4], a.vertices[2])
            _iso_add_four!(t, _iso_four(a.vertices[4], face_b, a.vertices[2], face_a, edge))
        end
    end
    return
end

"Quad `b` is above quad `a`."
function _iso_crossing_col!(t::_IsoTriangulator, a::_IsoCell, b::_IsoCell)
    if !isempty(a.children) && !isempty(b.children)
        _iso_crossing_col!(t, a.children[3], b.children[1])
        _iso_crossing_col!(t, a.children[4], b.children[2])
    elseif !isempty(a.children)
        _iso_crossing_col!(t, a.children[3], b)
        _iso_crossing_col!(t, a.children[4], b)
    elseif !isempty(b.children)
        _iso_crossing_col!(t, a, b.children[1])
        _iso_crossing_col!(t, a, b.children[2])
    else
        face_a = _iso_face_dual(t, a)
        face_b = _iso_face_dual(t, b)
        if a.depth < b.depth
            edge = _iso_edge_dual(t, b.vertices[1], b.vertices[2])
            _iso_add_four!(t, _iso_four(b.vertices[1], face_b, b.vertices[2], face_a, edge))
        else
            edge = _iso_edge_dual(t, a.vertices[3], a.vertices[4])
            _iso_add_four!(t, _iso_four(a.vertices[3], face_b, a.vertices[4], face_a, edge))
        end
    end
    return
end

function _iso_add_four!(t::_IsoTriangulator, tris)
    for i in 1:4
        _iso_next_sandwich!(t, tris[i], tris[mod1(i + 1, 4)], tris[mod1(i + 2, 4)])
    end
    append!(t.triangles, tris)
    return
end

function _iso_set_next!(t::_IsoTriangulator, tri1, tri2, vpos::_IsoPoint, vneg::_IsoPoint)
    (vpos.val > 0 >= vneg.val) || return
    pt, is_zero = _binary_search_zero(vpos, vneg, t.fn, t.tol)
    is_zero || return
    tri1.next_bisect = pt
    tri1.next = tri2
    tri2.prev = tri1
    return
end

"""
The "next" triangle of `b`, which shares its centre with `a` and `c`
(x = a[2] ≡ b[1], y = b[2] ≡ c[1]): the simple links stay inside the four,
the hanging ones wait for the triangle on the other side of the edge.
"""
function _iso_next_sandwich!(t::_IsoTriangulator, a, b, c)
    center = b.vertices[3]
    x = b.vertices[1]
    y = b.vertices[2]
    center.val > 0 >= y.val && _iso_set_next!(t, b, c, center, y)
    x.val > 0 >= center.val && _iso_set_next!(t, b, a, x, center)
    id = Tuple(x.pos + y.pos)
    if y.val > 0 >= x.val
        if haskey(t.hanging, id)
            _iso_set_next!(t, b, t.hanging[id], y, x)
            delete!(t.hanging, id)
        else
            t.hanging[id] = b
        end
    elseif y.val <= 0 < x.val
        if haskey(t.hanging, id)
            _iso_set_next!(t, t.hanging[id], b, x, y)
            delete!(t.hanging, id)
        else
            t.hanging[id] = b
        end
    end
    return
end

"The dual point on the edge p1–p2: the midpoint when it crosses, a gradient-guided point otherwise."
function _iso_edge_dual(t::_IsoTriangulator, p1::_IsoPoint, p2::_IsoPoint)
    (p1.val > 0) != (p2.val > 0) && return _iso_mid(p1, p2, t.fn)
    dt = 0.01
    df1 = t.fn(p1.pos * (1 - dt) + p2.pos * dt)
    df2 = t.fn(p1.pos * dt + p2.pos * (1 - dt))
    (df1 > 0) == (df2 > 0) && return _iso_mid(p1, p2, t.fn)
    return _iso_zero(_IsoPoint(p1.pos, df1), _IsoPoint(p2.pos, df2), t.fn)
end

_iso_face_dual(t::_IsoTriangulator, quad::_IsoCell) =
    _iso_mid(quad.vertices[1], quad.vertices[end], t.fn)

# ── the tracer ───────────────────────────────────────────────────────────

function _iso_trace(triangles::Vector{_IsoTriangle})
    curves = Vector{Vector{SVector{2,Float64}}}()
    for start in triangles
        (!start.visited && start.next !== nothing) || continue
        curve = SVector{2,Float64}[]
        tri = start
        closed = false
        while tri.prev !== nothing                 # walk back to the curve's start
            tri = tri.prev
            if tri === start
                closed = true
                break
            end
        end
        while tri !== nothing && !tri.visited
            tri.next_bisect === nothing || push!(curve, tri.next_bisect.pos)
            tri.visited = true
            tri = tri.next
        end
        closed && !isempty(curve) && push!(curve, curve[1])
        push!(curves, curve)
    end
    return curves
end

"The isoline f = 0 over the box as polylines (plot_isoline)."
function _plot_isoline(fn, pmin::SVector{2,Float64}, pmax::SVector{2,Float64};
                       min_depth::Int = 5, max_quads::Int = 10000)
    tol = (pmax - pmin) / 1000
    root = _iso_build_tree(fn, pmin, pmax, min_depth, max_quads, tol)
    t = _IsoTriangulator(_IsoTriangle[], Dict{NTuple{2,Float64},_IsoTriangle}(), fn, tol)
    _iso_triangulate_inside!(t, root)
    return _iso_trace(t.triangles)
end

"""
    ImplicitFunction(f; x_range=(-FRAME_X_RADIUS, FRAME_X_RADIUS),
                     y_range=(-FRAME_Y_RADIUS, FRAME_Y_RADIUS), min_depth=5,
                     max_quads=1500, use_smoothing=false, color, stroke_width, …)

The curve `f(x, y) = 0` over the box, as ManimGL draws it (functions.py:87):
one subpath per connected piece, made of corners (`use_smoothing = true`
smooths them), traced by the adaptive marching of `isosurfaces` ported
above. `min_depth` is the uniform refinement every cell gets; `max_quads`
caps the adaptive refinement past it. GL asks its VMobject for `no_joint`
and DRAWS `auto` (the uniform it reads is 0 — probed); the default here is
what GL draws.

```julia
circle = ImplicitFunction((x, y) -> x^2 + y^2 - 4; x_range = (-3, 3), y_range = (-3, 3))
heart = ImplicitFunction((x, y) -> (x^2 + y^2 - 1)^3 - x^2 * y^3; color = RED)
```
"""
function ImplicitFunction(f::Function;
                          x_range = (-FRAME_X_RADIUS, FRAME_X_RADIUS),
                          y_range = (-FRAME_Y_RADIUS, FRAME_Y_RADIUS),
                          min_depth::Int = 5, max_quads::Int = 1500,
                          use_smoothing::Bool = false,
                          joint_type::Symbol = :auto, kw...)
    fn = p -> Float64(f(p[1], p[2]))
    curves = _plot_isoline(fn, SVector{2,Float64}(x_range[1], y_range[1]),
                           SVector{2,Float64}(x_range[2], y_range[2]); min_depth, max_quads)
    m = VMobject(; joint_type, kw...)
    for curve in curves
        isempty(curve) && continue
        start_new_path!(m, Point3f(curve[1][1], curve[1][2], 0))
        for q in @view curve[2:end]
            add_line_to!(m, Point3f(q[1], q[2], 0))
        end
    end
    use_smoothing && make_smooth!(m)
    return m
end
