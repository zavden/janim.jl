# Course 3 · 1.6 — Track mattes
#
#     Layer(content; matte = :alpha | :luma | :alpha_inv | :luma_inv)
#
# The layer CONSUMES THE NEXT LAYER IN THE LIST as its matte: that next layer
# is not drawn, its alpha (or luminance) becomes the coverage of this one.
# After Effects spells it "the layer above"; here the list runs bottom-to-top,
# so it is the following entry.
#
#     :alpha      where the matte has alpha, the content shows
#     :luma       where the matte is BRIGHT, the content shows
#     :alpha_inv / :luma_inv     the same, inverted
#
# Matte vs mask, since both cut things out:
#
#   Mask(shapes...)   belongs to the layer, is built from mobjects you name,
#                     and takes `feather`, `hard`, `invert`, `luma`.
#   matte = :luma     consumes a whole LAYER, so the cutter can itself be a
#                     precomp with effects — a gradient, a noise field, a
#                     blurred silhouette. That is the reason it exists.
#
#   julia --project=. examples/tutorial/c3_01_layers/06_track_matte.jl

using Janim

const PREVIEW_T = 2.4

function construct(scene)
    title = TextMobject("a matte is a whole layer used as coverage";
                        size = 0.42, color = GREY_A)
    to_edge!(title, UP; buff = 0.3)

    "A band of colour to be cut."
    function band(x)
        g = VGroup()
        for (k, c) in enumerate(color_gradient(["#FF5E5E", "#FFD25E", "#7FDD58",
                                                "#58C4DD"], 24))
            r = Rectangle(width = 0.19, height = 3.0)
            set_fill!(r; color = c, opacity = 1.0); set_stroke!(r; opacity = 0)
            move_to!(r, Point3f(x - 2.3 + 0.2(k - 1), -0.1, 0))
            add!(g, r)
        end
        return g
    end

    # LEFT · :alpha — the matte's shape cuts the band.
    letters = TextMobject("MATTE"; size = 1.1)
    move_to!(letters, Point3f(-3.4, -0.1, 0))

    # RIGHT · :luma — a gradient's BRIGHTNESS becomes a soft gradient wipe.
    ramp = Rectangle(width = 4.8, height = 3.0)
    set_fill_by_gradient!(ramp, BLACK, WHITE)
    set_fill!(ramp; opacity = 1.0)
    set_stroke!(ramp; opacity = 0)
    move_to!(ramp, Point3f(3.4, -0.1, 0))

    l1 = TextMobject("matte = :alpha"; size = 0.32, color = GREY_B)
    l2 = TextMobject("matte = :luma"; size = 0.32, color = GREY_B)
    move_to!(l1, Point3f(-3.4, -2.4, 0)); move_to!(l2, Point3f(3.4, -2.4, 0))

    use_composition!(scene, Composition(
        Layer(band(-3.4); matte = :alpha),   # ← consumes the NEXT layer
        Layer(letters),                       #    …which is this one
        Layer(band(3.4); matte = :luma),
        Layer(ramp),
        Layer(title, l1, l2);
        background = (0.02f0, 0.03f0, 0.05f0, 1f0)))

    wait!(scene, 2.5)
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "06_track_matte.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
