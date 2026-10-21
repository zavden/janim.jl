# Reference · Scene and output

The game loop, the two sinks, checkpoints, the headless probes, the segment
renderer and the process farm, plus the video and codec layer.

The narrative versions are [Scenes](scenes.md) and [Rendering and
output](rendering.md).

```@index
Pages = ["api_scene.md"]
```

## The scene

```@autodocs
Modules = [Janim]
Pages = ["scene/scene.jl"]
Public = true
Private = false
```

## The scene macros

```@autodocs
Modules = [Janim]
Pages = ["scene/macros.jl"]
Public = true
Private = false
```

## Checkpoints

```@autodocs
Modules = [Janim]
Pages = ["scene/checkpoints.jl"]
Public = true
Private = false
```

## Progress

```@autodocs
Modules = [Janim]
Pages = ["scene/progress.jl"]
Public = true
Private = false
```

## Video and codecs

```@autodocs
Modules = [Janim]
Pages = ["video.jl", "codecs.jl", "backend/video_impl.jl"]
Public = true
Private = false
```
