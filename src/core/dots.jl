# core/dots.jl — DotCloud: a point-cloud render primitive.
#
# A point cloud drawn as camera-facing discs by the `true_dot` shader
# (backend/wgpu/shaders/true_dot.wgsl, ported from ManimGL): per-point
# position, radius and rgba; glow as a per-fragment falloff — no extra
# passes, unlike the Bloom layer effect; an optional fake-sphere shading mode
# (`make_3d!`).
#
# Design decisions:
#   · `points::Vector{Point3f}` — `reinterpret` gives the GPU a 3×n Float32
#     view with zero copies, and updaters mutate IN PLACE (`get_points(dc)`
#     hands out the live vector on purpose: the upload is per-frame anyway).
#   · Naive upload each frame (~32 MB/frame at 1M points, measured 1–3 ms).
#     If a scene outgrows that, a persistent GPU buffer is the next step —
#     not before it hurts.
#   · The bounding box is LAZY: computed on demand from the points (plus the
#     max radius, like ManimGL). On a million points that is an O(n) sweep —
#     fine for layout calls, deliberately not maintained incrementally.
#   · `Transform` only between clouds of the SAME size: pointwise lerp.
#     Aligning clouds of different sizes is a design question (spawn where?
#     kill which?) that is refused rather than answered silently.

const DEFAULT_TRUE_DOT_RADIUS = 0.05      # dot_cloud.py's DEFAULT_DOT_RADIUS
const DEFAULT_GLOW_DOT_RADIUS = 0.2

"""
    DotCloud(points; color=GREY_C, opacity=1.0, radius=0.05,
             glow_factor=0.0, anti_alias_width=2.0)

A cloud of `length(points)` discs, one draw call however many there are.
`radius` is in scene units. `glow_factor > 0` turns each disc into a soft
falloff (`GlowDots` is the preset). Updaters mutate `get_points(dc)` in
place — that IS the intended idiom for particle systems.
"""
mutable struct DotCloud <: Mobject
    points::Vector{Point3f}
    radii::Vector{Float32}          # per point, like GL's data["radius"]
    rgba::Vector{Vec4f}             # per point, like GL's data["rgba"]
    glow_factor::Float64
    anti_alias_width::Float64
    shading::NTuple{3,Float32}
    depth_test::Bool
    fixed_in_frame::Bool
    submobjects::Vector{Mobject}
    parents::Vector{Mobject}
    updaters::Vector{Updater}
    updating_suspended::Bool
    z_index::Float64                # draw order — an attribute of every mobject (GL)
end

function DotCloud(points::AbstractVector; color = GREY_C, opacity::Real = 1.0,
                  radius::Real = DEFAULT_TRUE_DOT_RADIUS,
                  glow_factor::Real = 0.0, anti_alias_width::Real = 2.0)
    pts = Point3f[Point3f(p) for p in points]
    n = length(pts)
    DotCloud(pts, fill(Float32(radius), n), fill(_rgba(color, opacity), n),
             Float64(glow_factor), Float64(anti_alias_width),
             (0f0, 0f0, 0f0), false, false,
             Mobject[], Mobject[], Updater[], false, 0.0)
end
DotCloud(; kw...) = DotCloud(Point3f[]; kw...)

"TrueDot(center) — one honest disc (ManimGL's name for the shader too)."
TrueDot(center = ORIGIN; kw...) = DotCloud([Point3f(center)]; kw...)

"GlowDots(points) — the glow preset: bigger radius, `pow(1-r, 2)` falloff."
GlowDots(points::AbstractVector = Point3f[]; color = YELLOW,
         radius::Real = DEFAULT_GLOW_DOT_RADIUS, glow_factor::Real = 2.0,
         kw...) = DotCloud(points; color, radius, glow_factor, kw...)

"GlowDot(center) — one glowing point."
GlowDot(center = ORIGIN; kw...) = GlowDots([Point3f(center)]; kw...)

tag(::DotCloud) = :DotCloud
Base.show(io::IO, m::DotCloud) =
    print(io, "DotCloud(", length(m.points), " points, r≈",
          round(get_radius(m); digits = 3),
          m.glow_factor > 0 ? ", glow=$(m.glow_factor)" : "", ")")

# ── points (the PMobject face) ──────────────────────────────────────────

has_points(m::DotCloud) = !isempty(m.points)
get_num_points(m::DotCloud) = length(m.points)
"The LIVE vector — mutate it from an updater; the next frame uploads it."
get_points(m::DotCloud) = m.points

"""
    set_points!(dc, points)

Replaces the cloud. If the count changes, radii and colours keep their
first `n` entries and REPEAT the last one to fill (empty cloud: the
defaults) — the simple rule, stated, instead of GL's silent interpolation.
"""
function set_points!(m::DotCloud, points::AbstractVector)
    pts = Point3f[Point3f(p) for p in points]
    n = length(pts)
    _refit!(v, fallback) = begin
        isempty(v) ? fill(fallback, n) :
        n <= length(v) ? v[1:n] : vcat(v, fill(v[end], n - length(v)))
    end
    m.radii = _refit!(m.radii, Float32(DEFAULT_TRUE_DOT_RADIUS))
    m.rgba = _refit!(m.rgba, _rgba(GREY_C, 1.0))
    m.points = pts
    return m
end

# ── style ───────────────────────────────────────────────────────────────

"""
    set_radius!(cloud, r)

Give every dot in the cloud the same radius, in scene units. For one radius per
dot, [`set_radii!`](@ref).
"""
set_radius!(m::DotCloud, r::Real) = (fill!(m.radii, Float32(r)); m)

"""
    set_radii!(cloud, rs)

Give the dots individual radii — one per point, and the lengths must match or
it throws.

This is how a particle system shows a scalar: mass, speed, charge. The radii
live in their own array, so writing them from an updater does not touch the
positions.
"""
function set_radii!(m::DotCloud, rs::AbstractVector)
    length(rs) == length(m.points) || throw(ArgumentError(
        "set_radii!: $(length(rs)) radii for $(length(m.points)) points"))
    m.radii .= Float32.(rs)
    return m
end
"""
    get_radii(cloud) → Vector{Float32}

The per-dot radii, live — writing into this vector changes the cloud, with no
copy in between. That is deliberate: a million-particle updater cannot afford
one.
"""
get_radii(m::DotCloud) = m.radii

"""
    get_radius(cloud) → Float64

The LARGEST radius in the cloud (`0.0` when it is empty) — the single number
that answers "how big are these dots", which is what a uniform cloud has
anyway.
"""
get_radius(m::DotCloud) = isempty(m.radii) ? 0.0 : Float64(maximum(m.radii))

"""
    scale_radii!(cloud, f)

Multiply every radius by `f`, leaving the positions alone.

Note that [`scale!`](@ref) on a cloud moves the POINTS — it spreads the
particles apart without making them bigger. These are two different operations
and the pair of names is the only warning you get.
"""
scale_radii!(m::DotCloud, f::Real) = (m.radii .*= Float32(f); m)

"""
    set_glow_factor!(cloud, g)

How sharply a glowing dot falls off towards its edge. `0` is a flat disc; the
bigger the number, the more the brightness concentrates in the centre and the
softer the halo — which is what makes [`GlowDots`](@ref) read as light rather
than as paint.
"""
set_glow_factor!(m::DotCloud, g::Real) = (m.glow_factor = Float64(g); m)

"""
    get_glow_factor(cloud) → Float64

The cloud's current glow falloff. See [`set_glow_factor!`](@ref).
"""
get_glow_factor(m::DotCloud) = m.glow_factor

function set_color!(m::DotCloud; color = nothing, opacity = nothing)
    for i in eachindex(m.rgba)
        row = m.rgba[i]
        rgb = color === nothing ? row : _rgba(color, 1)
        a = opacity === nothing ? row[4] : Float32(opacity)
        m.rgba[i] = Vec4f(rgb[1], rgb[2], rgb[3], a)
    end
    return m
end
set_opacity!(m::DotCloud, op::Real) = set_color!(m; opacity = op)
get_opacity(m::DotCloud) = isempty(m.rgba) ? 1.0 : Float64(m.rgba[1][4])

"Per-point colours (e.g. a colormap over speeds). Lengths must match."
function set_colors!(m::DotCloud, colors::AbstractVector; opacity = nothing)
    length(colors) == length(m.points) || throw(ArgumentError(
        "set_colors!: $(length(colors)) colours for $(length(m.points)) points"))
    for i in eachindex(m.rgba)
        a = opacity === nothing ? m.rgba[i][4] : Float32(opacity)
        c = _rgba(colors[i], 1)
        m.rgba[i] = Vec4f(c[1], c[2], c[3], a)
    end
    return m
end

"make_3d!(dc) — ManimGL's fake spheres: shading + the z-buffer."
function make_3d!(m::DotCloud; reflectiveness = 0.5, gloss = 0.1, shadow = 0.2)
    m.shading = (Float32(reflectiveness), Float32(gloss), Float32(shadow))
    m.depth_test = true
    return m
end

set_shading!(m::DotCloud; reflectiveness = nothing, gloss = nothing, shadow = nothing) =
    (m.shading = (Float32(something(reflectiveness, m.shading[1])),
                  Float32(something(gloss, m.shading[2])),
                  Float32(something(shadow, m.shading[3]))); m)
apply_depth_test!(m::DotCloud; value::Bool = true) = (m.depth_test = value; m)
fix_in_frame!(m::DotCloud; value::Bool = true) = (m.fixed_in_frame = value; m)

# ── bounding box (lazy, radius-expanded like GL) and the layout verbs ────

function get_bounding_box(m::DotCloud)
    isempty(m.points) && return Point3f[ORIGIN, ORIGIN, ORIGIN]
    lo = reduce((a, b) -> min.(a, b), m.points)
    hi = reduce((a, b) -> max.(a, b), m.points)
    r = Float32(get_radius(m))
    lo, hi = lo .- r, hi .+ r
    return Point3f[lo, (lo + hi) / 2, hi]
end
get_bounding_box_point(m::DotCloud, direction) =
    _bbox_point(get_bounding_box(m), direction)
get_center(m::DotCloud) = get_bounding_box(m)[2]

"""
    get_center_of_mass(dc::DotCloud) → Point3f

The mean of the cloud's own points — the one type where the name means exactly
what it says, since a [`DotCloud`](@ref)'s points ARE its dots and none of them
is a Bézier handle pulling the average somewhere nobody drew. See
[`get_center_of_mass`](@ref) for the VMobject case, where that caveat is the
whole story.
"""
function get_center_of_mass(m::DotCloud)
    n = 0
    sx = sy = sz = 0.0
    for mob in get_family(m)
        pts = mob isa DotCloud || mob isa VMobject ? mob.points : Point3f[]
        @inbounds for p in pts
            sx += p[1]; sy += p[2]; sz += p[3]
            n += 1
        end
    end
    n == 0 && return Point3f(ORIGIN)
    return Point3f(sx / n, sy / n, sz / n)
end

get_left(m::DotCloud)   = get_bounding_box_point(m, LEFT)
get_right(m::DotCloud)  = get_bounding_box_point(m, RIGHT)
get_top(m::DotCloud)    = get_bounding_box_point(m, UP)
get_bottom(m::DotCloud) = get_bounding_box_point(m, DOWN)
length_over_dim(m::DotCloud, dim::Int) = _dim_length(get_bounding_box(m), dim)
get_width(m::DotCloud)  = length_over_dim(m, 1)
get_height(m::DotCloud) = length_over_dim(m, 2)
get_depth(m::DotCloud)  = length_over_dim(m, 3)

# ── transforms (the image.jl pattern) ────────────────────────────

shift!(m::DotCloud, delta) = (d = Point3f(delta); m.points .+= Ref(d); m)

"scale! also scales the radii (GL parity); `scale_radii=false` opts out."
function scale!(m::DotCloud, factor::Real; about_point = nothing,
                scale_radii::Bool = true)
    c = SVector{3,Float64}(something(about_point, get_center(m)))
    f = Float64(factor)
    for i in eachindex(m.points)
        m.points[i] = Point3f(c + f * (SVector{3,Float64}(m.points[i]) - c))
    end
    scale_radii && (m.radii .*= Float32(abs(f)))
    return m
end

function rotate!(m::DotCloud, angle::Real; axis = OUT, about_point = nothing)
    c = SVector{3,Float64}(something(about_point, get_center(m)))
    R = rotation_matrix(Float64(angle), axis)
    for i in eachindex(m.points)
        m.points[i] = Point3f(c + R * (SVector{3,Float64}(m.points[i]) - c))
    end
    return m
end

function move_to!(m::DotCloud, target; aligned_edge = ORIGIN, coor_mask = (1, 1, 1))
    dest = target isa Mobject ? get_bounding_box_point(target, aligned_edge) :
              Point3f(target)
    anchor = get_bounding_box_point(m, aligned_edge)
    shift!(m, (dest - anchor) .* Point3f(coor_mask))
end

# ── updaters and the interpolation contract ─────────────────────────────

function update!(m::DotCloud, dt::Real)
    m.updating_suspended && return m
    for u in m.updaters
        u.takes_dt ? u.func(m, dt) : u.func(m)
    end
    return m
end
add_updater!(m::DotCloud, f; call::Bool = true, parallel::Bool = false) =
    (push!(m.updaters, Updater(f; parallel)); call && update!(m, 0.0); m)
has_updaters(m::DotCloud) = !isempty(m.updaters)
get_updaters(m::DotCloud) = m.updaters
# suspend_updating!/resume_updating!: the generic Mobject methods

is_interpolable(::DotCloud) = true

"Same size or a plain error — the decision stated in the header."
function align_data!(a::DotCloud, b::DotCloud)
    length(a.points) == length(b.points) || throw(ArgumentError(
        "Transform between DotClouds needs equal sizes " *
        "($(length(a.points)) vs $(length(b.points))): pointwise lerp is " *
        "all that is supported"))
    return a
end

function interpolate!(d::DotCloud, a::DotCloud, b::DotCloud, α::Real)
    t = Float32(α)
    for i in eachindex(d.points)
        d.points[i] = interpolate(a.points[i], b.points[i], α)
        d.radii[i] = (1 - t) * a.radii[i] + t * b.radii[i]
        d.rgba[i] = (1 - t) * a.rgba[i] + t * b.rgba[i]
    end
    d.glow_factor = a.glow_factor + Float64(α) * (b.glow_factor - a.glow_factor)
    return d
end

become!(d::DotCloud, s::DotCloud) =
    (d.points = copy(s.points); d.radii = copy(s.radii); d.rgba = copy(s.rgba);
     d.glow_factor = s.glow_factor; d.shading = s.shading;
     d.depth_test = s.depth_test; d)

Base.copy(m::DotCloud) =
    DotCloud(copy(m.points), copy(m.radii), copy(m.rgba), m.glow_factor,
             m.anti_alias_width, m.shading, m.depth_test, m.fixed_in_frame,
             Mobject[], Mobject[], copy(m.updaters), m.updating_suspended, m.z_index)

# ═══════════════════════════════════════════════════════════════════════
# PGroup
# ═══════════════════════════════════════════════════════════════════════

"""
    PGroup(clouds...)

A [`Group`](@ref) of point clouds, and nothing else:

```julia
sky = PGroup(GlowDots(stars), TrueDot.(planets)...)
shift!(sky, 2 * UP)               # the whole sky moves
```

`Group` would take these members anyway, so what `PGroup` adds is the DOOR: a
`Square` handed to it is an error naming the offending member, instead of a
group that renders one thing through the vector pipeline and the rest through
the points one and looks almost right. ManimGL's does exactly this and raises
too (measured: `PGroup(Square())` throws).

Use it when a scene mixes both kinds and you want the mistake to surface where
it is made rather than three transforms later.
"""
function PGroup(clouds::Mobject...)
    for (i, c) in enumerate(clouds)
        c isa DotCloud || throw(ArgumentError(
            "PGroup takes point clouds (DotCloud, TrueDot, GlowDots) and " *
            "member $i is a $(typeof(c)) — use Group for a mixed bag, or " *
            "VGroup when everything is vector geometry"))
    end
    return Group(clouds...)
end

# ── what a VGroup asks of a member that is not a VMobject ────────────
_leaf_bounding_box(m::DotCloud) = has_points(m) ? get_bounding_box(m) : nothing
_apply_leaf_points!(f, m::DotCloud, ap) = (_apply!(f, m.points, ap); nothing)
