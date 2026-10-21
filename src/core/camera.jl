# core/camera.jl — the Camera: the point of view a frame is rendered from,
# its geometry (ManimGL's CameraFrame, camera_frame.py) and the uniforms it
# hands the renderer (camera.py:238-255).
#
# A Camera is a quaternion, a frame size and a background, and `camera_uniforms`
# is arithmetic: nothing here names a graphics API. The renderer reads the
# NamedTuple it returns (`backend/wgpu/uniforms.jl` packs it into the frame
# block), so every rendered frame passes through these numbers.

using GeometryBasics: Point3f, Vec4f
using StaticArrays: SVector, SMatrix
using LinearAlgebra: norm, normalize

const FRAME_HEIGHT_DEF = FRAME_HEIGHT      # single source of truth: constants.jl
const FRAME_WIDTH_DEF = FRAME_WIDTH

"""
    Camera(; width, height, frame_width, frame_height, fovy, background,
             light_position, orientation, center_point)

The point of view a frame is rendered from: pixel size, how much of the scene
is visible, where it is looking from and what colour the void is.

You rarely build one. A [`Scene`](@ref) builds its own from `resolution` and
the rest, and what you animate is [`CameraFrame`](@ref) — `scene.frame` — which
is a mobject wrapped around this. Reach for `Camera` directly when driving
[`render_mobjects`](@ref) or [`render_composition`](@ref) by hand.

`width`/`height` are PIXELS; `frame_width`/`frame_height` are SCENE UNITS, and
the ratio between them is the zoom. Orientation is a quaternion, not three
angles — [`reorient!`](@ref) is the readable way in, and
[`get_theta`](@ref)/[`get_phi`](@ref)/[`get_gamma`](@ref) read the angles back
out.
"""
Base.@kwdef mutable struct Camera
    width::Int = 960
    height::Int = 540
    frame_width::Float64 = FRAME_WIDTH_DEF
    frame_height::Float64 = FRAME_HEIGHT_DEF
    fovy::Float64 = 45 * DEG
    background::NTuple{4,Float32} = (0f0, 0f0, 0f0, 1f0)
    light_position::NTuple{3,Float32} = (-10f0, 10f0, 10f0)
    # the FULL orientation as a quaternion (GL's CameraFrame) + center_point
    orientation::Quat = quat_identity()
    center_point::Point3f = Point3f(0, 0, 0)
end

focal_distance(c::Camera) = 0.5 * c.frame_height / tan(0.5 * c.fovy)

"""
    get_focal_distance(cam) → Float64

How far the eye sits from the frame plane, in scene units — the distance at
which the frame exactly fills the field of view.

It falls out of the frame height and `fovy`, so zooming changes it. It is what
decides how strong the perspective is: things nearer than this loom, things
beyond it shrink. [`set_focal_distance!`](@ref) sets it (by moving `fovy`).
"""
const get_focal_distance = focal_distance

"""
    get_scale(cam) → Float64

The camera's zoom as a ratio: its frame height over the nominal
[`FRAME_HEIGHT`](@ref). `1.0` is the default view, smaller is zoomed IN, larger
is zoomed out.

This is the number the renderer multiplies stroke widths by, which is why a
zoom does not thicken outlines.
"""
get_scale(c::Camera) = c.frame_height / FRAME_HEIGHT_DEF

"Current θ, φ, γ (radians) — derived from the quaternion, as in GL."
get_euler_angles(c::Camera) = euler_zxz_from_quat(c.orientation)
"""
    get_theta(cam) → Float64

The camera's azimuth in RADIANS — how far it has swung around the vertical
axis. The first of the three ZXZ Euler angles, derived from the quaternion.

Note the units: [`reorient!`](@ref) takes DEGREES, because that is how you
think about a camera; these getters answer in radians, because that is how the
maths stores it. `get_theta(cam) / DEG` converts.
"""
get_theta(c::Camera) = get_euler_angles(c)[1]

"""
    get_phi(cam) → Float64

The camera's polar angle in radians — how far it has tipped away from looking
straight down the z axis. `0` is the flat, head-on view of a 2D scene. See
[`get_theta`](@ref).
"""
get_phi(c::Camera) = get_euler_angles(c)[2]

"""
    get_gamma(cam) → Float64

The camera's roll in radians — rotation about its own line of sight. See
[`get_theta`](@ref).
"""
get_gamma(c::Camera) = get_euler_angles(c)[3]

"""
    set_euler_angles!(cam; theta=nothing, phi=nothing, gamma=nothing)

Sets the given angles, keeping the rest (camera_frame.py:131). Everything in
radians; `reorient!` is the shortcut in degrees.
"""
function set_euler_angles!(c::Camera; theta = nothing, phi = nothing, gamma = nothing)
    e = collect(get_euler_angles(c))
    for (i, v) in enumerate((theta, phi, gamma))
        v === nothing || (e[i] = Float64(v))
    end
    c.orientation = all(iszero, e) ? quat_identity() : quat_from_euler_zxz(e...)
    return c
end

"GL's increment_euler_angles: adds and CLAMPS φ to [0, π] (zxz)."
function increment_euler_angles!(c::Camera; dtheta = 0.0, dphi = 0.0, dgamma = 0.0)
    e = collect(get_euler_angles(c)) .+ [dtheta, dphi, dgamma]
    e[2] = clamp(e[2], 0.0, Float64(PI))
    c.orientation = quat_from_euler_zxz(e...)
    return c
end

"""
    reorient!(cam, theta_deg, phi_deg, gamma_deg=nothing; center=nothing, height=nothing)

GL's shortcut in DEGREES (camera_frame.py:172). `nothing` keeps the current
angle; `center` moves the frame; `height` zooms (it scales the whole frame,
preserving the aspect ratio).
"""
function reorient!(c::Camera, theta_deg = nothing, phi_deg = nothing, gamma_deg = nothing;
                   center = nothing, height = nothing)
    set_euler_angles!(c;
        theta = theta_deg === nothing ? nothing : theta_deg * DEG,
        phi = phi_deg === nothing ? nothing : phi_deg * DEG,
        gamma = gamma_deg === nothing ? nothing : gamma_deg * DEG)
    center === nothing || (c.center_point = Point3f(center...))
    if height !== nothing
        c.frame_width *= height / c.frame_height
        c.frame_height = Float64(height)
    end
    return c
end

"CameraFrame's rotate: composes ON THE LEFT (rot ∘ orientation)."
function rotate!(c::Camera, angle::Real; axis = (0, 0, 1))
    c.orientation = quat_mul(quat_axis_angle(axis, angle), c.orientation)
    return c
end

"fovy from the desired focal distance (camera_frame.py:217)."
set_focal_distance!(c::Camera, d::Real) = (c.fovy = 2atan(0.5 * c.frame_height / d); c)

"""
    get_view_matrix(cam) → Matrix{Float64} 4×4

view = (1/scale) · R⁻¹ · T(−center_point) — the affine map taking a world
point into the camera's frame (camera_frame.py:100).
"""
function get_view_matrix(c::Camera)
    R = quat_to_matrix(c.orientation)
    v = zeros(4, 4)
    v[4, 4] = 1.0
    v[1:3, 1:3] .= R'                       # R⁻¹ of a pure rotation
    v[1:3, 4] .= R' * (-SVector{3,Float64}(c.center_point))
    scale = get_scale(c)
    scale > 0 && (v[1:3, :] ./= scale)
    return v
end

"GL's frame.scale(factor, about_point): zooming the frame about a point."
function scale_frame!(c::Camera, factor::Real; about = nothing)
    p = about === nothing ? SVector{3,Float64}(c.center_point) : SVector{3,Float64}(Point3f(about))
    c.center_point = Point3f(p + factor * (SVector{3,Float64}(c.center_point) - p))
    c.frame_height *= factor
    c.frame_width *= factor
    return c
end

"CameraFrame's to_default_state: identity, origin, default frame."
function reset_camera!(c::Camera)
    c.orientation = quat_identity()
    c.center_point = Point3f(0, 0, 0)
    c.frame_width = FRAME_WIDTH_DEF
    c.frame_height = FRAME_HEIGHT_DEF
    return c
end

"center_point + d·(R·OUT): the implied eye — it feeds camera_position (speculars)."
function get_implied_camera_location(c::Camera)
    R = quat_to_matrix(c.orientation)
    d = focal_distance(c)
    return SVector{3,Float64}(c.center_point) + d * R[:, 3]
end

"""
The uniforms of camera.py:238-255. `flip_y=true` negates the y rescale
factor: the framebuffer ends up with row 0 ON TOP and the readback is already
a ready-made video frame (no vertical flip is needed). The winding orientation
is unaffected: it is computed in world coordinates, before projection.
"""
function camera_uniforms(c::Camera; flip_y::Bool = false)
    scale_factor = get_scale(c)                           # frame.get_scale()
    sy = flip_y ? -1 : 1
    cam_pos = get_implied_camera_location(c)
    (
        view = Matrix{Float32}(get_view_matrix(c)),  # column-major = GL's view.T.flatten()
        frame_scale = Float32(scale_factor),
        frame_rescale_factors = (Float32(2 / FRAME_WIDTH_DEF),
                                 Float32(sy * 2 / FRAME_HEIGHT_DEF),
                                 Float32(scale_factor / focal_distance(c))),
        pixel_size = Float32(c.frame_width / c.width),
        camera_position = (Float32(cam_pos[1]), Float32(cam_pos[2]), Float32(cam_pos[3])),
        light_position = c.light_position,
        is_fixed_in_frame = 0f0,
        shading = (0f0, 0f0, 0f0),
    )
end
