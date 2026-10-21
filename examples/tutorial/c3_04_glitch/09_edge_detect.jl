# Course 3 · 4.9 — EdgeDetect
#
#     EdgeDetect(; amount = 1.0, color = nothing, thickness = 1.0)
#
# A Sobel operator over luma: the silhouette of whatever is on the layer.
#
#   color = nothing   the edges keep the original colour — a rim-light look
#   color = WHITE     the layer becomes a LINE DRAWING on transparency, which
#                     is the pedagogical use: show the outline of a shape
#                     without redrawing it
#   thickness         the sampling step in pixels (a fatter kernel, not a
#                     thicker stroke)
#   amount            gain; 0 skips the pass entirely
#
# Two uses worth knowing. Put it on a layer of its OWN, on top of the same
# content with `blend = :add`, and you get outlines drawn over the solid
# shapes — the "annotate what is already there" move. Or put it on the only
# copy and the solid disappears, leaving the drawing.
#
#   julia --project=. examples/tutorial/c3_04_glitch/09_edge_detect.jl

using Janim

const PREVIEW_T = 1.4

"Solid shapes, which is what an edge detector wants."
function blobs(x)
    g = VGroup()
    for (dx, dy, r, colour) in ((-0.7, 0.5, 0.85, "#3D7BC0"),
                                (0.6, 0.75, 0.6, "#FFD25E"),
                                (0.15, -0.7, 1.0, "#FF3D8B"))
        c = Circle(radius = r)
        set_fill!(c; color = colour, opacity = 1.0); set_stroke!(c; opacity = 0)
        move_to!(c, Point3f(x + dx, dy - 0.1, 0))
        add!(g, c)
    end
    s = Square(side_length = 1.1)
    rotate!(s, PI / 7)
    set_fill!(s; color = "#7FDD58", opacity = 1.0); set_stroke!(s; opacity = 0)
    move_to!(s, Point3f(x - 0.1, -0.2, 0))
    add!(g, s)
    return g
end

function construct(scene)
    title = TextMobject("Sobel over luma: the silhouette";
                        size = 0.44, color = GREY_A)
    to_edge!(title, UP; buff = 0.3)

    labels = Mobject[]
    for (x, s) in ((-4.6, "as rendered"), (0.0, "EdgeDetect(color = WHITE)"),
                   (4.6, "solid + edges on :add"))
        lab = TextMobject(s; size = 0.28, color = GREY_B)
        move_to!(lab, Point3f(x, -2.6, 0))
        push!(labels, lab)
    end

    # The third panel needs TWO layers over the same geometry: the solid, and
    # a copy that has been reduced to its edges.
    solid = blobs(4.6)
    outline = copy(solid)

    use_composition!(scene, Composition(
        Layer(blobs(-4.6)),
        Layer(blobs(0.0); effects = [EdgeDetect(; color = WHITE, amount = 1.4)]),
        Layer(solid),
        Layer(outline; blend = :add,
              effects = [EdgeDetect(; color = "#FFFFFF", amount = 2.0, thickness = 1.6)]),
        Layer(title, labels...);
        background = (0.02f0, 0.03f0, 0.05f0, 1f0)))

    wait!(scene, 1.6)
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "09_edge_detect.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
