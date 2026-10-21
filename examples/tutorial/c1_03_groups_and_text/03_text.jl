# Course 1 · 3.3 — Text
#
#     TextMobject(s; font = "DejaVu Sans", size = 1.0, color = WHITE,
#                 t2c = nothing, t2w = nothing, center = true)
#
# Plain text straight through FreeType: outlines, advances and kerning, turned
# into quadratic Béziers. No LaTeX, no SVG round trip. Simple Latin is the
# honest frontier — complex shaping (Arabic, ligature-heavy scripts) is
# HarfBuzz's job and is deliberately out.
#
# Every glyph is a CHILD carrying its character as a key (`text["a"]` groups
# the a's), which is what makes colour-by-substring and per-symbol animation
# work without a second mechanism.
#
#   t2c = Dict("orbit" => YELLOW, 1:6 => BLUE)     colour by substring or range
#   t2w = Dict("important" => :bold)               weight, or a whole font name
#
# `t2c`/`t2w` are applied INSIDE the constructor, not afterwards, because that
# is the only place that knows which glyph came from which character — spaces
# produce no child, so glyph number ≠ character number.
#
# A miss is an ERROR, not a silent fallback: `findfont` is fuzzy and always
# answers with SOMETHING, so asking for a weight your system lacks would
# quietly give you the regular one. Janim checks and complains.
#
#   julia --project=. examples/tutorial/c1_03_groups_and_text/03_text.jl

using Janim

const PREVIEW_T = 2.8

function construct(scene)
    lines = VGroup()

    plain = TextMobject("plain text through FreeType"; size = 0.6)
    add!(lines, plain)

    coloured = TextMobject("colour by substring and by range";
                           size = 0.6,
                           t2c = Dict("substring" => YELLOW, 25:32 => "#7FDD58"))
    add!(lines, coloured)

    weighted = TextMobject("weight comes from a real face";
                           size = 0.6, t2w = Dict("real face" => :bold))
    add!(lines, weighted)

    serif = TextMobject("another family entirely"; size = 0.6,
                        font = "Liberation Serif", color = "#E8A33D")
    add!(lines, serif)

    arrange!(lines, DOWN; buff = 0.45)
    shift!(lines, 0.4 * UP)
    add!(scene, lines)

    # Glyphs are children keyed by their character, so this is a real group.
    println("the letter «e» appears ", length(find_by_key(plain, "e")), " times")

    play!(scene, LaggedStart([Write(l) for l in lines.submobjects]...;
                             lag_ratio = 0.25); run_time = 2.4)

    # `plain["e"]` is a group of SCATTERED glyphs, so `Indicate`'s default
    # scale_factor would scale the CONSTELLATION and pull the letters out of
    # their words. `scale_factor = 1.0` leaves the geometry alone and keeps
    # only the tint — which is what you meant by "highlight every e".
    play!(scene, Indicate(plain["e"]; color = "#FF5E5E", scale_factor = 1.0);
          run_time = 1.2)
    wait!(scene, 0.4)
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "03_text.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
