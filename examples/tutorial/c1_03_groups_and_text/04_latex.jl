# Course 1 · 3.4 — Formulas
#
#     Tex(formula; via = :math, size = 1.0, color = WHITE, isolate = String[])
#
# `via = :math` is the default and it does NOT run LaTeX: MathTeXEngine lays
# the formula out, FreeType supplies the outlines, and the result is a
# VMobject in 0.2–0.4 ms. A cold LaTeX round trip is three to four orders of
# magnitude slower, which is the difference between a live preview and a wait.
#
# THE STRUCTURE MATTERS, and it is not decoration: a `Tex` is a parent with no
# points and ONE CHILD PER GLYPH. Two reasons, both learned the hard way:
#
#   · with every glyph in a single VMobject, a Transform's intermediate blob
#     flies over its neighbours and CANCELS their winding fill — the formula
#     flickers;
#   · `Transform` pairs child with child, i.e. glyph with glyph in reading
#     order, instead of pairing subpaths sorted by length.
#
# Consequence to remember: `pointwise_become_partial!` is NOT recursive, so on
# a Tex (a parent with no points of its own) it does nothing. The creation
# animations walk the family themselves, which is why `Write(tex)` works.
#
#   julia --project=. examples/tutorial/c1_03_groups_and_text/04_latex.jl

using Janim

const PREVIEW_T = 2.4

function construct(scene)
    euler = Tex(raw"e^{i\pi} + 1 = 0"; size = 1.2)
    gauss = Tex(raw"\int_{-\infty}^{\infty} e^{-x^2}\,dx = \sqrt{\pi}"; size = 0.95)
    series = Tex(raw"\sum_{n=1}^{\infty} \frac{1}{n^2} = \frac{\pi^2}{6}"; size = 0.95)
    # Colour per part, using the keys every :math glyph carries (lesson 3.7).
    set_color_by_gradient!(series, "#58C4DD", "#FFD25E")

    # `arrange!` instead of three hand-written heights: a formula's extent
    # depends on its tallest construct (that ∫ with limits is 1.5 units on
    # its own), so stacking them by eye is how you get an overlap.
    board = VGroup(euler, gauss, series)
    arrange!(board, DOWN; buff = 0.65)
    move_to!(board, 0.2 * DOWN)
    add!(scene, board)
    println("children of the Euler formula (one per glyph): ",
            length(euler.submobjects), " · its keys: ", get_all_keys(euler))

    play!(scene, Write(euler); run_time = 1.5)
    play!(scene, Write(gauss); run_time = 1.8)
    play!(scene, DrawBorderThenFill(series); run_time = 2.0)
    wait!(scene, 0.5)
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "04_latex.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
