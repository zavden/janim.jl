# Demo 08 · LA LUZ SUMA, EL PIGMENTO MULTIPLICA — modos de fusión por capa.
#
# A la izquierda, tres discos de luz pura (R, G, B), cada uno en su capa con
# `blend = :add`: donde se solapan dos sale amarillo, cian o magenta, y donde
# se solapan los tres, BLANCO. A la derecha, tres tintas (C, M, Y) sobre un
# papel, cada una en su capa con `blend = :multiply`: los solapes dan rojo,
# verde y azul, y los tres juntos, NEGRO.
#
# Cada disco va en SU capa a propósito: dentro de una misma capa los mobjects
# se dibujan uno sobre otro (tapan), y el modo de fusión actúa entre la capa
# entera y lo que tiene debajo. Los tres de luz van dentro de una
# precomposición (`Layer(Composition(...))`) para ponerle el Bloom al
# conjunto y no al papel.
#
# Y el compositor compone en LUZ LINEAL: rojo + verde + azul da
# blanco de verdad, no el gris sucio de sumar bytes sRGB. Manim no tiene modos
# de fusión: un disco con opacidad 0.5 sobre otro es una mezcla alfa, que ni
# suma ni multiplica.
#
#   julia --project=. examples/demo/08_light_vs_pigment.jl

using Janim

"Un disco de color plano, sin borde, en `pos`."
function disc(color, pos)
  c = Circle(radius = 1.15, fill_opacity = 1.0)
  set_fill!(c; color, opacity = 1.0)
  set_stroke!(c; opacity = 0)
  move_to!(c, pos)
  c
end

"El k-ésimo de tres puntos a distancia r del centro, a 120°."
spread(center, k, r) = center + Point3f(
  r * cos(TAU / 4 + k * TAU / 3),
  r * sin(TAU / 4 + k * TAU / 3),
  0,
)

function construct(scene)
  c_light = Point3f(-3.6, -0.35, 0)
  c_pig = Point3f(3.6, -0.35, 0)
  far, near = 1.45, 0.62

  light = [
    disc(c, spread(c_light, k, far))
    for (k, c) in enumerate(("#FF0000", "#00FF00", "#0000FF"))
  ]
  pigment = [
    disc(c, spread(c_pig, k, far))
    for (k, c) in enumerate(("#00FFFF", "#FF00FF", "#FFFF00"))
  ]

  paper = RoundedRectangle(
    width = 6.2,
    height = 5.6,
    corner_radius = 0.3,
  )
  set_fill!(paper; color = "#F4F1E8", opacity = 1.0)
  set_stroke!(paper; opacity = 0)
  move_to!(paper, c_pig)

  title = TextMobject(
    "light ADDS, pigment MULTIPLIES";
    size = 0.5,
    color = GREY_A,
  )
  to_edge!(title, UP; buff = 0.3)
  t_light = TextMobject("blend = :add"; size = 0.34, color = GREY_B)
  t_pig = TextMobject("blend = :multiply"; size = 0.34, color = GREY_B)
  move_to!(t_light, Point3f(-3.6, -3.35, 0))
  move_to!(t_pig, Point3f(3.6, -3.35, 0))

  glow = Bloom(threshold = 0.55, intensity = 0.55, sigma = 0.14)
  use_composition!(
    scene,
    Composition(
      Layer(paper),
      Layer(
        Composition(
          Layer(light[1]; blend = :add),
          Layer(light[2]; blend = :add),
          Layer(light[3]; blend = :add),
        );
        blend = :add,
        effects = [glow],
      ),
      Layer(pigment[1]; blend = :multiply),
      Layer(pigment[2]; blend = :multiply),
      Layer(pigment[3]; blend = :multiply),
      Layer(title, t_light, t_pig);
      background = (0.02f0, 0.02f0, 0.03f0, 1f0),
    ),
  )

  # los seis giran como un todo mientras están juntos: la mezcla no depende
  # de quién está encima, porque no hay "encima"
  spinning = Ref(false)
  clock = VGroup()
  add_updater!(clock, (m, dt) -> begin
    (spinning[] && dt > 0) || return
    for d in light
      rotate!(d, 0.6dt; about_point = c_light)
    end
    for d in pigment
      rotate!(d, 0.6dt; about_point = c_pig)
    end
    nothing
  end)
  add!(scene, clock)

  wait!(scene, 0.8)
  play!(
    scene,
    AnimationGroup(
      (
        animate(d, (move_to!, spread(c_light, k, near)))
        for (k, d) in enumerate(light)
      )...,
      (
        animate(d, (move_to!, spread(c_pig, k, near)))
        for (k, d) in enumerate(pigment)
      )...,
    );
    run_time = 2.5,
  )
  wait!(scene, 1.0)
  spinning[] = true
  wait!(scene, 4.5)
  spinning[] = false
  play!(
    scene,
    AnimationGroup(
      (
        animate(d, (move_to!, spread(c_light, k, far)))
        for (k, d) in enumerate(light)
      )...,
      (
        animate(d, (move_to!, spread(c_pig, k, far)))
        for (k, d) in enumerate(pigment)
      )...,
    );
    run_time = 2.0,
  )
  wait!(scene, 1.0)
end

if abspath(PROGRAM_FILE) == @__FILE__
  Scene(
    construct;
    output = joinpath(@__DIR__, "08_light_vs_pigment.mp4"),
    fps = 30,
    resolution = (1280, 720),
  )
end
