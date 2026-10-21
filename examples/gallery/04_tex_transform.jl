# Galería · 04 — TexTransformExample (el morf de fórmulas clásico).
#
#   julia --project=. examples/gallery/04_tex_transform.jl
#
# Pitágoras despejado: a²+b²=c² → c=√(a²+b²), glyph a glyph (sin
# fantasmas de subpaths colapsados, alineación por children).

using Janim

const KEY_FRAME = 2.2
# Mid-morph, the source formula settled, the target held.
const KEY_FRAMES = [KEY_FRAME, 1.3, 3.5]
const RESOLUTION = (640, 360)

function construct(scene)
    f1 = Tex(raw"a^2 + b^2 = c^2"; size = 1.4)
    play!(scene, FadeIn(f1; shift = 0.3 * UP); run_time = 0.8)
    wait!(scene, 0.6)
    f2 = Tex(raw"c = \sqrt{a^2 + b^2}"; size = 1.4)
    play!(scene, Transform(f1, f2); run_time = 1.4)
    wait!(scene, 0.8)
end

if abspath(PROGRAM_FILE) == @__FILE__
    dir = joinpath(@__DIR__, "expected")
    mkpath(dir)
    for (i, t) in enumerate(KEY_FRAMES)
        name = i == 1 ? "04_tex_transform.png" : "04_tex_transform@$(t).png"
        path = joinpath(dir, name)
        render_frame(construct, t; fps = 30, resolution = RESOLUTION, png = path)
        println("→ ", path)
    end
end
