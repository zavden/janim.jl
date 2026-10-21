# Course 2 · 1.2 — dt updaters
#
#     add_updater!(m, (m, dt) -> …)   time-based: dt is the frame interval
#     add_updater!(m, m -> …)         state-based: no clock at all
#
# WHICH ONE YOU GET IS DECIDED BY ARITY. The engine asks `methods(f)` whether a
# two-argument method exists — the same question ManimGL asks `inspect`.
#
# Four things that bite, in the order they bite:
#
#   1. REGISTRATION CALLS THE UPDATER ONCE WITH dt = 0. So anything that
#      integrates must start with `dt > 0 &&`, or the first call advances a
#      solver by nothing and, worse, `TracedPath` would record a sample before
#      the scene has started.
#   2. dt IS THE FRAME INTERVAL, not wall-clock time. At 30 fps it is exactly
#      1/30 in production. That is what makes an updater deterministic.
#   3. A mobject whose POINTS are built inside an updater must be born with
#      its final style: new points re-stamp the factory style, so styling it
#      afterwards is undone on the next frame.
#   4. FREEZE an updater before fading its mobject out (a `Ref{Bool}` is
#      enough). Otherwise the updater keeps re-stamping the default style and
#      the fade has no visible effect.
#
# `suspend_updating!` / `resume_updating!` do the same job for a whole
# subtree, and `parallel = true` promises the scene that this updater touches
# only its own mobject — that promise is what lets it run on a thread.
#
#   julia --project=. examples/tutorial/c2_01_updaters_and_custom_mobjects/02_dt_updaters.jl

using Janim

const PREVIEW_T = 2.5

function construct(scene)
    title = TextMobject("dt is the frame interval, not the wall clock";
                        size = 0.44, color = GREY_A)
    to_edge!(title, UP; buff = 0.35)
    add!(scene, title)

    # A hand-rolled integrator: position += velocity·dt, with a wall bounce.
    ball = Dot(Point3f(-5.0, 1.2, 0); radius = 0.22)
    set_fill!(ball; color = "#58C4DD")
    vel = Ref(Point3f(3.4, 0.0, 0))
    live = Ref(true)                       # trap 4: the freeze switch
    add_updater!(ball, function (m, dt)
        (live[] && dt > 0) || return       # trap 1: the dt = 0 registration call
        p = get_center(m) + Float32(dt) * vel[]
        if abs(p[1]) > 5.0
            vel[] = Point3f(-vel[][1], vel[][2], 0)
            p = get_center(m) + Float32(dt) * vel[]
        end
        move_to!(m, p)
        nothing
    end)

    # Trap 3, made visible: this mobject's POINTS are rebuilt every frame, so
    # it is born with its final style and never restyled afterwards.
    ruler = VMobject(); set_stroke!(ruler; color = "#FFD25E", width = 3.0)
    add_updater!(ruler, function (m, dt)
        set_points_as_corners!(m, [Point3f(-5.6, -1.4, 0),
                                   Point3f(get_center(ball)[1], -1.4, 0)])
        nothing
    end)

    # A clock that counts frames, to show dt is exactly 1/fps in production.
    frames = Ref(0)
    seconds = DecimalNumber(0.0; num_decimal_places = 2, size = 0.6, color = GREY_A)
    move_to!(seconds.group, Point3f(4.6, -2.4, 0))
    add_updater!(seconds.group, function (m, dt)
        dt > 0 || return
        frames[] += 1
        nothing
    end)
    add_updater!(seconds, d -> set_number!(d, frames[] / 30))

    add!(scene, ball, ruler, seconds)
    wait!(scene, 3.0)

    # Trap 4: freeze first, THEN fade. Comment out the `live[] = false` and
    # the ball goes on moving as it fades, which is rarely what you meant.
    live[] = false
    play!(scene, FadeOut(ball); run_time = 0.8)
    println("frames counted by the updater: ", frames[],
            " · scene frames: ", scene.frames)
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "02_dt_updaters.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
