# Reference · Mobjects

What a mobject IS: the tree, the shape zoo, paths and the bounding box. Moving
and placing them is [the layout reference](api_layout.md); the things built ON
TOP of them — annotations, grids, surfaces, imported assets, particles and
fields — are in [the content reference](api_content.md).

The narrative versions are [Mobjects](mobjects.md) and [The shape
zoo](shapes.md).

```@index
Pages = ["api_mobjects.md"]
```

## The mobject and its tree

```@autodocs
Modules = [Janim]
Pages = ["core/mobject.jl", "core/interpolable.jl"]
Public = true
Private = false
```

## Shapes

```@autodocs
Modules = [Janim]
Pages = ["core/shapes.jl"]
Public = true
Private = false
```

## Paths

```@autodocs
Modules = [Janim]
Pages = ["core/paths.jl"]
Public = true
Private = false
```

## The bounding box

```@autodocs
Modules = [Janim]
Pages = ["core/bbox.jl"]
Public = true
Private = false
```

