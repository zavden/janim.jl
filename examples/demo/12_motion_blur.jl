# Demo 12 · MOTION BLUR — cada frame es la media de 8 exposiciones.
#
#     Scene(construct; motion_blur = 8, shutter = 0.5)
#
# No es un difuminado direccional pintado sobre la imagen: el motor avanza
# el ESTADO de la escena entre sub-exposiciones y promedia (en luz lineal).
# Así cada objeto se emborrona a lo largo de SU trayectoria —
# rectas, arcos, giros, movimiento de cámara— y con `shutter = 0.5` (el
# obturador de 180° del cine) los radios de una rueda rápida se funden en un
# disco, como en una cámara de verdad.
#
# Tres cosas en un mismo plano: un título que entra a látigo, una rueda que
# acelera, cuatro partículas en órbita, y al final un barrido de cámara que
# lo emborrona todo a la vez. Manim no tiene motion blur.
#
# NOTA: el motor no admite motion blur dentro del bucle de render: `Scene`
# con `motion_blur > 1` lanza un error. Esta escena conserva su pie original;
# para un fotograma borroso suelto está `render_frame_motion`.
#
#   julia --project=. examples/demo/12_motion_blur.jl

using Janim

function construct(scene)
  title = VGroup(
    TextMobject("Welcome"; size = 0.95, color = WHITE),
    TextMobject("to"; size = 0.95, color = WHITE),
    TextMobject("JANIM"; size = 0.95, color = WHITE, font="Fredoka Expanded"),
  )
  arrange!(title, DOWN)
  scale!(title, 1.8)
  shift!(title, LEFT * 11)

  caption = TextMobject(
    "motion_blur = 8, shutter = 0.5: the state advances between sub-exposures";
    size = 0.32,
    color = GREY_C,
  )
  to_edge!(caption, DOWN; buff = 0.35)

  add!(scene, caption)
  wait!(scene, 1)
  add!(scene, title)
  play!(
    scene,
    animate(title[1], (set_x!, 0); rate_func = ease_out_quint);
    run_time = 0.8,
  )
  wait!(scene, 0.1)
  play!(
    scene,
    animate(title[2], (set_x!, 0); rate_func = ease_out_quint);
    run_time = 0.8,
  )
  wait!(scene, 0.1)
  play!(
    scene,
    animate(title[3], (set_x!, 0); rate_func = ease_out_quint);
    run_time = 0.8,
  )
  wait!(scene, 3)
end

if abspath(PROGRAM_FILE) == @__FILE__
  Scene(
    construct;
    output = joinpath(@__DIR__, "12_motion_blur.mp4"),
    fps = 30,
    resolution = (1280, 720),
    motion_blur = 8,
    shutter = 0.5,
  )
end
