# Course 3 · 2.3 — BoxBlur
#
#     BoxBlur(radius)        radius in scene units
#
# One horizontal pass and one vertical pass with UNIFORM weights. It is the
# cheapest blur there is (no exponentials, no weight table) and it looks it:
# a box kernel has a hard cut-off, so a bright edge leaves a visible square
# halo where a Gaussian would fall off smoothly.
#
# The useful fact: chaining THREE box blurs approximates a Gaussian to within
# a few percent. That is the central limit theorem doing the work — convolving
# a uniform distribution with itself three times is already close to normal —
# and it is how most real-time engines fake a Gaussian.
#
# Reach for `BoxBlur` when you want the boxy look (a pixel-art bloom, a cheap
# shadow) or when you are chaining; reach for `Blur` when you want a blur.
#
#   julia --project=. examples/tutorial/c3_02_blur_and_glow/03_box_blur.jl

using Janim

const PREVIEW_T = 1.4

"A bright cross on a dark field: the shape that shows a kernel's profile."
function target(x)
    g = VGroup()
    for (w, h) in ((1.8, 0.24), (0.24, 1.8))
        r = Rectangle(width = w, height = h)
        set_fill!(r; color = WHITE, opacity = 1.0); set_stroke!(r; opacity = 0)
        move_to!(r, Point3f(x, 0.1, 0))
        add!(g, r)
    end
    dot = Circle(radius = 0.42)
    set_fill!(dot; color = "#FFD25E", opacity = 1.0); set_stroke!(dot; opacity = 0)
    move_to!(dot, Point3f(x, 0.1, 0))
    add!(g, dot)
    return g
end

function construct(scene)
    title = TextMobject("a box kernel cuts off; a Gaussian falls off";
                        size = 0.42, color = GREY_A)
    to_edge!(title, UP; buff = 0.3)

    cases = (("no blur", Any[]),
             ("BoxBlur(0.08)", Any[BoxBlur(0.08)]),
             ("BoxBlur ×3", Any[BoxBlur(0.08), BoxBlur(0.08), BoxBlur(0.08)]),
             ("Blur(0.08)", Any[Blur(0.08)]))

    layers = Layer[]
    labels = Mobject[]
    for (k, (name, fx)) in enumerate(cases)
        x = -5.1 + 3.4(k - 1)
        push!(layers, Layer(target(x); effects = fx))
        lab = TextMobject(name; size = 0.32, color = GREY_B)
        move_to!(lab, Point3f(x, -2.2, 0))
        push!(labels, lab)
    end
    push!(layers, Layer(title, labels...))

    use_composition!(scene, Composition(layers...;
                                        background = (0.02f0, 0.03f0, 0.05f0, 1f0)))
    wait!(scene, 1.5)
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "03_box_blur.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
