# Ejemplo 10 · EL ATRACTOR DE LORENZ — un millón de partículas con glow.
#
# El combo que solo esta biblioteca tiene entero: un `GlowDots` de
# 100³ partículas cuyo updater MUTA los puntos in place (el idioma de la
# primitiva: `get_points(dc)` entrega el vector vivo), sobre una capa `:add`
# con un Bloom suave.
#
# La medición que fija la receta: en nubes
# VOLUMÉTRICAS el glow por fragmento gana en coste (2.7×) y en lectura —
# la densidad local se ve como brillo. El Bloom va de acento, no de motor:
# con umbral alto solo enciende el corazón del atractor. En nubes DENSAS
# sobre una curva es al revés (el alfa satura y el halo lo pone Bloom) —
# esa es la regla que enseña la lección c1_06/05.
#
# El color es la condición inicial: cada partícula guarda para siempre la
# franja z de la que salió (el mapa 3b1b). Ver las bandas mezclarse ES ver
# la sensibilidad a condiciones iniciales — a los ~8 s el cubo ordenado es
# mármol veteado.
#
#   julia --project=. examples/scenes/10_lorenz_glow.jl

using Janim

const Σ10, Ρ10, Β10 = 10f0, 28f0, 8f0 / 3f0
const CENTRO10 = Point3f(0f0, 0f0, 25f0)
const ESCALA10 = 0.125f0

function _paso_lorenz!(raw::Vector{Point3f}, dt::Float32)
    @inbounds for i in eachindex(raw)
        p = raw[i]
        x, y, z = p[1], p[2], p[3]
        raw[i] = Point3f(x + dt * Σ10 * (y - x),
                         y + dt * (x * (Ρ10 - z) - y),
                         z + dt * (x * y - Β10 * z))
    end
end

function construct(scene)
    reorient!(scene.frame, -50.0, 65.0; height = 9.5)

    # 100³ semillas en un cubo pequeño cerca del atractor
    lado = 100
    raw = Point3f[Point3f(0.4 + 1.1i / lado, 0.4 + 1.1j / lado, 19.6 + 1.1k / lado)
                  for i in 1:lado for j in 1:lado for k in 1:lado]

    dc = GlowDots(fill(ORIGIN, length(raw)); radius = 0.024, glow_factor = 2.0)
    set_opacity!(dc, 0.13)
    # el color ES la condición inicial: la franja z de origen, para siempre
    # (el mapa 3b1b vía la API pública de gradientes)
    banda = color_gradient(["#1C758A", "#83C167", "#FFFF00", "#FC6255"], 256)
    zs = [p[3] for p in raw]
    zlo, zhi = extrema(zs)
    set_colors!(dc, [banda[1 + round(Int, 255 * (z - zlo) / (zhi - zlo))]
                     for z in zs]; opacity = 0.13)

    proyecta!(pts) = @inbounds for i in eachindex(pts)
        pts[i] = ESCALA10 * (raw[i] - CENTRO10)
    end
    proyecta!(get_points(dc))

    add_updater!(dc, (m, dt) -> begin
        dt <= 0 && return
        h = Float32(dt) / 4
        for _ in 1:4                       # 4 subpasos: Lorenz pide dt corto
            _paso_lorenz!(raw, h)
        end
        proyecta!(get_points(m))
    end)

    titulo = TextMobject("el atractor de Lorenz — 10⁶ partículas";
                         size = 0.4, color = GREY_A)
    to_corner!(titulo, UL; buff = 0.35)
    fix_in_frame!(titulo)

    use_composition!(scene, Composition(
        Layer(dc; effects = [Bloom(threshold = 0.6, sigma = 0.09)], blend = :add),
        Layer(titulo)))

    wait!(scene, 1.0)                      # el cubo ordenado, un instante
    play!(scene, animate(scene.frame, (reorient!, 30.0, 55.0)); run_time = 11.0)
    wait!(scene, 2.0)
end

if abspath(PROGRAM_FILE) == @__FILE__
    Scene(construct; output = joinpath(@__DIR__, "output", "10_lorenz_glow.mp4"),
          fps = 30, resolution = (1280, 720))
end
