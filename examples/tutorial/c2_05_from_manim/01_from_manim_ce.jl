# Course 2 · 5.1 — Translating a Manim CE scene
#
# The CE original, line for line, is in the comments. The full translation
# table is in examples/tutorial/course2.md; what this lesson is for is the SHAPE of the
# translation, and the five places where a literal translation is wrong.
#
#   class SquareToCircle(Scene):                 function construct(scene)
#       def construct(self):                       ← `scene`, not `self`
#           circle = Circle()                      circle = Circle()
#           circle.set_fill(BLUE, opacity=0.5)     set_fill!(circle; color = BLUE,
#                                                            opacity = 0.5)
#           square = Square()                      square = Square()
#           square.rotate(PI / 4)                  rotate!(square, PI / 4)
#           self.play(Create(square))              play!(scene, Create(square))
#           self.play(Transform(square, circle))   play!(scene, Transform(square, circle))
#           self.play(FadeOut(square))             play!(scene, FadeOut(square))
#           self.wait()                            wait!(scene, 1.0)
#
# THE FIVE THINGS THAT ARE NOT A LITERAL TRANSLATION:
#
#   1. `self.play(m.animate.shift(RIGHT))` → `animate(m, (shift!, RIGHT))`.
#      No chainable proxy; a tuple per call, applied in order.
#   2. Mutating methods carry a `!` and take the mobject FIRST:
#      `m.set_fill(BLUE)` → `set_fill!(m; color = BLUE)`. Colours and
#      opacities are KEYWORDS here, not positional.
#   3. `Text` → `TextMobject` and `MathTex`/`Tex` → `Tex(…; via = :math)`.
#      The name changed because Julia's `Text` and `Matrix` are taken; the
#      engine's `Tex` does NOT run LaTeX unless you ask for `via = :latex`.
#   4. `config.frame_rate`, `manim.cfg` and `-ql` do not exist. Settings are
#      `Scene` kwargs, and quality is `-r 854x480 --fps 30`.
#   5. `VGroup(*mobs)` → `VGroup(mobs...)`; `[…for…]` is a comprehension in
#      both, but a NESTED Julia comprehension gives a MATRIX, not a flat list.
#
#   julia --project=. examples/tutorial/c2_05_from_manim/01_from_manim_ce.jl

using Janim

const PREVIEW_T = 2.6

function construct(scene)
    # ── CE ──────────────────────────────────────────────────────────────
    # title = Text("From Manim CE", font_size=48).to_edge(UP)
    title = TextMobject("From Manim CE"; size = 0.6)
    to_edge!(title, UP; buff = 0.4)
    add!(scene, title)

    # circle = Circle().set_fill(BLUE, opacity=0.5)
    circle = Circle(radius = 1.2)
    set_fill!(circle; color = BLUE, opacity = 0.5)
    set_stroke!(circle; color = BLUE, width = 4.0)

    # square = Square().rotate(PI / 4).shift(3 * LEFT)
    square = Square(side_length = 2.0)
    rotate!(square, PI / 4)
    shift!(square, 3.4 * LEFT)
    set_fill!(square; color = "#E8A33D", opacity = 0.7)
    set_stroke!(square; color = "#E8A33D", width = 4.0)

    # dots = VGroup(*[Dot(RIGHT * i) for i in range(5)]).arrange(RIGHT, buff=0.4)
    dots = VGroup([begin
                       d = Dot(ORIGIN; radius = 0.13)
                       set_fill!(d; color = "#7FDD58")
                       d
                   end for _ in 1:5]...)
    arrange!(dots, RIGHT; buff = 0.4)
    move_to!(dots, 3.4 * RIGHT)

    # self.play(Create(square), FadeIn(circle))
    play!(scene, AnimationGroup(Create(square), FadeIn(circle)); run_time = 1.2)

    # self.play(LaggedStart(*[GrowFromCenter(d) for d in dots], lag_ratio=0.2))
    play!(scene, LaggedStart([GrowFromCenter(d) for d in dots.submobjects]...;
                             lag_ratio = 0.2); run_time = 1.2)

    # self.play(square.animate.shift(UP).set_color(YELLOW))
    #   ← two mutations, one animation, and set_color needs the adapter
    paint!(m, c) = set_color!(m; color = c)
    play!(scene, animate(square, (shift!, 1.0 * UP), (paint!, YELLOW));
          run_time = 1.0)

    # self.play(Transform(square, circle))
    play!(scene, Transform(square, circle); run_time = 1.2)

    # self.wait()
    wait!(scene, 1.0)
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "01_from_manim_ce.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
