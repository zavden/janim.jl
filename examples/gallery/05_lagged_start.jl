# Galería · 05 — LaggedStart (la cascada canónica de Manim).
#
#   julia --project=. examples/gallery/05_lagged_start.jl
#
# Cinco círculos aparecen en cascada (lag_ratio=0.25) y se van en cascada
# inversa. KEY_FRAME captura la cascada a medias: unos ya están, otros
# llegando, otros sin nacer.

using Janim

const KEY_FRAME = 1.0
# Mid-cascade, the reverse wave's end, the settled field.
const KEY_FRAMES = [KEY_FRAME, 2.5, 4.1]
const RESOLUTION = (640, 360)

function construct(scene)
    colores = [BLUE, GREEN, YELLOW, RED, WHITE]
    circulos = [Circle(radius = 0.5) for _ in 1:5]
    for (k, c) in enumerate(circulos)
        set_fill!(c; color = colores[k], opacity = 0.8)
        set_stroke!(c; color = WHITE, width = 3.0)
        move_to!(c, (1.3 * k - 3.9) * RIGHT)
    end
    play!(scene, LaggedStart([FadeIn(c; shift = 0.5 * UP) for c in circulos]...;
                           lag_ratio = 0.25); run_time = 2.0)
    wait!(scene, 0.6)
    play!(scene, LaggedStart([FadeOut(c; shift = 0.5 * DOWN) for c in reverse(circulos)]...;
                           lag_ratio = 0.25); run_time = 1.6)
    wait!(scene, 0.3)
end

if abspath(PROGRAM_FILE) == @__FILE__
    dir = joinpath(@__DIR__, "expected")
    mkpath(dir)
    for (i, t) in enumerate(KEY_FRAMES)
        name = i == 1 ? "05_lagged_start.png" : "05_lagged_start@$(t).png"
        path = joinpath(dir, name)
        render_frame(construct, t; fps = 30, resolution = RESOLUTION, png = path)
        println("→ ", path)
    end
end
