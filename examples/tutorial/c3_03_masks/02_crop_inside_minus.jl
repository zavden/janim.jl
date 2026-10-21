# Course 3 · 3.2 — `crop`: the two ways to say it
#
#     crop(base...; inside = shape, feather = 0.0, hard = false, kw...)
#     crop(base...; minus  = shape, feather = 0.0, hard = false, kw...)
#
# Sugar over `Layer(base...; mask = Mask(shape; invert = …))`, and it returns
# a `Layer`, so it drops straight into a `Composition`.
#
#     inside = shape    KEEP what is inside the shape (a window)
#     minus  = shape    REMOVE what is inside it (a hole)
#
# Exactly one of the two, always: asking for both, or neither, is an error
# with that sentence in it. The reason there are two words instead of an
# `invert` flag is that at the call site "keep the part inside this circle"
# and "punch this circle out" are different intentions, and reading
# `invert = true` six months later tells you neither.
#
#   julia --project=. examples/tutorial/c3_03_masks/02_crop_inside_minus.jl

using Janim

const PREVIEW_T = 1.4

"A dense grid, so the cut is unmistakable."
function mesh(x)
    g = VGroup()
    for k in -8:8
        v = Line(Point3f(x + 0.3k, -2.0, 0), Point3f(x + 0.3k, 2.0, 0))
        set_stroke!(v; color = "#3D7BC0", width = 2.0)
        add!(g, v)
    end
    for k in -6:6
        h = Line(Point3f(x - 2.4, 0.3k, 0), Point3f(x + 2.4, 0.3k, 0))
        set_stroke!(h; color = "#3D7BC0", width = 2.0)
        add!(g, h)
    end
    return g
end

function construct(scene)
    title = TextMobject("inside = a window · minus = a hole";
                        size = 0.44, color = GREY_A)
    to_edge!(title, UP; buff = 0.3)

    left, right = mesh(-3.5), mesh(3.5)
    window = Circle(radius = 1.5, fill_opacity = 1.0)
    move_to!(window, Point3f(-3.5, 0, 0))
    hole = Circle(radius = 1.5, fill_opacity = 1.0)
    move_to!(hole, Point3f(3.5, 0, 0))

    l1 = TextMobject("crop(mesh; inside = circle)"; size = 0.32, color = GREY_B)
    l2 = TextMobject("crop(mesh; minus = circle)"; size = 0.32, color = GREY_B)
    move_to!(l1, Point3f(-3.5, -2.6, 0)); move_to!(l2, Point3f(3.5, -2.6, 0))

    use_composition!(scene, Composition(
        crop(left; inside = window),
        crop(right; minus = hole),
        Layer(title, l1, l2);
        background = (0.02f0, 0.03f0, 0.05f0, 1f0)))

    wait!(scene, 1.5)
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__),
                   "02_crop_inside_minus.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
