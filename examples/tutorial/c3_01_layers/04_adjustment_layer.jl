# Course 3 · 1.4 — Adjustment layers
#
#     Layer(; effects = [ … ])        ← no mobjects at all
#
# A layer with no content applies its effects to WHATEVER IS ALREADY
# COMPOSITED BELOW IT. That is After Effects' adjustment layer, and it is what
# gives you "grade everything up to here" without touching any of it.
#
# The order in the list is the order of operations:
#
#     Layer(a)                  ← graded
#     Layer(b)                  ← graded
#     Layer(; effects = [Blur]) ← the adjustment: it blurs a and b together
#     Layer(c)                  ← NOT graded: it composites afterwards
#
# Two consequences worth having in your head:
#
#   · an adjustment layer blurs the SEAM between the layers below, not each
#     one separately — that is the whole difference from putting the same blur
#     on each of them;
#   · a title placed above it stays sharp while the film behind it goes soft,
#     which is the standard "dream transition" and costs one line.
#
#   julia --project=. examples/tutorial/c3_01_layers/04_adjustment_layer.jl

using Janim

const PREVIEW_T = 3.0

function construct(scene)
    title = TextMobject("one adjustment layer grades everything below it";
                        size = 0.42, color = GREY_A)
    to_edge!(title, UP; buff = 0.3)

    grid = VGroup()
    for x in -6.5:0.9:6.5
        l = Line(Point3f(x, -3.6, 0), Point3f(x, 3.6, 0))
        set_stroke!(l; color = "#25405C", width = 2.0)
        add!(grid, l)
    end
    for y in -3.6:0.9:3.6
        l = Line(Point3f(-6.8, y, 0), Point3f(6.8, y, 0))
        set_stroke!(l; color = "#25405C", width = 2.0)
        add!(grid, l)
    end

    shapes = VGroup()
    for (k, (x, colour)) in enumerate(((-3.4, "#3D7BC0"), (0.0, "#E8A33D"),
                                       (3.4, "#7FDD58")))
        s = RegularPolygon(3 + k; radius = 1.2)
        set_fill!(s; color = colour, opacity = 1.0); set_stroke!(s; opacity = 0)
        move_to!(s, Point3f(x, -0.2, 0))
        add!(shapes, s)
    end

    caption = TextMobject("this text is ABOVE the adjustment, so it stays sharp";
                          size = 0.36, color = GREY_A)
    move_to!(caption, 2.9 * DOWN)

    # The adjustment: a blur and a colour grade, applied to the grid AND the
    # shapes as one picture. Animated, so you can watch it take hold.
    soften = Blur(0.001)
    grade = ColorAdjust(; saturation = 1.0, brightness = 1.0)

    clock = VGroup()
    add_updater!(clock, function (m, dt)
        dt > 0 || return
        a = clamp((scene.t - 0.6) / 2.2, 0, 1)
        soften.sigma = 0.001 + 0.16a
        grade.saturation = 1.0 - 0.75a
        grade.brightness = 1.0 - 0.25a
        nothing
    end)
    add!(scene, clock)

    use_composition!(scene, Composition(
        Layer(grid),
        Layer(shapes),
        Layer(; effects = [soften, grade]),     # ← the adjustment layer
        Layer(title, caption);
        background = (0.02f0, 0.03f0, 0.05f0, 1f0)))

    wait!(scene, 3.4)
    println("final sigma: ", round(soften.sigma; digits = 3),
            " · saturation: ", round(grade.saturation; digits = 3))
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__),
                   "04_adjustment_layer.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
