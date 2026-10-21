# Demo 05 · RACK FOCUS — profundidad de campo POR CAPA, enfocada a mano.
#
# Cinco tarjetas a cinco profundidades, cada una en su capa con un `Dof`. El
# desenfoque de cada capa se recalcula CADA FRAME a partir de su distancia al
# plano focal de la cámara:
#
#     σ = min(aperture · |d − focus|, max_sigma)
#
# y `focus` es un campo de un struct mutable: enfocar es escribir un número.
# Eso es exactamente lo que hace un foquista, y es lo que Manim no puede
# hacer porque no tiene capas: todo va a un único framebuffer, y un blur que
# solo afecte a "lo que está lejos" no tiene dónde aplicarse.
#
# De propina, la cámara se mece un poco de lado: como las tarjetas están a
# distintas z y la cámara es de perspectiva, el PARALAJE sale solo.
#
#   julia --project=. examples/demo/05_rack_focus.jl

using Janim

"Una tarjeta: un panel redondeado con una fórmula, colocado en `pos` (con z)."
function card(formula, color, pos)
  panel = RoundedRectangle(
    width = 3.7,
    height = 1.55,
    corner_radius = 0.25,
  )
  set_fill!(panel; color = "#121A29", opacity = 0.94)
  set_stroke!(panel; color, width = 3.0)
  tex = Tex(formula; color, size = 0.95)
  get_width(tex) > 3.2 && set_width!(tex, 3.2)
  g = VGroup(panel, tex)
  move_to!(g, pos)
  g
end

const DEPTHS = [1.6, 0.8, 0.0, -0.8, -1.6]

function construct(scene)
  cards = [
    card(raw"e^{i\Pi} + 1 = 0", "#FFD25E", Point3f(-3.6, -1.9, DEPTHS[1])),
    card(raw"i\hbar \, \partial_t \psi = H \psi", "#58C4DD", Point3f(-1.8, -1.0, DEPTHS[2])),
    card(raw"\nabla \cdot E = \rho / \varepsilon_0", "#7FDD58", Point3f(0.0, -0.1, DEPTHS[3])),
    card(raw"G_{\mu\nu} = 8 \pi G \, T_{\mu\nu}", "#F0A045", Point3f(1.8, 0.8, DEPTHS[4])),
    card(raw"\Delta S \geq 0", "#FF3D8B", Point3f(3.6, 1.7, DEPTHS[5])),
  ]
  # σ en unidades de escena: 0.23 son ~21 px a 720p, el radio más grande que
  # el kernel del compositor calcula entero (pedir más solo avisa y recorta)
  dofs = [Dof(; aperture = 0.22, max_sigma = 0.23) for _ in cards]

  title = TextMobject(
    "depth of field per layer: focusing is animating a number";
    size = 0.4,
    color = GREY_A,
  )
  to_edge!(title, UP; buff = 0.3)
  fix_in_frame!(title)

  # las capas van de la más lejana a la más cercana: la cercana tapa
  layers = [
    Layer(c; effects = [d])
    for (c, d) in zip(reverse(cards), reverse(dofs))
  ]
  use_composition!(
    scene,
    Composition(
      layers...,
      Layer(title);
      background = (0.02f0, 0.03f0, 0.05f0, 1f0),
    ),
  )

  # el plano focal a la profundidad z: la cámara mira por -z desde `focal`
  focal = get_focal_distance(scene.camera)
  set_focus(z) = begin
    for d in dofs
      d.focus = focal - z
    end
    nothing
  end
  set_focus(DEPTHS[1])

  # la cámara se mece: paralaje entre profundidades, gratis
  pilot = VGroup()
  add_updater!(pilot, (m, dt) -> begin
    move_to!(scene.frame, Point3f(0.35 * sin(0.4 * scene.t), 0, 0))
    nothing
  end)
  add!(scene, pilot)

  wait!(scene, 1.0)
  # de la más cercana a la más lejana, parando en cada una
  for k in 1:4
    z0, z1 = DEPTHS[k], DEPTHS[k + 1]
    play!(
      scene,
      UpdateFromAlphaFunc(cards[k], (m, a) -> set_focus(z0 + a * (z1 - z0)));
      run_time = 1.2,
    )
    wait!(scene, 0.8)
  end
  # y la vuelta de un tirón
  play!(
    scene,
    UpdateFromAlphaFunc(cards[1], (m, a) -> set_focus(DEPTHS[5] + a * (DEPTHS[1] - DEPTHS[5])));
    run_time = 2.4,
  )
  wait!(scene, 1.2)
end

if abspath(PROGRAM_FILE) == @__FILE__
  Scene(
    construct;
    output = joinpath(@__DIR__, "05_rack_focus.mp4"),
    fps = 30,
    resolution = (1280, 720),
  )
end
