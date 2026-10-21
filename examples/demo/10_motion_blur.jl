# Demo 10 · MOTION BLUR — cada frame es la media de 8 exposiciones.
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
#   julia --project=. examples/demo/10_motion_blur.jl

using Janim

function construct(scene)
  title = TextMobject("motion blur"; size = 0.95, color = WHITE)
  move_to!(title, Point3f(-10.0, 2.4, 0))       # fuera de cuadro, a la izquierda

  # una rueda con radios: al girar deprisa, los radios se funden en un disco
  wheel = VGroup()
  for k in 0:5
    spoke = Rectangle(width = 3.0, height = 0.16)
    set_fill!(spoke; color = "#FFD25E", opacity = 1.0)
    set_stroke!(spoke; opacity = 0)
    rotate!(spoke, k * TAU / 12)
    add!(wheel, spoke)
  end
  rim = Circle(radius = 1.55)
  set_stroke!(rim; color = "#FFD25E", width = 8.0)
  add!(wheel, rim)
  hub = Circle(radius = 0.22, fill_opacity = 1.0)
  set_fill!(hub; color = "#FF3D8B", opacity = 1.0)
  set_stroke!(hub; opacity = 0)
  wheel_center = Point3f(-3.4, -0.9, 0)
  move_to!(wheel, wheel_center)
  move_to!(hub, wheel_center)

  # el giro es función CERRADA del tiempo: acelera 3 s y luego va a 3 rev/s
  ω_max, T_acc = 3.0 * TAU, 3.0
  angle(t) = t < T_acc ? ω_max * t^2 / (2T_acc) : ω_max * (t - T_acc / 2)
  θ_prev = Ref(0.0)
  add_updater!(wheel, (m, dt) -> begin
    θ = angle(scene.t)
    rotate!(m, θ - θ_prev[]; about_point = wheel_center)
    θ_prev[] = θ
    nothing
  end)

  # cuatro partículas en órbita rápida: cada una sigue su propio arco
  orbit_center = Point3f(3.4, -0.9, 0)
  ring = Circle(radius = 1.8)
  move_to!(ring, orbit_center)
  set_stroke!(ring; color = "#25405C", width = 2.0)
  orbiters = VGroup()
  for (k, c) in enumerate(("#FF3D8B", "#39D0FF", "#7FDD58", "#FFFFFF"))
    d = Dot(ORIGIN; radius = 0.18)
    set_fill!(d; color = c)
    add!(orbiters, d)
  end
  add_updater!(orbiters, (m, dt) -> begin
    t = scene.t
    for (k, d) in enumerate(m.submobjects)
      φ = 1.3 * TAU * t + (k - 1) * TAU / 4
      move_to!(d, orbit_center + Point3f(1.8cos(φ), 1.8sin(φ), 0))
    end
    nothing
  end)

  caption = TextMobject(
    "motion_blur = 8, shutter = 0.5: the state advances between sub-exposures";
    size = 0.32,
    color = GREY_C,
  )
  to_edge!(caption, DOWN; buff = 0.35)

  add!(scene, wheel, hub, ring, orbiters, title, caption)

  # 1 · el título entra a látigo
  play!(
    scene,
    animate(title, (move_to!, Point3f(0, 2.4, 0)); rate_func = ease_out_quint);
    run_time = 0.6,
  )
  # 2 · la rueda acelera y las partículas orbitan
  wait!(scene, 5.0)
  # 3 · barrido de cámara: todo se emborrona a la vez, incluido lo quieto
  play!(
    scene,
    animate(scene.frame, (move_to!, Point3f(3.2, -0.6, 0)), (scale_frame!, 0.6));
    run_time = 0.7,
  )
  wait!(scene, 0.8)
  play!(
    scene,
    animate(scene.frame, (move_to!, ORIGIN), (scale_frame!, 1 / 0.6));
    run_time = 0.7,
  )
  wait!(scene, 1.2)
end

if abspath(PROGRAM_FILE) == @__FILE__
  Scene(
    construct;
    output = joinpath(@__DIR__, "10_motion_blur.mp4"),
    fps = 30,
    resolution = (1280, 720),
    motion_blur = 8,
    shutter = 0.5,
  )
end
