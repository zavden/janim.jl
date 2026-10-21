# Ejemplo 01 · Teoría de conjuntos con MÁSCARAS DE RECORTE.
#
#   julia --project=. examples/scenes/01_sets.jl
#
# Dos conjuntos A y B; las regiones A∩B, A∖B, B∖A y A∪B se iluminan
# usando `crop` (máscaras desde VMobjects normales), con los títulos
# morfando entre fórmulas.

using Janim

const AZUL = "#58C4DD"
const NARANJA = "#F0A045"
const AMARILLO = "#FFD25E"

function construct(scene)
    centro_A = 1.05 * LEFT + 0.45 * DOWN
    centro_B = 1.05 * RIGHT + 0.45 * DOWN

    contorno(pos, color) = begin
        c = Circle(radius = 1.9, fill_opacity = 0.0)
        set_stroke!(c; color, width = 5.0)
        shift!(c, pos); c
    end
    relleno(pos, color, opacidad) = begin
        c = Circle(radius = 1.9, fill_opacity = opacidad)
        set_fill!(c; color, opacity = opacidad)
        set_stroke!(c; opacity = 0)
        shift!(c, pos); c
    end
    mascara(pos) = relleno(pos, "#FFFFFF", 1.0)      # la forma que recorta

    A, B = contorno(centro_A, AZUL), contorno(centro_B, NARANJA)

    # regiones resaltadas: rellenos completos RECORTADOS por el otro círculo
    hi_int = relleno(centro_A, AMARILLO, 0.85)       # A ∩ B (dentro de B)
    hi_AmB = relleno(centro_A, AZUL, 0.6)            # A ∖ B (menos B)
    hi_BmA = relleno(centro_B, NARANJA, 0.6)         # B ∖ A (menos A)
    hi_uA, hi_uB = relleno(centro_A, AZUL, 0.45), relleno(centro_B, NARANJA, 0.45)

    background = Rectangle(width = 16.0, height = 9.0, fill_color = "#101418",
                      fill_opacity = 1.0, stroke_opacity = 0, stroke_width = 0)

    label(s, pos) = begin
        t = Tex(s; color = "#FFFFFF", size = 1.1)
        move_to!(t, pos); t
    end
    etiq_A = label("A", centro_A + 2.1 * UL)
    etiq_B = label("B", centro_B + 2.1 * UR)

    title = Tex(raw"A \cap B"; color = AMARILLO, size = 1.35)
    move_to!(title, 2.85 * UP)
    formula(s, color) = begin
        t = Tex(s; color, size = 1.35)
        move_to!(t, 2.85 * UP); t
    end

    use_composition!(scene, Composition(
        Layer(background),
        crop(hi_int; inside = mascara(centro_B), feather = 0.02),
        crop(hi_AmB; minus = mascara(centro_B), feather = 0.02),
        crop(hi_BmA; minus = mascara(centro_A), feather = 0.02),
        Layer(hi_uA, hi_uB),
        Layer(A, B, etiq_A, etiq_B, title),
    ))

    # arranque: solo los contornos y las etiquetas (los resaltes, apagados)
    for m in (hi_int, hi_AmB, hi_BmA, hi_uA, hi_uB)
        set_fill!(m; opacity = 0.0)
    end
    # "aparecer" = Transform hacia una copia con la opacidad target
    # (FadeIn funde hacia el estado ACTUAL, que aquí es 0)
    aparecer(m, op) = Transform(m, (c = copy(m); set_fill!(c; opacity = op); c))

    play!(scene, LaggedStart(ShowCreation(A), ShowCreation(B); lag_ratio = 0.35);
          run_time = 1.8)
    play!(scene, AnimationGroup(FadeIn(etiq_A; shift = 0.3 * DOWN),
                              FadeIn(etiq_B; shift = 0.3 * DOWN)); run_time = 0.7)
    wait!(scene, 0.4)

    # A ∩ B — la lente amarilla solo existe donde A pisa B
    play!(scene, AnimationGroup(FadeIn(title), aparecer(hi_int, 0.85)); run_time = 0.9)
    wait!(scene, 1.8)

    # A ∖ B
    play!(scene, AnimationGroup(Transform(title, formula(raw"A \setminus B", AZUL)),
                              FadeOut(hi_int), aparecer(hi_AmB, 0.6)); run_time = 1.0)
    wait!(scene, 1.8)

    # B ∖ A
    play!(scene, AnimationGroup(Transform(title, formula(raw"B \setminus A", NARANJA)),
                              FadeOut(hi_AmB), aparecer(hi_BmA, 0.6)); run_time = 1.0)
    wait!(scene, 1.8)

    # A ∪ B
    play!(scene, AnimationGroup(Transform(title, formula(raw"A \cup B", "#7FDD58")),
                              FadeOut(hi_BmA), aparecer(hi_uA, 0.45), aparecer(hi_uB, 0.45));
          run_time = 1.0)
    wait!(scene, 2.0)

    play!(scene, AnimationGroup(FadeOut(hi_uA), FadeOut(hi_uB), FadeOut(title),
                              FadeOut(etiq_A), FadeOut(etiq_B),
                              FadeOut(A), FadeOut(B)); run_time = 1.2)
    wait!(scene, 0.4)
end

if abspath(PROGRAM_FILE) == @__FILE__
    path = joinpath(@__DIR__, "output", "01_sets.mp4")
    mkpath(dirname(path))
    Scene(construct; output = path, fps = 30, resolution = (1280, 720))
    println("→ ", path)
end
