# Demo 11 · PERSECUCIÓN Y MINIMAPA — tres cámaras y un HUD fijo.
#
# Un cometa recorre un nudo trébol atravesando tres puertas. En pantalla,
# tres vistas del MISMO mundo a la vez:
#
#   · la principal, con la cámara de la escena orbitando por `animate`, en
#     dos tramos: los 11 s del ejemplo original y otros 10 siguiendo la
#     vuelta, para que el cometa complete dos pasadas por las puertas;
#   · CHASE: una capa cuya cámara persigue al cometa con un updater
#     (`move_to!` al centro del cometa, cada frame) — el idiom que en CE
#     pide un `ZoomedScene`, aquí es un updater sobre un `CameraFrame`;
#   · TOP: un minimapa cenital en ventana CUADRADA — la ventana recorta la
#     vista de su cámara al mayor corte central con su aspecto, así que una
#     ventana cuadrada sobre una cámara 16:9 enseña el centro cuadrado.
#
# El HUD entero (marcos, etiquetas, leyenda) va con `fix_in_frame!`: la
# ventana de una capa se proyecta por la cámara del PADRE, y un mobject
# fijado a pantalla se queda quieto aunque la principal orbite — por eso los
# recuadros no derrapan durante el vuelo de cámara.
#
# La estela es UNA `TracedPath` compartida por las tres capas: la lista de
# updaters se deduplica por identidad, así que registra un punto por
# frame, no tres.
#
# Es `examples/scenes/12_chase_camera.jl` con los rótulos en inglés y diez segundos
# más de vuelo.
#
#   julia --project=. examples/demo/11_chase_camera.jl

using Janim
using LinearAlgebra: cross, norm, normalize

knot(t) = Point3f(
  0.85 * (sin(t) + 2sin(2t)),
  0.85 * (cos(t) - 2cos(2t)),
  -0.85 * sin(3t),
)

function construct(scene)
  reorient!(scene.frame, -30.0, 66.0; height = 9.5)

  # ── el mundo: suelo, puertas, cometa y su estela ─────────────────────
  floor = NumberPlane(
    (-4.0, 4.0, 1.0),
    (-4.0, 4.0, 1.0);
    width = 8.0,
    height = 8.0,
    background_line_color = "#1E3350",
    faded_opacity = 0.10,
  )

  gate(t0) = begin
    g = Torus(;
      r1 = 0.42,
      r2 = 0.055,
      resolution = (49, 25),
    )
    set_color!(g; color = "#8AE08A")
    apply_depth_test!(g)
    p = knot(t0)
    v = normalize(Point3f(knot(t0 + 1e-3) - p))
    axis = cross([0.0, 0.0, 1.0], [v...])
    s = norm(axis)
    s > 1e-6 && rotate!(g, atan(s, v[3]); axis = axis)
    move_to!(g, p)
    g
  end
  gates = [gate(0.8), gate(2.9), gate(5.0)]

  comet = Sphere(; radius = 0.14)
  set_color!(comet; color = "#FFD25E")
  apply_depth_test!(comet)
  τ = Ref(0.0)
  add_updater!(comet, (m, dt) -> begin
    τ[] += 0.55 * dt
    move_to!(m, knot(τ[]))
  end)
  trail = TracedPath(
    () -> get_center(comet);
    stroke_color = "#FFD25E",
    stroke_width = 2.5,
    time_traced = 4.0,
  )

  world = [floor.group, gates..., trail, comet]

  # ── las otras dos cámaras ────────────────────────────────────────────
  cam_chase = CameraFrame()
  reorient!(cam_chase, -30.0, 66.0)
  set_frame_height!(cam_chase, 2.4)
  add_updater!(cam_chase, f -> move_to!(f, get_center(comet)))

  cam_map = CameraFrame()
  set_frame_height!(cam_map, 7.5)             # cenital: φ = 0 es la planta

  # ── el HUD, fijado a pantalla ────────────────────────────────────────
  w_chase = Rectangle(
    width = 4.2,
    height = 4.2 * 9 / 16,
  )
  set_stroke!(w_chase; color = GREY_B, width = 3.0)
  set_fill!(w_chase; opacity = 0)
  to_corner!(w_chase, UR; buff = 0.35)

  w_map = Square(side_length = 2.9)
  set_stroke!(w_map; color = GREY_B, width = 3.0)
  set_fill!(w_map; opacity = 0)
  to_corner!(w_map, DR; buff = 0.35)

  tag(txt, w) = begin
    t = TextMobject(txt; size = 0.24, color = GREY_B)
    align_to!(t, w, UL)
    shift!(t, Point3f(0.14, -0.26, 0))
    t
  end
  caption = TextMobject(
    "three cameras, one world — the HUD does not drift: fix_in_frame";
    size = 0.34,
    color = GREY_C,
  )
  to_corner!(caption, DL; buff = 0.4)
  hud = [w_chase, w_map, tag("CHASE", w_chase), tag("TOP", w_map), caption]
  foreach(fix_in_frame!, hud)

  use_composition!(
    scene,
    Composition(
      Layer(world...),
      Layer(world...; camera = cam_chase, window = w_chase),
      Layer(world...; camera = cam_map, window = w_map),
      Layer(hud...);
      background = (0.015f0, 0.02f0, 0.04f0, 1f0),
    ),
  )

  # dos tramos de vuelo: el original y otros diez segundos siguiendo la vuelta
  wait!(scene, 0.5)
  play!(scene, animate(scene.frame, (reorient!, 25.0, 58.0)); run_time = 11.0)
  play!(scene, animate(scene.frame, (reorient!, 85.0, 64.0)); run_time = 10.0)
  wait!(scene, 0.5)
end

if abspath(PROGRAM_FILE) == @__FILE__
  Scene(
    construct;
    output = joinpath(@__DIR__, "11_chase_camera.mp4"),
    fps = 30,
    resolution = (1280, 720),
  )
end
