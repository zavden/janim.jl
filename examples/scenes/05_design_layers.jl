# Example 05 · DESIGN: per-layer effects, which Manim cannot do.
#
#   julia --project=. examples/scenes/05_design_layers.jl
#
# Manim draws EVERYTHING into the final framebuffer in z order. There are no
# intermediate textures, so there is nowhere to apply a blend mode or an
# effect "to this group and not that one". It is not a missing feature — it
# follows from the architecture.
#
# Janim's single compositing primitive is the layer: one texture plus its
# compositing parameters. The right half of this scene is the consequence.
#
# The two halves draw the SAME three shapes. The only difference is whether
# they go through layers.

using Janim

const RESOLUTION = (1280, 720)

# the same three shapes, built twice so each half owns its own copies
build_shapes() = begin
    fondo = Circle(radius = 1.6, fill_opacity = 1.0)
    set_fill!(fondo; color = "#2C5F8A")
    set_stroke!(fondo; opacity = 0)

    medio = Square(side_length = 2.2, fill_opacity = 1.0)
    rotate!(medio, TAU / 16)
    set_fill!(medio; color = "#F0A045")
    set_stroke!(medio; opacity = 0)

    frente = Triangle(radius = 1.1, fill_opacity = 1.0)
    set_fill!(frente; color = "#7FDD58")
    set_stroke!(frente; opacity = 0)
    (fondo, medio, frente)
end

function construct(scene)
    title = TextMobject("Efectos POR CAPA: lo que el diseño de Manim impide";
                        size = 0.5, color = GREY_A)
    to_edge!(title, UP; buff = 0.3)

    izq = TextMobject("un solo framebuffer, orden z"; size = 0.3, color = GREY_B)
    der = TextMobject("una capa por grupo, con efectos"; size = 0.3, color = GREY_B)

    # ── izquierda: plano, como dibuja Manim ────────────────────────────
    a1, b1, c1 = build_shapes()
    plano = VGroup(a1, b1, c1)
    shift!(plano, 3.4 * LEFT + 0.3 * DOWN)

    # ── derecha: las MISMAS formas, atravesando el compositor ──────────
    a2, b2, c2 = build_shapes()
    for m in (a2, b2, c2)
        shift!(m, 3.4 * RIGHT + 0.3 * DOWN)
    end

    # el desenfoque es de la capa de FONDO, no de la escena: el triángulo de
    # delante sigue nítido aunque se solape con él
    desenfoque = Blur(0.09)
    for (lab, x) in ((izq, -3.4), (der, 3.4))
        move_to!(lab, Point3f(x, -2.7, 0))
    end

    # NOTE: once a composition is mounted, the scene renders IT and not
    # `scene.mobjects` — so the flat half and the captions have to be layers
    # too. That is the honest shape of the design: everything on screen is a
    # layer, there is no privileged "just draw this" path.
    comp = Composition(
        Layer(a2; effects = [desenfoque]),
        Layer(b2; blend = :multiply),          # se funde con lo de debajo
        Layer(c2),
        Layer(plano, title, izq, der);         # la mitad plana y los rótulos
        background = (0.04f0, 0.04f0, 0.05f0, 1f0))
    use_composition!(scene, comp)

    # el fondo se va desenfocando: la separación entre las dos mitades crece
    # ante los ojos, y nada del lado izquierdo cambia
    add_updater!(a2, (m, dt) -> (desenfoque.sigma = min(desenfoque.sigma + 0.06dt, 0.16);
                                 nothing))
    wait!(scene, 2.0)
end

if abspath(PROGRAM_FILE) == @__FILE__
    path = joinpath(@__DIR__, "output", "05_design_layers.mp4")
    mkpath(dirname(path))
    Scene(construct; output = path, fps = 30, resolution = RESOLUTION)
    println("written ", path)
end
