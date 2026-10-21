# Galería · 03 — UpdatersExample (docs de Manim CE, adaptado).
#
#   julia --project=. examples/gallery/03_updaters.jl
#
# Un point_mob orbita por updater temporal; un square lo persigue con un
# updater de posición. Ambos nacen
# con su estilo final (un updater re-estampa estilo cada frame).

using Janim

const KEY_FRAME = 2.5
# One continuous updater act — frames spread by thirds instead of act ends.
const KEY_FRAMES = [KEY_FRAME, 1.2, 3.9]
const RESOLUTION = (640, 360)

function construct(scene)
    point_mob = Circle(radius = 0.12)
    set_fill!(point_mob; color = YELLOW, opacity = 1.0)
    set_stroke!(point_mob; opacity = 0.0, width = 0.0)

    box = Square(side_length = 0.6)
    set_stroke!(box; color = BLUE, width = 4.0)

    clock = Ref(0.0)
    add_updater!(point_mob, (m, dt) -> begin
        clock[] += dt
        move_to!(m, 2.2 * Point3f(cos(1.5 * clock[]), sin(1.5 * clock[]), 0))
    end)
    add_updater!(box, (m, dt) -> move_to!(m, get_center(point_mob)))

    add!(scene, point_mob, box)
    wait!(scene, 4.5)
end

if abspath(PROGRAM_FILE) == @__FILE__
    dir = joinpath(@__DIR__, "expected")
    mkpath(dir)
    for (i, t) in enumerate(KEY_FRAMES)
        name = i == 1 ? "03_updaters.png" : "03_updaters@$(t).png"
        path = joinpath(dir, name)
        render_frame(construct, t; fps = 30, resolution = RESOLUTION, png = path)
        println("→ ", path)
    end
end
