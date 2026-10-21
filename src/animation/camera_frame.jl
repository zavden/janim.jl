# The animatable 2D camera.
#
# GL's idiom is `self.frame.animate.scale(0.5).move_to(x)`: narrative zoom onto
# a part of the scene. Our `Camera` (core/camera.jl) is not a Mobject
# — it is a bag of uniforms — so it cannot be handed to Transform.
#
# There were two designs: a bespoke camera animation with its own
# begin!/interpolate!/finish!, or promoting the frame to a mobject.
# The second one wins, thanks to the interpolation contract: a
# `CameraFrame <: Mobject` that implements the four contract lines is
# animatable by `animate`, by Transform, inside an AnimationGroup, with any
# rate_func — for free. The bespoke class would have had to re-earn each of
# those.
#
# It is a VIEW, not a copy: the frame holds a reference to the live Camera, so
# mutating the frame moves the camera the scene is rendering with.

"""
    CameraFrame(camera)

The scene's camera as an animatable mobject. `scene.frame` is the one that
matters:

    play!(scene, animate(scene.frame, (scale_frame!, 0.5),
                         (move_to!, 2RIGHT)); run_time = 2)

Interpolating a frame means interpolating three things: the centre, the frame
height (the zoom) and the orientation quaternion. The quaternion is
interpolated with `quat_slerp`, so a rotating camera takes the short arc at
constant angular speed instead of the wobble a component-wise lerp gives.

Two things a scene translated from ManimGL trips on:

- **Its updaters run only while it is ON THE STAGE.** `_update_all!` walks
  `scene.mobjects`, so `add_updater!(scene.frame, f)` does nothing until
  `add!(scene, scene.frame)`. In ManimGL that line is cosmetic; here it is
  the whole chase. An animation of the frame needs no such line.
- **`scene.frame.camera` is the [`Camera`](@ref) behind it** — the receiver
  of the verbs that exist only on the camera (`set_focal_distance!`,
  `set_euler_angles!`) and of `frame_width`/`frame_height`.
"""
mutable struct CameraFrame <: Mobject
    camera::Camera
    updaters::Vector{Updater}       # a camera can track (the follow idiom)
    parents::Vector{Mobject}        # the node contract — it can live in a Group
end
CameraFrame(camera::Camera) = CameraFrame(camera, Updater[], Mobject[])

"""
    CameraFrame()

A free-standing camera, for a [`Layer`](@ref)'s `camera =` — default geometry,
aimed with the same verbs as `scene.frame` ([`move_to!`](@ref),
[`set_frame_height!`](@ref), [`reorient!`](@ref)) and animatable the same way.
Its pixel size is ignored there: a layer renders at the compositor's
resolution and takes only the frame geometry from here.
"""
CameraFrame() = CameraFrame(Camera())

# The dispatch half of Layer's camera check — the field cannot be annotated
# with a type that loads after compositor.jl (see the note on the struct).
_validate_layer_camera(::CameraFrame) = nothing

# ── the state a frame IS, detached from the live camera ────────────────────
# `copy` must NOT share the Camera: Transform snapshots the start and builds a
# target, and both must be able to sit still while the live one moves.
Base.copy(f::CameraFrame) = CameraFrame(_copy_camera(f.camera), copy(f.updaters), Mobject[])

function _copy_camera(c::Camera)
    Camera(; width = c.width, height = c.height,
           frame_width = c.frame_width, frame_height = c.frame_height,
           fovy = c.fovy, background = c.background,
           light_position = c.light_position,
           orientation = c.orientation, center_point = c.center_point)
end

is_interpolable(::CameraFrame) = true

function interpolate!(dst::CameraFrame, a::CameraFrame, b::CameraFrame, alpha::Real)
    α = Float64(alpha)
    ca, cb, cd = a.camera, b.camera, dst.camera
    cd.center_point = Point3f(SVector{3,Float64}(ca.center_point) +
                              α * (SVector{3,Float64}(cb.center_point) -
                                   SVector{3,Float64}(ca.center_point)))
    cd.frame_width = ca.frame_width + α * (cb.frame_width - ca.frame_width)
    cd.frame_height = ca.frame_height + α * (cb.frame_height - ca.frame_height)
    cd.fovy = ca.fovy + α * (cb.fovy - ca.fovy)
    cd.orientation = quat_slerp(ca.orientation, cb.orientation, α)
    return dst
end

function become!(dst::CameraFrame, src::CameraFrame)
    c, s = dst.camera, src.camera
    c.center_point = s.center_point
    c.frame_width = s.frame_width
    c.frame_height = s.frame_height
    c.fovy = s.fovy
    c.orientation = s.orientation
    return dst
end

# ── the frame's own verbs (camera_frame.py) ────────────────────────────────
# Named so they read in an `animate` call: animate(frame, (scale_frame!, 0.5)).

get_center(f::CameraFrame) = f.camera.center_point
get_width(f::CameraFrame) = f.camera.frame_width
get_height(f::CameraFrame) = f.camera.frame_height

move_to!(f::CameraFrame, p) = (f.camera.center_point = Point3f(p); f)
"Point the frame at a MOBJECT: GL's `frame.move_to(mob)` takes its centre (mobject.py:1220)."
move_to!(f::CameraFrame, m::Mobject) = move_to!(f, get_center(m))

"""
    get_bounding_box_point(frame, direction) → Point3f

That point of the frame's rectangle — `get_bounding_box_point(frame, LEFT)` is
the middle of the left edge, `UL` its upper-left corner, `ORIGIN` its centre.

ManimGL's `CameraFrame` carries five real points (`[ORIGIN, LEFT, RIGHT, DOWN,
UP]` scaled to the frame shape, `camera_frame.py:47`) and answers every
Mobject question from them; here the frame keeps no points, so the box is
computed from the centre and the frame size — the same rectangle.

**A rotated frame has the SAME box.** Rotating the camera writes the
quaternion and never touches those points (measured in GL: after
`increment_theta(0.5)` the left edge is still at x = -7.111111), so this is
the frame's rectangle in scene units, not what the camera happens to see.

It is what makes the layout verbs work against the frame:
`align_to!(logo, scene.frame, LEFT)` and `next_to!(hud, scene.frame, DOWN)`
go through `_as_point` and land here.
"""
function get_bounding_box_point(f::CameraFrame, direction)
    d = Point3f(direction)
    c = SVector{3,Float64}(get_center(f))
    half = SVector{3,Float64}(0.5 * get_width(f), 0.5 * get_height(f), 0.0)
    return Point3f(c + SVector{3,Float64}(sign.(Float64.(d))) .* half)
end
shift!(f::CameraFrame, d) =
    (f.camera.center_point = Point3f(SVector{3,Float64}(f.camera.center_point) +
                                     SVector{3,Float64}(Point3f(d))); f)

"Zoom by a factor about a point (GL's frame.scale): <1 zooms IN."
function scale_frame!(f::CameraFrame, factor::Real; about = nothing)
    scale_frame!(f.camera, factor; about)
    return f
end

"""
    scale!(frame, factor; about_point = nothing, about_edge = ORIGIN)

Zoom: `factor < 1` zooms IN (the frame shows less), `> 1` zooms out. It is
[`scale_frame!`](@ref) under the name every other mobject answers to, because
in ManimGL `frame.scale(2)` is just `Mobject.scale` and that is the form the
`.py` files use.

```julia
play!(scene, animate(scene.frame, (scale!, 0.5)))          # zoom in on the centre
scale!(scene.frame, 0.5; about_edge = LEFT)                # …keeping the left edge
```

`about_point` fixes a point; `about_edge` fixes that edge of the frame — GL's
two keywords, and they mean here what they mean everywhere else in the engine.
`scale_frame!` stays: it is the spelling the tutorials use, and it is what this
calls.
"""
function scale!(f::CameraFrame, factor::Real; about_point = nothing, about_edge = ORIGIN)
    about = about_point !== nothing ? Point3f(about_point) :
            all(Float64.(Point3f(about_edge)) .== 0) ? nothing :
            get_bounding_box_point(f, about_edge)
    return scale_frame!(f, factor; about)
end

# ── the euler angles, on the frame (GL's are CameraFrame methods) ──────────
# The camera object carries them; these are the same verbs where a ManimGL
# `.py` looks for them, `frame.get_theta()` and friends.

"The frame's azimuth, in radians. See [`get_theta`](@ref)`(::Camera)`."
get_theta(f::CameraFrame) = get_theta(f.camera)
"The frame's polar angle, in radians."
get_phi(f::CameraFrame) = get_phi(f.camera)
"The frame's roll, in radians."
get_gamma(f::CameraFrame) = get_gamma(f.camera)
"Set the frame's euler angles — see [`set_euler_angles!`](@ref)`(::Camera)`."
set_euler_angles!(f::CameraFrame; kw...) = (set_euler_angles!(f.camera; kw...); f)
"Add to the frame's euler angles — see [`increment_euler_angles!`](@ref)`(::Camera)`."
increment_euler_angles!(f::CameraFrame; kw...) = (increment_euler_angles!(f.camera; kw...); f)

"""
    increment_theta!(frame, dθ; units = 1.0)
    increment_phi!(frame, dφ; units = 1.0)
    increment_gamma!(frame, dγ; units = 1.0)

Turn the camera BY an angle instead of TO one (`camera_frame.py:200-210`) —
the form an ambient rotation is written with:

```julia
add_updater!(scene.frame, (m, dt) -> increment_theta!(m, 0.2 * dt))
```

`units = DEG` reads the number as degrees, which is GL's keyword.

**What comes back out wraps.** `get_theta` reads the ORIENTATION back
(`camera_frame.py:85`, through the quaternion), so after two increments of 4
radians it answers `8 - τ = 1.716815`, not 8 — as in ManimGL. A running
total is a [`ValueTracker`](@ref)'s job.
"""
increment_theta!(f::CameraFrame, dtheta::Real; units::Real = 1.0) =
    increment_euler_angles!(f; dtheta = Float64(dtheta) * Float64(units))

@doc (@doc increment_theta!)
increment_phi!(f::CameraFrame, dphi::Real; units::Real = 1.0) =
    increment_euler_angles!(f; dphi = Float64(dphi) * Float64(units))

@doc (@doc increment_theta!)
increment_gamma!(f::CameraFrame, dgamma::Real; units::Real = 1.0) =
    increment_euler_angles!(f; dgamma = Float64(dgamma) * Float64(units))

"""
    set_frame_height!(frame, h)

Set the frame's height, keeping the aspect ratio — the honest way to say
"show me this many scene units vertically".
"""
function set_frame_height!(f::CameraFrame, h::Real)
    c = f.camera
    c.frame_width *= h / c.frame_height
    c.frame_height = Float64(h)
    return f
end

"""
    set_frame_width!(frame, w)

Set how many scene units the camera shows HORIZONTALLY, keeping the aspect
ratio. The width-flavoured twin of [`set_frame_height!`](@ref); it converts and
delegates, so the two never disagree.
"""
set_frame_width!(f::CameraFrame, w::Real) =
    set_frame_height!(f, w * f.camera.frame_height / f.camera.frame_width)

"reorient! on the frame: the 3D camera's angles, animatable like everything else."
reorient!(f::CameraFrame, args...; kw...) = (reorient!(f.camera, args...; kw...); f)
rotate!(f::CameraFrame, angle::Real; kw...) = (rotate!(f.camera, angle; kw...); f)
"""
    reset_frame!(frame)

Put the camera back exactly where it started: default position, default size,
no rotation.

The way out of a sequence of zooms and reorientations without having to
remember, or undo, any of them — and it is animatable like any other change to
the frame:

```julia
play!(scene, animate(scene.frame, reset_frame!); run_time = 1.5)
```
"""
reset_frame!(f::CameraFrame) = (reset_camera!(f.camera); f)

# ── living in a scene ──────────────────────────────────────────────────────
# A frame draws nothing and has no points; the generic Mobject fallbacks
# (interpolable.jl) give it get_family; the updater surface below exists
# because a layer camera that TRACKS something is CE's
# zoomed-camera-follows idiom, and _mobjects_of already puts layer cameras on
# the update pass.
get_num_points(::CameraFrame) = 0
has_points(::CameraFrame) = false

function add_updater!(m::CameraFrame, f; call::Bool = true, parallel::Bool = false)
    push!(m.updaters, Updater(f; parallel))
    call && update!(m, 0.0)
    return m
end
add_updater!(f, m::CameraFrame; kw...) = add_updater!(m, f; kw...)

get_updaters(m::CameraFrame) = m.updaters
has_updaters(m::CameraFrame) = !isempty(m.updaters)

function update!(m::CameraFrame, dt::Real = 0.0; recurse::Bool = true)
    for u in m.updaters
        u(m, dt)
    end
    return m
end

remove_updater!(m::CameraFrame, f) = (filter!(u -> u.func !== f, m.updaters); m)
clear_updaters!(m::CameraFrame; recurse::Bool = true) = (empty!(m.updaters); m)
