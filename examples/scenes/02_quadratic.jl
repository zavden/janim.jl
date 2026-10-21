# Ejemplo 02 · Deducción de la fórmula cuadrática en 5 PASOS.
#
#   julia --project=. examples/scenes/02_quadratic.jl
#
# Una sola fórmula que MORFA por completación del cuadrado: los glifos
# comunes viajan (Transform glyph a glyph), el contador
# de paso morfa en la esquina, y el paso key lleva su subtítulo.

using Janim

const PASOS = [
    raw"ax^2 + bx + c = 0",
    raw"x^2 + \frac{b}{a}x = -\frac{c}{a}",
    raw"\left(x + \frac{b}{2a}\right)^2 = \frac{b^2 - 4ac}{4a^2}",
    raw"x + \frac{b}{2a} = \pm\frac{\sqrt{b^2 - 4ac}}{2a}",
    raw"x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}",
]
const NOTAS = ["la ecuación general", "dividir entre a y despejar",
               "completar el cuadrado", "raíz cuadrada a ambos lados",
               "despejar x"]

function construct(scene)
    title = TextMobject("La formula cuadratica")
    set_height!(title, 0.42)
    move_to!(title, 3.05 * UP)
    set_fill!(title; color = "#8899AA", opacity = 1.0)

    hacer_formula(k) = begin
        t = Tex(PASOS[k]; color = "#FFFFFF", size = 1.15)
        get_width(t) > 10.5 && set_width!(t, 10.5)
        move_to!(t, 0.3 * UP); t
    end
    hacer_paso(k) = begin
        p = Tex("$k"; color = "#FFD25E", size = 1.0)
        move_to!(p, 5.9 * RIGHT + 3.05 * UP); p
    end
    hacer_nota(k) = begin
        n = TextMobject(NOTAS[k])
        set_height!(n, 0.3)
        set_fill!(n; color = "#58C4DD", opacity = 1.0)
        move_to!(n, 2.35 * DOWN); n
    end

    f = hacer_formula(1)
    paso = hacer_paso(1)
    nota = hacer_nota(1)

    play!(scene, AnimationGroup(FadeIn(title; shift = 0.25 * DOWN),
                              FadeIn(f; shift = 0.4 * UP),
                              FadeIn(paso), FadeIn(nota)); run_time = 1.0)
    wait!(scene, 1.6)

    for k in 2:5
        play!(scene, AnimationGroup(Transform(f, hacer_formula(k)),
                                  Transform(paso, hacer_paso(k)),
                                  Transform(nota, hacer_nota(k))); run_time = 1.3)
        wait!(scene, k == 5 ? 2.4 : 1.7)
    end

    # el resultado, subrayado con una box que se dibuja sola
    box = Rectangle(width = get_width(f) + 0.7, height = get_height(f) + 0.55)
    set_stroke!(box; color = "#FFD25E", width = 4.0)
    move_to!(box, get_center(f))
    play!(scene, ShowCreation(box); run_time = 0.9)
    wait!(scene, 1.6)
    play!(scene, AnimationGroup(FadeOut(f), FadeOut(box), FadeOut(title),
                              FadeOut(paso), FadeOut(nota)); run_time = 1.0)
    wait!(scene, 0.3)
end

if abspath(PROGRAM_FILE) == @__FILE__
    path = joinpath(@__DIR__, "output", "02_quadratic.mp4")
    mkpath(dirname(path))
    Scene(construct; output = path, fps = 30, resolution = (1280, 720))
    println("→ ", path)
end
