# Galería — cinco escenas clásicas de Manim, portadas, y la galería de efectos

Son los ejemplos mínimos canónicos de la API: cada archivo enseña un mecanismo
y nada más. Cada escena declara `KEY_FRAMES` y `RESOLUTION`, y al ejecutarla
suelta escribe un PNG por fotograma clave, para poder MIRAR lo que hace.

| Escena | Original en Manim | Qué enseña |
|---|---|---|
| `01_square_to_circle.jl` | SquareToCircle (guía de inicio) | play!/Transform/FadeOut, estilo fill+stroke |
| `02_warp_square.jl` | WarpSquare (example_scenes) | apply_points_function! como objetivo de Transform |
| `03_updaters.jl` | UpdatersExample (docs CE) | updaters temporales y de seguimiento; add! + wait! |
| `04_tex_transform.jl` | TexTransformExample | Tex + morf glifo a glifo |
| `05_lagged_start.jl` | LaggedStartExample | LaggedStart/cascadas con lag_ratio |
| `06_effects.jl` | — | los once efectos de capa, uno por acto de 0,6 s sobre la misma placa |

Cada archivo se ejecuta suelto desde la raíz del repositorio:

    julia --project=. examples/gallery/01_square_to_circle.jl

o con la CLI, como cualquier escena:

    bin/janim render examples/gallery/01_square_to_circle.jl -ql
