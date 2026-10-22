# Janim.jl

**English** · [Español](README.es.md)

Janim is a Julia package for mathematical animation that speaks Manim's
narrated vocabulary — `Circle`, `Transform`, `play!`, `next_to!`,
`TextMobject`, `Tex` — on top of an engine of its own:

- **Deterministic rendering.** The same code gives the same frames on every
  run: the clock is fixed and nothing reads the wall clock. That is what
  makes previews, frame caches and parallel segment renders exact.
- **WebGPU.** Rendering goes through wgpu-native, on Vulkan (Linux: the GPU or
  the CPU with lavapipe), Metal (macOS) or DX12 (Windows: the GPU or the CPU
  with WARP), with no window and no display needed.
- **A layer compositor** that Manim lacks: blend modes, real masks with
  feather, blur, bloom, depth of field, editor effects, and a camera per
  layer (magnifiers, picture-in-picture, several 3D views of one world).
- **Text and formulas without LaTeX**: `Tex("x^2")` typesets in a fraction of
  a millisecond with MathTeXEngine; `via = :latex` and `via = :typst` are
  there for the cases it does not cover.
- **3D** with a quaternion camera, surfaces with analytic normals and depth
  testing.
- **Julia inside the scene**: SciML integrators in updaters, animation by
  gradient (ForwardDiff), a process farm for long renders.
- **For the terminal and for agents**: a pure-bash CLI on top of a warm TCP
  daemon (a frame in milliseconds), headless `render_frame`/`describe`, and
  `llms.txt`.
- **A live window** with Revise: edit the file and see the change, pause,
  step, scrub.

## Requirements

- **Linux** with a Vulkan driver (Mesa RADV, lavapipe or another), **macOS on
  Apple Silicon**, where Janim draws with Metal (tested on macOS 26.6, Apple
  M1), or **Windows 11**, where it draws with DX12 (tested on Windows 11
  25H2, AMD Radeon RX 9070 XT) and the command line runs from Git Bash (the
  port's notes are in [`WINDOWS.md`](WINDOWS.md)).
- **Julia 1.11 or newer** (developed on 1.12).
- The fonts your scenes ask for. The examples use DejaVu Sans.
- Optional: **`latex` and `dvisvgm`** on the `PATH`, only for
  `Tex(…; via = :latex)`.

`ffmpeg`, Typst, FreeType and the WebGPU library come with the Julia
dependencies.

## Install

```bash
git clone https://github.com/<user>/Janim.jl.git
cd Janim.jl
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

`Pkg.instantiate()` installs the exact versions recorded in `Manifest.toml`,
binaries included. Janim is not in the General registry yet; to use it from
another environment, `] dev path/to/Janim.jl`. Before that, each platform
needs its own packages.

### Linux

Julia from [juliaup](https://github.com/JuliaLang/juliaup)
(`curl -fsSL https://install.julialang.org | sh`) or from the distribution;
Mesa's Vulkan drivers and the DejaVu fonts; and, for `via = :latex`, LaTeX
with the `standalone` class and `dvisvgm`:

```bash
# Fedora
sudo dnf install mesa-vulkan-drivers dejavu-sans-fonts \
  texlive-latex texlive-standalone texlive-preview texlive-amsmath texlive-amsfonts texlive-xcolor texlive-dvisvgm
# Debian, Ubuntu
sudo apt install mesa-vulkan-drivers fonts-dejavu texlive-latex-extra dvisvgm
```

### macOS

```bash
curl -fsSL https://install.julialang.org | sh      # juliaup
brew install --cask font-dejavu                     # the examples' font, into ~/Library/Fonts
```

`via = :latex` needs MacTeX or BasicTeX plus `dvisvgm`
(`sudo tlmgr install dvisvgm` if it is missing); both live in
`/Library/TeX/texbin`, which must be on the `PATH`.

### Windows

In PowerShell. Julia comes from juliaup through winget; Git for Windows brings
Git Bash, which `bin/janim` runs from; MiKTeX, which brings `dvisvgm`, is
optional.

```powershell
winget install -e --id Julialang.Juliaup
winget install -e --id Git.Git
winget install -e --id MiKTeX.MiKTeX      # optional: Tex(…; via = :latex)
```

Open a new terminal so the `PATH` is fresh, then `juliaup add 1.12` and
`juliaup default 1.12` (the `Manifest.toml` was made with 1.12), and run
`Pkg.instantiate()` as above. One more step after it: the WebGPU library
comes in an artifact whose Windows tarball lacks the executable bit, which
Julia's `Tar` turns into a file Windows refuses to load (`could not load
library … Access is denied`). Grant it once per depot:

```powershell
Get-ChildItem "$env:USERPROFILE\.julia\artifacts" -Recurse -Filter wgpu_native.dll |
  ForEach-Object { icacls $_.FullName /grant "*S-1-1-0:(RX)" }
```

Fonts: download [DejaVu](https://github.com/dejavu-fonts/dejavu-fonts/releases),
select the `.ttf` files, right-click, *Install*. They land in
`%LOCALAPPDATA%\Microsoft\Windows\Fonts`, where Janim finds them. If you
installed MiKTeX, open MiKTeX Console and set the on-the-fly package
installation to *Always* (or run
`initexmf --set-config-value=[MPM]AutoInstall=1`).

The command line is the same `bin/janim` as on Linux and macOS, run from
**Git Bash** (the terminal Git for Windows installs). From the clone,
`bin/janim daemon start`, then `bin/janim render scene.jl -qm`,
`bin/janim scene.jl` for the live window, `bin/janim check` and the rest as
below; paths may hold spaces and be written `C:\…`, `C:/…` or `/c/…`. From
PowerShell, without the daemon, `julia --project=. scene.jl` renders and
`julia --project=. -e 'using Janim; live(\"scene.jl\")'` opens the live
window (PowerShell wants the inner quotes escaped like that).

## A minimal scene

```julia
using Janim

function construct(scene)
    c = Circle(radius = 1.0)
    set_fill!(c; color = YELLOW, opacity = 1.0)
    play!(scene, FadeIn(c; shift = 0.5 * UP); run_time = 0.8)
    play!(scene, Transform(c, Square()); run_time = 1.2)
    wait!(scene, 0.5)
end

if abspath(PROGRAM_FILE) == @__FILE__
    Scene(construct; output = "hello.mp4", fps = 30, resolution = (1280, 720))
end
```

Save it as `hello.jl` and render it with plain Julia:

```bash
julia --project=. hello.jl
```

`construct(scene)` is a contract, not a convention: the daemon, the render
farm and the live window all look that name up in your file.

## The command line

`bin/janim` never starts Julia itself: it talks to a daemon that stays warm,
so a frame costs milliseconds instead of a Julia start-up.

```bash
bin/janim daemon start                    # once per session
bin/janim render hello.jl -ql             # the video, next to the scene
bin/janim hello.jl                        # the live window; Esc or q to quit
bin/janim frame hello.jl 20 f.png -ql     # a single frame
bin/janim render hello.jl -s              # the last frame as a png
bin/janim daemon stop
```

A file may hold several scene functions: name the one you mean after `:`
(`bin/janim render scenes.jl:intro -ql`). `bin/janim --help` shows the rest
of the command line.

The quality flag sets resolution and frame rate together:

| flag | resolution | fps |
|---|---|---|
| `-qs` | 640×360 | 10 |
| `-ql` | 854×480 | 15 |
| `-qm` | 1280×720 | 30 (default) |
| `-qh` | 1920×1080 | 60 |
| `-qq` | 2560×1440 | 60 |
| `-qk` | 3840×2160 | 60 |

Rendering runs on the GPU by default. Set `JANIM_HEADLESS=1` (for the daemon,
or for a `julia` run) to render on the CPU: lavapipe on Linux, WARP on Windows
(macOS has no CPU adapter).

## Examples

| folder | contents |
|---|---|
| [`examples/tutorial/`](examples/tutorial/README.md) | the course: foundations, going deeper, what only Janim does, and the reference |
| [`examples/gallery/`](examples/gallery/README.md) | Manim classics and the effects gallery |
| [`examples/scenes/`](examples/scenes/README.md) | complete scenes: masks, formulas, 2D and 3D, the compositor |
| [`examples/demo/`](examples/demo/README.md) | demos of layers, cameras and effects |

```bash
bin/janim render examples/demo/03_portals.jl -ql
```

Each lesson explains itself in the comments at its top. The on-screen text
of many examples, and the comments of the demos, are in Spanish.

## Documentation

- [`docs/src/`](docs/src/index.md): the manual and the API reference. Build
  it with
  `julia --project=docs -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'`
  and then `julia --project=docs docs/make.jl`.
- [`llms.txt`](llms.txt): the whole API in one file.

## Known limitations

- **Windows is new.** Rendering, the command line with its daemon (from Git
  Bash) and the live window work with DX12, verified on one machine. Frames
  are reproducible within a route (RADV, lavapipe, Metal, DX12 or WARP), and
  routes can differ from each other by a pixel at some edges.
- **No motion blur in video.** `Scene` refuses `motion_blur > 1`, and so does
  the CLI's `--motion-blur`. What exists is `render_frame_motion`, which
  averages several exposures into a single still frame. The lessons in
  `examples/tutorial/c3_05_motion_blur/` and the demos `04_lorenz_glow.jl`,
  `10_motion_blur.jl` and `12_motion_blur.jl` still describe the in-video
  version; they will be revised.

## License

MIT, see [`LICENSE`](LICENSE). Janim follows ManimGL and Manim Community and
ports parts of them, and of the `isosurfaces` package, all MIT-licensed:
their notices are in [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
