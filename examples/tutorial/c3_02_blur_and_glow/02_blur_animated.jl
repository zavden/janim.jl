# Course 3 · 2.2 — An animated blur (the dream transition)
#
# `Blur` is a mutable struct, so σ is just a field. Writing to it from
# `UpdateFromAlphaFunc` — which stops exactly when the animation does — is the
# whole technique.
#
# It is continuous in σ, on purpose: the weights are recomputed per frame and
# the pass is skipped below 0.3 px rather than snapping to a 1-pixel kernel.
# So a blur that rises from 0 has no visible first step.
#
# THE STANDARD TRANSITION: an adjustment layer over everything, σ up while the
# old content leaves, σ down while the new content arrives. Nothing else has
# to know a transition is happening.
#
# And a trap this lesson exists to avoid. **`FadeIn(m)` animates from
# transparent TO THE MOBJECT AS IT STANDS** — so a mobject you already made
# invisible (`set_fill!(m; opacity = 0)`) fades in to… invisible, and nothing
# happens. Under a composition the fix is neater than fighting it: build the
# content opaque and animate the LAYER's opacity, which is one field and shows
# no internal seams (lesson 1.3).
#
#   julia --project=. examples/tutorial/c3_02_blur_and_glow/02_blur_animated.jl

using Janim

const PREVIEW_T = 2.4

function construct(scene)
    caption = TextMobject("blur up, swap, blur down"; size = 0.42, color = GREY_A)
    to_edge!(caption, UP; buff = 0.3)

    scene_a = VGroup()
    for k in 0:5
        c = Circle(radius = 0.55)
        set_fill!(c; color = "#3D7BC0", opacity = 1.0); set_stroke!(c; opacity = 0)
        move_to!(c, Point3f(-3.5 + 1.4k, 0.2, 0))
        add!(scene_a, c)
    end

    scene_b = VGroup()
    for k in 0:5
        s = Star(5; outer_radius = 0.62)
        set_fill!(s; color = "#FFD25E", opacity = 1.0)   # OPAQUE: see the note
        set_stroke!(s; opacity = 0)
        move_to!(s, Point3f(-3.5 + 1.4k, 0.2, 0))
        add!(scene_b, s)
    end

    soften = Blur(0.001)
    layer_a = Layer(scene_a)
    layer_b = Layer(scene_b; opacity = 0.0)      # …and hidden by its LAYER

    use_composition!(scene, Composition(
        layer_a, layer_b,
        Layer(; effects = [soften]),
        Layer(caption);
        background = (0.02f0, 0.03f0, 0.05f0, 1f0)))

    wait!(scene, 0.5)

    # UP: σ rises while the first set goes.
    play!(scene, UpdateFromAlphaFunc(scene_a, function (m, a)
              soften.sigma = 0.001 + 0.20a
              layer_a.opacity = 1.0 - a
              nothing
          end); run_time = 1.2)

    # DOWN: σ falls while the second arrives. The swap happened while nobody
    # could see it, which is the entire point of the gesture.
    play!(scene, UpdateFromAlphaFunc(scene_b, function (m, a)
              soften.sigma = 0.20 - 0.199a
              layer_b.opacity = a
              nothing
          end); run_time = 1.2)
    wait!(scene, 0.6)
    println("sigma back to ", round(soften.sigma; digits = 4),
            " (the pass is skipped) · layer opacities ",
            round(layer_a.opacity; digits = 2), " / ",
            round(layer_b.opacity; digits = 2))
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "02_blur_animated.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
