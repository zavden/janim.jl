# Course 1 · 2.3 — The settings NamedTuple (Manim's config dict)
#
# CE's `config["frame_rate"]` and `with tempconfig({…})` are a global mutable
# dictionary. The Julia equivalent is a plain `NamedTuple` that you splat, and
# it is better in the two ways that matter: it is LOCAL (two scenes in one
# session cannot fight over it) and it is VISIBLE (the settings that made the
# bytes are in the call, not in a file somewhere).
#
#     const DRAFT = (; fps = 15, resolution = (640, 360), crf = 30)
#     const FINAL = (; fps = 60, resolution = (1920, 1080), crf = 18,
#                      preset = "slow", encoder_threads = 1)
#
#     Scene(construct; output = "x.mp4", DRAFT...)
#     Scene(construct; output = "x.mp4", FINAL...)
#
# The same tuple feeds the whole family, because they all take the same
# kwargs: `render_frame`, `render_segment`, `render_parallel`, `live`.
#
# One setting deserves naming: `encoder_threads = 1`. x264 is NOT
# bit-deterministic multi-threaded, so a render you want to be byte-identical
# twice — blurred or high-contrast content especially — asks for one thread.
# The FRAMES are always deterministic; it is the encoder that is not.
#
#   julia --project=. examples/tutorial/c1_02_config_and_assets/03_config_dict.jl

using Janim

const PREVIEW_T = 1.2

"Fast and ugly: for iterating."
const DRAFT = (; fps = 15, resolution = (640, 360), crf = 30, preset = "veryfast")

"Slow and exact: for the film, and byte-reproducible."
const FINAL = (; fps = 60, resolution = (1920, 1080), crf = 18, preset = "slow",
               encoder_threads = 1)

"What the tutorial actually renders."
const TUTORIAL = (; fps = 30, resolution = (854, 480))

function construct(scene)
    title = TextMobject("one NamedTuple, splatted"; size = 0.5, color = GREY_A)
    to_edge!(title, UP; buff = 0.4)

    # The scene READS its own settings: nothing here is hard-coded twice.
    facts = ["fps        $(scene.fps)",
             "pixels     $(scene.camera.width)×$(scene.camera.height)",
             "seconds/frame  $(round(1 / scene.fps; digits = 4))"]
    rows = VGroup()
    for s in facts
        add!(rows, TextMobject(s; size = 0.42, color = GREY_B))
    end
    arrange!(rows, DOWN; buff = 0.3, aligned_edge = LEFT)
    shift!(rows, 0.6 * UP)

    # A bar whose length is the frame interval, drawn at a fixed scale: at 15
    # fps it is four times the 60 fps one, which is the whole point of a draft
    # profile — fewer, longer steps.
    bar = Rectangle(width = max(0.2, 60 / scene.fps), height = 0.45)
    set_fill!(bar; color = BLUE, opacity = 1.0)
    set_stroke!(bar; opacity = 0)
    move_to!(bar, 1.6 * DOWN)
    lab = TextMobject("one frame, to scale"; size = 0.33, color = GREY_C)
    next_to!(lab, bar, DOWN; buff = 0.25)

    add!(scene, title, rows, bar, lab)
    play!(scene, GrowFromEdge(bar, LEFT); run_time = 0.8)
    wait!(scene, 0.8)
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "03_config_dict.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, TUTORIAL...)      # ← swap for DRAFT / FINAL
    println("→ ", out)
end
