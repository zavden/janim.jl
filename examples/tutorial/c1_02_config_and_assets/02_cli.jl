# Course 1 · 2.2 — The CLI
#
# `bin/janim` is pure bash talking to a Julia daemon over /dev/tcp. It never
# starts Julia itself, so the compile time is paid ONCE by the daemon and a
# warm frame comes back in ~17 ms. That includes `preview`: with the daemon
# up, the live window opens in the warm process — Esc or `q` closes it (so
# does Ctrl-C in the terminal, or the window's close button). With no daemon
# it falls back to a cold start (~4 s of Julia) and says so.
#
#   janim daemon start                       # once per session
#   janim frame  <this file> 45 out.png      # frame 45, for looking at
#   janim render <this file> -o out.mp4 -r 1280x720 --fps 30
#   janim render <this file> --from act2     # skip everything before the mark
#   janim render <this file> -n 3,5          # only animations 3 to 5
#   janim render <this file> -j 4            # the farm: 4 processes
#   janim preview <this file>                # live window, hot reload, Esc/q quits
#   janim states  <this file>                # which checkpoints are fresh
#
# Flags adopted from Manim: -r/--resolution, --fps, -o, -n, -p — and, since
# the quality presets: -qs 360p10 · -ql 480p15 · -qm 720p30 · -qh 1080p60
# · -qq 1440p60 · -qk 4K60. You would type the geometry EVERY time otherwise, and
# the presets keep the numbers written out in the help instead of in someone's head.
#
# TWO WAYS TO CUT A LONG SCENE, and they are not the same tool:
#
#   -n X,Y     numbers every play! AND every wait!, gates the DRAWING only
#              (the scene is still simulated in full, which is what makes the
#              output byte-identical to those frames of the whole film).
#              Sugar for exploring: insert one play! and every number shifts.
#   --from L   jumps to `checkpoint!(scene, "L")` using a snapshot, so the
#              prefix is not even simulated. Anchored by NAME, so it survives
#              edits. The snapshot is keyed by a hash of the file BEFORE the
#              mark: edit the prefix and it invalidates itself.
#
#   julia --project=. examples/tutorial/c1_02_config_and_assets/02_cli.jl

using Janim

const PREVIEW_T = 3.0

function construct(scene)
    title = TextMobject("act 1"; size = 0.7, color = GREY_A)
    to_edge!(title, UP; buff = 0.5)
    add!(scene, title)

    # ── act 1 · animations 1–3 ───────────────────────────────────────────
    dots = VGroup()
    for k in 0:11
        d = Dot(Point3f(-4.4 + 0.8k, 0.8, 0); radius = 0.14)
        set_fill!(d; color = "#2C5F8A")
        add!(dots, d)
    end
    play!(scene, LaggedStart([FadeIn(d) for d in dots.submobjects]...;
                             lag_ratio = 0.12); run_time = 1.5)   # animation 1
    play!(scene, animate(dots, (rotate!, TAU / 24)); run_time = 1.0)  # animation 2
    wait!(scene, 0.5)                                                # animation 3

    # A checkpoint is one call, and it is the same call in both modes: in a
    # normal run it SAVES the state here; under `--from act2` it is where the
    # skipped prefix hands over. Keep it at top level of construct — the
    # invalidation hash is computed from its line in the source.
    checkpoint!(scene, "act2")

    # ── act 2 · animations 4–6 ───────────────────────────────────────────
    play!(scene, Transform(title, begin
              t = TextMobject("act 2"; size = 0.7, color = YELLOW)
              to_edge!(t, UP; buff = 0.5); t
          end); run_time = 0.8)                                      # animation 4
    ring = Circle(radius = 1.6)
    set_stroke!(ring; color = YELLOW, width = 5.0)
    set_fill!(ring; opacity = 0)
    move_to!(ring, 1.1 * DOWN)
    play!(scene, ShowCreation(ring); run_time = 1.2)                 # animation 5
    wait!(scene, 0.8)                                                # animation 6
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "02_cli.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
    println("now try:  bin/janim render ", @__FILE__, " -n 4,6 -o act2.mp4")
end
