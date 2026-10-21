# Course 3 · 1.8 — Animating the composition itself
#
# Every layer parameter and every effect dial is a plain mutable field, so
# animating them needs no new mechanism at all: an updater writes to them, or
# `UpdateFromAlphaFunc` does.
#
#     layer.opacity = …        layer.blend = :add        effect.sigma = …
#
# Two idioms, and the difference is when they run:
#
#   an UPDATER on a mobject you `add!` to the scene    → every frame, forever
#   UpdateFromAlphaFunc over the run of a `play!`      → only while it plays,
#                                                        and with an α
#
# The second is the honest one for a transition, because it ends exactly when
# the animation does instead of drifting on with the scene clock.
#
# `scene.t` is available inside an updater, which makes "a function of time"
# a one-liner — and it stays deterministic, because `scene.t` advances by
# exactly 1/fps per frame and never reads a wall clock.
#
#   julia --project=. examples/tutorial/c3_01_layers/08_animated_composition.jl

using Janim

const PREVIEW_T = 3.2

function construct(scene)
    title = TextMobject("layers and effects are mutable structs";
                        size = 0.42, color = GREY_A)
    to_edge!(title, UP; buff = 0.3)

    ring = VGroup()
    for k in 0:11
        θ = k * TAU / 12
        d = Circle(radius = 0.28)
        set_fill!(d; color = color_gradient(["#58C4DD", "#FFD25E"], 12)[k+1],
                  opacity = 1.0)
        set_stroke!(d; opacity = 0)
        move_to!(d, Point3f(2.1cos(θ), 2.1sin(θ) - 0.2, 0))
        add!(ring, d)
    end

    core = Star(7; outer_radius = 1.1)
    set_fill!(core; color = "#FF5E5E", opacity = 1.0); set_stroke!(core; opacity = 0)
    move_to!(core, 0.2 * DOWN)

    glow = Bloom(threshold = 0.35, intensity = 0.2, sigma = 0.10)
    soften = Blur(0.001)
    ring_layer = Layer(ring; effects = [glow])
    core_layer = Layer(core; blend = :normal, opacity = 1.0)

    use_composition!(scene, Composition(
        ring_layer,
        core_layer,
        Layer(; effects = [soften]),
        Layer(title);
        background = (0.02f0, 0.02f0, 0.04f0, 1f0)))

    # A rotation the ordinary way, so there is motion under the effects.
    add!(scene, ring)
    add_updater!(ring, (m, dt) -> (dt > 0 && rotate!(m, 0.6dt;
                                                     about_point = Point3f(0, -0.2, 0));
                                   nothing))

    # 1 · the glow swells, driven by α: it ends exactly with the play!.
    play!(scene, UpdateFromAlphaFunc(core, (m, a) -> begin
              glow.intensity = 0.2 + 1.6a
              core_layer.opacity = 1.0 - 0.3a
              nothing
          end); run_time = 2.0)

    # 2 · the blend mode is just a field: switch it mid-scene.
    core_layer.blend = :add
    wait!(scene, 0.8)

    # 3 · a dream transition: the adjustment layer's blur rises and falls.
    play!(scene, UpdateFromAlphaFunc(core, (m, a) ->
              (soften.sigma = 0.001 + 0.18 * there_and_back(a); nothing));
          run_time = 2.4)
    println("glow intensity: ", round(glow.intensity; digits = 2),
            " · core layer blend: ", core_layer.blend,
            " · final sigma: ", round(soften.sigma; digits = 4))
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__),
                   "08_animated_composition.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
