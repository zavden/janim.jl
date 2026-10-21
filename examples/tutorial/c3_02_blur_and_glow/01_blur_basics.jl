# Course 3 · 2.1 — Blur
#
#     Blur(σ; in_pixels = false)
#
# A separable Gaussian in two passes (horizontal, then vertical), which is
# what makes it O(2r) per pixel instead of O(r²).
#
# σ IS IN SCENE UNITS by default, converted through the camera. That is the
# decision worth copying into your own effects: a blur specified in pixels
# looks different at 480p and at 1080p, so the preview would lie about the
# film. `in_pixels = true` is there for the rare case where you really mean
# pixels.
#
# Two numbers behind it: the kernel radius is `ceil(3σ)` (three sigmas cover
# 99.7% of the mass) clamped to 63, and below σ = 0.3 px the pass is SKIPPED —
# it would be imperceptible, and skipping keeps σ → 0 continuous instead of
# quantising to a one-pixel kernel.
#
#   julia --project=. examples/tutorial/c3_02_blur_and_glow/01_blur_basics.jl

using Janim

const PREVIEW_T = 1.4

"A test card: hard edges, thin lines and text — everything a blur shows off."
function card(x)
    g = VGroup()
    sq = Square(side_length = 1.5)
    set_fill!(sq; color = "#E8A33D", opacity = 1.0); set_stroke!(sq; opacity = 0)
    move_to!(sq, Point3f(x, 0.85, 0))
    add!(g, sq)
    for k in 0:6
        l = Line(Point3f(x - 1.1 + 0.36k, -0.6, 0), Point3f(x - 1.1 + 0.36k, -1.7, 0))
        set_stroke!(l; color = "#58C4DD", width = 3.0)
        add!(g, l)
    end
    t = TextMobject("edge"; size = 0.42, color = WHITE)
    move_to!(t, Point3f(x, -2.2, 0))
    add!(g, t)
    return g
end

function construct(scene)
    title = TextMobject("sigma is in SCENE UNITS, so the look survives the resolution";
                        size = 0.38, color = GREY_A)
    to_edge!(title, UP; buff = 0.3)

    sigmas = (0.0, 0.03, 0.09, 0.22)
    layers = Layer[]
    labels = Mobject[]
    for (k, σ) in enumerate(sigmas)
        x = -5.1 + 3.4(k - 1)
        push!(layers, Layer(card(x); effects = σ == 0 ? Any[] : Any[Blur(σ)]))
        lab = TextMobject(σ == 0 ? "no blur" : "Blur($σ)"; size = 0.32, color = GREY_B)
        move_to!(lab, Point3f(x, -3.0, 0))
        push!(labels, lab)
    end
    push!(layers, Layer(title, labels...))

    use_composition!(scene, Composition(layers...;
                                        background = (0.02f0, 0.03f0, 0.05f0, 1f0)))
    wait!(scene, 1.5)
    println("at 854 px wide, 1 scene unit is ",
            round(854 / FRAME_WIDTH; digits = 1), " px — so Blur(0.09) is a ",
            round(0.09 * 854 / FRAME_WIDTH; digits = 1), " px sigma")
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "01_blur_basics.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
