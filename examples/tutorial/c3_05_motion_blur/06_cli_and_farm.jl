# Course 3 · 5.6 — Motion blur from the CLI, and the render farm
#
#     janim render scene.jl -o out.mp4 --motion-blur 8
#     janim render scene.jl -o out.mp4 --motion-blur 8,0.25    # n,shutter
#     janim render scene.jl -o out.mp4 --motion-blur 8 -j 4    # …across 4 processes
#
# The flag takes `n` or `n,shutter`, and it composes with everything else:
# `--from label` (skip to a checkpoint), `-j` (the farm), `-r`/`--fps`.
#
# WHAT IT DOES NOT COMPOSE WITH, and the refusal is deliberate: `-n X,Y` (an
# animation range) inside `render_parallel`. A worker whose frame range does
# not intersect the animation range would emit an mp4 with NO frames, and
# `ffmpeg -f concat` would splice an empty segment without complaining. So the
# farm refuses the combination instead of producing a silently short film.
#
# Two more practical notes:
#
#   · for a BYTE-reproducible blurred render, add `encoder_threads = 1`. x264
#     is not bit-deterministic multi-threaded, and blurred content is exactly
#     the high-frequency case where it shows. The FRAMES are deterministic
#     either way — measured: 30/30 identical at crf = 0.
#   · cost is linear in n: the scene is simulated once and DRAWN n times.
#     Check a still with `render_frame_motion` first (lesson 5.4).
#
#   julia --project=. examples/tutorial/c3_05_motion_blur/06_cli_and_farm.jl

using Janim

const PREVIEW_T = 1.4
const PREVIEW_MOTION = 8

function construct(scene)
    title = TextMobject("--motion-blur N[,SHUTTER]"; size = 0.5, color = GREY_A)
    to_edge!(title, UP; buff = 0.4)
    add!(scene, title)

    commands = VGroup()
    for s in ("janim render scene.jl -o out.mp4 --motion-blur 8",
              "janim render scene.jl -o out.mp4 --motion-blur 8,0.25",
              "janim render scene.jl -o out.mp4 --motion-blur 8 -j 4",
              "janim render scene.jl -o out.mp4 --motion-blur 8 --from act2")
        add!(commands, TextMobject(s; size = 0.32, color = "#7FDD58",
                                   font = "Liberation Mono"))
    end
    arrange!(commands, DOWN; buff = 0.28, aligned_edge = LEFT)
    move_to!(commands, 1.4 * UP)
    add!(scene, commands)

    # Something moving, so the rendered file actually shows the flag's effect.
    runner = VGroup()
    for k in 0:4
        d = Dot(Point3f(-5.4, -1.6 - 0.0k, 0); radius = 0.18 - 0.02k)
        set_fill!(d; color = color_gradient(["#39D0FF", "#FF3D8B"], 5)[k+1])
        add!(runner, d)
    end
    add!(scene, runner)

    play!(scene, LaggedStart([FadeIn(c) for c in commands.submobjects]...;
                             lag_ratio = 0.2); run_time = 1.2)
    play!(scene, AnimationGroup([animate(d, (shift!, Point3f(10.6, 0, 0));
                                         rate_func = linear)
                                 for d in runner.submobjects]...; lag_ratio = 0.08);
          run_time = 1.6)
    wait!(scene, 0.4)
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "06_cli_and_farm.mp4")
    mkpath(dirname(out))
    # The kwargs form of the same flags — plus the byte-reproducible encoder.
    Scene(construct; output = out, fps = 30, resolution = (854, 480),
          motion_blur = 8, shutter = 0.5, encoder_threads = 1)
    println("→ ", out)
end
