# Course 4 · 1.1 — Every flat shape, in one frame
#
# Course 4 is the REFERENCE course: each lesson is an exhaustive tour of one
# family of Janim's exported names, in a file that runs.
#
# This lesson is the 2D zoo. Every constructor below is a `VMobject`: one flat
# array of points in the interleaved quadratic layout, so they all take the
# same setters and all interpolate into each other.
#
#   julia --project=. examples/tutorial/c4_01_shape_zoo/01_every_flat_shape.jl

using Janim

const PREVIEW_T = 2.3   # after the cascade finishes

"Place `m` on a 6-column grid and label it."
function cell(gallery, m, i, name)
    row, col = divrem(i - 1, 6)
    # cap BOTH dimensions: set_width! alone lets a tall shape run into its label
    set_width!(m, 1.5; stretch = false)
    get_height(m) > 1.1 && set_height!(m, 1.1; stretch = false)
    move_to!(m, Point3f(-5.9 + 2.35 * col, 1.9 - 2.05 * row, 0))
    label = TextMobject(name; size = 0.2, color = GREY_B)
    get_width(label) > 2.1 && set_width!(label, 2.1)
    next_to!(label, m, DOWN; buff = 0.14)
    add!(gallery, m, label)
end

function construct(scene)
    title = TextMobject("the flat zoo — every VMobject constructor";
                        size = 0.42, color = GREY_A)
    to_edge!(title, UP; buff = 0.25)

    shapes = [
        (Circle(radius = 1.0), "Circle"),
        (Ellipse(width = 2.0, height = 1.2), "Ellipse"),
        (Arc(; angle = TAU / 3, radius = 1.0), "Arc"),
        (ArcBetweenPoints(LEFT, RIGHT; angle = TAU / 5), "ArcBetweenPoints"),
        (Annulus(inner_radius = 0.5, outer_radius = 1.0), "Annulus"),
        (Sector(angle = TAU / 3), "Sector"),
        (AnnularSector(inner_radius = 0.4, outer_radius = 1.0,
                       angle = TAU / 3), "AnnularSector"),
        (Square(side_length = 2.0), "Square"),
        (Rectangle(width = 2.4, height = 1.4), "Rectangle"),
        (RoundedRectangle(width = 2.4, height = 1.4, corner_radius = 0.3),
         "RoundedRectangle"),
        (Triangle(radius = 1.0), "Triangle"),
        (RegularPolygon(6; radius = 1.0), "RegularPolygon(6)"),
        (Polygon(Point3f(-1, -0.8, 0), Point3f(1, -0.8, 0),
                 Point3f(0.4, 0.9, 0), Point3f(-0.9, 0.4, 0)), "Polygon"),
        (Star(; outer_radius = 1.0), "Star"),
        (Elbow(width = 1.4, angle = 0.0), "Elbow"),
        (Line(LEFT, RIGHT), "Line"),
        (Arrow(LEFT, RIGHT), "Arrow"),
        (Dot(ORIGIN; radius = 0.5), "Dot"),
    ]

    gallery = VGroup()
    for (i, (m, name)) in enumerate(shapes)
        # every one of them takes the same two setters — that is the point
        set_stroke!(m; color = BLUE_B, width = 2.5)
        set_fill!(m; color = BLUE_E, opacity = 0.35)
        cell(gallery, m, i, name)
    end

    add!(scene, title, gallery)
    play!(scene, ShowCreation(gallery; lag_ratio = 0.03); run_time = 2.0)
    wait!(scene, 0.5)
end
