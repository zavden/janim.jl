# Course 1 · 3.5 — Choosing the typesetting route
#
#     Tex(f; via = :math)    MathTeXEngine — the default, milliseconds, the
#                            math subset. The only route that knows WHICH
#                            glyph is which, so `isolate` lives here.
#     Tex(f; via = :latex)   real latex + dvisvgm → SVG → VMobject. Covers
#                            everything: environments, \newcommand, packages.
#                            Needs texlive on the system.
#     Tex(f; via = :typst)   Typst_jll → SVG. TYPST syntax, not LaTeX — it is
#                            always installed, and it is not a LaTeX fallback.
#     Tex(f; via = :auto)    try :math, fall back with ONE warning naming the
#                            route that actually made the bytes.
#     config_tex!(via = :latex)   the session default (a module Ref, explicit
#                                 and visible — never a persistent global).
#
# THE CONTRACT that makes them interchangeable: the three routes share
# x-height and baseline. `:math` is the metric reference and the other two are
# CALIBRATED against a probe glyph, once per engine. Before that they used
# eyeballed ÷10 and ÷11 constants and were 5% off.
#
# The cache stores the SVG TEXT (not the mobject), keyed by route + engine
# version + the full compiled source. Edit a template and it invalidates
# honestly; ask twice in a session and the second is a memo hit.
#
#   julia --project=. examples/tutorial/c1_03_groups_and_text/05_latex_config.jl

using Janim

const PREVIEW_T = 1.5

"Typeset `source` by `via`, or say why not — a missing texlive is not a crash."
function try_route(source, via, size)
    try
        return Tex(source; via, size)
    catch err
        println("  via=:", via, " unavailable here: ",
                first(sprint(showerror, err), 90))
        return TextMobject("via=:$via unavailable"; size = 0.4, color = "#FF5E5E")
    end
end

function construct(scene)
    title = TextMobject("three engines, one baseline — but not one syntax";
                        size = 0.44, color = GREY_A)
    to_edge!(title, UP; buff = 0.4)
    add!(scene, title)

    # SAME formula, and note the third line: `:typst` speaks TYPST, not LaTeX.
    # The contract the three share is METRIC (x-height and baseline), not
    # syntactic. Feeding `\frac{a^2}{b}` to typst is a compile error, and it
    # should be — a silent reinterpretation would be worse.
    sources = ((:math, raw"\frac{a^2}{b} + \sqrt{c}", "#58C4DD"),
               (:latex, raw"\frac{a^2}{b} + \sqrt{c}", "#E8A33D"),
               (:typst, raw"frac(a^2, b) + sqrt(c)", "#7FDD58"))
    rows = VGroup()
    for (via, source, colour) in sources
        m = try_route(source, via, 0.9)
        set_color!(m; color = colour)
        lab = TextMobject("via = :$via"; size = 0.35, color = GREY_C)
        # `center = false` on Tex would keep the baseline at y = 0; here the
        # default centring is fine and the ROW is what we align.
        row = VGroup(lab, m)
        arrange!(row, RIGHT; buff = 0.8)
        add!(rows, row)
        # The calibrated quantity is the X-HEIGHT, so that is what to measure.
        # (Total height is not comparable: the three engines set `\sqrt` and
        # the fraction bar at slightly different sizes.)
        probe = try_route(via === :typst ? "x" : "x", via, 1.0)
        println("via=:", via, " → x-height ", round(get_height(probe); digits = 4))
    end
    arrange!(rows, DOWN; buff = 0.6, aligned_edge = LEFT)
    add!(scene, rows)

    play!(scene, LaggedStart([FadeIn(r; shift = 0.3 * RIGHT) for r in rows.submobjects]...;
                             lag_ratio = 0.3); run_time = 1.8)
    wait!(scene, 0.6)

    # Both routes label glyphs, and they do it differently. `:math` knows the
    # CHARACTER of every glyph, so `tex["x"]` works with nothing asked for.
    # A LaTeX SVG carries font ids, so Janim follows ManimGL's trick: the formula
    # is compiled ONCE with each isolated part in a colour of its own, and the
    # glyphs are attributed by that colour. The consequence is worth knowing —
    # through LaTeX a glyph answers only to the `isolate` patterns and `t2c`
    # keys you gave, and asking for anything else says so.
    f = Tex(raw"x^2 + y^2"; via = :latex, isolate = ["x^2"])
    println("via=:latex, isolate=[\"x^2\"] → tex[\"x^2\"] = ",
            length(f["x^2"].submobjects), " glyphs; keys: ", get_all_keys(f))
    println("and tex[\"y\"], which was never isolated: ",
            try; f["y"]; "found"; catch err; first(sprint(showerror, err), 120); end)
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "05_latex_config.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
