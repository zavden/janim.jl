# Galería · 02 — WarpSquare (example_scenes.py de ManimGL).
#
#   julia --project=. examples/gallery/02_warp_square.jl
#
# El square atraviesa el mapa conforme z ↦ e^z: un Transform hacia una
# copia deformada con apply_points_function! (el equivalente Janim de
# apply_complex_function).

using Janim

const KEY_FRAME = 1.4
# Mid-warp, the FadeIn's end, and the settled hold.
const KEY_FRAMES = [KEY_FRAME, 0.5, 2.7]
const RESOLUTION = (640, 360)

function _warpear!(m)
    apply_points_function!(m; about_point = ORIGIN) do p
        z = exp(complex(p[1], p[2]))
        Point3f(real(z) - 1.2, imag(z), 0)
    end
end

function construct(scene)
    hacer() = begin
        c = Square(side_length = 2.0)
        set_stroke!(c; color = YELLOW, width = 4.0)
        set_fill!(c; color = YELLOW, opacity = 0.2)
        c
    end
    square = hacer()
    play!(scene, FadeIn(square); run_time = 0.6)
    target = hacer()
    _warpear!(target)
    play!(scene, Transform(square, target); run_time = 1.6)
    wait!(scene, 0.6)
end

if abspath(PROGRAM_FILE) == @__FILE__
    dir = joinpath(@__DIR__, "expected")
    mkpath(dir)
    for (i, t) in enumerate(KEY_FRAMES)
        name = i == 1 ? "02_warp_square.png" : "02_warp_square@$(t).png"
        path = joinpath(dir, name)
        render_frame(construct, t; fps = 30, resolution = RESOLUTION, png = path)
        println("→ ", path)
    end
end
