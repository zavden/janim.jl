# Ejemplo 09 · LA ESTELA SUAVE — el equivalente de make_smooth() de Manim.
#
# Un solo doble péndulo, y su estela dibujada DOS VECES a partir de las MISMAS
# muestras: a la izquierda tal cual (poligonal, sin suavizar) y a la derecha con `smooth=true`. Comparar dos péndulos distintos
# no valdría: el doble péndulo es caótico y dos integraciones se separarían
# solas, así que el mérito de la curva no se podría distinguir del caos.
#
# El muestreo es a 20 fps A PROPÓSITO. Con muestreo fino la poligonal ya
# engaña al ojo; lo que se quiere ver aquí es qué pasa cuando el objeto se
# mueve rápido entre frame y frame, que es cuando make_smooth se nota.
#
#   julia --project=. examples/scenes/09_pendulum_trail.jl

using Janim
using OrdinaryDiffEqTsit5

const G09 = 9.8
function _dp09!(du, u, p, t)
    θ1, θ2, ω1, ω2 = u
    Δ = θ1 - θ2
    den = 3 - cos(2Δ)
    du[1] = ω1; du[2] = ω2
    du[3] = (-3G09 * sin(θ1) - G09 * sin(θ1 - 2θ2) - 2sin(Δ) * (ω2^2 + ω1^2 * cos(Δ))) / den
    du[4] = 2sin(Δ) * (2ω1^2 + 2G09 * cos(θ1) + ω2^2 * cos(Δ)) / den
end

# La estela alcanza 2L desde el pivote, así que las dos columnas necesitan al
# menos 4L de separación para no pisarse. Medido mirando el render, que es la
# regla de la casa para cualquier número geométrico.
const L09 = 1.15
const OFFSET = Point3f(6.0, 0, 0)
const PIVOTE = Point3f(-3.0, 0.95, 0)

function construct(scene)
    titulo = TextMobject("La misma estela, unida de dos maneras"; size = 0.55)
    to_edge!(titulo, UP; buff = 0.3)
    izq = TextMobject("poligonal"; size = 0.42, color = "#8894A6")
    der = TextMobject("make_smooth!"; size = 0.42, color = "#58C4DD")
    move_to!(izq, Point3f(-3.0, -3.15, 0))
    move_to!(der, Point3f(3.0, -3.15, 0))
    add!(scene, titulo, izq, der)

    integ = init(ODEProblem(_dp09!, [2.3, 2.7, 0.0, 0.0], (0.0, 1e4)), Tsit5();
                 reltol = 1e-10, abstol = 1e-10)
    estado = Ref((PIVOTE, PIVOTE))          # (codo, punta)

    # UN solo integrador: el de la varilla izquierda. Todo lo demás lo lee.
    varilla = VMobject(); set_stroke!(varilla; color = "#C8D2DC", width = 3.0)
    add_updater!(varilla, function (m, dt)
        if dt > 0
            step!(integ, dt, true)
            θ1, θ2 = integ.u[1], integ.u[2]
            a = PIVOTE + Point3f(L09 * sin(θ1), -L09 * cos(θ1), 0)
            estado[] = (a, a + Point3f(L09 * sin(θ2), -L09 * cos(θ2), 0))
        end
        set_points_as_corners!(m, [PIVOTE, estado[][1], estado[][2]])
        nothing
    end)

    "El mismo péndulo dibujado en la columna `off`: varilla y dos masas."
    function columna(off)
        v = off == OFFSET ? VMobject() : varilla
        if off == OFFSET
            set_stroke!(v; color = "#C8D2DC", width = 3.0)
            add_updater!(v, (m, dt) -> (set_points_as_corners!(m,
                [PIVOTE + off, estado[][1] + off, estado[][2] + off]); nothing))
        end
        b1 = Circle(radius = 0.085); set_fill!(b1; color = "#C8D2DC", opacity = 1.0)
        b2 = Circle(radius = 0.105); set_fill!(b2; color = "#FFD25E", opacity = 1.0)
        set_stroke!(b1; opacity = 0); set_stroke!(b2; opacity = 0)
        add_updater!(b1, (m, dt) -> (move_to!(m, estado[][1] + off); nothing))
        add_updater!(b2, (m, dt) -> (move_to!(m, estado[][2] + off); nothing))
        return (v, b1, b2)
    end

    # LA COMPARACIÓN: dos estelas alimentadas por el MISMO punto. `time_traced`
    # deja una estela rodante en vez de un ovillo: lo que se compara es cómo se
    # unen las muestras, y para eso hace falta poder ver los tramos.
    cruda = TracedPath(() -> estado[][2]; stroke_color = "#8894A6",
                       stroke_width = 2.8, time_traced = 5.0)
    suave = TracedPath(() -> estado[][2] + OFFSET; stroke_color = "#58C4DD",
                       stroke_width = 2.8, time_traced = 5.0, smooth = true)

    # EL ORDEN IMPORTA, y cuesta un frame entero equivocarse. `add!` fija a la
    # vez el orden de DIBUJO y el de ACTUALIZACIÓN, así que la estela tiene que
    # añadirse DESPUÉS de lo que sigue: si va antes, muestrea la posición del
    # frame anterior y se queda exactamente un frame por detrás del péndulo
    # (medido: 0.618 unidades, que es justo lo que la punta recorre en un frame
    # a 20 fps). Para dibujarla DEBAJO se usa `set_z_index!`, que toca el dibujo
    # y NO el orden de los updaters — `bring_to_back!` sí lo tocaría, y
    # reintroduciría el desfase sin decir nada.
    add!(scene, columna(Point3f(0, 0, 0))..., columna(OFFSET)..., cruda, suave)
    set_z_index!(cruda, -1); set_z_index!(suave, -1)
    wait!(scene, 14.0)
end

if abspath(PROGRAM_FILE) == @__FILE__
    Scene(construct; output = joinpath(@__DIR__, "output", "09_pendulum_trail.mp4"),
          fps = 20, resolution = (1280, 720))
end
