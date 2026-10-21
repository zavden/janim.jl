# Example 06 · DESIGN: the coordinate map is DERIVED, not stored.
#
#   julia --project=. examples/scenes/06_design_map.jl
#
# The design decision, made visible. `c2p` reads the axis line's CURRENT endpoints,
# so moving the axes moves the whole coordinate world with them — no
# invalidation, nothing to keep in sync.
#
# The alternative (storing the map as numbers, or equivalently computing a
# point once and keeping it) is simulated HONESTLY on the right: the dot is
# placed at `c2p(1,1)` ONCE, before the axes move. That is exactly what a
# cached map does, and the drift is the bug you would ship.
#
# Both halves get the same scale and the same shift.

using Janim

const RESOLUTION = (1280, 720)

marcador(color) = begin
    d = Dot(ORIGIN; radius = 0.11)
    set_color!(d; color)
    d
end

hacer_plano() = begin
    pl = NumberPlane((-3, 3, 1), (-2, 2, 1); width = 4.4, height = 3.0,
                     background_stroke_width = 2.5, faded_line_ratio = 2)
    pl
end

function construct(scene)
    title = TextMobject("El mapa de coordenadas: derivado vs cacheado";
                        size = 0.5, color = GREY_A)
    to_edge!(title, UP; buff = 0.3)
    add!(scene, title)

    izq, der = hacer_plano(), hacer_plano()
    shift!(izq, 3.3 * LEFT + 0.4 * DOWN)
    shift!(der, 3.3 * RIGHT + 0.4 * DOWN)

    vivo = marcador(YELLOW)
    cacheado = marcador(RED)
    add!(scene, izq, der, vivo, cacheado)

    # IZQUIERDA · el punto se pregunta cada frame: sigue al plano
    add_updater!(vivo, m -> (move_to!(m, coords_to_point(izq, 1, 1)); nothing))

    # DERECHA · el punto se calculó UNA vez, antes de mover nada. Eso es un
    # mapa cacheado, y por eso se queda atrás.
    move_to!(cacheado, coords_to_point(der, 1, 1))

    et_izq = TextMobject("c2p(1,1) preguntado cada frame"; size = 0.28, color = YELLOW)
    et_der = TextMobject("c2p(1,1) calculado una vez"; size = 0.28, color = RED)
    move_to!(et_izq, Point3f(-3.3, -3.0, 0))
    move_to!(et_der, Point3f(3.3, -3.0, 0))
    add!(scene, et_izq, et_der)

    wait!(scene, 0.5)
    # el MISMO movimiento en los dos lados
    play!(scene, AnimationGroup(animate(izq, (scale!, 0.62)),
                               animate(der, (scale!, 0.62))); run_time = 1.2)
    play!(scene, AnimationGroup(animate(izq, (shift!, 0.9 * UP + 0.5 * RIGHT)),
                               animate(der, (shift!, 0.9 * UP + 0.5 * RIGHT))),
          run_time = 1.2)
    play!(scene, AnimationGroup(animate(izq, (rotate!, TAU / 14)),
                               animate(der, (rotate!, TAU / 14))); run_time = 1.2)

    # y se señala el que se quedó atrás
    play!(scene, Circumscribe(cacheado; shape = :circle, buff = 0.25, color = RED);
          run_time = 1.0)
    wait!(scene, 0.8)
end

if abspath(PROGRAM_FILE) == @__FILE__
    path = joinpath(@__DIR__, "output", "06_design_map.mp4")
    mkpath(dirname(path))
    Scene(construct; output = path, fps = 30, resolution = RESOLUTION)
    println("written ", path)
end
