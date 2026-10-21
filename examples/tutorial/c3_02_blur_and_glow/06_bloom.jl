# Course 3 · 2.6 — Bloom (the glow)
#
#     Bloom(; threshold = 0.6, intensity = 1.0, sigma = 0.15)
#
# Three steps, and knowing them is what lets you tune it instead of guessing:
#
#   1. BRIGHT PASS — keep only what is brighter than `threshold`
#      (`max(colour − threshold, 0)`), so a mid-grey contributes nothing;
#   2. a PYRAMID of blurs at σ, 2σ and 4σ, summed. One σ gives a halo with a
#      visible edge; three octaves give the soft falloff a lens has;
#   3. ADD the halo back at `intensity`.
#
# How to tune it: `threshold` decides WHAT glows (lower it and everything
# does), `sigma` decides HOW FAR the light spills, `intensity` decides how
# bright the spill is. If the picture looks washed out, the threshold is too
# low — raise it before lowering the intensity.
#
# Bloom on a layer whose blend is `:add` is the classic neon recipe; that is
# lesson 2.8.
#
#   julia --project=. examples/tutorial/c3_02_blur_and_glow/06_bloom.jl

using Janim

const PREVIEW_T = 1.4

"A bright glyph and a mid-grey one: the threshold's whole point."
function pair(x)
    g = VGroup()
    hot = Star(6; outer_radius = 0.85)
    set_fill!(hot; color = "#FFF6C0", opacity = 1.0); set_stroke!(hot; opacity = 0)
    move_to!(hot, Point3f(x, 0.75, 0))
    add!(g, hot)
    cold = Star(6; outer_radius = 0.85)
    set_fill!(cold; color = "#4A5568", opacity = 1.0); set_stroke!(cold; opacity = 0)
    move_to!(cold, Point3f(x, -1.1, 0))
    add!(g, cold)
    return g
end

function construct(scene)
    title = TextMobject("threshold picks WHAT glows; sigma, how far";
                        size = 0.42, color = GREY_A)
    to_edge!(title, UP; buff = 0.3)

    cases = (("no bloom", nothing),
             ("threshold 0.6", Bloom(threshold = 0.6, intensity = 1.2, sigma = 0.10)),
             ("sigma 0.25", Bloom(threshold = 0.6, intensity = 1.2, sigma = 0.25)),
             ("threshold 0.15", Bloom(threshold = 0.15, intensity = 1.2, sigma = 0.10)))

    layers = Layer[]
    labels = Mobject[]
    for (k, (name, bloom)) in enumerate(cases)
        x = -5.1 + 3.4(k - 1)
        push!(layers, Layer(pair(x); effects = bloom === nothing ? Any[] : Any[bloom]))
        lab = TextMobject(name; size = 0.3, color = GREY_B)
        move_to!(lab, Point3f(x, -2.6, 0))
        push!(labels, lab)
    end
    push!(layers, Layer(title, labels...))

    use_composition!(scene, Composition(layers...;
                                        background = (0.02f0, 0.02f0, 0.04f0, 1f0)))
    wait!(scene, 1.5)
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "06_bloom.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
