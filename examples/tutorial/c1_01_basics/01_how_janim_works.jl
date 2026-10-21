# Course 1 · 1.1 — How Janim works
#
# Three ideas, and everything else in the course is a consequence of them.
#
# 1. `construct(scene)` is a CONTRACT, not a convention. The daemon, the render
#    farm and the live window all look that name up in your file. Define it
#    and every tool works on your scene.
# 2. A frame is one step of a FIXED clock. `play!(…; run_time = 2)` at 30 fps
#    is exactly 60 steps of dt = 1/30 s. Nothing is measured against the wall
#    clock, which is what makes two renders of this file give byte-identical
#    frames (the mp4 container is x264's: identical too with encoder_threads = 1).
# 3. Each of those steps hands the animation an α — and the αs are the
#    MIDPOINTS (k + ½)/n, never 0 and never 1. So the first drawn frame is
#    already half a step in, and the exact end pose (α = 1) belongs to
#    `finish!`, i.e. to the frame AFTER the animation.
#
#   julia --project=. examples/tutorial/c1_01_basics/01_how_janim_works.jl

using Janim

const PREVIEW_T = 1.6

function construct(scene)
    title = TextMobject("A frame is one step of a fixed clock"; size = 0.55)
    to_edge!(title, UP; buff = 0.6)
    add!(scene, title)

    # The sampling line: five ticks at α = 0.1, 0.3, 0.5, 0.7, 0.9 — where a
    # five-frame animation is actually evaluated.
    line = NumberLine((0.0, 1.0, 0.25); width = 9.0, include_numbers = true,
                      num_decimal_places = 2)
    shift!(line, 1.2 * DOWN)
    add!(scene, line)

    n = 5
    samples = VGroup()
    for k in 0:n-1
        d = Dot(number_to_point(line, (k + 0.5) / n); radius = 0.09)
        set_fill!(d; color = YELLOW)
        add!(samples, d)
    end
    add!(scene, samples)

    alpha_label = TextMobject("alpha = (k + 1/2) / n"; size = 0.42, color = YELLOW)
    next_to!(alpha_label, line, DOWN; buff = 0.55)
    add!(scene, alpha_label)

    # The thing being animated: a square crossing the same interval.
    box = Square(side_length = 0.7)
    set_fill!(box; color = BLUE, opacity = 1.0)
    set_stroke!(box; opacity = 0)
    move_to!(box, number_to_point(line, 0.0) + 1.4 * UP)
    add!(scene, box)

    play!(scene, LaggedStart([FadeIn(d; shift = 0.3 * UP) for d in samples.submobjects]...;
                             lag_ratio = 0.25); run_time = 1.2)
    # NOTE where `rate_func` goes: on the ANIMATION, not on `play!`. `play!`
    # only knows about time (`run_time`); how α moves inside that time is the
    # animation's business, and that split is why the same animation behaves
    # identically under `play!`, `Timeline` and `render_frame`.
    play!(scene, animate(box, (move_to!, number_to_point(line, 1.0) + 1.4 * UP);
                         rate_func = linear); run_time = 2.0)
    wait!(scene, 0.6)

    # A3, the agent hook: the scene's state as text, with no GL involved.
    # `scene.last_alphas` is literally the list the last `play!` handed the
    # animation — the arithmetic above, measured rather than promised.
    println("fps = ", scene.fps, " · frames so far = ", scene.frames,
            " · t = ", round(scene.t; digits = 3), " s")
    println("alphas of the last play!: ",
            round.(scene.last_alphas[1:min(end, 6)]; digits = 3), " …")
    println(join(first(split(describe(scene), '\n'), 4), '\n'), "\n  …")
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "01_how_janim_works.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
