# backend/expanded.jl — what a render VM is built from: the CPU preparation of
# a VMobject (the rows a run uploads), and the vocabulary of runs and records —
# the bit-for-bit mirrors, the row predicates, the batch key, the counters.
#
# `expanded_data` is a pure function of a mobject's rows and its gradient,
# `_bits_equal` is a memcmp, a batch key is four fields. Nothing here names a
# graphics API, which is why the file sits in `backend/` and not under
# `backend/wgpu/`: it is the half of the renderer that another backend would
# take as it is. The other half — the passes — lives in `backend/wgpu/`.

using GeometryBasics: Point3f, Vec2f, Vec4f
using StaticArrays: SVector, SMatrix
using LinearAlgebra: norm, normalize

# ═══════════════════════════════════════════════════════════════════════
# CPU preparation — what ManimGL's VMobject computes before uploading
# ═══════════════════════════════════════════════════════════════════════

function vector_area(m::VMobject)
    area = zeros(3)
    for sp in get_subpaths(m)
        anchors = @view sp[1:2:end]
        n = length(anchors)
        for i in 1:n
            p0 = anchors[i]; p1 = anchors[mod1(i + 1, n)]
            area[1] += 0.5 * (p0[2] + p1[2]) * (p1[3] - p0[3])
            area[2] += 0.5 * (p0[3] + p1[3]) * (p1[1] - p0[1])
            area[3] += 0.5 * (p0[1] + p1[1]) * (p1[2] - p0[2])
        end
    end
    return area
end

"The mobject's unit normal (get_unit_normal): the area vector, normalised."
function unit_normal_of(m::VMobject)
    get_num_points(m) < 3 && return Point3f(0, 0, 1)
    av = vector_area(m)
    a = norm(av)
    a > 0 && return Point3f(av / a)
    p = m.points
    v1 = normalize(SVector{3,Float64}(p[2] - p[1]))
    v2 = normalize(SVector{3,Float64}(p[3] - p[2]))
    cp = SVector{3,Float64}(v1[2]v2[3] - v1[3]v2[2], v1[3]v2[1] - v1[1]v2[3], v1[1]v2[2] - v1[2]v2[1])
    ncp = norm(cp)
    ncp < 1e-6 && return Point3f(0, 0, 1)
    return Point3f(cp / ncp)
end

"""
Per-point joint angles (get_joint_angles, v_mobject.py:1174): how much the
path's direction turns at each vertex, closing loops. The stroke's geometry
shader uses them to extend the corners (miter/bevel).
"""
function joint_angles_of(m::VMobject, normal::Point3f)
    n = get_num_points(m)
    ang = zeros(Float32, n)
    n < 3 && return ang

    # rotate the points so the normal lands on +z (like numpy: p @ R)
    pts = if normal ≈ Point3f(0, 0, 1)
        [SVector{3,Float64}(p) for p in m.points]
    else
        axis = SVector{3,Float64}(-normal[2], normal[1], 0)  # OUT × normal
        R = if norm(axis) < 1e-8
            SMatrix{3,3,Float64}(1, 0, 0, 0, -1, 0, 0, 0, -1)  # normal = −OUT
        else
            # The UNCHECKED door — a degenerate normal is NaN here and the
            # rendered bytes depend on it flowing through unchanged.
            Janim._rotation_matrix_unchecked(
                acos(clamp(Float64(normal[3]), -1, 1)), axis)
        end
        [R' * SVector{3,Float64}(p) for p in m.points]
    end

    cero = zero(SVector{3,Float64})
    v_in = fill(cero, n)
    v_out = fill(cero, n)
    for k in 1:(n-1)÷2
        a0h = pts[2k] - pts[2k-1]
        ha1 = pts[2k+1] - pts[2k]
        v_in[2k] = a0h; v_in[2k+1] = ha1
        v_out[2k-1] = a0h; v_out[2k] = ha1
    end

    ends = get_subpath_end_indices(m)
    starts = [1; ends[1:end-1] .+ 2]
    for (s, e) in zip(starts, ends)
        s == e && continue
        if m.points[s] == m.points[e]        # closed subpath: join the ends
            v_in[s] = v_out[e-1]
            v_out[e] = v_in[s+1]
        else                                 # open: no turn at the endpoints
            v_in[s] = v_out[s]
            v_out[e] = v_in[e]
        end
    end

    for i in 1:n
        d = atan(v_out[i][2], v_out[i][1]) - atan(v_in[i][2], v_in[i][1])
        d < -π && (d += 2π)
        d > π && (d -= 2π)
        ang[i] = Float32(d)
    end
    return ang
end

"""
Per-vertex data expanded into triples (0,1,2, 2,3,4, …) — get_outer_vert_indices.
With `grad` (an ACTIVE FillGradient) it also expands the per-point gradient uv
plus the uv of each subpath's fan base — the base is points[s], so its uv is
uv[s]: pure data plumbing, nothing is evaluated at render time.
"""
function expanded_data(m::VMobject; grad::Union{Nothing,FillGradient} = nothing)
    nc = get_num_curves(m)
    normal = unit_normal_of(m)
    joints = joint_angles_of(m, normal)
    # PER-SUBPATH fan base point (a deliberate divergence from manimgl, which
    # uses the global points[0] — v_mobject.py:1341). Winding is invariant to
    # the base, but with a global base one subpath's fans sweep across the
    # others and the ±α cancellation in float16 accumulates visible error
    # (formulas rendered with interiors at 55% and streaks). A local base
    # means local fans, which means zero cross overlap.
    bases = Vector{Point3f}(undef, get_num_points(m))
    uv_bases = grad === nothing ? nothing :
               Vector{Vec2f}(undef, get_num_points(m))
    if has_points(m)
        ends = get_subpath_end_indices(m)
        s = 1
        for e in ends
            bases[s:min(e + 1, length(bases))] .= Ref(m.points[s])
            uv_bases === nothing ||
                (uv_bases[s:min(e + 1, length(uv_bases))] .= Ref(grad.uv[s]))
            s = e + 2
        end
    end
    ovi = [2k - 2 + j for k in 1:nc for j in 0:2]   # 0-based
    ex = (i -> i + 1).(ovi)                          # 1-based
    (
        point = m.points[ex],
        stroke_rgba = m.stroke_rgba[ex],
        stroke_width = m.stroke_width[ex],
        joint_angle = joints[ex],
        fill_rgba = m.fill_rgba[ex],
        base_normal = [iszero((i - 1) % 2) ? bases[i] : normal for i in ex],
        grad_uv = grad === nothing ? nothing : grad.uv[ex],
        grad_uv_base = uv_bases === nothing ? nothing : uv_bases[ex],
        n = length(ex),
    )
end

# ═══════════════════════════════════════════════════════════════════════
# The renderer remembers
# ═══════════════════════════════════════════════════════════════════════
#
# A draw that created, filled and destroyed its buffers, rebuilt
# `expanded_data` for every mobject every frame and located every uniform by
# NAME would spend most of its time in that churn (95 % of the fill's `_draw!`
# and 96 % of the stroke's, measured with 3000 loose members). So the renderer
# keeps records instead; what stays per draw is the passes themselves —
# binds, clears, the quad.
#
# The cache lives in the RenderVM (the preview, the daemon and the compositor
# own several, and GPU objects belong to a device) and is keyed by IDENTITY:
# a Dict on mutable structs hashes objectid and compares with ===. It
# invalidates by COMPARISON, never by hooks: every VMobject's SOURCE rows —
# points, stroke_rgba, fill_rgba, stroke_width — are mirrored and memcmp'd
# once per pass, and since `expanded_data` is a pure function of those rows
# and the gradient, unchanged rows mean nothing to expand and nothing to
# upload. A run keeps its expanded SoA arrays in persistent buffers: a member
# whose rows differ is re-expanded and its range uploaded; a run whose
# members, gradient or curve counts changed is rebuilt whole. Meshes and
# clouds keep one buffer per array and re-upload the array whose mirror
# differs. Records and mirrors not drawn for a while are swept, because the
# keys pin the mobjects.
#
# Cached or not, the draw commands are the same vertices in the same order
# through the same programs, so the pixels are the same bytes by construction.

const _DISABLE_DRAW_CACHE = Ref(false)   # test-only: build, draw and release every record on the spot
const _SWEEP_EVERY = 64                  # passes between sweeps
const _KEEP_PASSES = 8                   # a record unseen for this many passes is released

function _bits_equal(a::Vector{T}, b::Vector{T}) where {T}
    length(a) == length(b) || return false
    isempty(a) && return true
    return ccall(:memcmp, Cint, (Ptr{Cvoid}, Ptr{Cvoid}, Csize_t), a, b,
                 sizeof(T) * length(a)) == 0
end

_bits_equal(a::Vector, b::Vector) = false     # different element types: never equal

_mirror!(dst::Vector{T}, src::Vector{T}) where {T} =
    (resize!(dst, length(src)); copyto!(dst, src); dst)

# `sizeof` on a ReinterpretArray is the WRAPPER: every byte count in the cache
# goes through this.
_nbytes(arr::AbstractVector) = sizeof(eltype(arr)) * length(arr)

_has_fill(rows::Vector{Vec4f}) = any(c -> c[4] > 0, rows)

_has_stroke(widths::Vector{Float32}, rows::Vector{Vec4f}) =
    any(>(0), widths) && any(c -> c[4] > 0, rows)

# Per-root batching (see _draw_list!). The switch makes every member its own
# run — the unbatched loop, byte for byte — for A/B comparisons and as a
# control; it costs one branch.
const _DISABLE_DRAW_BATCH = Ref(false)
const _DRAW_RUNS = Ref(0)      # runs submitted (a run of one counts)
const _DRAW_CALLS = Ref(0)     # draws issued by the passes (the composite quad is not one)

_batch_key(m::VMobject) = (m.joint_type, m.fixed_in_frame, m.shading, m.depth_test)

function _concat_expanded(datas)
    length(datas) == 1 && return datas[1]
    cat(f) = reduce(vcat, [getfield(d, f) for d in datas])
    return (
        point = cat(:point),
        stroke_rgba = cat(:stroke_rgba),
        stroke_width = cat(:stroke_width),
        joint_angle = cat(:joint_angle),
        fill_rgba = cat(:fill_rgba),
        base_normal = cat(:base_normal),
        grad_uv = nothing,             # a gradient fill is always a run of one
        grad_uv_base = nothing,
        n = sum(d.n for d in datas),
    )
end

function _same_members(a::Vector{VMobject}, b::Vector{VMobject})
    length(a) == length(b) || return false
    for i in eachindex(a)
        a[i] === b[i] || return false
    end
    return true
end

const _IMAGE_UV = Float32[0, 0, 0, 1, 1, 0, 1, 1]     # UL, DL, UR, DR
