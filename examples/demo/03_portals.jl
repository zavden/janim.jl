# Demo 03 · PORTALES — una figura, tres cámaras: la de la escena en el centro
# y dos LUPAS iguales a los lados, una circular y otra con forma de estrella.
#
# Un mundo 2D (una roseta con rótulos diminutos y dos puntos que la recorren
# en sentidos opuestos) dibujado por la cámara de la escena en el centro. A
# los lados, dos capas que ven el MISMO mundo con cámaras propias, y cuya
# ventana no es un rectángulo. Las dos cámaras son la misma lupa ×3 que
# persigue a un punto (un updater sobre el `CameraFrame`, lo que en CE pide
# un `ZoomedScene` entero): el círculo va tras el punto amarillo y la
# estrella tras el verde. Es un render de verdad, no una copia escalada: el
# trazo no engorda con el zoom y los rótulos de 0.1 unidades salen nítidos.
# La forma del portal es solo la máscara — la cámara no sabe si es un
# círculo o una estrella. Y la estrella GIRA sobre sí misma (máscara y aro,
# con un updater): la imagen de dentro sigue derecha, lo que gira es el
# recorte. Como la caja de una estrella que gira cambia de tamaño y de
# centro, la VENTANA de esa capa es un cuadrado fijo que no se dibuja, y la
# estrella es solo la máscara: el aumento no oscila y la imagen no baila.
#
# La mecánica: `window =` coloca la vista en la CAJA del mobject (la lupa es
# un cuadrado; la estrella, casi), y `crop(...; inside = forma)` recorta esa
# caja con la forma de verdad. La máscara se aplica en el espacio del PADRE,
# después de la ventana, así que la misma forma sirve de ventana y de recorte.
# La forma que recorta va rellena y NO se dibuja; el aro visible es otro
# mobject, solo stroke, en la capa de arriba.
#
#   julia --project=. examples/demo/03_portals.jl

using Janim

"Una hipotrocoide: cinco lóbulos, cerrada tras dos vueltas."
function rosette_point(t)
  R, r, d = 2.0, 0.8, 1.15
  k = (R - r) / r
  Point3f(
    (R - r) * cos(t) + d * cos(k * t),
    (R - r) * sin(t) - d * sin(k * t),
    0,
  )
end

function construct(scene)
  # ── el mundo 2D ────────────────────────────────────────────────────────
  plane = NumberPlane(
    (-7.0, 7.0, 1.0),
    (-4.0, 4.0, 1.0);
    width = 14.0,
    height = 8.0,
    background_line_color = "#1C2E4A",
    faded_opacity = 0.12,
  )

  rosette = VMobject()
  set_points_smoothly!(rosette, [rosette_point(t) for t in range(0, 4π; length = 721)])
  set_stroke!(rosette; width = 4.0)
  set_stroke_by_gradient!(rosette, "#FF3D8B", "#FFD25E", "#39D0FF", "#7FDD58", "#FF3D8B")

  # rótulos DIMINUTOS a lo largo de la curva: en el centro apenas se leen, en
  # la lupa salen nítidos — la prueba de que la lupa es un render y no un zoom
  # de píxeles
  labels = VGroup()
  for k in 1:10
    p = point_from_proportion(rosette, (k - 0.5) / 10)
    t = TextMobject(string(k); size = 0.11, color = GREY_A)
    move_to!(t, p + 0.22 * Point3f(-p[2], p[1], 0) / max(hypot(p[1], p[2]), 1e-6))
    add!(labels, t)
  end
  fine_print = TextMobject("a real render, not a copy"; size = 0.09, color = GREY_B)
  move_to!(fine_print, Point3f(0, -0.1, 0))

  # dos puntos, del color del aro que los persigue, recorriendo la roseta en
  # sentidos opuestos (una vuelta cada 7 s)
  runner(color, α_of_t) = begin
    d = Dot(ORIGIN; radius = 0.11)
    set_fill!(d; color)
    set_stroke!(d; color = WHITE, width = 1.5, opacity = 1.0)
    add_updater!(d, (m, dt) -> begin
      move_to!(m, point_from_proportion(rosette, α_of_t(scene.t)))
      nothing
    end)
    d
  end
  dot_a = runner("#FFD25E", t -> mod(t / 7.0, 1.0))
  dot_b = runner("#7FDD58", t -> mod(0.5 - t / 7.0, 1.0))
  # las colas van DESPUÉS de sus puntos en la lista: así muestrean la
  # posición de este frame y no la del anterior
  tail_a = TracingTail(() -> get_center(dot_a); time_traced = 0.9, color = WHITE, stroke_width = 7.0)
  tail_b = TracingTail(() -> get_center(dot_b); time_traced = 0.9, color = WHITE, stroke_width = 7.0)

  world = [plane.group, rosette, labels, fine_print, tail_a, tail_b, dot_a, dot_b]

  # ── las dos cámaras ────────────────────────────────────────────────────
  # la misma lupa dos veces: ×3, pegada a su punto. La estrella recorta con
  # una caja de aspecto ~1.05, así que ve 1.3 unidades de alto igual que el
  # círculo — el aumento es el mismo
  cam_lens = CameraFrame()
  set_frame_height!(cam_lens, 1.3)
  add_updater!(cam_lens, f -> move_to!(f, get_center(dot_a)))

  cam_star = CameraFrame()
  set_frame_height!(cam_star, 1.3)
  add_updater!(cam_star, f -> move_to!(f, get_center(dot_b)))

  # ── los portales: la forma RELLENA recorta y no se dibuja; el aro se ve ──
  lens_mask = Circle(radius = 1.9, fill_opacity = 1.0)
  set_fill!(lens_mask; color = WHITE, opacity = 1.0)
  set_stroke!(lens_mask; opacity = 0)
  move_to!(lens_mask, Point3f(-4.9, 0.2, 0))
  lens_rim = Circle(radius = 1.9)
  set_fill!(lens_rim; opacity = 0)
  set_stroke!(lens_rim; color = "#FFD25E", width = 4.0)
  move_to!(lens_rim, Point3f(-4.9, 0.2, 0))

  # El centro de la CAJA de una estrella de cinco puntas no es su centro:
  # está 0.2 u por encima (la punta de arriba llega a R y las de abajo a
  # R·cos 36°). Girar sobre él la haría orbitar, así que se coloca y se gira
  # por el centroide, que `get_real_center_of_mass` da exacto.
  star_center = Point3f(4.9, 0.2, 0)
  star_mask = Star(5; outer_radius = 2.15, inner_radius = 1.15)
  set_fill!(star_mask; color = WHITE, opacity = 1.0)
  set_stroke!(star_mask; opacity = 0)
  shift!(star_mask, star_center - get_real_center_of_mass(star_mask))
  star_rim = Star(5; outer_radius = 2.15, inner_radius = 1.15)
  set_fill!(star_rim; opacity = 0)
  set_stroke!(star_rim; color = "#7FDD58", width = 4.0)
  shift!(star_rim, star_center - get_real_center_of_mass(star_rim))
  # la ventana: una caja fija del tamaño de la estrella (no se dibuja)
  star_window = Square(side_length = 4.3)
  move_to!(star_window, star_center)
  # la estrella gira: la máscara (que recorta y hace de ventana) y el aro
  # visible reciben el mismo giro cada frame, sobre el mismo punto
  add_updater!(star_mask, (m, dt) -> begin
    dt > 0 || return
    rotate!(m, 0.3dt; about_point = star_center)
    rotate!(star_rim, 0.3dt; about_point = star_center)
    nothing
  end)

  # ── rótulos ────────────────────────────────────────────────────────────
  tag_lens = TextMobject("LENS ×3"; size = 0.34, color = "#FFD25E")
  next_to!(tag_lens, lens_rim, DOWN; buff = 0.3)
  tag_star = TextMobject("LENS ×3"; size = 0.34, color = "#7FDD58")
  move_to!(tag_star, Point3f(4.9, -2.65, 0))       # bajo la punta más baja que pueda haber
  tag_mid = TextMobject("the scene camera"; size = 0.3, color = GREY_B)
  move_to!(tag_mid, Point3f(0, -2.65, 0))
  caption = TextMobject(
    "one 2D world, three cameras — two identical lenses, each chasing its own dot: the portal's shape is just a mask, and it can spin";
    size = 0.3,
    color = GREY_C,
  )
  get_width(caption) > FRAME_WIDTH - 1.0 && set_width!(caption, FRAME_WIDTH - 1.0)
  to_edge!(caption, DOWN; buff = 0.3)

  use_composition!(
    scene,
    Composition(
      Layer(world...),
      crop(
        world...;
        inside = lens_mask,
        feather = 0.02,
        camera = cam_lens,
        window = lens_mask,
      ),
      crop(
        world...;
        inside = star_mask,
        feather = 0.02,
        camera = cam_star,
        window = star_window,
      ),
      Layer(lens_rim, star_rim, tag_lens, tag_star, tag_mid, caption);
      background = (0.015f0, 0.02f0, 0.04f0, 1f0),
    ),
  )

  # dos vueltas de cada punto; todo lo demás son updaters
  wait!(scene, 14.0)
end

if abspath(PROGRAM_FILE) == @__FILE__
  Scene(
    construct;
    output = joinpath(@__DIR__, "03_portals.mp4"),
    fps = 30,
    resolution = (1280, 720),
  )
end
