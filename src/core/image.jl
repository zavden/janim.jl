# core/image.jl — raster assets as pure data. Nothing here touches the GPU:
# the backend samples `pixels` (backend/wgpu/).
#
# Two mobjects share the engine's sampled-texture piece (a texture in a
# mobject pass):
#
#   ImageMobject     a textured quad — 4 corner points transformed by the
#                    ordinary machinery, so shift!/rotate!/scale! just work
#   TexturedSurface  the Surface's uv mesh with the vertex colour replaced by a
#                    texture sample (manimgl's textured_surface pipeline)
#
# The pixel convention, stated once: `pixels` is 4×w×h RGBA8 with ROW 1 AT THE
# TOP — the layout a texture upload consumes, so the upload is one copy and
# uv (0,0) is the image's top-left corner.
#
# `pixels` is IMMUTABLE BY CONVENTION: `Base.copy` shares it (a texture can be
# megabytes and the texture cache is keyed by the array's identity — shared pixels
# = one texture on the GPU). To change the image, `set_pixels!` swaps the
# whole array, which the cache sees as a new texture.

using Colors: RGBA, red, green, blue, alpha
using FixedPointNumbers: N0f8
import PNGFiles

# ── decoding ────────────────────────────────────────────────────────────

"Colorant matrix (h×w, image convention) → our 4×w×h RGBA8, top row first."
function _pixels_from_matrix(img::AbstractMatrix)
    h, w = size(img)
    out = Array{UInt8,3}(undef, 4, w, h)
    @inbounds for j in 1:h, i in 1:w
        c = RGBA{N0f8}(img[j, i])
        out[1, i, j] = reinterpret(UInt8, red(c))
        out[2, i, j] = reinterpret(UInt8, green(c))
        out[3, i, j] = reinterpret(UInt8, blue(c))
        out[4, i, j] = reinterpret(UInt8, alpha(c))
    end
    return out
end

"""
PNG through PNGFiles (already a dependency); anything else through VideoIO —
ffmpeg's image demuxer reads jpg/bmp/tiff/webp as a one-frame video, which
buys every common format without a new dependency.
"""
function _load_pixels(path::AbstractString)
    isfile(path) || throw(ArgumentError("image not found: «$path»"))
    if endswith(lowercase(path), ".png")
        # `gamma = 1.0` — the raw samples. PNGFiles' default honours a
        # gAMA/sRGB chunk and corrects to the 2.2 screen (a file declaring
        # gAMA 1.0 would have its 180 come out 218); PIL, and so ManimGL, read
        # the bytes as they are.
        return _pixels_from_matrix(PNGFiles.load(path; gamma = 1.0))
    end
    frame = try
        # VideoIO lives behind `_ensure_video!` (video.jl) — a PNG
        # never reaches here, so a scene without exotic images never loads it.
        _ensure_video!()
        Base.invokelatest(_read_first_frame, String(path))
    catch err
        throw(ArgumentError(
            "cannot decode «$path» ($(first(sprint(showerror, err), 60))…) — " *
            "PNG is decoded natively; other formats go through ffmpeg"))
    end
    return _pixels_from_matrix(frame)
end

# ── ImageMobject ────────────────────────────────────────────────────────

"""
    ImageMobject(path; height=4.0, opacity=1.0)
    ImageMobject(img::AbstractMatrix; height=4.0, opacity=1.0)

A raster image as a mobject (manimgl's, default height 4). The second form
takes any Colorant matrix — an image COMPUTED in Julia needs no file. The 4
corner points go through the ordinary transform machinery: `shift!`,
`rotate!`, `scale!`, `move_to!` and the interpolation contract all work; the
raster itself is sampled by the backend (bilinear).
"""
mutable struct ImageMobject <: Mobject
    pixels::Array{UInt8,3}          # 4 × w × h, RGBA8, row 1 on top
    points::Vector{Point3f}         # UL, DL, UR, DR (a triangle strip)
    opacity::Float64
    depth_test::Bool
    fixed_in_frame::Bool
    submobjects::Vector{Mobject}
    parents::Vector{Mobject}
    updaters::Vector{Updater}
    updating_suspended::Bool
    z_index::Float64                # draw order — an attribute of every mobject (GL)
end

function _image_corners(w_px::Int, h_px::Int, height::Float64)
    w = height * w_px / h_px
    hw, hh = w / 2, height / 2
    return Point3f[Point3f(-hw, hh, 0), Point3f(-hw, -hh, 0),
                   Point3f(hw, hh, 0), Point3f(hw, -hh, 0)]
end

function ImageMobject(pixels::Array{UInt8,3}; height::Real = 4.0,
                      opacity::Real = 1.0)
    size(pixels, 1) == 4 || throw(ArgumentError(
        "pixels must be 4×w×h RGBA8 (got $(size(pixels)))"))
    ImageMobject(pixels, _image_corners(size(pixels, 2), size(pixels, 3), Float64(height)),
                 Float64(opacity), false, false,
                 Mobject[], Mobject[], Updater[], false, 0.0)
end
ImageMobject(path::AbstractString; kw...) = ImageMobject(_load_pixels(path); kw...)
ImageMobject(img::AbstractMatrix; kw...) = ImageMobject(_pixels_from_matrix(img); kw...)

"The raster's dimensions in pixels, (w, h)."
pixel_size(m::ImageMobject) = (size(m.pixels, 2), size(m.pixels, 3))

"Swap the raster (a NEW array — copies share pixels, so never mutate in place)."
set_pixels!(m::ImageMobject, px::Array{UInt8,3}) =
    (size(px, 1) == 4 || throw(ArgumentError("pixels must be 4×w×h")); m.pixels = px; m)

set_opacity!(m::ImageMobject, op::Real) = (m.opacity = clamp(Float64(op), 0, 1); m)
get_opacity(m::ImageMobject) = m.opacity

# the minimum to live in a scene (the Surface pattern)
get_family(m::ImageMobject) = Mobject[m]
has_points(m::ImageMobject) = !isempty(m.points)   # no points, no geometry
get_num_points(m::ImageMobject) = length(m.points)
has_updaters(m::ImageMobject) = !isempty(m.updaters)
get_updaters(m::ImageMobject) = m.updaters
tag(::ImageMobject) = :ImageMobject

function get_center(m::ImageMobject)
    lo = reduce((a, b) -> min.(a, b), m.points)
    hi = reduce((a, b) -> max.(a, b), m.points)
    return Point3f((lo + hi) / 2)
end
get_width(m::ImageMobject) = norm(m.points[3] - m.points[1])   # UR − UL
get_height(m::ImageMobject) = norm(m.points[2] - m.points[1])  # DL − UL

shift!(m::ImageMobject, delta) = (d = Point3f(delta); m.points .+= Ref(d); m)
# `move_to!` is transforms.jl's Mobject method: it takes a point OR a mobject,
# `aligned_edge` and `coor_mask` (the box's centre is get_center).

# The pivot of an image transform, in Float64 like the corners:
# `about_point` wins, else the box point at `about_edge` (GL's `_pivot`). For
# the default ORIGIN that is the box's centre — get_center's own bits.
_image_pivot(m::ImageMobject, about_point, about_edge) =
    SVector{3,Float64}(about_point === nothing ? get_bounding_box_point(m, about_edge) :
                       Point3f(about_point))

function scale!(m::ImageMobject, factor::Real; about_point = nothing, about_edge = ORIGIN,
                min_scale_factor::Real = 1e-8)
    c = _image_pivot(m, about_point, about_edge)
    f = max(Float64(factor), Float64(min_scale_factor))   # GL's Mobject.scale
    for i in eachindex(m.points)
        m.points[i] = Point3f(c + f * (SVector{3,Float64}(m.points[i]) - c))
    end
    return m
end

"Anisotropic scaling of the corners along ONE dimension, Float64 like `scale!`."
function stretch!(m::ImageMobject, factor::Real, dim::Int; about_point = nothing,
                  about_edge = ORIGIN)
    1 <= dim <= 3 || throw(ArgumentError("dim=$dim does not exist: 1=x, 2=y, 3=z"))
    c = _image_pivot(m, about_point, about_edge)
    s = SVector{3,Float64}(ntuple(i -> i == dim ? Float64(factor) : 1.0, 3))
    for i in eachindex(m.points)
        m.points[i] = Point3f(c + s .* (SVector{3,Float64}(m.points[i]) - c))
    end
    return m
end

function rotate!(m::ImageMobject, angle::Real; axis = OUT, about_point = nothing,
                 about_edge = ORIGIN)
    c = _image_pivot(m, about_point, about_edge)
    R = rotation_matrix(angle, axis)
    for i in eachindex(m.points)
        m.points[i] = Point3f(R * (SVector{3,Float64}(m.points[i]) - c) + c)
    end
    return m
end

"See [`flip!`](@ref) — a half turn about `axis`, as for a VMobject."
flip!(m::ImageMobject; axis = UP, about_point = nothing, about_edge = ORIGIN) =
    rotate!(m, TAU / 2; axis, about_point, about_edge)

"See [`fade!`](@ref): an image's only style is its opacity."
fade!(m::ImageMobject, darkness::Real = 0.5) = set_opacity!(m, 1.0 - Float64(darkness))

# The colour verbs a scene calls on a Group with an image inside.
# ManimGL's ImageMobject answers them by writing an rgba array its shader
# never reads, and the answer here is the same no-op: the raster is the
# colour, and only `set_opacity!` reaches the screen.
set_color!(m::ImageMobject; kw...) = m
set_fill!(m::ImageMobject; kw...) = m
set_stroke!(m::ImageMobject; kw...) = m

set_height!(m::ImageMobject, h::Real) = scale!(m, Float64(h) / max(get_height(m), 1e-12))
set_width!(m::ImageMobject, w::Real) = scale!(m, Float64(w) / max(get_width(m), 1e-12))

apply_depth_test!(m::ImageMobject; value::Bool = true) = (m.depth_test = value; m)
fix_in_frame!(m::ImageMobject; value::Bool = true) = (m.fixed_in_frame = value; m)

function update!(m::ImageMobject, dt::Real)
    m.updating_suspended && return m
    for u in m.updaters
        u.takes_dt ? u.func(m, dt) : u.func(m)
    end
    return m
end
add_updater!(m::ImageMobject, f; call::Bool = true, parallel::Bool = false) =
    (push!(m.updaters, Updater(f; parallel)); call && update!(m, 0.0); m)

# the interpolation contract: 4 lines and the ordinary `animate` works
is_interpolable(::ImageMobject) = true
Base.copy(m::ImageMobject) =
    ImageMobject(m.pixels, copy(m.points), m.opacity, m.depth_test,
                 m.fixed_in_frame, Mobject[], Mobject[], copy(m.updaters),
                 m.updating_suspended, m.z_index)
function interpolate!(d::ImageMobject, a::ImageMobject, b::ImageMobject, α::Real)
    for i in eachindex(d.points)
        d.points[i] = interpolate(a.points[i], b.points[i], α)
    end
    d.opacity = a.opacity + Float64(α) * (b.opacity - a.opacity)
    d.pixels = α < 0.5 ? a.pixels : b.pixels       # rasters swap at the midpoint
    return d
end
become!(d::ImageMobject, s::ImageMobject) =
    (d.pixels = s.pixels; d.points .= s.points; d.opacity = s.opacity; d)

# ── TexturedSurface ─────────────────────────────────────────────────────

"""
    TexturedSurface(surface::Surface, image; opacity=1.0)

The Surface's uv mesh with the texture sampled per fragment (manimgl's
textured_surface): the vertex normal still lights it through finalize_color,
the colour comes from the image. `image` is a path or a Colorant matrix.
uv follows manimgl: u maps the image's width, v=v_max is the image's TOP row
(an upright picture on PlaneXY).
"""
mutable struct TexturedSurface <: Mobject
    points::Vector{Point3f}
    d_normal_points::Vector{Point3f}
    uv::Vector{NTuple{2,Float32}}
    resolution::NTuple{2,Int}
    indices::Vector{Int32}
    pixels::Array{UInt8,3}
    opacity::Float64
    shading::NTuple{3,Float32}
    depth_test::Bool
    fixed_in_frame::Bool
    submobjects::Vector{Mobject}
    parents::Vector{Mobject}
    updaters::Vector{Updater}
    updating_suspended::Bool
    z_index::Float64                # draw order — an attribute of every mobject (GL)
end

function TexturedSurface(surf::Surface, image; opacity::Real = 1.0)
    px = image isa Array{UInt8,3} ? image :
         image isa AbstractMatrix ? _pixels_from_matrix(image) :
         _load_pixels(String(image))
    nu, nv = surf.resolution
    uv = Vector{NTuple{2,Float32}}(undef, nu * nv)
    k = 0
    for iu in 1:nu, iv in 1:nv                      # u-outer/v-inner, like Surface
        k += 1
        uv[k] = (Float32((iu - 1) / max(nu - 1, 1)),
                 Float32(1 - (iv - 1) / max(nv - 1, 1)))
    end
    TexturedSurface(copy(surf.points), copy(surf.d_normal_points), uv,
                    surf.resolution, copy(surf.indices), px, Float64(opacity),
                    surf.shading, surf.depth_test, surf.fixed_in_frame,
                    Mobject[], Mobject[], Updater[], false, 0.0)
end

pixel_size(m::TexturedSurface) = (size(m.pixels, 2), size(m.pixels, 3))
set_opacity!(m::TexturedSurface, op::Real) = (m.opacity = clamp(Float64(op), 0, 1); m)
get_opacity(m::TexturedSurface) = m.opacity
set_pixels!(m::TexturedSurface, px::Array{UInt8,3}) =
    (size(px, 1) == 4 || throw(ArgumentError("pixels must be 4×w×h")); m.pixels = px; m)

get_family(m::TexturedSurface) = Mobject[m]
has_points(m::TexturedSurface) = !isempty(m.points)
get_num_points(m::TexturedSurface) = length(m.points)
has_updaters(m::TexturedSurface) = !isempty(m.updaters)
get_updaters(m::TexturedSurface) = m.updaters
tag(::TexturedSurface) = :TexturedSurface

function get_center(m::TexturedSurface)
    isempty(m.points) && return Point3f(0, 0, 0)
    lo = reduce((a, b) -> min.(a, b), m.points)
    hi = reduce((a, b) -> max.(a, b), m.points)
    return Point3f((lo + hi) / 2)
end

function shift!(m::TexturedSurface, delta)
    d = Point3f(delta)
    m.points .+= Ref(d)
    m.d_normal_points .+= Ref(d)
    return m
end
# `move_to!`: transforms.jl's Mobject method, as for ImageMobject.

function rotate!(m::TexturedSurface, angle::Real; axis = OUT, about_point = nothing)
    c = SVector{3,Float64}(something(about_point, get_center(m)))
    R = rotation_matrix(angle, axis)
    for arr in (m.points, m.d_normal_points)
        @inbounds for i in eachindex(arr)
            arr[i] = Point3f(R * (SVector{3,Float64}(arr[i]) - c) + c)
        end
    end
    return m
end

function scale!(m::TexturedSurface, factor::Real; about_point = nothing)
    c = SVector{3,Float64}(something(about_point, get_center(m)))
    for arr in (m.points, m.d_normal_points)
        @inbounds for i in eachindex(arr)
            arr[i] = Point3f(c + factor * (SVector{3,Float64}(arr[i]) - c))
        end
    end
    return m
end

set_shading!(m::TexturedSurface; reflectiveness = nothing, gloss = nothing,
             shadow = nothing) =
    (m.shading = (Float32(something(reflectiveness, m.shading[1])),
                  Float32(something(gloss, m.shading[2])),
                  Float32(something(shadow, m.shading[3]))); m)
apply_depth_test!(m::TexturedSurface; value::Bool = true) = (m.depth_test = value; m)
fix_in_frame!(m::TexturedSurface; value::Bool = true) = (m.fixed_in_frame = value; m)

function update!(m::TexturedSurface, dt::Real)
    m.updating_suspended && return m
    for u in m.updaters
        u.takes_dt ? u.func(m, dt) : u.func(m)
    end
    return m
end
add_updater!(m::TexturedSurface, f; call::Bool = true, parallel::Bool = false) =
    (push!(m.updaters, Updater(f; parallel)); call && update!(m, 0.0); m)

# the interpolation contract — geometry and opacity; the raster is identity
is_interpolable(::TexturedSurface) = true
Base.copy(m::TexturedSurface) =
    TexturedSurface(copy(m.points), copy(m.d_normal_points), copy(m.uv),
                    m.resolution, copy(m.indices), m.pixels, m.opacity,
                    m.shading, m.depth_test, m.fixed_in_frame,
                    Mobject[], Mobject[], copy(m.updaters), m.updating_suspended,
                    m.z_index)
function interpolate!(d::TexturedSurface, a::TexturedSurface, b::TexturedSurface, α::Real)
    length(a.points) == length(b.points) || throw(ArgumentError(
        "cannot interpolate TexturedSurfaces of different resolutions " *
        "($(a.resolution) vs $(b.resolution))"))
    for i in eachindex(d.points)
        d.points[i] = interpolate(a.points[i], b.points[i], α)
        d.d_normal_points[i] = interpolate(a.d_normal_points[i], b.d_normal_points[i], α)
    end
    d.opacity = a.opacity + Float64(α) * (b.opacity - a.opacity)
    d.pixels = α < 0.5 ? a.pixels : b.pixels
    return d
end
become!(d::TexturedSurface, s::TexturedSurface) =
    (d.pixels = s.pixels; d.points .= s.points; d.d_normal_points .= s.d_normal_points;
     d.opacity = s.opacity; d)

# ═══════════════════════════════════════════════════════════════════════
# The bounding box and the layout family (`next_to!`, `to_edge!`,
# `align_to!` and everything else that starts from get_bounding_box_point).
# One method per concrete union, never an abstract `::Mobject` signature —
# the measured 0→272-bytes trap that surface.jl and bbox.jl both document. The
# bodies mirror the VMobject ones line for line. ImageMobject keeps its own
# EDGE-BASED get_width/get_height above (intrinsic, rotation-invariant —
# what set_height! wants); being more specific, they win over the union's
# bbox-based pair, which serves TexturedSurface.
# ═══════════════════════════════════════════════════════════════════════

const SampledMobject = Union{ImageMobject,TexturedSurface}

function get_bounding_box(m::SampledMobject)
    isempty(m.points) && return Point3f[ORIGIN, ORIGIN, ORIGIN]
    lo = reduce((a, b) -> min.(a, b), m.points)
    hi = reduce((a, b) -> max.(a, b), m.points)
    return Point3f[lo, (lo + hi) / 2, hi]
end
get_bounding_box_point(m::SampledMobject, direction) =
    _bbox_point(get_bounding_box(m), direction)

get_left(m::SampledMobject)   = get_bounding_box_point(m, LEFT)
get_right(m::SampledMobject)  = get_bounding_box_point(m, RIGHT)
get_top(m::SampledMobject)    = get_bounding_box_point(m, UP)
get_bottom(m::SampledMobject) = get_bounding_box_point(m, DOWN)
length_over_dim(m::SampledMobject, dim::Int) = _dim_length(get_bounding_box(m), dim)
get_width(m::SampledMobject)  = length_over_dim(m, 1)
get_height(m::SampledMobject) = length_over_dim(m, 2)
get_depth(m::SampledMobject)  = length_over_dim(m, 3)

get_coord(m::SampledMobject, dim::Int; direction = ORIGIN) =
    get_bounding_box_point(m, direction)[dim]

function set_coord!(m::SampledMobject, value::Real, dim::Int; direction = ORIGIN)
    1 <= dim <= 3 || throw(ArgumentError("dim=$dim does not exist: 1=x, 2=y, 3=z"))
    delta = Float32(value) - get_coord(m, dim; direction)
    return shift!(m, Point3f(ntuple(i -> i == dim ? delta : 0f0, 3)))
end

center!(m::SampledMobject) = shift!(m, -get_center(m))

function align_on_border!(m::SampledMobject, direction;
                          buff::Real = DEFAULT_MOBJECT_TO_EDGE_BUFF)
    d = Point3f(direction)
    s = Point3f(sign(d[1]), sign(d[2]), sign(d[3]))
    target = Point3f(s[1] * FRAME_X_RADIUS, s[2] * FRAME_Y_RADIUS, 0)
    shift_val = target - get_bounding_box_point(m, d) - Float32(buff) * d
    return shift!(m, shift_val .* abs.(s))
end

to_edge!(m::SampledMobject, edge = LEFT; buff::Real = DEFAULT_MOBJECT_TO_EDGE_BUFF) =
    align_on_border!(m, edge; buff)
to_corner!(m::SampledMobject, corner = DL; buff::Real = DEFAULT_MOBJECT_TO_EDGE_BUFF) =
    align_on_border!(m, corner; buff)

function next_to!(m::SampledMobject, reference, direction = RIGHT;
                  buff::Real = DEFAULT_MOBJECT_TO_MOBJECT_BUFF,
                  aligned_edge = ORIGIN, coor_mask = (1, 1, 1))
    d = Point3f(direction)
    ae = Point3f(aligned_edge)
    target = _as_point(reference, ae + d)
    anchor = get_bounding_box_point(m, ae - d)
    return shift!(m, (target - anchor + Float32(buff) * d) .* Point3f(coor_mask))
end

function align_to!(m::SampledMobject, reference, direction = ORIGIN)
    d = Point3f(direction)
    p = _as_point(reference, d)
    for dim in 1:3
        d[dim] == 0 || set_coord!(m, p[dim], dim; direction = d)
    end
    return m
end

# ── what a VGroup asks of a member that is not a VMobject ────────────
# (bbox.jl counts the box, transforms.jl moves the points)
_leaf_bounding_box(m::SampledMobject) = isempty(m.points) ? nothing : get_bounding_box(m)
_apply_leaf_points!(f, m::ImageMobject, ap) = (_apply!(f, m.points, ap); nothing)
_apply_leaf_points!(f, m::TexturedSurface, ap) =
    (_apply!(f, m.points, ap); _apply!(f, m.d_normal_points, ap); nothing)
