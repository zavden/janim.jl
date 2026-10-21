# Course 3 · 4.6 — The cheap family
#
# Four effects that cost one pass each and are used constantly:
#
#     ColorAdjust(; brightness = 1, contrast = 1, saturation = 1, hue = 0)
#     Pixelate(size = 0.2)
#     Vignette(; amount = 0.5, radius = 0.5, feather = 0.4)
#     Grain(; amount = 0.15, seed = 1, rate = 1, levels = 8)
#
# `ColorAdjust` is ONE struct with four dials rather than four structs,
# because they are always used together and each alone would pay for its own
# fullscreen pass. `brightness` multiplies, `contrast` pivots about 0.5,
# `saturation` mixes towards the luma, and `hue` rotates in radians about the
# grey axis (Rodrigues) — so greys are a fixed point and the rotation is
# exactly 2π-periodic. All four at identity → the pass is skipped.
#
# `Pixelate`'s `size` is in scene units, so "zoom until you see the pixels"
# looks the same at any resolution. Every cell takes the colour of its CENTRE,
# so a cell really is one colour.
#
# `Vignette`'s `radius` and `feather` are fractions of the half-diagonal: the
# centre is untouched exactly and the corner falls by exactly `amount`.
#
# `Grain`'s `levels` quantises the noise factor to exact binary steps. That is
# not decoration: a continuous factor over a colour leaves ~0.3% of pixels
# within one ULP of the 8-bit rounding edge, and those flip between runs.
#
#   julia --project=. examples/tutorial/c3_04_glitch/06_cheap_family.jl

using Janim

const PREVIEW_T = 1.2

"A photographic-looking tile."
function tile(x)
    g = VGroup()
    sky = Rectangle(width = 2.9, height = 2.1)
    set_fill_by_gradient!(sky, "#1B4F8C", "#39D0FF")
    set_fill!(sky; opacity = 1.0); set_stroke!(sky; opacity = 0)
    move_to!(sky, Point3f(x, 0.5, 0))
    add!(g, sky)
    sun = Circle(radius = 0.36)
    set_fill!(sun; color = "#FFF0B0", opacity = 1.0); set_stroke!(sun; opacity = 0)
    move_to!(sun, Point3f(x + 0.8, 1.1, 0))
    add!(g, sun)
    hill = Triangle(radius = 1.0)
    set_fill!(hill; color = "#2F7A46", opacity = 1.0); set_stroke!(hill; opacity = 0)
    move_to!(hill, Point3f(x - 0.3, -0.1, 0))
    add!(g, hill)
    return g
end

function construct(scene)
    title = TextMobject("four dials, one pass each"; size = 0.44, color = GREY_A)
    to_edge!(title, UP; buff = 0.3)

    cases = (("as rendered", Any[]),
             ("ColorAdjust(hue = 2.1)", Any[ColorAdjust(; hue = 2.1, saturation = 1.3)]),
             ("Pixelate(0.13)", Any[Pixelate(0.13)]),
             ("Vignette + Grain", Any[Vignette(; amount = 0.75, radius = 0.35),
                                      Grain(; amount = 0.28, seed = 9)]))

    layers = Layer[]
    labels = Mobject[]
    for (k, (name, fx)) in enumerate(cases)
        x = -5.1 + 3.4(k - 1)
        push!(layers, Layer(tile(x); effects = fx))
        lab = TextMobject(name; size = 0.28, color = GREY_B)
        move_to!(lab, Point3f(x, -1.6, 0))
        push!(labels, lab)
    end
    push!(layers, Layer(title, labels...))

    use_composition!(scene, Composition(layers...;
                                        background = (0.02f0, 0.03f0, 0.05f0, 1f0)))
    wait!(scene, 1.5)
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "06_cheap_family.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
