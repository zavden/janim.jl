# Course 3 · 4.1 — Glitch
#
#     Glitch(; intensity = 0.5, seed = 1, rate = 3, rgb_shift = 0.05,
#              slices = 12, block = 0.3)
#
# Three ingredients in one pass: horizontal BANDS displaced sideways, a few
# BLOCKS jumping harder, and the RGB channels pulled apart.
#
#   intensity   the master dial. **0 is an exact no-op** — the pass is
#               skipped, so the layer comes out bit for bit as it went in.
#   rate        how many FRAMES the pattern is held for. Re-rolling every
#               frame reads as television snow; 2–4 reads as a glitch.
#   slices      how many horizontal bands the frame is cut into.
#   rgb_shift,  in SCENE UNITS, so the look survives the resolution. The
#   block       defaults were MEASURED, not guessed: 0.01 and 0.04 would be
#               0.34 px and 1.35 px at 480p — an invisible separation and
#               one-pixel "blocks" that read as salt-and-pepper.
#   seed        the pattern. It is mixed with the effect's TYPE NAME before
#               reaching the shader, so a Glitch(seed=1) and a Grain(seed=1)
#               on the same layer do not draw the same numbers.
#
# And it is DETERMINISTIC: the randomness is a hash of (pixel, frame, seed),
# never `rand()`, so two renders agree byte for byte.
#
#   julia --project=. examples/tutorial/c3_04_glitch/01_glitch_basics.jl

using Janim

const PREVIEW_T = 1.2

"A broadcast-looking card: flat colour, hard edges, readable text."
function card(x)
    g = VGroup()
    plate = Rectangle(width = 2.9, height = 2.0)
    set_fill!(plate; color = "#1F3B5C", opacity = 1.0); set_stroke!(plate; opacity = 0)
    move_to!(plate, Point3f(x, 0.2, 0))
    add!(g, plate)
    bar = Rectangle(width = 2.9, height = 0.45)
    set_fill!(bar; color = "#FF3D8B", opacity = 1.0); set_stroke!(bar; opacity = 0)
    move_to!(bar, Point3f(x, 0.95, 0))
    add!(g, bar)
    t = TextMobject("SIGNAL"; size = 0.5, color = WHITE)
    move_to!(t, Point3f(x, 0.05, 0))
    add!(g, t)
    return g
end

function construct(scene)
    title = TextMobject("bands, blocks and an RGB split — one pass";
                        size = 0.42, color = GREY_A)
    to_edge!(title, UP; buff = 0.3)

    cases = (("intensity = 0", Glitch(; intensity = 0.0)),
             ("0.35", Glitch(; intensity = 0.35, seed = 3)),
             ("0.8", Glitch(; intensity = 0.8, seed = 3)),
             ("0.8, slices = 40", Glitch(; intensity = 0.8, seed = 3, slices = 40)))

    layers = Layer[]
    labels = Mobject[]
    for (k, (name, fx)) in enumerate(cases)
        x = -5.1 + 3.4(k - 1)
        push!(layers, Layer(card(x); effects = [fx]))
        lab = TextMobject(name; size = 0.3, color = GREY_B)
        move_to!(lab, Point3f(x, -1.6, 0))
        push!(labels, lab)
    end
    push!(layers, Layer(title, labels...))

    use_composition!(scene, Composition(layers...;
                                        background = (0.02f0, 0.03f0, 0.05f0, 1f0)))
    wait!(scene, 1.5)
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "01_glitch_basics.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
