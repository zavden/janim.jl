# Course 3 · 3.8 — An SVG's own clipPaths
#
#     clip_layers(svg) → Vector{Layer}
#
# An SVG file can declare `<clipPath>` elements, and a real renderer honours
# them per pixel. Manim rasterises them away — the shapes are imported, the
# clipping is not. Here the importer keeps them: every clipped child gets its
# own `Layer` with a real `Mask`, and `clip_layers` hands you the list ready
# to drop into a `Composition`.
#
#     comp = Composition(clip_layers(svg)...; background = (0, 0, 0, 1))
#     use_composition!(scene, comp)
#
# What to know:
#
#   · children WITHOUT a clip share painter's-order layers; each clipped one
#     gets a layer of its own, because two elements may reference the same
#     clipPath from different transforms.
#   · the mask shapes are COPIES frozen at call time — a static clip. Move the
#     drawing and call `clip_layers` again if the clip must follow.
#   · without it, `SVGMobject` still imports everything; the clip simply has
#     no effect, which is exactly what you saw in course 1, lesson 2.4.
#
#   julia --project=. examples/tutorial/c3_03_masks/08_svg_clip_layers.jl

using Janim

# Careful with this one: `render_frame`'s fallback for a `t` PAST THE END of
# the scene draws `scene.mobjects`, which a composition-based scene leaves
# empty — so an out-of-range preview time comes out black. Keep it inside.
const PREVIEW_T = 1.2

function construct(scene)
    path = joinpath(@__DIR__, "..", "..", "assets", "badge.svg")

    plain = SVGMobject(path; height = 3.6)
    move_to!(plain, 3.6 * LEFT + 0.2 * DOWN)

    clipped = SVGMobject(path; height = 3.6)
    move_to!(clipped, 3.6 * RIGHT + 0.2 * DOWN)

    title = TextMobject("clipPath, honoured per pixel"; size = 0.44, color = GREY_A)
    to_edge!(title, UP; buff = 0.3)
    l1 = TextMobject("SVGMobject alone"; size = 0.32, color = GREY_B)
    l2 = TextMobject("clip_layers(svg)"; size = 0.32, color = GREY_B)
    move_to!(l1, Point3f(-3.6, -2.6, 0)); move_to!(l2, Point3f(3.6, -2.6, 0))

    layers = clip_layers(clipped)
    println("clip_layers gave ", length(layers), " layers · ",
            count(l -> l.mask !== nothing, layers), " of them masked")

    use_composition!(scene, Composition(
        Layer(plain),
        layers...,
        Layer(title, l1, l2);
        background = (0.02f0, 0.03f0, 0.05f0, 1f0)))

    wait!(scene, 1.5)
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__),
                   "08_svg_clip_layers.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
