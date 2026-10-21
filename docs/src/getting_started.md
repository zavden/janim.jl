# Getting started

## Install

Janim is not in the General registry yet, so it is installed from a checkout.

```bash
git clone <the repository>
cd Janim
julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'
```

`Pkg.instantiate()` restores the exact versions recorded in `Manifest.toml`.
Keep that file: deleting it swaps a reproducible restoration for a fresh
dependency resolution. If Julia reports `failed to find source of parent
package`, the manifest knows about a transitive dependency the local depot is
missing — run the command above from this directory. `Pkg.add` in the default
environment does not repair a checkout's environment.

To use it from another project:

```julia-repl
] dev path/to/Janim
```

Julia 1.11 or newer. `ffmpeg` arrives with the dependencies; LaTeX is optional
and only for `Tex(via = :latex)`.

### A screen is not required

`using Janim` never touches the window system — GLFW loads at the first
PREVIEW, not at import, and a render to a file opens no window at all. What
a render needs is a Vulkan driver (Metal on macOS, DX12 on Windows): on
Linux `mesa-vulkan-drivers` brings both the GPU's ICD and lavapipe, the CPU
adapter, so a machine with no display and no GPU renders in software,
byte-stable across processes and with no xvfb. `JANIM_HEADLESS=1` picks the
CPU adapter on a machine that does have a GPU. On a Wayland session the
preview's window is native Wayland (no Xwayland in the path);
`JULIA_GLFW_PLATFORM=x11` brings X11 back and `Janim.gl_platform()` tells
you which one is running. The platform is not part of the pixels: an X11
process and a Wayland process render the same frame, byte for byte.

## Your first scene

Put this in `scene.jl`:

```julia
using Janim

function construct(scene)
    c = Circle(; radius = 1.0)
    set_fill!(c; color = YELLOW, opacity = 1.0)

    play!(scene, FadeIn(c; shift = 0.5 * UP); run_time = 0.8)
    play!(scene, Transform(c, Square()); run_time = 1.2)
    wait!(scene, 0.5)
end
```

Then render it:

```bash
./bin/janim render scene.jl -ql -p
```

`-ql` is a quality preset (854×480 at 15 fps — see [the CLI](cli.md)) and `-p`
opens the result when it is done.

Two things about that file are worth noticing straight away.

**The function is called `construct` and takes one argument.** That is a
contract, not a convention: the CLI, the daemon, the render farm and the live
window all look that exact name up in your file. One scene per file — the file
is the unit of address, because there is no class to name.

**There is no `Scene(...)` line at the bottom.** There does not need to be:
`janim render` builds the scene for you with the flags you gave it. Adding one
is also fine, and then the file runs on its own with `julia --project=. scene.jl`
— but if you do, guard it, or the daemon will render your scene every time it
loads the file:

```julia
if abspath(PROGRAM_FILE) == @__FILE__
    Scene(construct; output = "scene.mp4", fps = 30, resolution = (1280, 720))
end
```

## Working faster

Rendering a whole video to check one detail is the slow way round. Three
shortcuts, in increasing order of usefulness:

```bash
janim daemon start                        # a warm process: ~17 ms per frame
janim frame scene.jl 42 out.png           # one frame, as a png
janim preview scene.jl                    # the live window, hot reload
```

The live window is the one to reach for. It watches the file with Revise, so
saving an edit shows up in about 80 ms without restarting anything, and you can
pause, step frame by frame and scrub backwards through the scene exactly as it
will be rendered. See [the interactive session](interactive.md).

**Before you start editing, run `janim check`**, and `janim finish` if it
complains. A daemon left over from a previous session is not idle noise — it
holds the port and it holds its heap. See
[the CLI](cli.md).

## Looking at the result

Nothing here is finished until you have looked at pixels. The render is
deterministic — the same code produces the same frames — so a frame you inspect
is exactly the frame that ends up in the video, and that is what makes the
following loop trustworthy:

```julia
using Janim
include("scene.jl")

animation_map(construct)                        # → (start frames, total)
render_frame(construct, 1.4; png = "check.png")
```

[`animation_map`](@ref) is how you choose a meaningful instant instead of
guessing one: it tells you which frame each `play!` begins at, offline and
without drawing anything.

For the tree as text rather than as pixels there is [`describe`](@ref), which
takes the SCENE — so you call it either from inside `construct`, at the moment
you care about, or on a scene you built yourself:

```julia
scene = Scene(; fps = 30, resolution = (854, 480))
construct(scene)
println(describe(scene))          # the state the scene ended in
close(scene)
```

It answers "is it there at all, and where?" without opening an image, and its
output is stable — the same state always prints the same text, so two of them
can be diffed.

## Where to go next

- [Scenes](scenes.md) for what `Scene` can be asked for.
- [The shape zoo](shapes.md) and [Layout](layout.md) to build something.
- [Animations](animations.md) to move it.
- `examples/tutorial/` in the repository: 89 runnable lessons in four courses,
  each with its explanation in the header comment.
