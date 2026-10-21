# Course 3 · 1.5 — Precomps (a composition inside a layer)
#
#     Layer(inner_composition; blend, opacity, effects, mask)
#
# A `Composition` can be a layer's CONTENT. It is rendered to its own texture
# and then treated like any other layer — natural recursion, no special case
# in the compositor.
#
# Why you want it: it is the only way to apply an effect to the RESULT of a
# blend. Consider three shapes that must be combined with `:multiply` and then
# blurred as one picture. Blurring each of them and multiplying afterwards is
# a different image; a precomp gets the order right.
#
# It is also how you keep a complicated piece of a scene readable — build the
# gauge, the diagram, the lower third as its own Composition, then drop it
# into the film as one layer.
#
# The cost is one extra fullscreen texture per level of nesting, which is
# cheap; the accumulators are local to each call, so a precomp never tramples
# its parent's.
#
#   julia --project=. examples/tutorial/c3_01_layers/05_precomp.jl

using Janim

const PREVIEW_T = 1.8

"Three discs that must be MULTIPLIED together — the thing to precomp."
function ink(x)
    cs = Layer[]
    for (dx, dy, colour) in ((-0.5, 0.35, "#FF5E5E"), (0.5, 0.35, "#58C4DD"),
                             (0.0, -0.5, "#FFD25E"))
        c = Circle(radius = 1.0)
        set_fill!(c; color = colour, opacity = 1.0); set_stroke!(c; opacity = 0)
        move_to!(c, Point3f(x + dx, dy - 0.2, 0))
        push!(cs, Layer(c; blend = isempty(cs) ? :normal : :multiply))
    end
    return Composition(cs...)
end

function construct(scene)
    title = TextMobject("a precomp blurs the RESULT of the blend";
                        size = 0.42, color = GREY_A)
    to_edge!(title, UP; buff = 0.3)

    l1 = TextMobject("multiply, then blur (precomp)"; size = 0.32, color = GREY_B)
    l2 = TextMobject("blur each, then multiply"; size = 0.32, color = GREY_B)
    move_to!(l1, Point3f(-3.4, -2.6, 0)); move_to!(l2, Point3f(3.4, -2.6, 0))

    # LEFT: the three discs are composited FIRST (inside the precomp) and the
    # blur is applied to that one texture.
    left = Layer(ink(-3.4); effects = [Blur(0.09)])

    # RIGHT: the same three discs, each blurred on its own layer, multiplied
    # afterwards. Same ingredients, different picture.
    right = Layer[]
    for (dx, dy, colour) in ((-0.5, 0.35, "#FF5E5E"), (0.5, 0.35, "#58C4DD"),
                             (0.0, -0.5, "#FFD25E"))
        c = Circle(radius = 1.0)
        set_fill!(c; color = colour, opacity = 1.0); set_stroke!(c; opacity = 0)
        move_to!(c, Point3f(3.4 + dx, dy - 0.2, 0))
        push!(right, Layer(c; blend = isempty(right) ? :normal : :multiply,
                           effects = [Blur(0.09)]))
    end

    use_composition!(scene, Composition(
        left, right..., Layer(title, l1, l2);
        background = (0.02f0, 0.03f0, 0.05f0, 1f0)))

    wait!(scene, 2.0)
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "05_precomp.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
