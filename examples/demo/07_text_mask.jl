# Demo 07 · LETRAS DE MAR — el título como MÁSCARA de un mundo 3D animado.
#
# Un `TextMobject` es un mobject como cualquier otro, así que puede ser el
# recorte de una capa: `crop(mar; inside = palabra)`. Y la capa recortada
# tiene su PROPIA cámara (`camera =`), inclinada sobre un mar de olas que se
# mueve por updater con normales analíticas (luz de verdad, no un degradado).
# Dentro de cada letra hay un render 3D iluminado; el resto de la pantalla no
# sabe que existe.
#
# El final es el plano clásico de cabecera: la máscara se agranda hasta que
# el ojo entra por la «I» y aparece el mar entero. La máscara es un mobject,
# así que ese vuelo es un `animate` cualquiera con un `about_point`.
#
# Manim no tiene máscaras: `TextMobject` solo se puede dibujar, no recortar.
#
#   julia --project=. examples/demo/07_text_mask.jl

using Janim

function construct(scene)
  # ── el mar: una superficie animada con normales analíticas ──────────
  X, Y, NU, NV = 12.0, 5.5, 101, 51
  sea = PlaneXY(
    x_range = (-X, X),
    y_range = (-Y, Y),
    resolution = (NU, NV),
    color = "#0F3D6E",
    opacity = 1.0,
    shading = (0.25, 0.35, 0.5),
  )
  add_updater!(sea, (m, dt) -> begin
    t = scene.t
    k = 0
    for u in range(-X, X; length = NU), v in range(-Y, Y; length = NV)
      k += 1
      z = 0.34sin(1.7u + 1.8t) * cos(1.4v + 1.3t) + 0.12sin(2.6u - 1.1t)
      dzx = 0.578cos(1.7u + 1.8t) * cos(1.4v + 1.3t) + 0.312cos(2.6u - 1.1t)
      dzy = -0.476sin(1.7u + 1.8t) * sin(1.4v + 1.3t)
      inv = 1e-3 / sqrt(dzx^2 + dzy^2 + 1)
      m.points[k] = Point3f(u, v, z)
      m.d_normal_points[k] = Point3f(u - dzx * inv, v - dzy * inv, z + inv)
    end
    nothing
  end)
  sun = Sphere(; radius = 0.9)
  set_color!(sun; color = "#FFB84D")
  move_to!(sun, Point3f(1.5, 5.5, 1.6))

  # la cámara del mar: inclinada, y meciéndose un poco
  cam_sea = CameraFrame()
  reorient!(cam_sea, 0.0, 62.0)
  set_frame_height!(cam_sea, 6.0)
  move_to!(cam_sea, Point3f(0, 0.6, 0))
  add_updater!(cam_sea, (f, dt) -> begin
    reorient!(f, 6.0 * sin(0.22 * scene.t), 62.0)
    nothing
  end)

  # ── las letras: la RELLENA recorta y no se dibuja; el aro sí ─────────
  word_mask = TextMobject("JANIM"; font = "DejaVu Sans", size = 2.3)
  get_width(word_mask) > FRAME_WIDTH - 1.6 && set_width!(word_mask, FRAME_WIDTH - 1.6)
  set_fill!(word_mask; color = WHITE, opacity = 1.0)
  set_stroke!(word_mask; opacity = 0)
  move_to!(word_mask, 0.25 * UP)
  word_rim = copy(word_mask)
  set_fill!(word_rim; opacity = 0)
  set_stroke!(word_rim; color = "#9ADCFF", width = 2.5, opacity = 1.0)

  caption = TextMobject(
    "the world seen THROUGH the letters: a lit 3D render, cut out by a TextMobject";
    size = 0.3,
    color = GREY_C,
  )
  to_edge!(caption, DOWN; buff = 0.35)

  use_composition!(
    scene,
    Composition(
      crop(sea, sun; inside = word_mask, feather = 0.015, camera = cam_sea),
      Layer(
        word_rim;
        blend = :add,
        effects = [Bloom(threshold = 0.25, intensity = 1.1, sigma = 0.055)],
      ),
      Layer(caption);
      background = (0.01f0, 0.012f0, 0.03f0, 1f0),
    ),
  )
  set_opacity!(caption, 0.0)
  wait!(scene, 1.0)
  set_opacity!(caption, 1.0)
  play!(scene, FadeIn(caption; shift = 0.2 * UP); run_time = 1.0)
  wait!(scene, 2.5)
  play!(scene, FadeOut(caption); run_time = 0.6)

  # el vuelo: la máscara crece 90× alrededor de la «I» — el ojo entra por
  # la letra y el mar lo llena todo
  anchor = get_center(word_mask["I"])
  blowup!(m, k) = scale!(m, k; about_point = anchor)
  dim!(m) = set_stroke!(m; opacity = 0.0)
  # el aro se agranda Y se apaga en el MISMO animate: dos animaciones sobre un
  # mobject se pisan (cada una escribe el estado entero), una sola no
  play!(
    scene,
    AnimationGroup(
      animate(word_mask, (blowup!, 90.0); rate_func = ease_in_cubic),
      animate(word_rim, (blowup!, 90.0), dim!; rate_func = ease_in_cubic),
    );
    run_time = 5,
  )
  wait!(scene, 4)
end

if abspath(PROGRAM_FILE) == @__FILE__
  Scene(
    construct;
    output = joinpath(@__DIR__, "07_text_mask.mp4"),
    fps = 30,
    resolution = (1280, 720),
  )
end
