# Surface — a port of mobject/types/surface.py.
#
# A uv mesh: `resolution` samples of `uv_func`, triangulated with GL's SAME
# index formula (compute_triangle_indices). The per-vertex normal travels as a
# SECOND point (d_normal_point = p + nudge·n̂, surface.py:105): that way
# shift!/rotate! transform the normal for free and the shader recovers it with
# normalize(d_normal_point − point).

using LinearAlgebra: cross, norm, normalize
using StaticArrays: SVector
using GeometryBasics: Point3f, Vec4f

mutable struct Surface <: Mobject
    points::Vector{Point3f}
    d_normal_points::Vector{Point3f}
    rgba::Vector{Vec4f}
    resolution::NTuple{2,Int}
    indices::Vector{Int32}          # 0-based, ready for an index buffer
    shading::NTuple{3,Float32}      # (reflectiveness, gloss, shadow)
    depth_test::Bool
    fixed_in_frame::Bool
    submobjects::Vector{Mobject}
    parents::Vector{Mobject}
    updaters::Vector{Updater}
    updating_suspended::Bool
    z_index::Float64                # draw order — an attribute of every mobject (GL)
end

"""
    Surface(uv_func; u_range, v_range, resolution=(101,101), color, opacity,
               shading=(0.3,0.2,0.4), epsilon=1e-3, normal_nudge=1e-3)

`uv_func(u,v) → (x,y,z)`. Normals from du/dv (cross product of the ε steps,
as in surface.py:101). Point order is u-outer/v-inner (indexing='ij').
"""
function Surface(uv_func::Function;
                    u_range = (0.0, 1.0), v_range = (0.0, 1.0),
                    resolution::NTuple{2,Int} = (101, 101),
                    color = GREY_C, opacity = 1.0,
                    shading = (0.3, 0.2, 0.4),
                    epsilon::Float64 = 1e-3, normal_nudge::Float64 = 1e-3,
                    depth_test::Bool = true)
    nu, nv = resolution
    pts = Vector{Point3f}(undef, nu * nv)
    dnp = Vector{Point3f}(undef, nu * nv)
    k = 0
    for u in range(u_range[1], u_range[2]; length = nu),
        v in range(v_range[1], v_range[2]; length = nv)
        k += 1
        p = SVector{3,Float64}(uv_func(u, v))
        du = SVector{3,Float64}(uv_func(u + epsilon, v)) - p
        dv = SVector{3,Float64}(uv_func(u, v + epsilon)) - p
        n = cross(du, dv)
        nn = norm(n)
        n = nn > 0 ? n / nn : SVector(0.0, 0.0, 1.0)
        pts[k] = Point3f(p)
        dnp[k] = Point3f(p + normal_nudge * n)
    end
    Surface(pts, dnp, fill(_rgba(color, opacity), nu * nv), resolution,
               _triangle_indices(nu, nv),
               NTuple{3,Float32}(Float32.(shading)), depth_test, false,
               Mobject[], Mobject[], Updater[], false, 0.0)
end

"The index mesh of surface.py:149 (two triangles per cell, 0-based)."
function _triangle_indices(nu::Int, nv::Int)
    (nu == 0 || nv == 0) && return Int32[]
    idx = Vector{Int32}(undef, 6 * (nu - 1) * (nv - 1))
    k = 0
    for i in 0:nu-2, j in 0:nv-2
        tl = i * nv + j
        bl = (i + 1) * nv + j
        tr = i * nv + j + 1
        br = (i + 1) * nv + j + 1
        idx[k+1] = tl; idx[k+2] = bl; idx[k+3] = tr
        idx[k+4] = tr; idx[k+5] = bl; idx[k+6] = br
        k += 6
    end
    return idx
end

"Unit normals per vertex (get_unit_normals)."
unit_normals(s::Surface) =
    [Point3f(normalize(SVector{3,Float64}(s.d_normal_points[i] - s.points[i])))
     for i in eachindex(s.points)]

"""
    SurfaceMesh(surface; resolution=(21,11), stroke_width=1.0, stroke_color=GREY_A,
                normal_nudge=1e-2, depth_test=true, joint_type=:no_joint)

The wireframe of a [`Surface`](@ref) (three_dimensions.py:31): `resolution[1]`
lines of constant u and `resolution[2]` lines of constant v, each a smooth
curve through the surface's own grid points nudged `normal_nudge` along the
unit normal — so the lines sit ON the surface instead of z-fighting with it.
A line that falls between two grid rows is the linear interpolation of the
two, exactly as GL treats the fractional index. Returns a `VGroup` of
`VMobject`s, depth-tested by default like the surface they dress.
"""
function SurfaceMesh(s::Surface; resolution::NTuple{2,Int} = (21, 11),
                     stroke_width::Real = 1.0, stroke_color = GREY_A,
                     normal_nudge::Real = 1e-2, depth_test::Bool = true,
                     joint_type::Symbol = :no_joint)
    full_nu, full_nv = s.resolution
    part_nu, part_nv = resolution
    normals = unit_normals(s)
    nudged = [SVector{3,Float64}(s.points[i]) +
              Float64(normal_nudge) * SVector{3,Float64}(normals[i])
              for i in eachindex(s.points)]
    # the grid is u-outer/v-inner: row i (constant u) is contiguous, column j
    # (constant v) is strided by full_nv — both 0-based, like GL's indices
    row(i) = view(nudged, (i * full_nv + 1):((i + 1) * full_nv))
    column(j) = view(nudged, (j + 1):full_nv:length(nudged))
    lerp(a, b, t) = [(1 - t) * p + t * q for (p, q) in zip(a, b)]
    indices(count, full) = count == 1 ? [0.0] : range(0.0, full - 1; length = count)
    group = VGroup()
    for (count, full, pick) in ((part_nu, full_nu, row), (part_nv, full_nv, column))
        for index in indices(count, full)
            lo, hi = floor(Int, index), ceil(Int, index)
            path = VMobject(; stroke_color, stroke_width, joint_type)
            set_points_smoothly!(path, lerp(pick(lo), pick(hi), index - lo))
            depth_test && apply_depth_test!(path)
            add!(group, path)
        end
    end
    return group
end

# ── the 3D zoo ───────────────────────────────────────────────────────────

"""
    Sphere(; radius=1.0, resolution=(101,51), color, opacity, ...)

uv from three_dimensions.py:116; TRUE radial normals (du/dv degenerates at
the poles — surface.py dodges it the same way).
"""
function Sphere(; radius::Real = 1.0, resolution::NTuple{2,Int} = (101, 51), kw...)
    r = Float64(radius)
    s = Surface((u, v) -> (r * cos(u) * sin(v), r * sin(u) * sin(v), -r * cos(v));
                   u_range = (0.0, TAU), v_range = (0.0, Float64(PI)), resolution, kw...)
    f = (r + 1e-3) / r
    for i in eachindex(s.points)
        s.d_normal_points[i] = Point3f(f * SVector{3,Float64}(s.points[i]))
    end
    return s
end

"Torus(; r1=3, r2=1): (r1 − r2·cos v)·(cos u, sin u, 0) − r2·sin v·ẑ."
function Torus(; r1::Real = 3.0, r2::Real = 1.0,
              resolution::NTuple{2,Int} = (101, 101), kw...)
    Surface((u, v) -> ((r1 - r2 * cos(v)) * cos(u),
                          (r1 - r2 * cos(v)) * sin(u),
                          -r2 * sin(v));
               u_range = (0.0, TAU), v_range = (0.0, TAU), resolution, kw...)
end

"Parametric plane [x0,x1]×[y0,y1] at z=0 (for floors and DOF demos)."
function PlaneXY(; x_range = (-3.0, 3.0), y_range = (-3.0, 3.0),
                 resolution::NTuple{2,Int} = (2, 2), kw...)
    Surface((u, v) -> (u, v, 0.0);
               u_range = Float64.(x_range), v_range = Float64.(y_range), resolution, kw...)
end

# ── the 3D trio (CE's three_dimensions.py) ──────────────────

"Turn a mesh built along +Z so that its axis points along `direction`."
function _aim_z_to!(s::Surface, direction)
    d = SVector{3,Float64}(Point3f(direction))
    n = norm(d)
    n == 0 && return s
    d = d / n
    c = clamp(d[3], -1.0, 1.0)          # dot(ẑ, d̂)
    isapprox(c, 1.0) && return s
    axis = isapprox(c, -1.0) ? SVector(1.0, 0.0, 0.0) : cross(SVector(0.0, 0.0, 1.0), d)
    rotate!(s, acos(c); axis = Point3f(axis), about_point = ORIGIN)
    return s
end

"""
    Cylinder(; radius=1, height=2, direction=OUT, resolution=(24,24))

A tube along `direction`, centred on the origin. It has NO end caps: a
`Surface` is ONE uv patch, and a capped cylinder would be three mobjects that
no longer move as one. For `Line3D` (a thin tube) the caps are invisible
anyway, which is what this is for.

`resolution` counts SAMPLES, not faces (ManimGL's convention), so the default
`(2, 25)` closes the loop with 24 equal faces — an even number, which is what
makes the bounding box exactly `2·radius` wide instead of a chord short.
"""
function Cylinder(; radius::Real = 1.0, height::Real = 2.0, direction = OUT,
                  resolution::NTuple{2,Int} = (2, 25), kw...)
    r, h = Float64(radius), Float64(height)
    s = Surface((u, v) -> (r * cos(v), r * sin(v), u);
                u_range = (-h / 2, h / 2), v_range = (0.0, TAU), resolution, kw...)
    return _aim_z_to!(s, direction)
end

"""
    Cone(; base_radius=1, height=1, direction=OUT, resolution=(24,24))

A cone with its APEX at the origin and its base `height` away along
`direction` — CE's parametrisation (the radius runs along the SLANT, so the
mesh is uniform on the surface instead of bunching at the tip).
"""
function Cone(; base_radius::Real = 1.0, height::Real = 1.0, direction = OUT,
              resolution::NTuple{2,Int} = (2, 25), kw...)
    r, h = Float64(base_radius), Float64(height)
    slant = hypot(r, h)
    st, ct = r / slant, h / slant
    s = Surface((u, v) -> (u * st * cos(v), u * st * sin(v), u * ct);
                u_range = (0.0, slant), v_range = (0.0, TAU), resolution, kw...)
    return _aim_z_to!(s, direction)
end

# The literal, like `Dot` — `DEFAULT_DOT_RADIUS` is the 0.05
# ManimGL exports from dot_cloud.py, and a Dot3D is a Dot with volume.
"""
    Dot3D(point=ORIGIN; radius=0.08, resolution=(17,9))

A small sphere — the 3D dot for marking a point in space.
"""
function Dot3D(point = ORIGIN; radius::Real = 0.08,
               resolution::NTuple{2,Int} = (17, 9), kw...)
    s = Sphere(; radius, resolution, kw...)
    shift!(s, Point3f(point))
    return s
end

"""
    Line3D(start=LEFT, stop=RIGHT; thickness=0.02, resolution=(2,24))

A segment with volume: a thin cylinder from `start` to `stop`. Unlike a 2D
`Line`, this one has a real surface, so the 3D lighting and the depth test
treat it like everything else in the scene.
"""
function Line3D(start = LEFT, stop = RIGHT; thickness::Real = 0.02,
                resolution::NTuple{2,Int} = (2, 25), kw...)
    a, b = Point3f(start), Point3f(stop)
    d = b - a
    len = Float64(norm(d))
    len == 0 && throw(ArgumentError(
        "Line3D needs two different points (start == stop)"))
    s = Cylinder(; radius = thickness, height = len, direction = d, resolution, kw...)
    shift!(s, Point3f(0.5 * (a + b)))
    return s
end

"""
    Arrow3D(start=LEFT, stop=RIGHT; thickness=0.02, height=0.3, base_radius=0.08)

A 3D arrow — shaft plus head — as ONE surface. CE builds it out of two
mobjects (a Line3D and a Cone); ours is a single uv patch whose radius jumps
at the shoulder, so it moves, colours and draws as one thing.
"""
function Arrow3D(start = LEFT, stop = RIGHT; thickness::Real = 0.02,
                 height::Real = 0.3, base_radius::Real = 0.08,
                 resolution::NTuple{2,Int} = (33, 25), kw...)
    a, b = Point3f(start), Point3f(stop)
    d = b - a
    len = Float64(norm(d))
    len > height || throw(ArgumentError(
        "Arrow3D: the arrow ($(round(len; digits=3))) is shorter than its own " *
        "head (height=$height) — shorten the head or lengthen the arrow"))
    shoulder = len - Float64(height)
    r_shaft, r_base = Float64(thickness), Float64(base_radius)
    # The profile is parametrised over u ∈ [0,1] in THREE zones — shaft, the
    # flat annular shoulder, head — and the middle one is exactly ONE sample
    # step wide. That is what puts a ring of samples ON the shoulder, so the
    # head really is `base_radius` wide instead of one step short of it.
    nu = max(resolution[1], 4)
    step = 1 / (nu - 1)
    u_shoulder = clamp(round(Int, 0.5 * (nu - 1)), 1, nu - 2) * step
    u_head = u_shoulder + step
    function profile(u)
        u <= u_shoulder && return (u / u_shoulder * shoulder, r_shaft)
        u <= u_head && return (shoulder,
                               r_shaft + (u - u_shoulder) / step * (r_base - r_shaft))
        t = (u - u_head) / (1 - u_head)
        return (shoulder + t * Float64(height), r_base * (1 - t))
    end
    s = Surface((u, v) -> begin
                    z, r = profile(u)
                    (r * cos(v), r * sin(v), z)
                end;
                u_range = (0.0, 1.0), v_range = (0.0, TAU),
                resolution = (nu, resolution[2]), kw...)
    _aim_z_to!(s, d)
    shift!(s, a)
    return s
end

# ── the minimum of the Mobject interface that Scene/render need ────────

get_family(s::Surface) = Mobject[s]
has_points(s::Surface) = !isempty(s.points)
get_num_points(s::Surface) = length(s.points)
has_updaters(s::Surface) = !isempty(s.updaters)
get_updaters(s::Surface) = s.updaters
tag(::Surface) = :Surface

"""
The mesh's bounding box, in the same [mins, mids, maxs] shape a VMobject
gives. With this, every getter in bbox.jl — get_width, get_left, next_to!,
the layout verbs — works on a Surface too.
"""
function get_bounding_box(s::Surface)
    isempty(s.points) && return Point3f[ORIGIN, ORIGIN, ORIGIN]
    lo = reduce((a, b) -> min.(a, b), s.points)
    hi = reduce((a, b) -> max.(a, b), s.points)
    return Point3f[lo, (lo + hi) / 2, hi]
end

# One method per type, never an abstract signature on this path: the getters
# below are what `next_to!`, `rotate!` and the layout verbs call in their
# hot loops, and an abstract `::Mobject` here costs 272 bytes per call.
get_bounding_box_point(s::Surface, direction) = _bbox_point(get_bounding_box(s), direction)
get_center(s::Surface) = get_bounding_box(s)[2]
get_left(s::Surface)   = get_bounding_box_point(s, LEFT)
get_right(s::Surface)  = get_bounding_box_point(s, RIGHT)
get_top(s::Surface)    = get_bounding_box_point(s, UP)
get_bottom(s::Surface) = get_bounding_box_point(s, DOWN)
length_over_dim(s::Surface, dim::Int) = _dim_length(get_bounding_box(s), dim)
get_width(s::Surface)  = length_over_dim(s, 1)
get_height(s::Surface) = length_over_dim(s, 2)
get_depth(s::Surface)  = length_over_dim(s, 3)

# Same body as the VMobject method, on this type.
function move_to!(s::Surface, target; aligned_edge = ORIGIN, coor_mask = (1, 1, 1))
    dest = target isa Mobject ? get_bounding_box_point(target, aligned_edge) :
              Point3f(target)
    anchor = get_bounding_box_point(s, aligned_edge)
    shift!(s, (dest - anchor) .* Point3f(coor_mask))
end

function shift!(s::Surface, delta)
    d = Point3f(delta)
    s.points .+= Ref(d)
    s.d_normal_points .+= Ref(d)
    return s
end

"scale!(s, factor; about_point=centre): points AND d_normal_points, like a TexturedSurface."
function scale!(s::Surface, factor::Real; about_point = nothing)
    c = SVector{3,Float64}(something(about_point, get_center(s)))
    for arr in (s.points, s.d_normal_points)
        @inbounds for i in eachindex(arr)
            arr[i] = Point3f(c + factor * (SVector{3,Float64}(arr[i]) - c))
        end
    end
    return s
end

"rotate!(s, angle; axis=OUT, about_point=centre): points AND d_normal_points."
function rotate!(s::Surface, angle::Real; axis = OUT, about_point = nothing)
    c = SVector{3,Float64}(something(about_point, get_center(s)))
    R = rotation_matrix(angle, axis)
    for arr in (s.points, s.d_normal_points)
        @inbounds for i in eachindex(arr)
            arr[i] = Point3f(R * (SVector{3,Float64}(arr[i]) - c) + c)
        end
    end
    return s
end

"""
    stretch!(s, factor, dim; about_point = centre)

Scale a surface along ONE axis — points and `d_normal_points`, like the two
above. The reason is worth a line: a `Prism` is a `Cube` stretched per axis,
and `Group`'s `stretch!` forwards only to members that ANSWER (`_can`); a
`Surface` without this verb would leave the mesh `Prism` 2 × 2 × 2 with no
error at all. A verb a container silently skips is worse than one that is
missing.

The normal points ride along, so a stretched surface still lights from its
own geometry; a non-uniform stretch tilts those normals exactly as it tilts
the surface, which is what GL's `apply_points_function` does too.
"""
function stretch!(s::Surface, factor::Real, dim::Int; about_point = nothing)
    1 <= dim <= 3 || throw(ArgumentError("dim is 1, 2 or 3 (x, y, z), got $dim"))
    c = Float64(something(about_point, get_center(s))[dim])
    for arr in (s.points, s.d_normal_points)
        @inbounds for i in eachindex(arr)
            p = arr[i]
            arr[i] = Point3f(ntuple(k -> k == dim ? c + factor * (Float64(p[k]) - c) :
                                         Float64(p[k]), 3))
        end
    end
    return s
end

set_opacity!(s::Surface, op::Real) = set_color!(s; opacity = op)

function set_color!(s::Surface; color = nothing, opacity = nothing)
    for i in eachindex(s.rgba)
        base = color === nothing ? s.rgba[i] : _rgba(color, 1)
        a = opacity === nothing ? s.rgba[i][4] : Float32(opacity)
        s.rgba[i] = Vec4f(base[1], base[2], base[3], a)
    end
    return s
end

"The shading (reflectiveness, gloss, shadow) of finalize_color."
set_shading!(s::Surface; reflectiveness = nothing, gloss = nothing, shadow = nothing) =
    (s.shading = (Float32(something(reflectiveness, s.shading[1])),
                  Float32(something(gloss, s.shading[2])),
                  Float32(something(shadow, s.shading[3]))); s)

function set_shading!(m::VMobject; reflectiveness = nothing, gloss = nothing, shadow = nothing)
    for sub in get_family(m)
        sub isa VMobject || continue
        sub.shading = (Float32(something(reflectiveness, sub.shading[1])),
                       Float32(something(gloss, sub.shading[2])),
                       Float32(something(shadow, sub.shading[3])))
    end
    return m
end

"GL's apply_depth_test: the mobject (and its family) joins the z-buffer."
apply_depth_test!(s::Surface; value::Bool = true) = (s.depth_test = value; s)
function apply_depth_test!(m::VMobject; value::Bool = true)
    for sub in get_family(m)
        sub isa VMobject && (sub.depth_test = value)
    end
    return m
end

"GL's fix_in_frame: ignore the camera (HUD, formulas pinned to the screen)."
fix_in_frame!(s::Surface; value::Bool = true) = (s.fixed_in_frame = value; s)
function fix_in_frame!(m::VMobject; value::Bool = true)
    for sub in get_family(m)
        sub isa VMobject && (sub.fixed_in_frame = value)
    end
    return m
end

function update!(s::Surface, dt::Real)
    s.updating_suspended && return s
    for u in s.updaters
        u.takes_dt ? u.func(s, dt) : u.func(s)
    end
    return s
end

function add_updater!(s::Surface, f; call::Bool = true, parallel::Bool = false)
    push!(s.updaters, Updater(f; parallel))
    call && update!(s, 0.0)
    return s
end

# ═══════════════════════════════════════════════════════════════════════
# The two 3D groups
# ═══════════════════════════════════════════════════════════════════════

"""
    VGroup3D(vmobs...; depth_test=true, shading=(0.2,0.2,0.2), joint_type=:no_joint)

A [`VGroup`](@ref) whose members are set up to live in three dimensions:

```julia
faces = VGroup3D(front, back, left, right, top, bottom)
```

The three settings are what a flat `VGroup` does NOT do by default, and each
one fixes a specific thing that goes wrong when flat geometry is put in space:

  - `depth_test` — without it the members draw in list order and a face behind
    another one still paints over it.
  - `shading` — `(reflectiveness, gloss, shadow)`; a 2D mobject is flat-lit,
    and in space that reads as a paper cut-out.
  - `joint_type = :no_joint` — the stroke's corner join is computed in screen
    space, so on a polygon seen edge-on it flares. Turning it off is what
    ManimGL does, measured: its `VGroup3D` writes `joint_type = 0` into every
    member (the shader's uniform, not the constructor attribute — reading the
    attribute says `auto` and is a false reading).

All three recurse into the members, and all three are plain keywords, so
`VGroup3D(...; depth_test = false)` is how you take one back.
"""
const VGroup3D = VMobject{:VGroup3D}

function (::Type{VGroup3D})(vmobs::Mobject...; depth_test::Bool = true,
                            shading::NTuple{3,<:Real} = (0.2, 0.2, 0.2),
                            joint_type::Symbol = :no_joint, kw...)
    g = vmob(:VGroup3D; kw...)
    isempty(vmobs) || add!(g, vmobs...)
    set_shading!(g; reflectiveness = shading[1], gloss = shading[2],
                 shadow = shading[3])
    set_joint_type!(g, joint_type)
    depth_test && apply_depth_test!(g)
    return g
end

# SGroup (ManimGL) is NOT here, and the reason is measured rather than
# aesthetic: `get_family(s::Surface) = Mobject[s]` — a Surface in Janim has no
# family at all. GL's SGroup is a Surface that CONTAINS surfaces, so porting it
# means teaching Surface to recurse, and that walk is shared by the draw
# pipeline and by all three surface verbs (`set_shading!`, `apply_depth_test!`,
# `fix_in_frame!`). That is a mechanism, not a composition.
#
# What covers the use is `Group`: it holds and moves a set of surfaces as one
# and propagates `set_shading!`, `apply_depth_test!`, `fix_in_frame!`,
# `set_opacity!` and `set_color!` to the members that answer. `Cube` below is
# exactly that — GL's SGroup of six squares, held in a Group instead of in a
# Surface.

# ═══════════════════════════════════════════════════════════════════════
# Polyhedra
# ═══════════════════════════════════════════════════════════════════════
# Manim CE's Polyhedron (the OFF format: vertices + faces by index) and the
# platonic solids over it, plus ManimGL's cube family. All of them are
# VGroup3D — flat polygons that need depth testing and shading to read as a
# solid, which is exactly what that group is for.
#
# ONE DELIBERATE DIFFERENCE FROM CE, and it is measured: CE's Polyhedron also
# carries a `Graph` of dots and edges, and those dots have a FIXED pixel size.
# The consequence is that CE's solids do not scale linearly — probed,
# Tetrahedron(edge_length=2) comes out 1.815× the width of edge_length=1, not
# 2×. Janim's are the faces alone, so `edge_length` means what it says. Add
# the vertex markers yourself if you want them.

"""
    Polyhedron(vertices, faces; ...)

A solid given the way a `.off` file gives one: a list of vertex coordinates
and a list of faces, each face being the INDICES of its corners.

```julia
pyramid = Polyhedron([( 1,  1, 0), ( 1, -1, 0), (-1, -1, 0), (-1, 1, 0),
                      ( 0,  0, 2)],
                     [[1, 2, 5], [2, 3, 5], [3, 4, 5], [4, 1, 5], [1, 2, 3, 4]])
```

Indices are 1-based, as everything else in Julia is. Each face becomes a
[`Polygon`](@ref) and the whole thing is a [`VGroup3D`](@ref), so it is depth
tested and shaded from the start.

It is the mechanism under [`Tetrahedron`](@ref), [`Octahedron`](@ref),
[`Icosahedron`](@ref) and [`Dodecahedron`](@ref); reach for it directly when
your solid is not one of those.
"""
const Polyhedron = VMobject{:Polyhedron}

function (::Type{Polyhedron})(vertices, faces;
                              fill_color = BLUE_D, fill_opacity::Real = 1.0,
                              stroke_color = BLUE_E, stroke_width::Real = 1.0,
                              shading::NTuple{3,<:Real} = (0.2, 0.2, 0.2),
                              depth_test::Bool = true, kw...)
    vs = Point3f[Point3f(v) for v in vertices]
    isempty(faces) && throw(ArgumentError("a polyhedron needs at least one face"))
    polys = VMobject[]
    for (k, f) in enumerate(faces)
        length(f) >= 3 || throw(ArgumentError(
            "face $k has $(length(f)) corners and a face needs 3"))
        for i in f
            1 <= i <= length(vs) || throw(ArgumentError(
                "face $k refers to vertex $i and there are $(length(vs)) — " *
                "the indices are 1-based"))
        end
        p = Polygon(Point3f[vs[i] for i in f]...;
                    fill_color, fill_opacity, stroke_color, stroke_width)
        push!(polys, p)
    end
    g = vmob(:Polyhedron; kw...)
    add!(g, polys...)
    set_shading!(g; reflectiveness = shading[1], gloss = shading[2],
                 shadow = shading[3])
    set_joint_type!(g, :no_joint)
    depth_test && apply_depth_test!(g)
    return g
end

# The four platonic solids CE ships, with CE's vertex tables. `edge_length` is
# the distance between two adjacent vertices — probed: Tetrahedron(1) has
# |v1 - v2| = 1.0 exactly.

"""
    Tetrahedron(; edge_length = 1)

Four triangles, six edges, four vertices — the simplest platonic solid.

```julia
t = Tetrahedron(; edge_length = 2)
reorient!(scene.frame, 30.0, 70.0)
```

`edge_length` is the distance between two adjacent vertices, and unlike Manim
CE's the solid scales linearly with it (CE's carries fixed-size vertex dots
that do not — measured, 1.815× instead of 2×).
"""
function Tetrahedron(; edge_length::Real = 1.0, kw...)
    u = edge_length * sqrt(2) / 4
    return Polyhedron([(u, u, u), (u, -u, -u), (-u, u, -u), (-u, -u, u)],
                      [[1, 2, 3], [4, 1, 3], [1, 2, 4], [4, 2, 3]]; kw...)
end

"""
    Octahedron(; edge_length = 1)

Eight triangles, twelve edges, six vertices — the solid whose corners sit on
the three axes.
"""
function Octahedron(; edge_length::Real = 1.0, kw...)
    u = edge_length / sqrt(2)
    return Polyhedron([(u, 0, 0), (-u, 0, 0), (0, u, 0),
                       (0, -u, 0), (0, 0, u), (0, 0, -u)],
                      [[3, 5, 2], [1, 5, 3], [5, 4, 1], [2, 4, 5],
                       [4, 6, 1], [2, 6, 4], [3, 6, 2], [1, 6, 3]]; kw...)
end

"""
    Icosahedron(; edge_length = 1)

Twenty triangles, thirty edges, twelve vertices. Its coordinates are the
golden ratio's: three orthogonal rectangles of sides 1 and φ.
"""
function Icosahedron(; edge_length::Real = 1.0, kw...)
    φ = (1 + sqrt(5)) / 2
    a, b = edge_length / 2, edge_length * φ / 2
    return Polyhedron([(0, a, b), (0, -a, b), (0, a, -b), (0, -a, -b),
                       (a, b, 0), (a, -b, 0), (-a, b, 0), (-a, -b, 0),
                       (b, 0, a), (b, 0, -a), (-b, 0, a), (-b, 0, -a)],
                      [[2, 9, 1], [2, 6, 8], [9, 6, 2], [8, 4, 6], [6, 10, 4],
                       [9, 10, 6], [4, 3, 10], [10, 5, 3], [9, 5, 10], [1, 5, 9],
                       [7, 5, 1], [7, 3, 5], [12, 3, 7], [4, 12, 3], [1, 7, 11],
                       [11, 2, 1], [11, 8, 2], [12, 8, 4], [11, 12, 8],
                       [11, 12, 7]]; kw...)
end

"""
    Dodecahedron(; edge_length = 1)

Twelve pentagons, thirty edges, twenty vertices.

Both engines have this one and they DISAGREE on the size, because they
parameterise it differently: Manim CE takes an `edge_length` (this signature),
while ManimGL builds it straight from the golden ratio at a fixed circumradius
of √3 ≈ 1.7321 — measured, GL's comes out 3.2361 wide against CE's 2.7780 at
`edge_length = 1`. Janim follows CE here so that the four platonic solids
share one parameter and can be compared with each other; for GL's exact size
ask for `edge_length = 1.1656` (√3 / 1.4859, its circumradius ratio).
"""
function Dodecahedron(; edge_length::Real = 1.0, kw...)
    φ = (1 + sqrt(5)) / 2
    a, b, c = edge_length * φ / 2, edge_length / 2, edge_length * φ^2 / 2
    return Polyhedron([(a, a, a), (a, a, -a), (a, -a, a), (a, -a, -a),
                       (-a, a, a), (-a, a, -a), (-a, -a, a), (-a, -a, -a),
                       (0, b, c), (0, b, -c), (0, -b, -c), (0, -b, c),
                       (b, c, 0), (-b, c, 0), (b, -c, 0), (-b, -c, 0),
                       (c, 0, b), (-c, 0, b), (c, 0, -b), (-c, 0, -b)],
                      [[19, 17, 1, 13, 2], [4, 19, 17, 3, 15],
                       [4, 11, 10, 2, 19], [2, 10, 6, 14, 13],
                       [1, 9, 5, 14, 13], [3, 17, 1, 9, 12],
                       [5, 18, 7, 12, 9], [18, 20, 6, 14, 5],
                       [20, 8, 16, 7, 18], [7, 16, 15, 3, 12],
                       [20, 6, 10, 11, 8], [8, 11, 4, 15, 16]]; kw...)
end

"""
    Square3D(; side_length = 2, resolution = (2, 2), color, opacity, shading)

A flat square as a MESH — ManimGL's `Square3D` (`three_dimensions.py:237`),
the face [`Cube`](@ref) is built from.

```julia
Square3D(; side_length = 3, color = BLUE)
```

It is a [`Surface`](@ref) over `(u, v) ↦ (u, v, 0)` on `(-1, 1)²`, scaled to
`side_length / 2`, so it costs one mesh draw instead of a fill pass — which
is the whole point: six of these are a cube that never touches the winding
pipeline.
"""
function Square3D(; side_length::Real = 2.0, resolution::NTuple{2,Int} = (2, 2),
                  color = GREY_C, opacity::Real = 1.0,
                  shading::NTuple{3,<:Real} = (0.3, 0.2, 0.4), kw...)
    s = Surface((u, v) -> (u, v, 0.0); u_range = (-1.0, 1.0), v_range = (-1.0, 1.0),
                resolution, color, opacity, shading, kw...)
    return scale!(s, Float64(side_length) / 2)
end

"""
GL's `square_to_cube_faces` (`three_dimensions.py:258`): the +Z face, then
four quarter-turns about the compass directions, then the half-turn that
gives −Z. The order is GL's and the probe agrees with it face for face:
`+Z, −Y, +X, +Y, −X, −Z`.
"""
function _square_to_cube_faces(square::Surface)
    radius = get_height(square) / 2
    move_to!(square, Float32(radius) * Point3f(OUT))
    faces = Mobject[copy(square)]
    for vect in compass_directions(4)
        push!(faces, rotate!(copy(square), PI / 2; axis = vect, about_point = ORIGIN))
    end
    push!(faces, rotate!(copy(square), PI; axis = RIGHT, about_point = ORIGIN))
    return faces
end

"""
    Cube(; side_length = 2, color = BLUE, opacity = 1, shading = (0.1, 0.5, 0.1),
           square_resolution = (2, 2))

Six square MESHES — ManimGL's `Cube` (`three_dimensions.py:270`), probed:
2 × 2 × 2 centred on the origin, faces `#58C4DD` at full opacity, shading
`(0.1, 0.5, 0.1)`, depth-tested.

```julia
c = Cube(; side_length = 3, color = TEAL)
reorient!(scene.frame, 30.0, 70.0)
```

As in ManimGL, a `Cube` is six `Square3D` surfaces; the six-polygon version
is [`VCube`](@ref). The difference is not cosmetic: a filled polygon pays a
whole fill pass (two framebuffer switches, a clear and a quad) for every face,
while a mesh is one draw. That per-face skeleton is what remained of a
9455-face scene's cost once the per-mobject overhead was cached; a mesh
removes it.

A `Cube` is a [`Group`](@ref), so it MOVES, scales, shades and depth-tests as
one — what it has no notion of is fill and stroke, because a mesh has a single
colour. `set_color!(c; color, opacity)` is the verb; `set_fill!` says so.
`VCube` keeps the vector behaviour for anything that needs a stroke, an
outline, or `Transform` against a flat shape.
"""
function Cube(; side_length::Real = 2.0, color = BLUE, opacity::Real = 1.0,
              shading::NTuple{3,<:Real} = (0.1, 0.5, 0.1),
              square_resolution::NTuple{2,Int} = (2, 2),
              depth_test::Bool = true, kw...)
    _check_no_vector_style(:Cube, kw)
    face = Square3D(; side_length, resolution = square_resolution, color, opacity,
                    shading, depth_test)
    return Group(_square_to_cube_faces(face)...)
end

"""
A `Cube` of meshes cannot take the vector style words, and saying which verb
to use beats a `MethodError` about a keyword nobody names in a docstring.
"""
function _check_no_vector_style(what::Symbol, kw)
    for k in (:fill_color, :fill_opacity, :stroke_color, :stroke_width, :stroke_opacity)
        haskey(kw, k) && throw(ArgumentError(
            "$what is built from MESHES, and a mesh has one colour: " *
            "no $k. Use `color =` and `opacity =` (ManimGL's own spelling), " *
            "or ask for `V$what`, the six-polygon version, which takes it."))
    end
    return nothing
end

"""
    VCube(; side_length = 2)

Six square POLYGONS — ManimGL's `VCube`, and Manim CE's `Cube`. Probed in GL:
2 × 2 × 2, centred on the origin, faces filled `BLUE_D` with no stroke.

```julia
c = VCube(; side_length = 3, stroke_width = 2)
```

The six-polygon cube, ManimGL's `VCube`. Reach for it when the
faces need a stroke, when they have to `Transform` against flat shapes, or
when you want the fill pipeline's look; reach for `Cube` when you want GL's,
and its speed.
"""
const VCube = VMobject{:VCube}

function (::Type{VCube})(; side_length::Real = 2.0, fill_color = BLUE_D,
                         fill_opacity::Real = 1.0, stroke_width::Real = 0.0,
                         shading::NTuple{3,<:Real} = (0.2, 0.2, 0.2),
                         depth_test::Bool = true, kw...)
    r = Float64(side_length) / 2
    faces = VMobject[]
    for (axis, sign) in ((3, 1), (2, -1), (1, 1), (2, 1), (1, -1), (3, -1))
        sq = Square(; side_length, fill_color, fill_opacity, stroke_width)
        axis == 1 && rotate!(sq, PI / 2; axis = UP, about_point = ORIGIN)
        axis == 2 && rotate!(sq, PI / 2; axis = RIGHT, about_point = ORIGIN)
        shift!(sq, Point3f(ntuple(i -> i == axis ? sign * r : 0.0, 3)))
        push!(faces, sq)
    end
    g = vmob(:VCube; kw...)
    add!(g, faces...)
    set_shading!(g; reflectiveness = shading[1], gloss = shading[2],
                 shadow = shading[3])
    set_joint_type!(g, :no_joint)
    depth_test && apply_depth_test!(g)
    return g
end

"""
    Prism(; width = 3, height = 2, depth = 1)

A [`Cube`](@ref) stretched to a box. ManimGL's `Prism(Cube)`, whose defaults
these are (probed: 3 × 2 × 1), so it is six meshes.

```julia
Prism(; width = 4, height = 1, depth = 2)
```

[`VPrism`](@ref) is the same box built from polygons.
"""
function Prism(; width::Real = 3.0, height::Real = 2.0, depth::Real = 1.0, kw...)
    c = Cube(; kw...)
    set_width!(c, width; stretch = true)
    set_height!(c, height; stretch = true)
    set_depth!(c, depth; stretch = true)
    return c
end

"""
    VPrism(; width = 3, height = 2, depth = 1)

A [`VCube`](@ref) stretched to a box — the polygon prism.
"""
function VPrism(; width::Real = 3.0, height::Real = 2.0, depth::Real = 1.0, kw...)
    c = VCube(; kw...)
    set_width!(c, width; stretch = true)
    set_height!(c, height; stretch = true)
    set_depth!(c, depth; stretch = true)
    return c
end

"""
    Prismify(flat; depth = 1, direction = IN)

Extrude a flat shape into a solid by sweeping it `depth` units along
`direction` and walling in the sides:

```julia
Prismify(Triangle(); depth = 0.5)
Prismify(RegularPolygon(6); depth = 2, direction = OUT)
```

The result is a [`VGroup3D`](@ref) holding the original face, one wall per
edge and the far face. ManimGL's, and its assumption too: the edges are taken
as STRAIGHT, so a shape with curved sides gets walls built from its anchors
and the curve is lost on the way up.

One difference from GL, and it is deliberate: a closed shape repeats its first
anchor, so GL builds one extra wall of zero area (a `Square` gives it seven
pieces where six are real). Degenerate walls are skipped here — they draw
nothing and only make the family longer to walk.
"""
const Prismify = VMobject{:Prismify}

function (::Type{Prismify})(flat::VMobject; depth::Real = 1.0, direction = IN,
                            shading::NTuple{3,<:Real} = (0.2, 0.2, 0.2),
                            depth_test::Bool = true, kw...)
    has_points(flat) || throw(ArgumentError(
        "Prismify needs a shape with points — a group has none of its own"))
    vect = Float32(depth) * Point3f(direction)
    anchors = get_anchors(flat)
    pieces = VMobject[copy(flat)]
    for i in 1:length(anchors)
        p1, p2 = anchors[i], anchors[mod1(i + 1, length(anchors))]
        # The closing repeat of a closed path gives a zero-area wall.
        sum(abs2, p2 - p1) < 1.0f-12 && continue
        wall = vmob(:Polygon)
        match_style!(wall, flat)
        set_points_as_corners!(wall, (p1, p2, p2 + vect, p1 + vect, p1))
        push!(pieces, wall)
    end
    top = copy(flat)
    shift!(top, vect)
    push!(pieces, top)
    g = vmob(:Prismify; kw...)
    add!(g, pieces...)
    set_shading!(g; reflectiveness = shading[1], gloss = shading[2],
                 shadow = shading[3])
    set_joint_type!(g, :no_joint)
    depth_test && apply_depth_test!(g)
    return g
end

# ═══════════════════════════════════════════════════════════════════════
# The interpolation contract, and the two verbs it needs
# ═══════════════════════════════════════════════════════════════════════
# Geometry and colour interpolate; the meshes must match, as
# for `TexturedSurface`; the flags (`depth_test`, `shading`, `fixed_in_frame`)
# stay the destination's, as they do for a VMobject.

"The vertices — the LIVE vector, like a DotCloud's."
get_points(s::Surface) = s.points

"""
    set_points!(surface, pts)

Replace the vertices, same count. Each normal point moves with its vertex
(exact for a translation, a fair approximation for anything else). A
different count needs a new `Surface(f; resolution = …)`: the mesh and the
normals come from the sampling.
"""
function set_points!(s::Surface, pts)
    n = length(pts)
    n == length(s.points) || throw(ArgumentError(
        "set_points!(::Surface): $n points for a mesh of $(length(s.points)) " *
        "($(s.resolution[1])×$(s.resolution[2])) — the count comes from " *
        "`resolution`; build a new Surface for a different one"))
    @inbounds for i in 1:n
        q = Point3f(pts[i])
        s.d_normal_points[i] = q + (s.d_normal_points[i] - s.points[i])
        s.points[i] = q
    end
    return s
end

is_interpolable(::Surface) = true

Base.copy(s::Surface) =
    Surface(copy(s.points), copy(s.d_normal_points), copy(s.rgba), s.resolution,
            copy(s.indices), s.shading, s.depth_test, s.fixed_in_frame,
            Mobject[], Mobject[], copy(s.updaters), s.updating_suspended, s.z_index)

function interpolate!(d::Surface, a::Surface, b::Surface, α::Real)
    length(a.points) == length(b.points) || throw(ArgumentError(
        "cannot interpolate Surfaces of different resolutions " *
        "($(a.resolution) vs $(b.resolution))"))
    length(d.points) == length(a.points) || become!(d, a)
    t = Float32(α)
    @inbounds for i in eachindex(d.points)
        d.points[i] = a.points[i] + t * (b.points[i] - a.points[i])
        d.d_normal_points[i] = a.d_normal_points[i] +
                               t * (b.d_normal_points[i] - a.d_normal_points[i])
        d.rgba[i] = a.rgba[i] + t * (b.rgba[i] - a.rgba[i])
    end
    return d
end

function become!(d::Surface, s::Surface)
    d.points = copy(s.points)
    d.d_normal_points = copy(s.d_normal_points)
    d.rgba = copy(s.rgba)
    d.resolution = s.resolution
    d.indices = copy(s.indices)
    return d
end

# what a VGroup asks of a member that is not a VMobject (bbox.jl, transforms.jl)
_leaf_bounding_box(s::Surface) = has_points(s) ? get_bounding_box(s) : nothing
_apply_leaf_points!(f, s::Surface, ap) =
    (_apply!(f, s.points, ap); _apply!(f, s.d_normal_points, ap); nothing)

"""
    ParametricSurface(uv_func; u_range, v_range, resolution, …)

ManimGL's name for exactly this — an alias of [`Surface`](@ref).

The two engines split the word differently: GL's `Surface` is the ABSTRACT
base (its `uv_func` is a method to override, and `Surface(f)` raises), and
`ParametricSurface(uv_func, …)` is the concrete one that takes a function
(`surface.py:268`). Janim's `Surface` has always been the concrete one, so
both names name it, and a `.py` that says `ParametricSurface` translates
straight across.
"""
const ParametricSurface = Surface
