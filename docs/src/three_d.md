# 3D and the camera

There is no `ThreeDScene` and no `MovingCameraScene`. Every scene's camera is
already three-dimensional and already animatable — those classes exist in Manim
because its camera is not, and here there is nothing for them to add.

## The camera is a mobject

`scene.frame` is a [`CameraFrame`](@ref): a mobject wrapped around the camera,
so it animates through exactly the same machinery as a circle.

```julia
play!(scene, animate(scene.frame, (scale_frame!, 0.5), (move_to!, 2 * RIGHT));
      run_time = 2)

play!(scene, animate(scene.frame, (reorient!, 40, 70)); run_time = 3)
play!(scene, animate(scene.frame, reset_frame!))
```

| | |
|---|---|
| [`reorient!`](@ref) | set θ, φ, γ — in DEGREES |
| [`scale_frame!`](@ref) | zoom by a factor, optionally `about` a point |
| [`set_frame_height!`](@ref) | "show me this many scene units vertically" |
| [`set_frame_width!`](@ref) | the same, horizontally |
| [`move_to!`](@ref) | point it somewhere else |
| [`reset_frame!`](@ref) | back to the default view |

Orientation is stored as a QUATERNION and interpolated with slerp, so a
rotating camera takes the short arc and never gimbal-locks halfway through a
move. The angles come back out with [`get_theta`](@ref), [`get_phi`](@ref) and
[`get_gamma`](@ref) — in RADIANS, because that is how the maths stores them,
while `reorient!` takes degrees because that is how you think about a camera.

There is no `ZoomedScene` — there is something stronger: a
[`Layer`](@ref) can carry its own `CameraFrame` and a `window`, which is a
real second render rather than a scaled copy. Two layers over the same 3D
world with two cameras are a genuine multicam, each view with its own
z-buffer — see [the compositor](compositor.md) and
`examples/scenes/11_multicam_views.jl`.

## Surfaces

```julia
Surface((u, v) -> (cos(u) * sin(v), sin(u) * sin(v), cos(v));
        u_range = (0, TAU), v_range = (0, PI), resolution = (101, 51))

Sphere(; radius = 1, resolution = (101, 51))
Torus(; …)
PlaneXY(; …)
Cylinder(; radius = 1, height = 2, direction = OUT)
Cone(; base_radius = 1, height = 1, direction = OUT)
```

A [`Surface`](@ref) is a uv mesh with ANALYTIC normals — computed from the
parametrisation rather than estimated from neighbouring triangles, which is
what keeps the shading clean on a coarse mesh. [`unit_normals`](@ref) exposes
them.

### Antialiasing

Every frame renders at FOUR samples: the 4× resolve is the fill's own
antialiasing, so a surface's silhouette gets manimlib's `ThreeDScene`
treatment by default — the limb ramp ~1.4 px. Strokes and dots antialias in
their shaders. `samples = 0` and `samples = 4` are
the same frame; the aliased picture is one notch away when you want it:

```julia
Scene(construct; samples = 1)      # no multisampling: a hard 0.89 px limb
```

…or `janim render scene.jl --samples 1` from the CLI.

The cost of the four samples, measured on a 3D scene of tilted faces with a
wire at `-ql`: 10.0 ms a frame on RADV and 34 ms on lavapipe; the multisample
attachment costs 32 B/px. `samples = 1` never creates the multisample twin.

The 3D line primitives are solids, not strokes: [`Dot3D`](@ref),
[`Line3D`](@ref), [`Arrow3D`](@ref) are built out of surfaces, so they take
part in the depth buffer and can be occluded.

[`TexturedSurface`](@ref) maps an image onto one.

## Shading

```julia
set_shading!(m; reflectiveness = 0.3, gloss = 0.2, shadow = 0.4)
```

Three numbers, all zero by default — which is why a flat scene stays flat. The
camera's `light_position` is where the light comes from.

## Depth

```julia
apply_depth_test!(m)          # this mobject joins the z-buffer
```

**2D mobjects do not join the z-buffer by default, and should not.** A flat
scene has a drawing ORDER, not a depth, and putting one into the depth buffer
would make its anti-aliased edges cut holes in whatever is behind them.

Janim's z is honest: only actual ink writes depth. ManimGL's anti-aliasing
fringes write it too, which is what makes a fringe punch a hole through a
stroke behind it. If you are comparing renders between the two, that difference
is deliberate.

For the flat case, drawing order is [`set_z_index!`](@ref)'s business, not the
depth buffer's — the two are different questions and Janim keeps them separate.

## A HUD that ignores the camera

```julia
fix_in_frame!(hud)
```

The mobject stops being part of the world and is drawn in frame coordinates,
so the camera can orbit around a scene while a title stays exactly where it
is. It is also what makes a legend, a readout or a watermark survive a camera
move.

## Depth of field

```julia
Layer(content; effects = [Dof(; aperture = 0.4, max_sigma = 4.0)])
```

[`Dof`](@ref) is a PER-LAYER effect: each frame it measures the layer's
distance from the focal plane along the view axis and blurs it by
`min(aperture · |d − focus|, max_sigma)`. `focus = nothing` uses the camera's
own focal distance, so with the default camera the plane through the origin is
in focus. See [the compositor](compositor.md).

## The interactive camera

In the live window, dragging pans and the wheel zooms; hold `d` while dragging
to rotate in 3D and `f` to pan. Those deltas live in [`Controls`](@ref) and are
composed ON TOP of the scene's own camera by
[`compose_camera!`](@ref) — panning a preview never edits your scene.

## Reference

[`CameraFrame`](@ref) · [`Camera`](@ref) · [`reorient!`](@ref) ·
[`scale_frame!`](@ref) · [`Surface`](@ref) · [`Sphere`](@ref) ·
[`set_shading!`](@ref) · [`apply_depth_test!`](@ref) ·
[`fix_in_frame!`](@ref) · [`Dof`](@ref) — in
[the animation](api_animation.md) and [backend](api_backend.md) references.
