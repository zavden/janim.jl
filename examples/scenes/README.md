# Janim examples — the potential in four scenes

Each file defines `construct(scene)` and renders to 720p into `output/`:

    julia --project=. examples/scenes/NN_name.jl

| # | scene | what it shows | dur. |
|---|---|---|---|
| 01 | `01_sets.jl` | set theory with MASKS (`crop`: A∩B, A∖B, B∖A, A∪B lit by real cut-outs), morphing Tex titles | ~19 s |
| 02 | `02_quadratic.jl` | deriving the quadratic formula in 5 steps: ONE formula morphing glyph by glyph, a step counter and footnotes | ~22 s |
| 03 | `03_field_and_chaos.jl` | the whole 2D stack: Tsit5 streamlines, a DiffEq double pendulum in an updater, a trail with Bloom on an `:add` layer, a spotlight = an ANIMATED mask following the pendulum, background DOF, an animated transition blur, and the finale: gradient descent (ForwardDiff) down to a star | ~62 s |
| 04 | `04_space.jl` | the whole 3D stack: a sea of waves (an animated surface with analytic normals), a lit sphere and torus, depth-tested rings, a quaternion camera orbiting with choreographed φ and zoom, a morphing `fix_in_frame` HUD | ~60 s |

## The design examples (05–07)

Where 01–04 show what the engine can do, these three show **why it is built
the way it is**. Each one is an honest A/B: the same content, twice, with one
design decision as the only difference.

| # | scene | the decision it shows |
|---|---|---|
| 05 | `05_design_layers.jl` | **Per-layer effects.** Manim draws everything into the final framebuffer in z order, so there is nowhere to apply a blend mode or a blur "to this group only". The left half is drawn flat; the right half is the SAME three shapes through the compositor, with the background blurred and the middle one in `:multiply`. |
| 06 | `06_design_map.jl` | **The coordinate map is derived, not stored.** Two identical planes get the same scale, shift and rotation. The yellow dot asks `c2p(1,1)` every frame and stays on the gridlines' crossing; the red one was computed ONCE beforehand — which is exactly what a cached map does — and drifts. |
| 07 | `07_design_contract.jl` | **The interpolation contract.** A thermometer type defined in USER CODE, given the four contract lines, animated by the ordinary `animate` alongside a plain circle in the same `AnimationGroup`. Not a line of `animation/` knows it exists. It also documents the two mistakes that are easy to make: a `copy` that forgets the position, and a `get_family` that forgets to include itself. |

The two long ones (03, 04) are rendered with `render_parallel` (4 processes).

A scene-writing lesson: a mobject whose points are
CREATED by an updater (trails, optimised curves) must be born with its FINAL
style — `set_points…` rebuilds the style from the mobject's defaults, so
"appearing" by raising only the alpha rows has no effect on it; and the
updater has to be frozen BEFORE a FadeOut or it re-stamps the style every
frame.

The scenes' own prose (titles, labels, notes) stays in Spanish on purpose:
it is the content being taught, not code.

## 09 · La estela suave

`09_pendulum_trail.jl` — un doble péndulo y su estela dibujada DOS VECES a
partir de las mismas muestras: poligonal a la izquierda, `make_smooth!` a la
derecha. Muestrea a 20 fps a propósito: con muestreo fino la poligonal ya
engaña al ojo, y lo que se quiere ver es qué pasa cuando el objeto se mueve
rápido entre frame y frame.

## 10 · El atractor de Lorenz

`10_lorenz_glow.jl` — un millón de partículas (`GlowDots`, 100³) cuyo
updater muta los puntos IN PLACE, sobre una capa `:add` con un Bloom
suave. El color es la condición inicial (la franja z de origen, mapa
3b1b): ver las bandas mezclarse ES ver la
sensibilidad a condiciones iniciales. La receta glow-vs-Bloom está medida:
en nubes volumétricas el glow por fragmento gana en coste y en lectura.

## 11 · Cuatro cámaras, un mundo

`11_multicam_views.jl` — el panel de un editor 3D con la primitiva del compositor:
cuatro capas que comparten el MISMO vector de mobjects, cada una con su
`CameraFrame` (`camera =`) y su rectángulo en pantalla (`window =`). Cada
vista es un render de verdad con su z-buffer propio — el satélite que
enhebra el toro se esconde tras el tubo en unas vistas mientras sigue
visible en otras — y los updaters corren UNA vez por frame aunque el mundo
esté en cuatro capas (la lista viva se deduplica por identidad).

## 12 · Persecución y minimapa

`12_chase_camera.jl` — un cometa recorre un nudo trébol con tres vistas a la
vez: la principal orbitando por `animate`, una cámara de PERSECUCIÓN cuyo
updater la pega al cometa (`add_updater!(cam, f -> move_to!(f, …))` — lo que
en CE pide un `ZoomedScene`), y un minimapa cenital en ventana CUADRADA que
enseña el recorte central. El HUD entero va con `fix_in_frame!` y no derrapa
mientras la principal vuela; la estela es UNA `TracedPath` compartida por
las tres capas y registra un punto por frame, no tres.
