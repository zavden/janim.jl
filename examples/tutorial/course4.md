# Curso 4 — La referencia

Los cursos 1 a 3 enseñan a usar el motor. Este es distinto: cada lección es
un recorrido exhaustivo por una familia de nombres exportados de Janim, en un
archivo que se ejecuta y se mira.

Por ahora el curso trae un capítulo, el zoo de formas:

```bash
julia --project=. examples/tutorial/c4_01_shape_zoo/01_every_flat_shape.jl
julia --project=. examples/tutorial/c4_01_shape_zoo/02_groups_and_the_base.jl
```

Se ejecuta como cualquier otra lección del tutorial (ver el `README.md` de
esta carpeta).

## El capítulo

| capítulo | lección | qué cubre |
|---|---|---|
| `c4_01_shape_zoo` | `01_every_flat_shape.jl` | los constructores planos de 2D, todos en un fotograma, cada uno con su nombre |
| `c4_01_shape_zoo` | `02_groups_and_the_base.jl` | `VMobject`/`VGroup`/`Group`, la API de caminos (`start_new_path!`, `add_line_to!`, `add_arc_to!`, `add_subpath!`, `set_points_*`, `make_smooth!`/`make_jagged!`), y `VMobject(:Tag; …)`, el constructor en bruto sobre el que se escribe el zoo (`vmob` es su alias): la costura de extensión |

## Por qué sirve una referencia exhaustiva

Los otros tres cursos escogen. Eso deja huecos que nadie ve hasta que alguien
los busca, y al buscarlos salen cosas que conviene tener a la vista:

- **`Group` se transforma y se anima** como en Manim CE y ManimGL: recorre los
  miembros que saben moverse y deja en paz a los que no.
- **Una `Arrow` se pinta con `fill_color`, no con `color`** — se dibuja por su
  relleno. ManimGL hace lo mismo.
- **Un `Dot` igual**: `Dot(p; color = …)` sale blanco; va `fill_color`.
