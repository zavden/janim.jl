# Course 3 · 3.7 — Text as the cutter
#
# A `TextMobject` or a `Tex` is a mobject like any other, so it can be the
# mask. That gives you the title-sequence look — the world seen THROUGH the
# letters — with no new machinery.
#
# It works because every glyph is real vector geometry with real antialiased
# coverage: the cut is per pixel, so the letterforms keep their curves. A
# rasterised text mask would show its own pixels at the edges.
#
# TWO DIRECTIONS, both here:
#
#   inside = word    the content shows INSIDE the letters
#   minus = word     the letters are punched OUT of the content
#
# And one composition detail: the moving content underneath is an ordinary
# layer with its own updater, so the text stays still while the world slides
# behind it.
#
#   julia --project=. examples/tutorial/c3_03_masks/07_text_as_mask.jl

using Janim

const PREVIEW_T = 2.0

"A drifting field of colour to be seen through the letters."
function drift(y)
    g = VGroup()
    for k in 0:23
        c = Circle(radius = 0.75)
        set_fill!(c; color = color_gradient(["#FF3D8B", "#FFD25E", "#39D0FF"], 24)[k+1],
                  opacity = 1.0)
        set_stroke!(c; opacity = 0)
        move_to!(c, Point3f(-8.0 + 0.7k, y + 0.5 * sin(0.9k), 0))
        add!(g, c)
    end
    add_updater!(g, function (m, dt)
        dt > 0 || return
        shift!(m, Point3f(1.1dt, 0, 0))
        get_center(m)[1] > 2.0 && shift!(m, Point3f(-8.0, 0, 0))
        nothing
    end)
    return g
end

function construct(scene)
    top = TextMobject("THROUGH"; size = 1.5)
    move_to!(top, 1.35 * UP)
    bottom = TextMobject("AROUND"; size = 1.5)
    move_to!(bottom, 1.35 * DOWN)

    plate = Rectangle(width = 8.6, height = 2.2)
    set_fill!(plate; color = "#1B2430", opacity = 1.0); set_stroke!(plate; opacity = 0)
    move_to!(plate, 1.35 * DOWN)

    caption = TextMobject("inside = the letters · minus = the letters";
                          size = 0.34, color = GREY_B)
    move_to!(caption, 3.1 * DOWN)

    use_composition!(scene, Composition(
        crop(drift(1.35); inside = top),          # seen through the word
        Layer(plate),
        crop(drift(-1.35); minus = bottom),       # …and punched out of it
        Layer(caption);
        background = (0.02f0, 0.03f0, 0.05f0, 1f0)))

    wait!(scene, 3.0)
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "07_text_as_mask.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
