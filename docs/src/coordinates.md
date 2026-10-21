# Coordinate systems

An axis system is a mobject like any other — it can be moved, scaled, faded and
animated — plus a MAP between data coordinates and scene coordinates.

```julia
ax = Axes((-3.0, 3.0, 1.0), (-2.0, 2.0, 1.0); width = 8, height = 5,
          include_numbers = true)
add!(scene, ax)
```

Each range is `(min, max, step)`.

## The map

Everything hangs off one function, so there is one definition and one place for
it to be wrong:

```julia
c2p(ax, 1.5, 0.7)          # data → scene point   (coords_to_point)
p2c(ax, point)             # scene point → data   (point_to_coords)
get_origin(ax)             # where (0, 0) lands
get_unit_size(axis)        # scene units per data unit
```

`get_origin` is NOT the centre of the frame, and not the centre of the axes
either unless the ranges happen to be symmetric: `Axes((0, 10, 1), (0, 5, 1))`
has its origin in the bottom-left corner of the grid.

**Anything you place on a plot goes through `c2p`.** That is what keeps a
label, a dot and a graph agreeing with each other when the axes move.

## Plotting

```julia
graph = plot(ax, x -> x^2; color = BLUE, stroke_width = 3)
add!(scene, graph)

plot(ax, sin; x_range = (-PI, PI), n = 200)
```

`n` is the number of sample points. The result is an ordinary VMobject, so
[`ShowCreation`](@ref) draws it, [`Transform`](@ref) morphs it into another
graph and `get_color` reads its colour.

Around a graph:

```julia
get_area(ax, graph, 0.0, 1.5; color = BLUE, opacity = 0.35)
get_graph_label(ax, graph, Tex(raw"f(x)"); x = 1.2, direction = UR)
get_v_line(ax, point)
get_h_line(ax, point)
```

## Tracing a graph

The idiom, and the reason [`ValueTracker`](@ref) exists:

```julia
vt = ValueTracker(-3.0)
add!(scene, vt)

dot = Dot(; color = YELLOW)
add_updater!(dot, m -> move_to!(m, c2p(ax, get_value(vt), f(get_value(vt)))))

play!(scene, animate(vt, (set_value!, 3.0)); run_time = 4, rate_func = linear)
```

One animated number; the dot, a label, a vertical line and a readout can all
follow it. See [Updaters and trackers](updaters.md).

## The other systems

```julia
NumberLine((-8.0, 8.0, 1.0); width = 10, include_numbers = true)
NumberPlane((-8.0, 8.0, 1.0), (-4.0, 4.0, 1.0))
ComplexPlane((-3.0, 3.0, 1.0), (-2.0, 2.0, 1.0))
PolarPlane(; r_max = 4.0, n_radii = 8, n_circles = 4)
ThreeDAxes((-3.0, 3.0, 1.0), (-3.0, 3.0, 1.0), (-2.0, 2.0, 1.0))
```

A [`NumberLine`](@ref) on its own is the right tool for a one-dimensional
argument — a parameter sweep, a proof about the reals — and it answers
[`number_to_point`](@ref) and [`point_to_number`](@ref).

[`PolarPlane`](@ref) adds [`polar_to_point`](@ref).
[`ThreeDAxes`](@ref) takes a third range and works with the 3D camera; see
[3D and the camera](three_d.md).

## Getting at the parts

```julia
get_x_axis(ax)             # a NumberLine, to restyle or label
get_y_axis(ax)
get_tick_range(axis)       # the data values the ticks fall on
```

Both axes are ordinary mobjects, so anything in [Layout](layout.md) applies to
them individually.

## Reference

[`Axes`](@ref) · [`NumberLine`](@ref) · [`NumberPlane`](@ref) ·
[`c2p`](@ref) · [`p2c`](@ref) · [`plot`](@ref) · [`get_area`](@ref) ·
[`get_graph_label`](@ref) · [`get_origin`](@ref) — in
[the coordinate reference](api_coordinates.md).
