# Course 3 · 4.7 — ChromaticAberration and Sharpen
#
#     ChromaticAberration(amount = 0.1)      scene units, AT THE CORNER
#     Sharpen(amount = 0.6; sigma = 0.05)
#
# `ChromaticAberration` is the clean cousin of `Glitch`'s RGB split: the
# separation is RADIAL — zero at the centre, growing with the distance to it —
# like a real lens. `amount` is the separation at the CORNER, measured rather
# than guessed: 0.05 puts 1.1 px there at 320p and nothing at all near the
# middle. Use it at tiny values as a "photographic" finish, or wide as an
# effect.
#
# `Sharpen` is an unsharp mask: `src + amount·(src − blur)`, reusing the same
# Gaussian rather than writing a second one. Over a UNIFORM region the blur
# equals the source, so the effect is the exact identity there — which is what
# makes it safe to leave on: it touches edges and nothing else.
#
# `sigma` sets which SCALE of detail is enhanced: small σ sharpens fine
# texture, large σ gives the halo-ish "local contrast" look.
#
#   julia --project=. examples/tutorial/c3_04_glitch/07_chromatic_and_sharpen.jl

using Janim

const PREVIEW_T = 1.2

"A pattern with detail at two scales and a flat area, to see both effects."
function chart(x)
    g = VGroup()
    flat = Rectangle(width = 2.6, height = 0.9)
    set_fill!(flat; color = "#3D7BC0", opacity = 1.0); set_stroke!(flat; opacity = 0)
    move_to!(flat, Point3f(x, 1.35, 0))
    add!(g, flat)
    for k in 0:11
        l = Line(Point3f(x - 1.25 + 0.23k, -0.1, 0), Point3f(x - 1.25 + 0.23k, 0.75, 0))
        set_stroke!(l; color = WHITE, width = 2.5)
        add!(g, l)
    end
    ring = Circle(radius = 0.75)
    set_stroke!(ring; color = "#FFD25E", width = 4.0); set_fill!(ring; opacity = 0)
    move_to!(ring, Point3f(x, -1.15, 0))
    add!(g, ring)
    return g
end

function construct(scene)
    title = TextMobject("radial split · unsharp mask"; size = 0.44, color = GREY_A)
    to_edge!(title, UP; buff = 0.3)

    cases = (("as rendered", Any[]),
             ("ChromaticAberration(0.05)", Any[ChromaticAberration(0.05)]),
             ("…(0.25)", Any[ChromaticAberration(0.25)]),
             ("Sharpen(1.4, sigma = 0.03)", Any[Sharpen(1.4; sigma = 0.03)]))

    layers = Layer[]
    labels = Mobject[]
    for (k, (name, fx)) in enumerate(cases)
        x = -5.1 + 3.4(k - 1)
        push!(layers, Layer(chart(x); effects = fx))
        lab = TextMobject(name; size = 0.26, color = GREY_B)
        move_to!(lab, Point3f(x, -2.4, 0))
        push!(labels, lab)
    end
    push!(layers, Layer(title, labels...))

    use_composition!(scene, Composition(layers...;
                                        background = (0.02f0, 0.03f0, 0.05f0, 1f0)))
    wait!(scene, 1.5)
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__),
                   "07_chromatic_and_sharpen.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
