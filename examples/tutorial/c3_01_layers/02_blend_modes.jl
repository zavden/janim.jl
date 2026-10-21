# Course 3 · 1.2 — Blend modes
#
#     Layer(m; blend = :normal | :add | :multiply | :screen | :overlay)
#
# The compositor uses the W3C / PDF / SVG equation over PREMULTIPLIED colour:
#
#     C = (1−αs)·Cb + (1−αb)·Cs + αs·αb·B(Cb, Cs)
#     α = αs + αb·(1−αs)
#
# where B is the mode over non-premultiplied colour:
#
#     normal    B = Cs                       (collapses to Porter-Duff `over`)
#     multiply  B = Cb·Cs                    (darkens; white is the identity)
#     screen    B = Cb + Cs − Cb·Cs          (lightens; black is the identity)
#     overlay   multiply or screen, per channel, depending on the BACKDROP
#     add       a plain sum of premultiplied values — the classic glow mode,
#               and the only one that is not the equation above
#
# Blending happens on raw sRGB values, like Manim and like After Effects'
# default. (Linear-light blending is a deliberate non-goal for now.)
#
#   julia --project=. examples/tutorial/c3_01_layers/02_blend_modes.jl

using Janim

const PREVIEW_T = 1.2

const MODES = (:normal, :add, :multiply, :screen, :overlay)

function construct(scene)
    title = TextMobject("the same two shapes, five equations";
                        size = 0.44, color = GREY_A)
    to_edge!(title, UP; buff = 0.3)

    "A backdrop disc and a source disc, at column `k`."
    function pair(k)
        x = -5.4 + 2.7(k - 1)
        b = Circle(radius = 0.95)
        set_fill!(b; color = "#3D7BC0", opacity = 1.0); set_stroke!(b; opacity = 0)
        move_to!(b, Point3f(x - 0.32, 0.1, 0))
        s = Circle(radius = 0.95)
        set_fill!(s; color = "#E8A33D", opacity = 1.0); set_stroke!(s; opacity = 0)
        move_to!(s, Point3f(x + 0.32, -0.35, 0))
        lab = TextMobject(string(":", MODES[k]); size = 0.34, color = GREY_B)
        move_to!(lab, Point3f(x, -2.1, 0))
        return (b, s, lab)
    end

    layers = Layer[]
    labels = Mobject[]
    for k in 1:5
        b, s, lab = pair(k)
        push!(layers, Layer(b))                    # the backdrop
        push!(layers, Layer(s; blend = MODES[k]))  # …and the source over it
        push!(labels, lab)
    end
    push!(layers, Layer(title, labels...))

    use_composition!(scene, Composition(layers...;
                                        background = (0.05f0, 0.05f0, 0.06f0, 1f0)))
    wait!(scene, 1.5)
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "02_blend_modes.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
