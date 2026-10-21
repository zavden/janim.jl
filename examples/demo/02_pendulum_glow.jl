# Demo 02 · EL PÉNDULO CON GLOW — física SciML dentro de un updater, una
# estela con Bloom en una capa aditiva y un foco que es una MÁSCARA ANIMADA.
#
# Un doble péndulo integrado con Tsit5 (OrdinaryDiffEq) DENTRO del updater de
# la varilla: el integrador vive fuera, el updater le pide `step!(integ, dt)`
# y lee el estado. Tres cosas que Manim no tiene:
#
#   · la estela va en una capa `blend = :add` con `Bloom`: la luz SUMA en vez
#     de tapar, y el halo sale del propio color del trazo. Las muestras se
#     unen con `set_points_smoothly!` (el `make_smooth` de GL): una curva por
#     los mismos puntos, sin esquinas;
#   · la masa lleva detrás un `GlowDot`: un halo REDONDO por fragmento
#     (`pow(1-r, 2)`), que es lo que un Bloom no puede dar a un punto — el
#     nivel más ancho de su pirámide chocaba con el tope del kernel (±63 px)
#     y el halo salía CUADRADO;
#   · el foco que sigue a la punta es una máscara con `feather`: recorta la
#     rejilla encendida, y como es un mobject normal se mueve con un updater;
#   · debajo queda la rejilla tenue, siempre visible — la misma geometría dos
#     veces, con dos estilos, en dos capas.
#
# Es el acto 2 de `examples/scenes/03_field_and_chaos.jl`, sin las líneas de campo
# de fondo y con la rejilla completa.
#
#   julia --project=. examples/demo/02_pendulum_glow.jl

using Janim
using OrdinaryDiffEqTsit5

const G02 = 9.8
function _double_pendulum!(du, u, p, t)
  θ1, θ2, ω1, ω2 = u
  Δ = θ1 - θ2
  den = 3 - cos(2Δ)
  du[1] = ω1
  du[2] = ω2
  du[3] = (-3G02 * sin(θ1) - G02 * sin(θ1 - 2θ2) - 2sin(Δ) * (ω2^2 + ω1^2 * cos(Δ))) / den
  du[4] = 2sin(Δ) * (2ω1^2 + 2G02 * cos(θ1) + ω2^2 * cos(Δ)) / den
end

"La rejilla de fondo, con el color y el grosor que se le pidan."
function grid(color, width)
  g = VGroup()
  for x in -7.2:0.8:7.2
    l = Line(Point3f(x, -4.2, 0), Point3f(x, 4.2, 0))
    set_stroke!(l; color, width)
    add!(g, l)
  end
  for y in -4.0:0.8:4.0
    l = Line(Point3f(-7.2, y, 0), Point3f(7.2, y, 0))
    set_stroke!(l; color, width)
    add!(g, l)
  end
  g
end

function construct(scene)
  background = Rectangle(
    width = 16.0,
    height = 9.0,
    fill_color = "#0B0E14",
    fill_opacity = 1.0,
    stroke_opacity = 0,
    stroke_width = 0,
  )
  grid_dim = grid("#182338", 1.2)      # la rejilla tenue, siempre visible
  grid_lit = grid("#4A6FA8", 1.8)      # la rejilla encendida bajo el foco

  # el foco: un círculo relleno que NO se dibuja — recorta la rejilla encendida
  spotlight = Circle(radius = 1.45, fill_opacity = 1.0)

  # ── el péndulo ───────────────────────────────────────────────────────
  pivot = Point3f(0, 0.4, 0)
  L = 1.25
  rod = VMobject()
  set_stroke!(rod; color = "#C8D2DC", width = 3.5)
  bob1 = Circle(radius = 0.11, fill_opacity = 1.0)
  set_fill!(bob1; color = "#C8D2DC", opacity = 0.0)
  set_stroke!(bob1; opacity = 0)
  bob2 = Circle(radius = 0.13, fill_opacity = 1.0)
  set_fill!(bob2; color = "#FFD25E", opacity = 0.0)
  set_stroke!(bob2; opacity = 0)
  trail = VMobject()
  set_stroke!(trail; color = "#58C4DD", width = 2.6, opacity = 0.85)
  # el halo de la masa: un GlowDot nace con su estilo final (lo mueve un
  # updater, y un updater no re-estampa la opacidad de un DotCloud)
  halo = GlowDot(ORIGIN; color = "#FFD25E", radius = 0.55, glow_factor = 2.0, opacity = 0.0)

  u0 = [2.1, 2.6, 0.0, 0.0]
  integ = init(
    ODEProblem(_double_pendulum!, u0, (0.0, 1e4)),
    Tsit5();
    reltol = 1e-9,
    abstol = 1e-9,
  )
  positions(u) = begin
    p1 = pivot + Point3f(L * sin(u[1]), -L * cos(u[1]), 0)
    p2 = p1 + Point3f(L * sin(u[2]), -L * cos(u[2]), 0)
    (p1, p2)
  end
  # el estado inicial ya dibujado: nada aparece en el origen y salta después
  p1, p2 = positions(u0)
  set_points_as_corners!(rod, [pivot, p1, p2])
  move_to!(bob1, p1)
  move_to!(bob2, p2)
  move_to!(halo, p2)
  move_to!(spotlight, p2)

  samples = Point3f[]
  tip = Ref(p2)
  running = Ref(false)
  add_updater!(rod, (m, dt) -> begin
    (running[] && dt > 0) || return
    step!(integ, dt, true)
    p1, p2 = positions(integ.u)
    set_points_as_corners!(m, [pivot, p1, p2])
    move_to!(bob1, p1)
    move_to!(bob2, p2)
    move_to!(halo, p2)
    tip[] = p2
    push!(samples, p2)
    length(samples) > 300 && popfirst!(samples)
    # corners + make_smooth! en una llamada: la misma curva
    length(samples) > 1 && set_points_smoothly!(trail, copy(samples))
    nothing
  end)
  add_updater!(spotlight, (m, dt) -> begin
    running[] && move_to!(m, tip[])
    nothing
  end)

  # ── el título ────────────────────────────────────────────────────────
  make_title(s, color) = begin
    t = Tex(s; color, size = 0.95)
    move_to!(t, 3.3 * UP)
    t
  end
  title = make_title(raw"E = T + V", "#C8D2DC")

  use_composition!(
    scene,
    Composition(
      Layer(background, grid_dim),
      crop(grid_lit; inside = spotlight, feather = 0.2),
      Layer(rod, bob1),
      # σ = 0.055 u son 5 px a 720p: los tres niveles de la pirámide (σ, 2σ,
      # 4σ) caben enteros en el kernel, así que el halo es gaussiano de verdad
      Layer(
        trail,
        halo,
        bob2;
        blend = :add,
        effects = [Bloom(threshold = 0.25, intensity = 1.8, sigma = 0.055)],
      ),
      Layer(title),
    ),
  )

  # "aparecer" = Transform hacia una copia con la opacidad target (FadeIn
  # funde hacia el estado ACTUAL, que aquí es 0)
  appear(m, op) = begin
    c = copy(m)
    set_fill!(c; opacity = op)
    Transform(m, c)
  end

  play!(
    scene,
    AnimationGroup(
      FadeIn(title; shift = 0.3 * DOWN),
      appear(bob1, 1.0),
      appear(bob2, 1.0),
      UpdateFromAlphaFunc(halo, (m, a) -> set_opacity!(m, 0.7a)),
    );
    run_time = 1.2,
  )
  running[] = true
  wait!(scene, 8.0)
  play!(
    scene,
    Transform(title, make_title(raw"\dot\theta_1, \; \dot\theta_2", "#FFD25E"));
    run_time = 1.0,
  )
  wait!(scene, 10.0)

  # congelar ANTES del fade: si el updater sigue, re-estampa el estilo cada
  # frame y el fundido no se ve
  running[] = false
  play!(
    scene,
    AnimationGroup(
      FadeOut(rod),
      FadeOut(bob1),
      FadeOut(bob2),
      FadeOut(trail),
      FadeOut(title),
      UpdateFromAlphaFunc(halo, (m, a) -> set_opacity!(m, 0.7 * (1 - a))),
    );
    run_time = 1.8,
  )
  wait!(scene, 0.6)
end

if abspath(PROGRAM_FILE) == @__FILE__
  Scene(
    construct;
    output = joinpath(@__DIR__, "02_pendulum_glow.mp4"),
    fps = 30,
    resolution = (1280, 720),
  )
end
