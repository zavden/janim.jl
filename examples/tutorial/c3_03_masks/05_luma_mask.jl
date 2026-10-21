# Course 3 · 3.5 — Luma masks
#
#     Mask(shape; luma = true)
#
# Coverage is taken from the mask's LUMINANCE (0.2126 R + 0.7152 G + 0.0722 B)
# instead of its alpha. White shows, black hides, and every grey in between is
# a partial cut.
#
# Careful with one detail, and it is the only surprise here: the luminance is
# read from a PREMULTIPLIED texture, so it is already multiplied by alpha.
# Black and transparent both count as "hide", which is what you want — a
# transparent region has no light to give.
#
# What it buys you over an alpha mask: gradients. Paint a mask with
# `set_fill_by_gradient!` and you have a soft wipe with a shape you control
# exactly; add a noise texture and you have a dissolve.
#
#   julia --project=. examples/tutorial/c3_03_masks/05_luma_mask.jl

using Janim

const PREVIEW_T = 2.4

function construct(scene)
    title = TextMobject("luma: white shows, black hides, grey partly";
                        size = 0.42, color = GREY_A)
    to_edge!(title, UP; buff = 0.3)

    "The content to be revealed."
    function content(x)
        g = VGroup()
        for k in 0:7
            c = RegularPolygon(6; radius = 0.55)
            set_fill!(c; color = color_gradient(["#FF3D8B", "#FFD25E"], 8)[k+1],
                      opacity = 1.0)
            set_stroke!(c; opacity = 0)
            move_to!(c, Point3f(x - 2.4 + 0.7k, -0.2 + 0.35 * sin(1.4k), 0))
            add!(g, c)
        end
        return g
    end

    # A gradient painted onto a rectangle: its brightness IS the coverage.
    ramp = Rectangle(width = 6.2, height = 3.0)
    set_fill_by_gradient!(ramp, BLACK, WHITE)
    set_fill!(ramp; opacity = 1.0); set_stroke!(ramp; opacity = 0)
    move_to!(ramp, Point3f(-3.5, -0.2, 0))

    # A moving wipe: the same idea with the gradient sliding across.
    wipe = Rectangle(width = 6.2, height = 3.0)
    set_fill_by_gradient!(wipe, WHITE, BLACK)
    set_fill!(wipe; opacity = 1.0); set_stroke!(wipe; opacity = 0)
    move_to!(wipe, Point3f(3.5, -0.2, 0))
    add_updater!(wipe, function (m, dt)
        dt > 0 || return
        move_to!(m, Point3f(3.5 + 2.4 * sin(0.9 * scene.t), -0.2, 0))
        nothing
    end)

    l1 = TextMobject("a still gradient"; size = 0.3, color = GREY_B)
    l2 = TextMobject("…and the same thing, moving"; size = 0.3, color = GREY_B)
    move_to!(l1, Point3f(-3.5, -2.5, 0)); move_to!(l2, Point3f(3.5, -2.5, 0))

    use_composition!(scene, Composition(
        Layer(content(-3.5); mask = Mask(ramp; luma = true)),
        Layer(content(3.5); mask = Mask(wipe; luma = true)),
        Layer(title, l1, l2);
        background = (0.02f0, 0.03f0, 0.05f0, 1f0)))

    wait!(scene, 3.5)
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "05_luma_mask.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
