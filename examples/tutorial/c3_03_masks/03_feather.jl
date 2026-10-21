# Course 3 · 3.3 — Feather: the soft edge
#
#     Mask(shape; feather = 0.25)        σ in SCENE UNITS
#
# `feather` blurs THE MASK, not the layer. The layer keeps every bit of its
# detail; what softens is the coverage, so the content fades out towards the
# edge instead of stopping at it.
#
# That distinction matters when the layer is also blurred: blurring the layer
# and feathering its mask look nothing alike. The first smears the content;
# the second leaves it sharp and dissolves it.
#
# Numbers to keep: σ is in scene units like every other size here, and the
# usable range is small — 0.05 is a soft edge, 0.4 is a vignette, and past
# about 1.0 there is no hard part of the mask left at all.
#
#   julia --project=. examples/tutorial/c3_03_masks/03_feather.jl

using Janim

const PREVIEW_T = 1.4

"A photograph stand-in: something with fine detail to keep."
function detail(x)
    g = VGroup()
    for k in 0:9
        c = Circle(radius = 0.16 + 0.16k)
        set_stroke!(c; color = color_gradient(["#FFD25E", "#FF3D8B"], 10)[k+1],
                    width = 3.0)
        set_fill!(c; opacity = 0)
        move_to!(c, Point3f(x, -0.1, 0))
        add!(g, c)
    end
    return g
end

function construct(scene)
    title = TextMobject("feather blurs the MASK, not the layer";
                        size = 0.44, color = GREY_A)
    to_edge!(title, UP; buff = 0.3)

    feathers = (0.0, 0.06, 0.25)
    xs = (-5.1, -1.7, 1.7, 5.1)          # four columns, so nothing collides
    layers = Layer[]
    labels = Mobject[]
    for (k, f) in enumerate(feathers)
        x = xs[k]
        window = Circle(radius = 1.25, fill_opacity = 1.0)
        move_to!(window, Point3f(x, -0.1, 0))
        push!(layers, Layer(detail(x); mask = Mask(window; feather = f)))
        lab = TextMobject("feather = $f"; size = 0.3, color = GREY_B)
        move_to!(lab, Point3f(x, -2.4, 0))
        push!(labels, lab)
    end

    # …and the comparison that makes the point: the SAME window, but the LAYER
    # blurred instead of the mask feathered.
    x = xs[4]
    window = Circle(radius = 1.25, fill_opacity = 1.0)
    move_to!(window, Point3f(x, -0.1, 0))
    push!(layers, Layer(detail(x); mask = Mask(window), effects = [Blur(0.09)]))
    lab = TextMobject("the LAYER blurred"; size = 0.3, color = "#FF5E5E")
    move_to!(lab, Point3f(x, -2.4, 0))
    push!(labels, lab)

    push!(layers, Layer(title, labels...))
    use_composition!(scene, Composition(layers...;
                                        background = (0.02f0, 0.03f0, 0.05f0, 1f0)))
    wait!(scene, 1.5)
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "03_feather.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
