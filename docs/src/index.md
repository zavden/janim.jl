# Janim.jl

A mathematical animation engine in Julia, with Manim's narrated API
(`Circle`, `Transform`, `play!`) and an engine of its own: a deterministic
WebGPU renderer (same code → same frames, byte for byte), a layer compositor with masks and
effects, mathematical text without LaTeX (milliseconds per formula), 3D with
a quaternion camera, SciML physics inside updaters, a process farm, and a TCP
daemon for agents.

## Your first scene

```julia
using Janim

function construct(scene)
    c = Circle(radius = 1.0)
    set_fill!(c; color = YELLOW, opacity = 1.0)
    play!(scene, FadeIn(c; shift = 0.5 * UP); run_time = 0.8)
    play!(scene, Transform(c, Square()); run_time = 1.2)
    wait!(scene, 0.5)
end

Scene(construct; output = "hello.mp4", fps = 30, resolution = (1280, 720))
```

The name `construct` is a contract: the daemon, the render farm and the live
window look it up in your script.

A single frame, no video: `render_frame(construct, 0.75; png = "f.png")`.
A live window with hot reload: `live("scene.jl")`.

## Reading order

If you are new, [Getting started](getting_started.md) and then
[Scenes](scenes.md) are enough to be productive; the rest can be read when you
need it.

If you are coming from Manim, start at [Coming from Manim](from_manim.md) —
it is the translation table plus the five places where a literal translation
is wrong.

### The manual

| | |
|---|---|
| [Getting started](getting_started.md) | install, render, look at the result |
| [Scenes](scenes.md) | `Scene`, the `construct` contract, the fixed clock, where the output goes |
| [Mobjects](mobjects.md) | the tree, style, the family, keys, copies |
| [The shape zoo](shapes.md) | every shape, and which of them are built out of the others |
| [Layout](layout.md) | placing things relatively instead of by coordinates |
| [Animations](animations.md) | the catalogue, the life cycle, composing them |
| [Rate functions](rate_functions.md) | how progress is spread over time |
| [Updaters and trackers](updaters.md) | per-frame behaviour, and the four traps it carries |
| [Text and formulas](text.md) | `Tex`, `TextMobject`, matrices and tables |
| [Coordinate systems](coordinates.md) | axes, plots, number planes |
| [3D and the camera](three_d.md) | surfaces, the quaternion camera, depth |
| [The compositor](compositor.md) | layers, blending, masks, effects |
| [Rendering and output](rendering.md) | resolution, determinism, the farm, alpha, the blurred still |
| [The CLI](cli.md) | `janim render`, `frame`, `preview`, `check` |
| [The interactive session](interactive.md) | the live window, the daemon, checkpoints |
| [Coming from Manim](from_manim.md) | the translation table and what has no equivalent |
| [Performance and memory](performance.md) | what costs what, measured |
| [Extending the engine](extending.md) | custom mobjects, animations and effects |

### The reference

Every exported name, generated from its docstring:
[mobjects](api_mobjects.md) · [transforms and layout](api_layout.md) ·
[annotations, assets and particles](api_content.md) ·
[the palette](api_palette.md) ·
[animation](api_animation.md) · [coordinates](api_coordinates.md) ·
[text](api_text.md) · [scene and output](api_scene.md) ·
[renderer and interactivity](api_backend.md).

### In the repository

- `examples/tutorial/` — 89 runnable lessons in four courses, each a `construct` with
  its explanation in the header comment. The best few-shot corpus there is.
- `examples/gallery/` — six minimal classics, one per mechanism, each a worked
  example.
- `examples/scenes/` — twelve complete scenes stacking the whole engine.
- `examples/demo/` — twelve short demos of what the compositor, the cameras and
  the particle clouds do.
- `llms.txt` — the same API summarised for an AI agent.

## The module

```@docs
Janim
```
