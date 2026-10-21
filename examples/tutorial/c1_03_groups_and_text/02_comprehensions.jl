# Course 1 · 3.2 — Comprehensions
#
# Manim tutorials teach Python list comprehensions here. Julia's are the same
# shape and they compose with the splat `...`, which is what turns a list of
# mobjects into a VGroup and a list of animations into a LaggedStart:
#
#     VGroup([Dot(p) for p in points]...)
#     LaggedStart([FadeIn(d) for d in g.submobjects]...; lag_ratio = 0.1)
#
# Two Julia-specific things worth knowing:
#
#   · A nested comprehension `[f(i, j) for i in 1:3, j in 1:4]` produces a
#     MATRIX, not a flat list. `vec(...)` flattens it, and `MatrixMobject`
#     and `Table` take the matrix as it stands.
#   · Ranges are lazy and cheap: `0:0.05:TAU` is a range object, not an array.
#
#   julia --project=. examples/tutorial/c1_03_groups_and_text/02_comprehensions.jl

using Janim

const PREVIEW_T = 2.4

function construct(scene)
    title = TextMobject("build many, animate as one"; size = 0.5, color = GREY_A)
    to_edge!(title, UP; buff = 0.4)
    add!(scene, title)

    # A curve as a comprehension over a range — the samples ARE the geometry.
    curve = VMobject()
    set_points_as_corners!(curve, [Point3f(t, 1.3 * sin(1.5t), 0)
                                   for t in -6.0:0.1:6.0])
    set_stroke!(curve; color = "#37506B", width = 3.0)
    shift!(curve, 1.1 * UP)

    # Dots ON that curve: one comprehension, splatted into a VGroup.
    dots = VGroup([begin
                       d = Dot(Point3f(t, 1.3 * sin(1.5t) + 1.1, 0); radius = 0.1)
                       set_fill!(d; color = "#58C4DD")
                       d
                   end for t in -6.0:0.6:6.0]...)

    # A grid: the nested comprehension gives a MATRIX, which is exactly what
    # `Table` wants. `vec` would flatten it if you needed a VGroup instead.
    grid = Table([string(i * j) for i in 1:3, j in 1:4];
                 cell = s -> TextMobject(s; size = 0.42),
                 row_labels = ["1", "2", "3"], col_labels = ["1", "2", "3", "4"],
                 include_outer_lines = true)
    scale!(grid, 0.75)
    move_to!(grid, 1.6 * DOWN)

    add!(scene, curve, dots, grid)
    play!(scene, ShowCreation(curve); run_time = 1.0)

    # A list of ANIMATIONS, splatted. lag_ratio turns it into a wave.
    play!(scene, LaggedStart([FadeIn(d; shift = 0.35 * UP) for d in dots.submobjects]...;
                             lag_ratio = 0.07); run_time = 1.6)
    play!(scene, LaggedStart([Write(cell) for cell in get_entries(grid).submobjects]...;
                             lag_ratio = 0.05); run_time = 1.6)
    wait!(scene, 0.4)
    println("dots: ", length(dots.submobjects), " · table cells: ",
            length(get_entries(grid).submobjects))
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__),
                   "02_comprehensions.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
