# Course 1 · 3.7 — Symbol by symbol
#
# Three ways to address the pieces of a formula, weakest to strongest:
#
#   tex[3] · tex[2:4]     by POSITION. Fine for a one-off, fragile under any
#                         edit of the formula.
#   tex["x"]              by CHARACTER. Every `:math` glyph carries the
#                         character it represents as a key, for free.
#   isolate = ["x^2"]     by PATTERN. The pattern is compiled ON ITS OWN, its
#                         glyph sequence is matched against the formula's, and
#                         every non-overlapping occurrence gets the pattern
#                         added as a key. So `tex["x^2"]` is the whole
#                         subexpression, superscript included.
#
# All three return MEMOISED groups: `tex["x"] === tex["x"]`. That matters —
# calling it inside an updater at 60 fps would otherwise build a new VGroup
# every frame and register it as a parent of the glyphs, and the parent list
# would grow without bound.
#
# The known fragility, shared with Manim: matching is by glyph SEQUENCE, so
# `isolate = ["b"]` also claims the b of `b^2` when it comes first. Isolate
# the longer pattern too when it bites.
#
#   julia --project=. examples/tutorial/c1_03_groups_and_text/07_symbol_by_symbol.jl

using Janim

const PREVIEW_T = 3.0

function construct(scene)
    title = TextMobject("address the parts, then animate them";
                        size = 0.46, color = GREY_A)
    to_edge!(title, UP; buff = 0.4)
    add!(scene, title)

    # isolate labels the glyph runs; the longer pattern is isolated too, so
    # it outranks its own substring when both could match.
    f = Tex(raw"x^2 + 2xy + y^2"; size = 1.5, isolate = ["x^2", "y^2", "2xy"])
    move_to!(f, 0.6 * UP)
    add!(scene, f)
    play!(scene, Write(f); run_time = 1.4)

    println("keys carried by this formula: ", get_all_keys(f))
    println("glyphs labelled «x^2»: ", length(find_by_key(f, "x^2")))
    println("memoised? ", f["x^2"] === f["x^2"])

    # By pattern: the subexpression as one group.
    play!(scene, Indicate(f["x^2"]; color = "#58C4DD", scale_factor = 1.3);
          run_time = 1.0)
    play!(scene, Indicate(f["2xy"]; color = "#E8A33D", scale_factor = 1.3);
          run_time = 1.0)

    # By character: every «y» at once, wherever it is.
    play!(scene, Circumscribe(f["y"]; color = "#7FDD58", buff = 0.12);
          run_time = 1.2)

    # By position: the third child, whatever that turns out to be.
    play!(scene, Indicate(f[3]; color = "#FF5E5E"); run_time = 0.8)

    # And the payoff — a matched morph that pairs the isolated parts, so the
    # square lands on the square and the cross term is the thing that leaves.
    g = Tex(raw"(x + y)^2"; size = 1.5, isolate = ["x", "y"])
    move_to!(g, 0.6 * UP)
    play!(scene, TransformMatchingTex(f, g); run_time = 1.8)
    wait!(scene, 0.6)
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__),
                   "07_symbol_by_symbol.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
