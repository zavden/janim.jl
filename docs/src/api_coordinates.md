# Reference · Coordinates and constants

Lines, arrows and dots; axes, planes and plots; the vector algebra underneath;
and the engine's constants — directions, angles, the frame and the palette.

The narrative version is [Coordinate systems](coordinates.md).

```@index
Pages = ["api_coordinates.md"]
```

## Lines, arrows and dots

```@autodocs
Modules = [Janim]
Pages = ["core/coordinates.jl"]
Public = true
Private = false
```

## Axes and planes

```@autodocs
Modules = [Janim]
Pages = ["core/axes.jl"]
Public = true
Private = false
```

## Vector algebra

```@autodocs
Modules = [Janim]
Pages = ["core/algebra.jl"]
Public = true
Private = false
```

## Constants

```@autodocs
Modules = [Janim]
Pages = ["core/constants.jl"]
Public = true
Private = false
```

## `Point3f`

Janim also re-exports `Point3f` from
[GeometryBasics](https://github.com/JuliaGeometry/GeometryBasics.jl), so it has
no entry of its own above — its documentation belongs to that package.

It is the engine's point type: three `Float32`s, which is already the layout
the GPU wants, so a mobject's points upload as a vertex buffer with no
conversion step anywhere. Every direction constant is one, every position is
one, and every function here that returns a position returns one.

Geometry is COMPUTED in `Float64` and STORED in `Float32` — the same split GL
forces on you — which is why [`TAU`](@ref) and the angles are `Float64` while
the points are not.

## Function graphs and implicit curves

```@autodocs
Modules = [Janim]
Pages = ["core/functions.jl", "core/implicit.jl"]
Public = true
Private = false
```
