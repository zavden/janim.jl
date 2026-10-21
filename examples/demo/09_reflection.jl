# Demo 09 · EL REFLEJO — un título sobre el agua, con ondas de verdad.
#
# El reflejo es una copia volteada del título y de la luna en una capa
# propia, y esa capa lleva cuatro cosas que Manim no puede darle:
#
#   · `Wave` con la fase animada desde un updater: las uv se desplazan con un
#     seno que viaja — el agua se mueve, y el reflejo con ella;
#   · `Blur`, porque un reflejo nunca es tan nítido como el original;
#   · `opacity` de capa, para atenuarlo entero de una vez;
#   · una `Mask` con `feather` grande: la cobertura cae suavemente hacia el
#     fondo, que es como se apaga un reflejo con la distancia.
#
# La luna y las estrellas van en una capa `:add` con `Bloom` (el glow del
# cielo), y un `Vignette` en una capa de ajuste cierra el plano. La luna sube
# por updater y su reflejo baja: dos mobjects, un solo movimiento.
#
#   julia --project=. examples/demo/09_reflection.jl

using Janim

const WATERLINE = -0.2

"La copia especular de `m` respecto a la línea del agua."
function mirror(m)
  r = copy(m)
  flip!(r; axis = RIGHT)
  c = get_center(m)
  move_to!(r, Point3f(c[1], 2WATERLINE - c[2], c[3]))
  r
end

"Parte fraccionaria: la secuencia R2 (Roberts) reparte las estrellas sin filas."
frac(x) = x - floor(x)

function construct(scene)
  # ── el cielo ─────────────────────────────────────────────────────────
  title = TextMobject("Janim"; font = "DejaVu Sans", size = 1.7)
  set_fill_by_gradient!(title, "#FFF1C1", "#FFB36B")
  move_to!(title, Point3f(0, WATERLINE + 0.95, 0))

  moon = Circle(radius = 0.5, fill_opacity = 1.0)
  set_fill!(moon; color = "#FFF4D6", opacity = 1.0)
  set_stroke!(moon; opacity = 0)
  move_to!(moon, Point3f(4.6, WATERLINE + 2.5, 0))

  star_points = [
    Point3f(-6.6 + 13.2 * frac(0.7548777k), WATERLINE + 0.7 + 3.2 * frac(0.5698403k), 0)
    for k in 1:90
  ]
  stars = GlowDots(
    star_points;
    color = WHITE,
    radius = 0.035,
    glow_factor = 1.5,
  )

  # ── el agua y los reflejos ───────────────────────────────────────────
  water = Rectangle(width = 16.0, height = 4.0)
  set_fill!(water; color = "#04081A", opacity = 1.0)
  set_stroke!(water; opacity = 0)
  move_to!(water, Point3f(0, WATERLINE - 2.0, 0))

  title_r = mirror(title)
  moon_r = mirror(moon)
  stars_r = GlowDots(
    [Point3f(p[1], 2WATERLINE - p[2], 0) for p in star_points];
    color = WHITE,
    radius = 0.035,
    glow_factor = 1.5,
  )

  # la cobertura del reflejo: 1 junto a la orilla, y cae con la distancia
  fade = Rectangle(width = 16.0, height = 3.2)
  set_fill!(fade; color = WHITE, opacity = 1.0)
  set_stroke!(fade; opacity = 0)
  move_to!(fade, Point3f(0, WATERLINE - 1.0, 0))

  ripple = Wave(; amplitude = 0.035, wavelength = 0.55, angle = TAU / 4, phase = 0.0)

  subtitle = TextMobject(
    "an animation engine with a compositor, in Julia";
    size = 0.34,
    color = GREY_B,
  )
  to_edge!(subtitle, DOWN; buff = 0.3)

  use_composition!(
    scene,
    Composition(
      Layer(
        stars,
        moon;
        blend = :add,
        effects = [Bloom(threshold = 0.6, intensity = 1.0, sigma = 0.12)],
      ),
      Layer(title),
      Layer(water),
      Layer(
        stars_r,
        moon_r,
        title_r;
        opacity = 0.55,
        effects = [ripple, Blur(0.025)],
        mask = Mask(fade; feather = 0.7),
      ),
      Layer(subtitle),
      Layer(; effects = [Vignette(; amount = 0.45, radius = 0.5, feather = 0.5)]);
      background = (0.03f0, 0.04f0, 0.11f0, 1f0),
    ),
  )

  # el agua se mueve y la luna sube (su reflejo, baja)
  clock = VGroup()
  add_updater!(clock, (m, dt) -> begin
    dt > 0 || return
    ripple.phase += 2.4dt
    shift!(moon, Point3f(0, 0.03dt, 0))
    shift!(moon_r, Point3f(0, -0.03dt, 0))
    nothing
  end)
  add!(scene, clock)

  play!(
    scene,
    AnimationGroup(
      FadeIn(title; shift = 0.25 * UP),
      FadeIn(title_r; shift = 0.25 * DOWN),
    );
    run_time = 1.8,
  )
  play!(scene, FadeIn(subtitle); run_time = 0.8)
  wait!(scene, 8.0)
  play!(
    scene,
    AnimationGroup(
      FadeOut(title),
      FadeOut(title_r),
      FadeOut(subtitle),
    );
    run_time = 1.4,
  )
  wait!(scene, 0.8)
end

if abspath(PROGRAM_FILE) == @__FILE__
  Scene(
    construct;
    output = joinpath(@__DIR__, "09_reflection.mp4"),
    fps = 30,
    resolution = (1280, 720),
  )
end
