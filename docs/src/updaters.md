# Updaters and trackers

An updater is a function that runs once per frame, for as long as its mobject
is on stage. It is how anything behaves rather than merely being animated.

```julia
add_updater!(m, (m, dt) -> shift!(m, dt * RIGHT))     # 1 unit per second
add_updater!(label, m -> next_to!(m, dot, UP))        # a follower
add_updater!(m) do mob, dt                            # do-block, for several lines
    rotate!(mob, dt * TAU / 4)
end
```

The arity is DETECTED: a function of `(mob, dt)` gets the frame's time step, one
of `(mob)` does not. A `dt`-taking updater INTEGRATES and therefore depends on
how it got here; a position-following one is a pure function of the current
state. [`has_time_based_updaters`](@ref) is how the scene tells them apart.

## The four traps

These are not edge cases. Every one of them is something a scene hits on the
way to working.

### 1 · Registration calls the updater with `dt = 0`

`add_updater!` runs it once immediately, which is what places a follower
correctly on the frame it is created. Anything that steps an integrator must
therefore guard:

```julia
add_updater!(m, (m, dt) -> begin
    dt > 0 && step!(integrator, dt, true)
    move_to!(m, point_of(integrator))
end)
```

Pass `call = false` to skip the initial call.

### 2 · Points made in an updater re-stamp the factory style

A mobject whose points are rebuilt every frame must be BORN with its final
style. A `set_fill!` afterwards, or a fade, writes on water.

```julia
trail = VMobject(; color = YELLOW, stroke_width = 3)   # right
add_updater!(trail, m -> set_points_smoothly!(m, history))
```

### 3 · Freeze before fading out

An updater that keeps writing while [`FadeOut`](@ref) runs undoes the fade
every frame. The idiom is a flag the updater checks:

```julia
alive = Ref(true)
add_updater!(m, mob -> begin
    alive[] || return
    next_to!(mob, dot, UP)
end)
…
alive[] = false
play!(scene, FadeOut(m))
```

[`suspend_updating!`](@ref) does the same for every updater on a mobject, and
[`resume_updating!`](@ref) brings them back.

### 4 · `bring_to_back!` also moves the UPDATE order

A [`TracedPath`](@ref) sent to the back reads last frame's position and lags
exactly one frame. When a mobject's updater reads state another updater writes,
order matters — use [`set_z_index!`](@ref), which changes what draws on top
without touching who runs first.

## Trackers

A [`ValueTracker`](@ref) is a number that lives in the scene, so it can be
animated like anything else and read from anywhere.

```julia
vt = ValueTracker(0.0)
add!(scene, vt)

dot = Dot()
add_updater!(dot, m -> move_to!(m, c2p(ax, get_value(vt), f(get_value(vt)))))

play!(scene, animate(vt, (set_value!, 10.0)); run_time = 4, rate_func = linear)
```

This is the central idiom for a graph being traced, a parameter being swept, a
counter running: ONE animated number, and everything else follows it through
updaters. [`increment_value!`](@ref) adds to it.

[`DecimalNumber`](@ref) is the number as text, and it re-centres on its
previous centre when the value changes — so a counter going 9.9 → 10.0 does not
jump sideways as it gains a digit:

```julia
counter = DecimalNumber(0.0; num_decimal_places = 1)
add_updater!(counter, m -> set_number!(m, get_value(vt)))
```

## `always_redraw`

When something is easier to REBUILD than to update, rebuild it:

```julia
vt = ValueTracker(1.0)
circle = always_redraw(() -> Circle(; radius = get_value(vt)))
```

The function builds a mobject from scratch every frame and the result is
adopted through [`become!`](@ref), so the object's IDENTITY is stable: the
scene, a group holding it and the compositor all keep pointing at the same
thing, with nothing to re-add and no dangling references.

## Physics inside an updater

Julia's differential-equation ecosystem works inside an updater with no
adapter, which is one of the things Janim can do that Manim cannot:

```julia
integrator = init(ODEProblem(pendulum!, u0, (0.0, 1e6), p), Tsit5())

add_updater!(bob, (m, dt) -> begin
    dt > 0 && step!(integrator, dt, true)
    move_to!(m, c2p(ax, integrator.u[1], integrator.u[2]))
end)
```

Keep the integrator OUTSIDE the updater — it holds the state — and guard on
`dt > 0` for the reason in trap 1. A double pendulum driven this way holds its
energy to about 3·10⁻¹⁰ over a scene.

There is no in-loop motion blur, so nothing subdivides `dt` behind an
integrator's back; [`render_frame_motion`](@ref) makes a blurred still.

## Determinism

Two renders of the same code produce the same frames, and updaters are where
that promise is easiest to break. No unseeded randomness and no wall-clock
time: seed your generator explicitly, and derive anything periodic from the
frame number or from a tracker rather than from `time()`.

## Reference

[`add_updater!`](@ref) · [`remove_updater!`](@ref) ·
[`clear_updaters!`](@ref) · [`suspend_updating!`](@ref) ·
[`resume_updating!`](@ref) · [`update!`](@ref) · [`Updater`](@ref) ·
[`ValueTracker`](@ref) · [`get_value`](@ref) · [`set_value!`](@ref) ·
[`always_redraw`](@ref) · [`DecimalNumber`](@ref) — in
[the mobject](api_mobjects.md) and [animation](api_animation.md) references.
