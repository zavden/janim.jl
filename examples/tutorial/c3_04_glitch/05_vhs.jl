# Course 3 · 4.5 — VHS
#
#     VHS(; intensity = 0.5, seed = 1, rate = 2, chroma_bleed = 0.15,
#           jitter = 0.04, noise = 0.12, head_switch = 0.08)
#
# Video tape: per-LINE horizontal jitter, chroma smearing, tape noise, and the
# torn band at the bottom where the head switches.
#
#   chroma_bleed  in SCENE UNITS. The smear keeps each pixel's OWN luma and
#                 takes only the neighbours' COLOUR — which is what a tape
#                 does, and it means that over a GREYSCALE image the smear
#                 changes nothing at all, exactly.
#   jitter        also scene units. The measured defaults matter here:
#                 0.06 and 0.004 would be 2 px and 0.13 px at 480p — an
#                 invisible wobble.
#   head_switch   the height of the torn band as a fraction of the frame; the
#                 tear starts exactly at that row.
#   rate          how many frames the pattern is held for.
#   intensity     master dial; 0 is an exact no-op.
#
#   julia --project=. examples/tutorial/c3_04_glitch/05_vhs.jl

using Janim

const PREVIEW_T = 1.6

"A colour panel and a grey one, side by side: the chroma smear only touches one."
function panel(x, grey)
    g = VGroup()
    for k in 0:4
        r = Rectangle(width = 0.62, height = 2.2)
        c = grey ? color_gradient([BLACK, WHITE], 5)[k+1] :
            color_gradient(["#FF3D8B", "#FFD25E", "#39D0FF"], 5)[k+1]
        set_fill!(r; color = c, opacity = 1.0); set_stroke!(r; opacity = 0)
        move_to!(r, Point3f(x - 1.3 + 0.65k, 0.3, 0))
        add!(g, r)
    end
    t = TextMobject(grey ? "greyscale" : "colour"; size = 0.32, color = GREY_A)
    move_to!(t, Point3f(x, -1.2, 0))
    add!(g, t)
    return g
end

function construct(scene)
    title = TextMobject("the chroma smear takes colour, never luma";
                        size = 0.42, color = GREY_A)
    to_edge!(title, UP; buff = 0.3)

    caption = TextMobject("left: as rendered · right: VHS(intensity = 0.9)";
                          size = 0.34, color = GREY_B)
    move_to!(caption, 2.8 * DOWN)

    use_composition!(scene, Composition(
        Layer(panel(-4.6, false), panel(-1.7, true)),
        Layer(panel(1.7, false), panel(4.6, true);
              effects = [VHS(; intensity = 0.9, seed = 5)]),
        Layer(title, caption);
        background = (0.02f0, 0.02f0, 0.03f0, 1f0)))

    wait!(scene, 2.0)
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "05_vhs.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
