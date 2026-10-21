# Demo 04 · EL ATRACTOR DE LORENZ — un millón de partículas con glow y motion
# blur de verdad.
#
# El combo que solo esta biblioteca tiene entero: un `GlowDots` de
# 100³ partículas cuyo updater MUTA los puntos in place (el idioma de la
# primitiva: `get_points(dc)` entrega el vector vivo), sobre una capa `:add`
# con un Bloom suave — y el motion blur, que avanza la SIMULACIÓN entre
# sub-exposiciones: las estelas son trayectoria real, no un difuminado.
#
# NOTA: el motor no admite motion blur dentro del bucle de render: `Scene`
# con `motion_blur > 1` lanza un error. Esta escena conserva su pie original;
# para un fotograma borroso suelto está `render_frame_motion`.
#
# Manim no tiene ni nube de puntos con glow por fragmento, ni capas aditivas,
# ni motion blur; y un millón de mobjects lo pararía en seco.
#
# El color es la condición inicial: cada partícula guarda para siempre la
# franja z de la que salió (el mapa de 3b1b). Ver las bandas mezclarse ES ver
# la sensibilidad a condiciones iniciales — a los ~8 s el cubo ordenado es
# mármol veteado.
#
#   julia --project=. examples/demo/04_lorenz_glow.jl

using Janim

const Σ04, Ρ04, Β04 = 10f0, 28f0, 8f0 / 3f0
const CENTER04 = Point3f(0f0, 0f0, 25f0)
const SCALE04 = 0.125f0

function _lorenz_step!(raw::Vector{Point3f}, dt::Float32)
  @inbounds for i in eachindex(raw)
    p = raw[i]
    x, y, z = p[1], p[2], p[3]
    raw[i] = Point3f(
      x + dt * Σ04 * (y - x),
      y + dt * (x * (Ρ04 - z) - y),
      z + dt * (x * y - Β04 * z),
    )
  end
end

function construct(scene)
  reorient!(scene.frame, -50.0, 65.0; height = 9.5)

  # 100³ semillas en un cubo pequeño cerca del atractor
  side = 100
  raw = Point3f[
    Point3f(0.4 + 1.1i / side, 0.4 + 1.1j / side, 19.6 + 1.1k / side)
    for i in 1:side for j in 1:side for k in 1:side
  ]

  dc = GlowDots(
    fill(ORIGIN, length(raw));
    radius = 0.024,
    glow_factor = 2.0,
  )
  set_opacity!(dc, 0.13)
  # el color ES la condición inicial: la franja z de origen, para siempre
  band = color_gradient(["#1C758A", "#83C167", "#FFFF00", "#FC6255"], 256)
  zs = [p[3] for p in raw]
  zlo, zhi = extrema(zs)
  set_colors!(
    dc,
    [band[1 + round(Int, 255 * (z - zlo) / (zhi - zlo))] for z in zs];
    opacity = 0.13,
  )

  project!(pts) = @inbounds for i in eachindex(pts)
    pts[i] = SCALE04 * (raw[i] - CENTER04)
  end
  project!(get_points(dc))

  add_updater!(dc, (m, dt) -> begin
    dt <= 0 && return
    h = Float32(dt) / 4
    for _ in 1:4                       # 4 subpasos: Lorenz pide dt corto
      _lorenz_step!(raw, h)
    end
    project!(get_points(m))
  end)

  title = TextMobject(
    "the Lorenz attractor — 10⁶ particles";
    size = 0.4,
    color = GREY_A,
  )
  to_corner!(title, UL; buff = 0.35)
  fix_in_frame!(title)

  use_composition!(
    scene,
    Composition(
      Layer(dc; effects = [Bloom(threshold = 0.6, sigma = 0.09)], blend = :add),
      Layer(title),
    ),
  )

  wait!(scene, 1.0)                      # el cubo ordenado, un instante
  play!(scene, animate(scene.frame, (reorient!, 30.0, 55.0)); run_time = 15.0)
  wait!(scene, 2.0)
end

if abspath(PROGRAM_FILE) == @__FILE__
  Scene(
    construct;
    output = joinpath(@__DIR__, "04_lorenz_glow.mp4"),
    fps = 30,
    resolution = (1280, 720),
    motion_blur = 4,
    shutter = 0.5,
  )
end
