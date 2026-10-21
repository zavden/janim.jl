# Course 3 · 4.3 — CRT
#
#     CRT(; intensity = 1.0, scanlines = 240, scan_depth = 0.35, mask = 0.3,
#           curvature = 0.15, vignette = 0.35, roll = 0.0)
#
# A cathode-ray television in one pass: barrel curvature, scanlines, an
# aperture-grille mask and a vignette.
#
#   scanlines    how many visible lines fit in the FRAME HEIGHT. The shader
#                puts exactly that many minima there — a count, not a size.
#   scan_depth   how dark the gaps between lines are.
#   mask         depth of the aperture grille: a 3-pixel RGB stripe, the
#                period of a real shadow mask.
#   curvature    barrel distortion. What falls outside the tube is
#                TRANSPARENT, not black, so the layer below still shows.
#   vignette     the darkening towards the corners.
#   intensity    master dial; 0 is an exact no-op.
#
# The sizes here are fractions of the frame and counts, NOT scene units — and
# deliberately so: that is how a television is specified. A blur radius is a
# distance in the world; a scanline count is a property of the screen.
#
#   julia --project=. examples/tutorial/c3_04_glitch/03_crt.jl

using Janim

const PREVIEW_T = 1.2

"Something worth putting on a tube: flat colour and big type."
function programme(x)
    g = VGroup()
    sky = Rectangle(width = 3.0, height = 2.1)
    set_fill!(sky; color = "#1B4F8C", opacity = 1.0); set_stroke!(sky; opacity = 0)
    move_to!(sky, Point3f(x, 0.4, 0))
    add!(g, sky)
    sun = Circle(radius = 0.42)
    set_fill!(sun; color = "#FFD25E", opacity = 1.0); set_stroke!(sun; opacity = 0)
    move_to!(sun, Point3f(x + 0.85, 1.0, 0))
    add!(g, sun)
    hill = Triangle(radius = 0.95)
    set_fill!(hill; color = "#3E8E52", opacity = 1.0); set_stroke!(hill; opacity = 0)
    move_to!(hill, Point3f(x - 0.3, -0.15, 0))
    add!(g, hill)
    t = TextMobject("CH 3"; size = 0.34, color = WHITE)
    move_to!(t, Point3f(x, -0.95, 0))
    add!(g, t)
    return g
end

function construct(scene)
    title = TextMobject("scanlines are a COUNT; curvature is a fraction of the frame";
                        size = 0.36, color = GREY_A)
    to_edge!(title, UP; buff = 0.3)

    cases = (("off", CRT(; intensity = 0.0)),
             ("default", CRT()),
             ("scanlines = 90", CRT(; scanlines = 90, scan_depth = 0.55)),
             ("curvature = 0.4", CRT(; curvature = 0.4, vignette = 0.6)))

    layers = Layer[]
    labels = Mobject[]
    for (k, (name, fx)) in enumerate(cases)
        x = -5.1 + 3.4(k - 1)
        push!(layers, Layer(programme(x); effects = [fx]))
        lab = TextMobject(name; size = 0.3, color = GREY_B)
        move_to!(lab, Point3f(x, -2.0, 0))
        push!(labels, lab)
    end
    push!(layers, Layer(title, labels...))

    use_composition!(scene, Composition(layers...;
                                        background = (0.03f0, 0.03f0, 0.04f0, 1f0)))
    wait!(scene, 1.5)
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "03_crt.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
