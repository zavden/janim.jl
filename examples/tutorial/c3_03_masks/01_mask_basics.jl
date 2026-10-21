# Course 3 · 3.1 — Masks
#
#     Mask(mobjects...; invert = false, feather = 0.0, hard = false, luma = false)
#     Layer(content...; mask = Mask(shape))
#
# The mask's mobjects are rendered into their own buffer and the layer is
# MULTIPLIED by that buffer's alpha. So the cut-out is per PIXEL and exact —
# antialiased edges included — not a polygon intersection.
#
# What can be a mask: anything that draws. A circle, a text mobject, an
# imported SVG, a group of a hundred dots, a shape being animated. If you can
# see it, you can cut with it.
#
# The masking mobjects are NOT drawn: they only contribute coverage. They do
# still get updated, so a mask can follow something (lesson 3.6).
#
#   julia --project=. examples/tutorial/c3_03_masks/01_mask_basics.jl

using Janim

const PREVIEW_T = 1.4

"A striped field — something whose cut edge is easy to see."
function stripes(x)
    g = VGroup()
    for (k, c) in enumerate(color_gradient(["#FF5E5E", "#FFD25E", "#7FDD58",
                                            "#58C4DD", "#C77DFF"], 22))
        r = Rectangle(width = 0.22, height = 3.6)
        set_fill!(r; color = c, opacity = 1.0); set_stroke!(r; opacity = 0)
        move_to!(r, Point3f(x - 2.3 + 0.22(k - 1), -0.1, 0))
        add!(g, r)
    end
    return g
end

function construct(scene)
    title = TextMobject("the mask is coverage, per pixel"; size = 0.44, color = GREY_A)
    to_edge!(title, UP; buff = 0.3)

    # LEFT: no mask.
    plain = stripes(-3.4)

    # RIGHT: the same stripes, cut by a star. The star is never drawn.
    cut = stripes(3.4)
    cutter = Star(5; outer_radius = 1.8, fill_opacity = 1.0)
    move_to!(cutter, Point3f(3.4, -0.1, 0))

    l1 = TextMobject("as rendered"; size = 0.32, color = GREY_B)
    l2 = TextMobject("mask = Mask(star)"; size = 0.32, color = GREY_B)
    move_to!(l1, Point3f(-3.4, -2.5, 0)); move_to!(l2, Point3f(3.4, -2.5, 0))

    use_composition!(scene, Composition(
        Layer(plain),
        Layer(cut; mask = Mask(cutter)),
        Layer(title, l1, l2);
        background = (0.02f0, 0.03f0, 0.05f0, 1f0)))

    wait!(scene, 1.5)
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "01_mask_basics.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
