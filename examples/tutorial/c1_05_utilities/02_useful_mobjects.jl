# Course 1 · 5.2 — The rest of the zoo
#
# Shapes:      Arc · Circle · Ellipse · Polygon · RegularPolygon · Triangle ·
#              Rectangle · RoundedRectangle · Square · Star · Annulus ·
#              Sector · AnnularSector · ArcBetweenPoints · Elbow
# Primitives:  Line · Arrow · Dot  (their ends may be MOBJECTS: the facing
#              borders are used, which is what makes diagrams hold together)
# Annotation:  Brace · BraceLabel · Underline · Cross · BackgroundRectangle ·
#              SurroundingRectangle · DashedLine · DashedVMobject ·
#              Angle · RightAngle (+ `angle_value`, `line_intersection`)
# Grids:       MatrixMobject · Table (read them with get_entries/get_rows/
#              get_columns/get_cell/get_brackets/get_lines, or by key "(i,j)")
# Live:        TracedPath · ValueTracker · DecimalNumber · always_redraw
# 3D:          Sphere · Torus · Cylinder · Cone · PlaneXY · Surface ·
#              Dot3D · Line3D · Arrow3D
#
# Two of these are better than Manim's, for the same reason both times — the
# renderer is ours. `Brace` is a native stretchable PATH, not
# `Tex("\underbrace{\qquad}")`, so it needs no LaTeX and its strokes stay even
# at any width. `Annulus` is two subpaths turning in opposite directions, and
# the hole comes free from winding fill — no mask, no boolean op.
#
#   julia --project=. examples/tutorial/c1_05_utilities/02_useful_mobjects.jl

using Janim

const PREVIEW_T = 3.2

function construct(scene)
    title = TextMobject("the zoo"; size = 0.5, color = GREY_A)
    to_edge!(title, UP; buff = 0.3)
    add!(scene, title)

    # ── row 1: shapes ────────────────────────────────────────────────────
    shapes = VGroup()
    for m in (RegularPolygon(6; radius = 0.55),
              Star(5; outer_radius = 0.6),
              Annulus(; inner_radius = 0.28, outer_radius = 0.6),
              Sector(; angle = TAU / 3, radius = 0.6),
              RoundedRectangle(width = 1.2, height = 0.9, corner_radius = 0.22),
              Ellipse(; width = 1.3, height = 0.8))
        set_fill!(m; color = "#2C5F8A", opacity = 1.0)
        set_stroke!(m; color = "#58C4DD", width = 2.5)
        add!(shapes, m)
    end
    arrange!(shapes, RIGHT; buff = 0.35)
    move_to!(shapes, 1.7 * UP)

    # ── row 2: a diagram — Line/Arrow between MOBJECTS, plus an angle ─────
    a = Dot(Point3f(-5.2, 0.0, 0); radius = 0.1); set_fill!(a; color = YELLOW)
    b = Dot(Point3f(-2.6, 0.9, 0); radius = 0.1); set_fill!(b; color = YELLOW)
    c = Dot(Point3f(-2.6, -0.9, 0); radius = 0.1); set_fill!(c; color = YELLOW)
    ab = Line(a, b; buff = 0.12)          # the ends are mobjects: borders used
    ac = Line(a, c; buff = 0.12)
    for l in (ab, ac)
        set_stroke!(l; color = GREY_A, width = 3.0)
    end
    # `quadrant` and `other_angle` choose WHICH of the four angles at the
    # crossing you mean. The default (1,1) here would sweep the reflex one —
    # 327°, i.e. almost a full circle round the vertex.
    mark = Angle(ab, ac; radius = 0.55, other_angle = true, color = "#FF5E5E")
    arrow = Arrow(b, c; buff = 0.15, thickness = 3.0)
    set_fill!(arrow; color = "#7FDD58")

    # ── row 3: annotation and grids ──────────────────────────────────────
    slab = Rectangle(width = 2.2, height = 0.7)
    set_fill!(slab; color = "#37506B", opacity = 1.0); set_stroke!(slab; opacity = 0)
    move_to!(slab, Point3f(1.4, -1.4, 0))
    brace = Brace(slab, DOWN; buff = 0.12, color = GREY_A)
    blabel = TextMobject("Brace: a native path"; size = 0.28, color = GREY_B)
    next_to!(blabel, brace, DOWN; buff = 0.12)

    dashed = DashedLine(Point3f(-1.2, -3.3, 0), Point3f(3.8, -3.3, 0);
                        dash_length = 0.12)
    set_stroke!(dashed; color = "#8894A6", width = 3.0)

    matrix = MatrixMobject([1 2; 3 4]; cell = s -> Tex(s; size = 0.7))
    scale!(matrix, 0.8)
    move_to!(matrix, Point3f(4.6, -1.2, 0))

    add!(scene, shapes, a, b, c, ab, ac, mark, arrow, slab, brace, blabel,
         dashed, matrix)
    play!(scene, LaggedStart(FadeIn(shapes), ShowCreation(ab), ShowCreation(ac),
                             ShowCreation(mark), GrowArrow(arrow), FadeIn(slab),
                             FadeIn(brace), Write(blabel), ShowCreation(dashed),
                             Write(matrix); lag_ratio = 0.12); run_time = 3.0)
    println("angle at the vertex: ",
            round(abs(angle_value(ab, ac; other_angle = true)) / DEG; digits = 1),
            "° (the default quadrant would report its reflex, ",
            round(angle_value(ab, ac) / DEG; digits = 1), "°)")
    println("matrix cell (1,2): ", tag(get_cell(matrix, 1, 2)))
    wait!(scene, 0.5)
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "02_useful_mobjects.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
