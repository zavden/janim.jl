# Rendering and output

## The three ways out

```julia
Scene(construct; output = "out.mp4", fps = 30, resolution = (1280, 720))
render_frame(construct, 1.4; png = "f.png")
render_parallel(construct, "out.mp4"; nprocs = 4, frames_total = 900)
```

From the shell, the same three are `janim render`, `janim frame` and
`janim render -j 4`. See [the CLI](cli.md).

## Determinism

**The same code produces the same frames, byte for byte.** That is the
property everything else is built on: scrubbing, frame caching, rendering
segments in parallel and concatenating them, previews that are exactly the
final film, and comparing SHA-256 hashes of decoded frames instead of eyeballs.

What it asks of you:

- No unseeded randomness in a scene, and no wall-clock time.
- Nothing from the driver. The WebGPU drivers compile at pipeline creation and
  have no shader-variant race, so high-frequency content — noise effects, fine
  textures — needs no driver knob: `strict_gl()` keeps its name with nothing
  behind it, and the property is MEASURED: six cold processes render one file,
  in RADV and in lavapipe.
- The mp4 CONTAINER is x264's. Multithreaded by default
  (`encoder_threads = nothing`), it comes out bit-stable on one machine (10 of
  10 renders of `examples/scenes/04_space.jl` at 1080p60 gave one mp4), but
  that is not a promise across thread counts or machines. When the file's
  bytes are what you need, `encoder_threads = 1` — at 4.3× the render at
  1080p60 (24 s → 104 s), which is why it is not the default.

The clock is fixed and never consults the wall: `run_time = 2` at 30 fps is 60
steps of `dt = 1/30`, always. See [Scenes](scenes.md).

Frame hashes are driver-specific and PER ROUTE: the native adapter (RADV, for
instance) and the CPU adapter (lavapipe) each give their own bytes, and on a
different GPU the native route's bytes differ BY DESIGN while the picture stays
the same. The WINDOW SYSTEM, on the other hand, is not part of the bytes: under
one driver an X11 process and a Wayland process render the same frame.

### The WebGPU backend

The renderer is WebGPU, and the only one: `backend()` reports `:wgpu`, and
`JANIM_BACKEND=gl` is an error (`wgpu` is the only backend). It talks to
wgpu-native (Vulkan on Linux, Metal on macOS, DX12 on Windows) with no window
at all, so the two routes are two ADAPTERS of the same instance:
`JANIM_HEADLESS=1` means «the CPU adapter» (lavapipe, which Mesa ships with its
Vulkan drivers — nothing to install), otherwise the discrete GPU is used, and
`JANIM_ADAPTER=<part of the device name>` overrides both. `gpu_info()` is the
driver identity, with a three-field header: `# driver: radv · vulkan · Mesa
26.1.8`, or `# driver: llvmpipe · vulkan · Mesa 26.1.8 (LLVM 22.1.8)`.

The backend draws the stroke (by instancing: each expanded Bézier triple is
one instance of a fixed-corner quad strip, with the step count per run
computed on the CPU), `DotCloud`, `Surface`, `ImageMobject`,
`TexturedSurface` and the fill. **The fill is stencil-then-cover**, what
ManimGL does: each VMobject's curves are COUNTED into the stencil aspect of the
frame's own attachment by the nonzero rule (IncrementWrap on a front face,
DecrementWrap on a back face — a hole is a count of zero, a shape seen from
behind counts −1 and fills), the curved edge's coverage written per sample
through `sample_mask`, and then COVERED once per sample where the count is not
zero, with the colour and the triangle's own z. There is no canvas, no cap, no
inverse — an opaque interior is the colour's own byte (`#58C4DD` lands on
`0x58C4DD`) — and a frame is ONE render pass whatever it holds: the count and
the cover of every filled member, the strokes, the meshes, the clouds and the
images in the frame's order, the arena's eight buffers bound once. The
antialiasing of the fill is the 4× resolve of that pass, so every frame
renders at four samples unless `samples = 1` is asked — surfaces get
`ThreeDScene`'s limb by default.

Where a stroke lies on a depth-tested face, the cover yields by one pixel of
its own depth slope (`depthBiasSlopeScale = 1`, the smallest push that shows
the wire of a tilted-face scene whole; a constant bias moves nothing, a line
0.05 units behind stays hidden), so the stroke wins the tie whatever order
`add!` gave — its INK does: a line thinner than a pixel is all antialiasing
apron, writes no depth, and an opaque face drawn after it paints over it; the
scene gives the order (draw the wire last by `z_index`), as ManimGL does with
`normal_nudge`.

The compositor runs on it too — every layer, blend mode, precomp, mask,
matte, per-layer camera and window, the two borders of the linear world, the
five blurs and the eleven editor effects, and MSAA (`samples = 4`) — on
`rgba16float` surfaces: a quad pass is one render pass, the layer's current
texture is carried instead of copied back, and a whole frame is ONE command
buffer. The quad's vertex negates NDC y instead of flipping the uv, so the
interpolated uv is exact and an effect samples the same texel; and `flip_y` is
honoured, because the two routes (`render_composition` and the mp4) differ in
orientation on anything with a vertical asymmetry (the VHS's torn band sits at
the bottom of `render_composition`'s picture and at the top of the mp4's).
There is no in-loop motion blur: `motion_blur > 1` is refused by name, and
`render_frame_motion` accumulates sub-frames on the CPU.

A `Scene` renders to an mp4 (or a transparent mov) or through `render_frame`,
and previews too: the window is opened by GLFW WITHOUT a graphics API, a
WebGPU surface is made from its native handles (Wayland or X11; on macOS a
`CAMetalLayer` on the window's content view), and one
render pass puts the frame on it — a triangle over the screen sampling the
target nearest, so at 1:1 the window receives the frame's own bytes (the
swapchain read back is byte-identical). `Fifo` is the vsync. A surface exists
only for a VISIBLE window on a native platform: hidden sessions and
`JANIM_HEADLESS=1` (the CPU adapter and GLFW's Null platform) draw into the
target and present nothing. And a process has ONE GPU: every `Scene` borrows
it, a render to a file opens no window at all, and the daemon serves `janim
frame` without creating a device per request (creating the device costs 15 ms
of what would be a 27 ms warm frame; a render VM per Scene costs 2.4 ms and
stays per Scene).

Some measured costs: 3 000 stroke-only roots render in 0.95 ms, 3 000 filled
ones in 8.6 ms (one pass at four samples), and the 1M-point cloud in 15.0 ms.
Errors come as exceptions: `GPUValidationError` carries the library's own text
(for WGSL, naga's diagnostic with line and column) and `GPUDeviceLostError`
says the device is gone.

## Resolution and frame rate

`Scene` defaults to 1080p at 60 fps. The CLI's presets are the working
vocabulary:

| | | | |
|---|---|---|---|
| `-qs` | 640×360 · 10 fps | `-qh` | 1920×1080 · 60 fps |
| `-ql` | 854×480 · 15 fps | `-qq` | 2560×1440 · 60 fps |
| `-qm` | 1280×720 · 30 fps | `-qk` | 3840×2160 · 60 fps |

A preset sets both halves, and `-r`/`--fps` still override whichever half they
name, last flag winning. Scene units are resolution-independent, so the same
scene is the same picture at every one of them.

## One frame instead of a video

```bash
janim render scene.jl -s              # the last frame
janim render scene.jl -s --to 40      # frame 40
janim render scene.jl -s --to 1.5s    # the frame at 1.5 seconds
```

`-s` is a SPELLING of `janim frame`, not a second implementation: same
code, same warm cache, same alpha, so the two give identical bytes. It refuses `-j`, `--from` and `-n` rather than ignoring them.

Frame `K` is the instant `t = (K − ½)/fps`.

## Transparency

`-t` / `transparent = true` exports an alpha channel. The video becomes a
`.mov` with **ProRes 4444** — an mp4 cannot carry alpha, so with `-t` and no
`-o` the extension changes rather than writing a file that lies about itself.
`janim frame -t` writes an RGBA png.

Two things matter if you composite the result:

- The engine works in PREMULTIPLIED alpha and the exporter
  **un-premultiplies on the way out**, which is what editors expect. Without
  it the clip looks perfect alone and grows a dark fringe over a light
  background.
- The alpha path does not go through VideoIO, which drops the alpha channel by
  design. It pipes raw RGBA into ffmpeg, as Manim does.

`-t` composes with `--from`, `--to` and `-n`: those gate WHAT IS DRAWN and the
alpha decides what the drawn pixels carry. A transparent segment comes out
byte-identical to those frames of the whole transparent render, with no
tolerance at all, because ProRes 4444 codes each frame independently.

**`-t` will not combine with `-j`, and that is deliberate rather than a gap.**
The farm does work with ProRes — `ffmpeg -f concat -c copy` keeps the alpha
plane intact, measured. The reason is size: the same scene at 720p30 is 6 KB as
h264 and 839 KB as ProRes 4444, **137× bigger**, at near-constant bitrate. The
farm exists to finish LONG renders faster, and a long ProRes render is exactly
the file you do not want on disk. The two barely share a use case.

## The render farm

```julia
render_parallel(construct, "out.mp4"; nprocs = 4, frames_total = 900,
                fps = 30, resolution = (1280, 720))
```

It splits the frames across `nprocs` Julia PROCESSES, each rendering a segment,
and concatenates them. Determinism is what makes the seams invisible: segment
boundaries are not approximations.

Each worker runs the WHOLE simulation and draws only its own range, which is
why the result is byte-identical to a single-process render.

**It only pays off when the encoder does not scale across threads anyway** —
AV1, 4K, or more cores than the codec can use. A single process already
saturates 16 cores on 720p h264, and there `-j 4` is slower, not faster.

Each worker costs about 862 MB. `-j` is NOT capped — see
[Performance and memory](performance.md).

## Selecting part of a scene

```bash
janim render scene.jl -n 3,5          # only animations 3 to 5
janim render scene.jl --from setup    # resume from a checkpoint
janim render scene.jl --to 1.5s
```

`-n` gates the DRAWING and the encoding, not the simulation: the scene is still
simulated in full, which is exactly what makes the output byte-identical to
those frames of the whole video. To skip the simulation too, use a checkpoint.

`wait!` is numbered too, and inserting one `play!` shifts every number after
it. `-n` is for exploring; [checkpoints](scenes.md) are what survive edits.

## Motion blur

```julia
render_frame_motion(construct, 1.7; n = 8, shutter = 0.5, png = "mb.png")
```

One blurred FRAME: `n` sub-frames averaged in linear light inside the
shutter (a fraction of the frame interval, 0.5 is cinema's 180°), centred on
`t`. It is often the only way to see a subject that is invisible in a still.

There is no in-loop motion blur for video: `Scene(motion_blur = n)` with
`n > 1` and `janim render --motion-blur` are refused by name, and
`render_frame_motion` is the way to a blurred still.

## Sound

```julia
add_sound(scene, "clap.wav"; time = 2.0, gain = 0.8)
```

Muxed into the mp4 at the end, so the VIDEO stays byte-deterministic.

## Codecs

[`codec_report`](@ref), or `janim codecs`, says what this ffmpeg build can do.
`crf` (lower is better, 23 by default) and `preset` are x264's usual dials.

## Reference

[`Scene`](@ref) · [`render_frame`](@ref) · [`render_segment`](@ref) ·
[`render_parallel`](@ref) · [`render_frame_motion`](@ref) ·
[`save_png`](@ref) · [`add_sound`](@ref) · [`strict_gl`](@ref) ·
[`codec_report`](@ref) — in [the scene reference](api_scene.md).
