# Reference · Renderer and interactivity

The WebGPU backend — the GPU, the render VM and its passes, the mp4
pipeline, the preview's window — plus the camera, the compositor and its
effects (types that live in the core, passes that live in the backend), the
strict-determinism switch, the live window, its input state and the daemon.

The narrative versions are [Rendering and output](rendering.md), [The
compositor](compositor.md), [3D and the camera](three_d.md) and [The
interactive session](interactive.md).

```@index
Pages = ["api_backend.md"]
```

## The GPU, the render VM and the frame

```@autodocs
Modules = [Janim]
Pages = ["backend/wgpu/context.jl", "backend/wgpu/targets.jl",
         "backend/wgpu/triangle.jl", "backend/wgpu/pipeline.jl",
         "backend/wgpu/uniforms.jl", "backend/wgpu/pipelines.jl",
         "backend/wgpu/records.jl", "backend/wgpu/render.jl",
         "backend/expanded.jl"]
Public = true
Private = false
```

## The camera

```@autodocs
Modules = [Janim]
Pages = ["core/camera.jl"]
Public = true
Private = false
```

## The compositor

```@autodocs
Modules = [Janim]
Pages = ["core/compositor_types.jl", "backend/wgpu/compositor.jl"]
Public = true
Private = false
```

## Effects

```@autodocs
Modules = [Janim]
Pages = ["core/effects_types.jl"]
Public = true
Private = false
```

## The window and the presentation

```@autodocs
Modules = [Janim]
Pages = ["backend/glfw.jl", "backend/window.jl", "backend/wgpu/window.jl"]
Public = true
Private = false
```

## Determinism

```@autodocs
Modules = [Janim]
Pages = ["backend/determinism.jl"]
Public = true
Private = false
```

## Interactivity

```@autodocs
Modules = [Janim]
Pages = ["interactive/controls.jl", "interactive/daemon.jl",
         "interactive/live.jl"]
Public = true
Private = false
```
