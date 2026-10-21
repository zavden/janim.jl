# Course 1 · 3.6 — Transforming one formula into another
#
#     TransformMatchingTex(src, dst; key_map = Dict(), run_time = 1.0, …)
#
# Glyphs that share a KEY morph in pairs; source-only glyphs fade out;
# target-only glyphs fade in. Longest keys claim first, so an isolated "x^2"
# outranks its own "x", and ties break lexicographically (determinism).
# `key_map = Dict("a" => "b")` renames on the way across.
#
# When it ends, THE SCENE HOLDS `dst` — the source is consumed (hidden in
# `begin!`, removed at the end), exactly like manimgl. So keep using `dst`
# afterwards, not `src`.
#
# Three decisions inside it:
#
#   1. It animates COPIES. Our draw loop renders every scene root's family
#      with no cross-root dedup, so a live glyph shared between source and
#      animation group would be drawn twice and the winding alpha would
#      deepen (2a − a²).
#   2. It restructures NEITHER formula. Regrouping children orphans every
#      external reference — including the memoised key groups you are holding.
#   3. The scene swap rides the same protocol as ReplacementTransform, so the
#      animation stays ignorant of the scene and behaves identically under
#      `play!`, `Timeline`, `render_frame` and the daemon.
#
#   julia --project=. examples/tutorial/c1_03_groups_and_text/06_tex_transformations.jl

using Janim

const PREVIEW_T = 1.6

function construct(scene)
    title = TextMobject("matched by key, not by position"; size = 0.46, color = GREY_A)
    to_edge!(title, UP; buff = 0.4)
    add!(scene, title)

    a = Tex(raw"a^2 + b^2 = c^2"; size = 1.3)
    b = Tex(raw"c^2 - b^2 = a^2"; size = 1.3)
    c = Tex(raw"c = \sqrt{a^2 + b^2}"; size = 1.3)
    for m in (a, b, c)
        move_to!(m, 0.3 * UP)
    end

    add!(scene, a)
    play!(scene, Write(a); run_time = 1.2)
    wait!(scene, 0.5)

    # Every :math glyph already carries its character as a key, so this needs
    # no preparation at all: the a's find the a's, the ² finds the ².
    play!(scene, TransformMatchingTex(a, b); run_time = 1.6)
    wait!(scene, 0.6)
    # From here on the scene holds `b` — carry on with THAT one.
    play!(scene, TransformMatchingTex(b, c); run_time = 1.6)
    wait!(scene, 0.6)

    println("the scene now holds the last formula: ",
            any(m -> m === c, scene.mobjects))
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__),
                   "06_tex_transformations.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
