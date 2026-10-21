# Course 1 · 2.7 — Several scenes in one file
#
# A scene is a FUNCTION, and one file may hold several of them. Address the
# one you mean with a `:name` suffix — everywhere a scene file is accepted:
#
#   janim render <this file>:intro -qm         → 07_multiscene_intro.mp4
#   janim render <this file>:orbit -qm         → 07_multiscene_orbit.mp4
#   janim render <this file> -qm               → construct, exactly as always
#   janim <this file>:orbit                    # live preview of THAT scene
#   janim frame <this file>:intro 30 out.png   # one frame of the intro
#   janim render <this file>:orbit -j 4        # the farm takes the name too
#
# The rules, all of them small:
#
#   · No suffix means `construct` — a file with a single scene needs no suffix
#     at all.
#   · The default output gains the name: `x.jl:intro` writes `x_intro.mp4`,
#     so two scenes of one file never fight over one file name.
#   · The split is at the LAST `:`, and only when what is left of it ends
#     in `.jl` — `C:\ruta\x.jl` is a Windows path, not an address.
#   · A typo'd name fails naming the FILE and the SYMBOL. There is no scene
#     listing on purpose: a helper like `wipe!` below is indistinguishable
#     from a scene by signature, so a list would either lie or guess.
#   · Checkpoints are kept PER SCENE: `intro` and `orbit` may both write
#     `checkpoint!(scene, "act2")` without ever crossing snapshots.
#
# MIXING is the other half, and it costs zero machinery: a scene is a
# function, so another scene can just CALL it — Manim's
# `OtherScene.construct(self)` becomes `intro(scene)`. State FLOWS across
# the call (that is the point: mixing is continuing the SAME scene); wipe
# `scene.mobjects` between parts when you want a clean stage. This file's
# `construct` is exactly that mix, so the suffixless render tells the whole
# story.
#
#   julia --project=. examples/tutorial/c1_02_config_and_assets/07_multiscene.jl

using Janim

const PREVIEW_T = 4.2                  # mid-orbit, trail already drawn

"Clear the stage between parts — the optional wipe, in one line."
wipe!(scene) = remove!(scene, scene.mobjects...)

# ── scene 1 · `intro` — render it alone with  <file>:intro ───────────────
function intro(scene)
    title = TextMobject("varias escenas, un fichero"; size = 0.62)
    to_edge!(title, UP; buff = 0.7)
    rule = Line(Point3f(-3.4, 0, 0), Point3f(3.4, 0, 0))
    set_stroke!(rule; color = GREY_B, width = 3.0)
    next_to!(rule, title, DOWN; buff = 0.25)

    play!(scene, Write(title); run_time = 1.2)
    play!(scene, ShowCreation(rule); run_time = 0.6)

    tag = TextMobject("esta es «intro»"; size = 0.45, color = YELLOW)
    next_to!(tag, rule, DOWN; buff = 0.6)
    play!(scene, FadeIn(tag; shift = 0.3 * UP); run_time = 0.8)
    wait!(scene, 0.4)
end

# ── scene 2 · `orbit` — render it alone with  <file>:orbit ───────────────
function orbit(scene)
    sun = Dot(Point3f(0, -0.4, 0); radius = 0.18)
    set_fill!(sun; color = YELLOW)
    path = Circle(radius = 1.7)
    set_stroke!(path; color = GREY_C, width = 2.0)
    move_to!(path, get_center(sun))
    planet = Dot(point_from_proportion(path, 0.0); radius = 0.11)
    set_fill!(planet; color = "#2C5F8A")
    trail = TracedPath(() -> get_center(planet); stroke_color = "#2C5F8A",
                       stroke_width = 2.5)

    add!(scene, sun, path, trail, planet)
    play!(scene, MoveAlongPath(planet, path); run_time = 2.2)
    wait!(scene, 0.3)
end

# ── the default scene: the MIX — `construct` is what a bare render runs ──
function construct(scene)
    intro(scene)                       # scene 1, called like any function
    wipe!(scene)                       # optional: without it, state FLOWS
    orbit(scene)                       # scene 2, on a clean stage
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "07_multiscene.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
    println("now try:  bin/janim render ", @__FILE__, ":orbit -qm")
end
