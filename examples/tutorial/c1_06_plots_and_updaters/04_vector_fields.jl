# Course 1 · 6.4 — Vector fields and stream lines
#
#     VectorField(func, axes; density, magnitude_range, stroke_width)
#     TimeVaryingVectorField((coords, t) -> ..., axes; ...)
#     update_vectors!(vf)                 re-lay the arrows after a change
#     StreamLines(func, axes; density, solution_time, dt, magnitude_range,
#                 color_by_magnitude, taper_stroke_width)
#     AnimatedStreamLines(sl; time_width, lag_range)
#     ode_solution_points(func, state0, time; dt)
#
# `func` is pointwise over COORDINATES: `c -> (fx, fy)`. A whole field is
# ONE VMobject — every arrow is 8 points and its head is a per-point
# stroke-width pattern, so a dense field costs one draw call. Long vectors
# clamp smoothly with tanh instead of overlapping their neighbours, and
# colour follows the coordinate-space magnitude through the 3b1b colormap.
#
# Two things ManimGL cannot promise here, and this engine does:
#   · the stream-line seeds and the flow phases come from a COUNTER HASH,
#     not from np.random — the same scene gives the same bytes in any
#     process, so scrubbing and the render farm both work;
#   · the integrator is a fixed-step RK4 with no external dependency,
#     checked against the CLOSED FORM (the rotation field's lines are
#     circles to 0.03%).
#
#   julia --project=. examples/tutorial/c1_06_plots_and_updaters/04_vector_fields.jl

using Janim

const PREVIEW_T = 5.8

function construct(scene)
    axes = Axes((-4.0, 4.0, 1.0), (-3.0, 3.0, 1.0); width = 11.0, height = 8.0,
                color = "#37506B", stroke_width = 2.0)

    # A time-varying field: the classic rotation, breathing with cos(t/2).
    # The updater it installs advances `vf.time` and re-lays every arrow —
    # 221 arrows re-laid in ~0.4 ms, so it never touches the frame budget.
    vf = TimeVaryingVectorField((c, t) -> (cos(0.5t) * -c[2], cos(0.5t) * c[1]),
                                axes; density = 2.0, magnitude_range = (0.0, 3.0))
    add!(scene, axes, vf)

    # Stream lines are the same field INTEGRATED: seeds on the grid
    # (hash-jittered), each line a smoothed RK4 solution, coloured by the
    # local magnitude. AnimatedStreamLines turns them into travelling
    # packets — a gaussian window over the per-point stroke widths; the
    # points themselves never move.
    sl = StreamLines(c -> (-c[2], c[1]), axes; density = 1.0,
                     solution_time = 3.0, magnitude_range = (0.0, 3.0),
                     stroke_width = 2.0)
    add!(scene, AnimatedStreamLines(sl))

    hud = TextMobject("d/dt (x, y) = ω(t) · (-y, x)"; size = 0.4, color = GREY_A)
    to_corner!(hud, UL; buff = 0.35)
    fix_in_frame!(hud)
    add!(scene, hud)

    wait!(scene, 6.5)
    println("arrows: ", length(vf.sample_coords),
            " · lines: ", length(sl),
            " · points per line: ", length(sl[1].points))
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "04_vector_fields.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
