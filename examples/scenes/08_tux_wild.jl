# Example 08 · Tux, three wild ways — a REAL icon-set SVG (16 gradients,
# 23 paths) put through everything the engine can throw at it:
#
#   A · big bang: every child explodes on its own, morphs to an acid
#       palette, and Transform re-assembles the penguin, gradients intact
#   B · style-row surgery: a rainbow wave repaints the SoA style rows LIVE
#       from an updater, then a pure-style Transform to neon wireframe
#   C · the compositor: a glowing giant Tux behind (:add + animated Blur +
#       Bloom) while the camera dives in
#
#   julia --project=. examples/scenes/08_tux_wild.jl        # renders the three
#
# Deterministic on purpose: the "randomness" is index arithmetic.

using Janim
using Colors: HSV, RGB, red, green, blue
using LinearAlgebra: norm

const TUX = joinpath(@__DIR__, "..", "assets", "linux.svg")
const RESOLUTION = (1280, 720)

# an acid palette, by index (no rand: same video every run)
acid_color(i) = begin
    c = RGB(HSV(mod(47.0i, 360.0), 0.9, 1.0))
    Janim.Vec4f(red(c), green(c), blue(c), 1)
end

# ═══════════════════════════════════════════════════════════════════════
# A · big bang
# ═══════════════════════════════════════════════════════════════════════

function construct_a(scene)
    title = TextMobject("Tux · big bang por hijos"; size = 0.45, color = GREY_A)
    to_edge!(title, UP; buff = 0.3)
    tux = SVGMobject(TUX; height = 4.6)
    shift!(tux, 0.2 * DOWN)
    original = copy(tux)                      # the way home
    add!(scene, title, tux)
    wait!(scene, 0.4)

    # every child gets its own throw: direction from the centre, a spin and
    # a squash — all derived from its index (deterministic chaos)
    c0 = get_center(tux)
    anims = Animation[]
    for (i, child) in enumerate(tux.submobjects)
        d = get_center(child) - c0
        n = norm(d)
        dir = n > 1e-6 ? d / n : Point3f(cos(0.7i), sin(0.7i), 0)
        dist = 2.0 + 1.6 * mod(0.23i, 1.0)
        spin = (isodd(i) ? 1 : -1) * TAU * (0.25 + 0.5 * mod(0.37i, 1.0))
        squash = 0.55 + 0.9 * mod(0.61i, 1.0)
        push!(anims, animate(child, (shift!, dist * dir), (rotate!, spin),
                             (scale!, squash)))
    end
    play!(scene, AnimationGroup(anims...; lag_ratio = 0.03); run_time = 1.7)
    wait!(scene, 0.3)

    # while shattered, morph the WHOLE thing onto an acid recolour of the
    # intact penguin: one Transform aligns the 23 children pairwise
    acid = SVGMobject(TUX; height = 4.6)
    shift!(acid, 0.2 * DOWN)
    rotate!(acid, TAU / 28)
    for (i, child) in enumerate(acid.submobjects)
        for k in eachindex(child.fill_rgba)
            a = child.fill_rgba[k][4]
            col = acid_color(i + 3)
            child.fill_rgba[k] = Janim.Vec4f(col[1], col[2], col[3], a)
        end
    end
    play!(scene, Transform(tux, acid); run_time = 1.4)
    wait!(scene, 0.4)

    # and home: the file's own gradients come back through the same door
    play!(scene, Transform(tux, original); run_time = 1.2)
    wait!(scene, 0.6)
end

# ═══════════════════════════════════════════════════════════════════════
# B · style-row surgery
# ═══════════════════════════════════════════════════════════════════════

function construct_b(scene)
    title = TextMobject("Tux · cirugía de filas de estilo en vivo";
                        size = 0.45, color = GREY_A)
    to_edge!(title, UP; buff = 0.3)
    tux = SVGMobject(TUX; height = 5.0)
    shift!(tux, 0.2 * DOWN)
    pristine = copy(tux)                      # gradients, as imported
    add!(scene, title, tux)

    # a rainbow wave: an updater repaints EVERY style row per frame as a
    # function of position and time — the SoA rows are just data
    tt = Ref(0.0)
    add_updater!(tux, (m, dt) -> begin
        tt[] += dt
        for child in m.submobjects
            rows = child.fill_rgba
            pts = child.points
            for k in eachindex(rows)
                h = 360.0 * mod(0.21 * (pts[k][1] + 0.6 * pts[k][2]) + 0.35 * tt[], 1.0)
                c = RGB(HSV(h, 0.85, 1.0))
                rows[k] = Janim.Vec4f(red(c), green(c), blue(c), rows[k][4])
            end
        end
        nothing
    end)
    wait!(scene, 3.0)
    clear_updaters!(tux)                      # freeze BEFORE the next play

    # pure-STYLE Transform: same points, rows crossfade to a neon wireframe
    neon = copy(pristine)
    for (i, child) in enumerate(neon.submobjects)
        set_fill!(child; opacity = 0)
        set_stroke!(child; color = acid_color(2i), opacity = 1.0, width = 3.0)
    end
    play!(scene, Transform(tux, neon); run_time = 1.3)
    wait!(scene, 0.5)
    play!(scene, Transform(tux, pristine); run_time = 1.3)
    wait!(scene, 0.6)
end

# ═══════════════════════════════════════════════════════════════════════
# C · the compositor: glow behind, camera diving
# ═══════════════════════════════════════════════════════════════════════

function construct_c(scene)
    title = TextMobject("Tux · capas: glow aditivo + blur animado + zoom";
                        size = 0.42, color = GREY_A)
    to_edge!(title, UP; buff = 0.3)

    front = SVGMobject(TUX; height = 4.2)
    shift!(front, 0.3 * DOWN)
    back = SVGMobject(TUX; height = 7.8)      # the ghost: huge, additive, soft
    shift!(back, 0.3 * DOWN)

    halo = Blur(0.22)
    comp = Composition(
        Layer(back; blend = :add, opacity = 0.55, effects = [halo]),
        Layer(front; effects = [Bloom(threshold = 0.55, intensity = 0.9,
                                      sigma = 0.10)]),
        Layer(title);
        background = (0.05f0, 0.04f0, 0.09f0, 1f0))
    use_composition!(scene, comp)

    # the ghost spins slowly and its blur BREATHES — mutating the effect's
    # field from an updater is the idiom
    tt = Ref(0.0)
    add_updater!(back, (m, dt) -> begin
        tt[] += dt
        rotate!(m, 0.25 * dt)
        halo.sigma = 0.22 + 0.12 * sin(1.6 * tt[])
        nothing
    end)

    wait!(scene, 1.2)
    play!(scene, animate(scene.frame, (scale_frame!, 0.72)); run_time = 1.8)
    wait!(scene, 1.0)
    play!(scene, animate(scene.frame, (scale_frame!, 1 / 0.72)); run_time = 1.8)
    wait!(scene, 0.8)
end

# ═══════════════════════════════════════════════════════════════════════

if abspath(PROGRAM_FILE) == @__FILE__
    outdir = joinpath(@__DIR__, "output")
    mkpath(outdir)
    for (name, construct) in [("08_tux_a", construct_a), ("08_tux_b", construct_b),
                              ("08_tux_c", construct_c)]
        path = joinpath(outdir, name * ".mp4")
        Scene(construct; output = path, fps = 30, resolution = RESOLUTION)
        println("written ", path)
    end
end
