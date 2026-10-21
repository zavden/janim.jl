# Galería · 01 — SquareToCircle (el «hola mundo» de Manim).
#
#   julia --project=. examples/gallery/01_square_to_circle.jl
#
# Un square se dibuja, gira 45°, morfa a círculo y se desvanece.
# KEY_FRAME cae a mitad del Transform: el fotograma captura la
# interpolación, no solo los estados de reposo.

using Janim

const KEY_FRAME = 1.7
# Mid-Transform first, then settled act ends — the hold after the morph and
# the FadeOut's tail.
const KEY_FRAMES = [KEY_FRAME, 2.8, 3.8]
const RESOLUTION = (640, 360)

function construct(scene)
    square = Square()
    set_fill!(square; color = BLUE, opacity = 0.7)
    set_stroke!(square; color = WHITE, width = 4.0)
    rotate!(square, TAU / 8)
    play!(scene, ShowCreation(square); run_time = 1.0)

    circle = Circle(radius = 1.2)
    set_fill!(circle; color = YELLOW, opacity = 0.7)
    set_stroke!(circle; color = WHITE, width = 4.0)
    play!(scene, Transform(square, circle); run_time = 1.4)
    wait!(scene, 0.5)
    play!(scene, FadeOut(square; shift = 0.5 * DOWN); run_time = 1.0)
    wait!(scene, 0.4)
end

if abspath(PROGRAM_FILE) == @__FILE__
    dir = joinpath(@__DIR__, "expected")
    mkpath(dir)
    for (i, t) in enumerate(KEY_FRAMES)
        name = i == 1 ? "01_square_to_circle.png" : "01_square_to_circle@$(t).png"
        path = joinpath(dir, name)
        render_frame(construct, t; fps = 30, resolution = RESOLUTION, png = path)
        println("→ ", path)
    end
end
