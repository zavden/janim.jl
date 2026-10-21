# Course 3 · 3.4 — invert and hard
#
#     Mask(shape; invert = true)     coverage → 1 − coverage
#     Mask(shape; hard = true)       coverage → step(0.5, coverage)
#
# `invert` is what `crop(…; minus = …)` is built on.
#
# `hard` thresholds the mask at 0.5, which throws away the antialiasing and
# gives a crisp, aliased edge. That is usually the wrong thing — and exactly
# the right thing when the mask is a FEATHERED or NOISY shape being used as a
# stencil: threshold a blurred circle and you get a hard edge you can animate
# smoothly, because the σ moves continuously while the cut stays sharp.
#
# The two compose: `invert` is applied first, then `hard`.
#
#   julia --project=. examples/tutorial/c3_03_masks/04_invert_and_hard.jl

using Janim

const PREVIEW_T = 2.2

"Diagonal bars: fine edges, so aliasing is visible."
function bars(x)
    g = VGroup()
    for k in 0:13
        r = Rectangle(width = 0.22, height = 5.0)
        set_fill!(r; color = k % 2 == 0 ? "#58C4DD" : "#FFD25E", opacity = 1.0)
        set_stroke!(r; opacity = 0)
        rotate!(r, PI / 6)
        move_to!(r, Point3f(x - 1.5 + 0.31k, -0.1, 0))
        add!(g, r)
    end
    return g
end

function construct(scene)
    title = TextMobject("invert flips the coverage; hard thresholds it";
                        size = 0.42, color = GREY_A)
    to_edge!(title, UP; buff = 0.3)

    # The third panel's mask is FEATHERED and then thresholded: the σ can be
    # animated smoothly while the edge stays crisp — a growing stencil.
    grow = Ref(0.35)
    stencil = Circle(radius = 1.4, fill_opacity = 1.0)
    move_to!(stencil, Point3f(4.6, -0.1, 0))
    soft = Mask(stencil; feather = 0.35, hard = true)
    clock = VGroup()
    add_updater!(clock, function (m, dt)
        dt > 0 || return
        soft.feather = 0.05 + 0.55 * (0.5 + 0.5 * sin(1.3 * scene.t))
        nothing
    end)
    add!(scene, clock)

    win1 = Circle(radius = 1.4, fill_opacity = 1.0); move_to!(win1, Point3f(-4.6, -0.1, 0))
    win2 = Circle(radius = 1.4, fill_opacity = 1.0); move_to!(win2, Point3f(0.0, -0.1, 0))

    labels = Mobject[]
    for (x, s) in ((-4.6, "plain"), (0.0, "invert = true"),
                   (4.6, "feather + hard = true"))
        lab = TextMobject(s; size = 0.3, color = GREY_B)
        move_to!(lab, Point3f(x, -2.7, 0))
        push!(labels, lab)
    end

    use_composition!(scene, Composition(
        Layer(bars(-4.6); mask = Mask(win1)),
        Layer(bars(0.0); mask = Mask(win2; invert = true)),
        Layer(bars(4.6); mask = soft),
        Layer(title, labels...);
        background = (0.02f0, 0.03f0, 0.05f0, 1f0)))

    wait!(scene, 3.0)
    println("stencil feather at the end: ", round(soft.feather; digits = 3))
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__),
                   "04_invert_and_hard.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
