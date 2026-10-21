# Course 3 · 2.4 — DirectionalBlur
#
#     DirectionalBlur(sigma, angle)      sigma in scene units, angle in radians
#
# A ONE-dimensional Gaussian along `angle`. Half the cost of a full blur, and
# it reads as SPEED: a shape smeared along its direction of travel is what the
# eye expects from something moving fast.
#
# It is not motion blur. Motion blur (chapter 5) averages several exposures of
# the scene as the state advances, so it smears every object along its own
# path, curves included. This one smears the whole layer along one straight
# direction. Use it when the direction is obvious and the cost matters — a
# speed line, a wipe, a horizontal scan — and motion blur when the truth
# matters.
#
# `angle` is a plain field, so animating it sweeps the smear around.
#
#   julia --project=. examples/tutorial/c3_02_blur_and_glow/04_directional_blur.jl

using Janim

const PREVIEW_T = 2.0

function construct(scene)
    title = TextMobject("a one-dimensional Gaussian reads as speed";
                        size = 0.42, color = GREY_A)
    to_edge!(title, UP; buff = 0.3)

    "A little rocket: a triangle and two dots."
    function rocket(x, y)
        g = VGroup()
        t = Triangle(radius = 0.5)
        rotate!(t, -PI / 2)
        set_fill!(t; color = "#FFD25E", opacity = 1.0); set_stroke!(t; opacity = 0)
        move_to!(t, Point3f(x, y, 0))
        add!(g, t)
        for dx in (-0.55, -0.95)
            d = Circle(radius = 0.16)
            set_fill!(d; color = "#FF5E5E", opacity = 1.0); set_stroke!(d; opacity = 0)
            move_to!(d, Point3f(x + dx, y, 0))
            add!(g, d)
        end
        return g
    end

    still = rocket(-3.6, 1.2)
    smear = rocket(-3.6, -1.2)
    swept = rocket(3.4, 0.0)

    l1 = TextMobject("as rendered"; size = 0.3, color = GREY_B)
    move_to!(l1, Point3f(-3.6, 2.1, 0))
    l2 = TextMobject("DirectionalBlur(0.12, angle = 0)"; size = 0.3, color = GREY_B)
    move_to!(l2, Point3f(-3.6, -2.3, 0))
    l3 = TextMobject("…with the angle animated"; size = 0.3, color = GREY_B)
    move_to!(l3, Point3f(3.4, -2.3, 0))

    spin = DirectionalBlur(0.12, 0.0)
    clock = VGroup()
    add_updater!(clock, function (m, dt)
        dt > 0 || return
        spin.angle = 0.9 * scene.t
        nothing
    end)
    add!(scene, clock)

    use_composition!(scene, Composition(
        Layer(still),
        Layer(smear; effects = [DirectionalBlur(0.12, 0.0)]),
        Layer(swept; effects = [spin]),
        Layer(title, l1, l2, l3);
        background = (0.02f0, 0.03f0, 0.05f0, 1f0)))

    wait!(scene, 3.0)
    println("swept angle at the end: ", round(spin.angle / DEG; digits = 1), "°")
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__),
                   "04_directional_blur.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
