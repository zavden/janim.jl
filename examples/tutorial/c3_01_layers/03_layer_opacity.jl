# Course 3 · 1.3 — Layer opacity vs mobject opacity
#
# Two different things wear the same word, and choosing wrong is a classic
# source of "why does that look wrong":
#
#   set_fill!(m; opacity = 0.5)      per MOBJECT. Each shape becomes
#                                    translucent, so shapes inside the same
#                                    group show through EACH OTHER.
#   Layer(m…; opacity = 0.5)         per LAYER. The group is composited as one
#                                    picture and THEN faded, so overlaps
#                                    inside it stay opaque.
#
# The layer's opacity scales the PREMULTIPLIED texture, which is exactly what
# After Effects does — and it is why a half-transparent layer never shows its
# own internal seams.
#
# Use the first when the shapes really are translucent (glass, shadows), the
# second when a whole thing should fade as a thing (a panel, a diagram, a
# subtitle card).
#
#   julia --project=. examples/tutorial/c3_01_layers/03_layer_opacity.jl

using Janim

const PREVIEW_T = 2.4

"Three overlapping discs, as one group."
function cluster(x, opacity)
    g = VGroup()
    for (dx, dy, colour) in ((-0.55, 0.3, "#3D7BC0"), (0.55, 0.3, "#E8A33D"),
                             (0.0, -0.55, "#7FDD58"))
        c = Circle(radius = 0.95)
        set_fill!(c; color = colour, opacity = opacity)
        set_stroke!(c; opacity = 0)
        move_to!(c, Point3f(x + dx, dy - 0.1, 0))
        add!(g, c)
    end
    return g
end

function construct(scene)
    title = TextMobject("mobject opacity shows the seams; layer opacity does not";
                        size = 0.4, color = GREY_A)
    to_edge!(title, UP; buff = 0.3)

    per_mobject = cluster(-3.3, 0.5)     # each disc is translucent
    per_layer = cluster(3.3, 1.0)        # opaque discs, faded as a layer

    l1 = TextMobject("set_fill!(opacity = 0.5)"; size = 0.34, color = GREY_B)
    l2 = TextMobject("Layer(…, opacity = 0.5)"; size = 0.34, color = GREY_B)
    move_to!(l1, Point3f(-3.3, -2.5, 0)); move_to!(l2, Point3f(3.3, -2.5, 0))

    fade = Ref(0.5)
    layer = Layer(per_layer; opacity = 0.5)
    clock = VGroup()
    add_updater!(clock, function (m, dt)
        dt > 0 || return
        layer.opacity = 0.5 + 0.45 * sin(1.4 * scene.t)^2
        nothing
    end)
    add!(scene, clock)

    use_composition!(scene, Composition(
        Layer(per_mobject),
        layer,
        Layer(title, l1, l2);
        background = (0.04f0, 0.05f0, 0.07f0, 1f0)))

    wait!(scene, 3.0)
    println("layer opacity at the end: ", round(layer.opacity; digits = 3))
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "03_layer_opacity.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
