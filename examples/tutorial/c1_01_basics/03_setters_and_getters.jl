# Course 1 · 1.3 — Setters and getters
#
# Setters end in `!` (they mutate) and return the mobject, so they chain.
# Getters answer in SCENE UNITS: the default frame is 8 units tall and
# 8·16/9 ≈ 14.22 wide, whatever the pixel resolution is.
#
#   style     set_fill!(m; color, opacity) · set_stroke!(m; color, width,
#             opacity) · set_color! (both at once) · get_color
#   place     shift! · move_to! · to_edge! · next_to! · center!
#   size      scale! · set_width! · set_height! · stretch! · rescale_to_fit!
#   turn      rotate!(m, angle; axis, about_point) · flip!
#   ask       get_center · get_left/right/top/bottom · get_width/height
#             get_bounding_box_point(m, direction) — the general one
#
# The trap worth naming: `set_fill!(m; opacity = 0.5)` with NO colour keeps
# every row's own colour and moves only the alpha. That is what lets a fade
# survive a gradient (lesson 5.1) — and it is why "set the opacity" never
# silently repaints your gradient grey.
#
#   julia --project=. examples/tutorial/c1_01_basics/03_setters_and_getters.jl

using Janim

const PREVIEW_T = 1.5

function construct(scene)
    title = TextMobject("getters answer in scene units"; size = 0.5, color = GREY_A)
    to_edge!(title, UP; buff = 0.4)

    box = Rectangle(width = 4.0, height = 2.4)
    set_fill!(box; color = "#2C5F8A", opacity = 1.0)
    set_stroke!(box; color = BLUE, width = 3.0)
    shift!(box, 0.4 * DOWN)

    # The five bounding-box points every layout call is built on.
    marks = VGroup()
    for (p, name) in ((get_left(box), "get_left"), (get_right(box), "get_right"),
                      (get_top(box), "get_top"), (get_bottom(box), "get_bottom"),
                      (get_center(box), "get_center"))
        d = Dot(p; radius = 0.07)
        set_fill!(d; color = YELLOW)
        add!(marks, d)
    end

    # A brace measures what get_width() reports — the number and the picture
    # come from the same bounding box, so they cannot disagree.
    brace = Brace(box, DOWN; buff = 0.15, color = GREY_A)
    w = DecimalNumber(Float64(get_width(box)); num_decimal_places = 2, size = 0.45,
                      color = GREY_A)
    next_to!(w.group, brace, DOWN; buff = 0.12)

    add!(scene, title, box, marks, brace, w)
    println("width = ", round(get_width(box); digits = 3),
            " · height = ", round(get_height(box); digits = 3),
            " · centre = ", get_center(box))

    play!(scene, FadeIn(box); run_time = 0.6)
    wait!(scene, 0.6)

    # Setters chain because each one returns the mobject.
    play!(scene, animate(box, (set_width!, 6.0), (rotate!, TAU / 24)); run_time = 1.2)
    # …and the getters follow, because they are read off the live geometry.
    set_number!(w, Float64(get_width(box)))
    move_to!(brace, get_bottom(box) + 0.35 * DOWN)
    for (d, p) in zip(marks.submobjects,
                      (get_left(box), get_right(box), get_top(box),
                       get_bottom(box), get_center(box)))
        move_to!(d, p)
    end
    next_to!(w.group, brace, DOWN; buff = 0.12)
    wait!(scene, 0.8)
    println("after set_width!(6) + rotate!: width = ",
            round(get_width(box); digits = 3), "  ← the bbox grew with the turn")
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__),
                   "03_setters_and_getters.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
