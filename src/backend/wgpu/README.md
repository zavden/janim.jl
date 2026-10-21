# backend/wgpu — the renderer

This folder is the whole GPU backend: WebGPU through wgpu-native (Vulkan on
Linux, Metal and DX12 on the other platforms). `backend()` reports `:wgpu`,
the only backend; `fill_mode()` reports `:stencil`, the only fill. Nothing
outside this folder may call a `wgpu*(` function, name a `WGPU_*` constant,
use a WGSL entry attribute or hold a `.wgsl` file.

Two routes, chosen by adapter: `JANIM_HEADLESS=1` selects the CPU adapter
(lavapipe), otherwise the discrete GPU is used (RADV on AMD);
`JANIM_ADAPTER=<substring>` overrides both by device name.

What lives beside the folder, because none of it names the API: the Camera
and its uniforms (`core/camera.jl`), the compositor's types and geometry
(`core/compositor_types.jl`), the effects as types (`core/effects_types.jl`),
the CPU side every render VM is built from — `expanded_data`, the run
vocabulary, the counters (`backend/expanded.jl`) — the window system
(`backend/glfw.jl` through raw ccalls, `backend/window.jl` for GLFW.jl) and
the strict-determinism switch (`backend/determinism.jl`).

## Files

| file | what |
|---|---|
| `bindings.jl` | generated: 89 whitelisted functions of wgpu-native v24.0.0.1 with the structs, handles and enums they reach, as `@ccall`s into the artifact's library (`Artifacts.toml`). None of the 32 functions that are `unimplemented!()` in v24 and abort the process. Struct sizes and field offsets match the C headers |
| `context.jl` | the `GPU` (instance, adapter, device, queue) without a window; adapter choice; errors as exceptions (`GPUValidationError`, `GPUDeviceLostError`) through mute callbacks, error scopes and `_check_gpu_errors!`; `wgpu_log()`; the driver identity (`gpu_info`, `driver_header`); `backend()`, `fill_mode()` |
| `targets.jl` | `GPUTarget` (`rgba8unorm`, optional `depth24plus-stencil8`, optional multisample twin), the synchronous readbacks (`read_rgba_topdown`, `read_rgb_topdown`) and the 256-byte row padding they crop |
| `triangle.jl` | `compile_wgsl` (a shader module inside an error scope), the first pipeline, `demo_triangle` |
| `pipeline.jl` | `FramePipeline`, the mp4 pipeline: readback one frame behind over two MapRead buffers, a converter task that crops the padded rows and drops the alpha, the encoder task (`video_impl.jl`), the drain on close; `_FRAME_TAP`; the un-premultiply of the transparent route |
| `uniforms.jl` | the two uniform blocks as isbits structs (`FrameUniforms` 112 B, group 0; `MobjectUniforms` 64 B, group 1), the bind-group helpers, the mobject `UniformArena` (a block per run, dynamic offsets at the adapter's alignment, one write per frame) and the `ParamArena` rings (`QuadParams`, 304 B) |
| `pipelines.jl` | `_wgsl` (sources read at include time, inserts spliced), the substituted constants (`Z_PASS`, `Z_CORE`, `SAMPLES`, `CULL_ALPHA`, `THIN_PX`), the vertex layouts, and the pipelines keyed `(kind, depth, z_pass, sample_count, format)` |
| `records.jl` | what the renderer remembers between frames: run records as spans of the `VertexArena` (eight SoA buffers per VM, sub-allocated with a free list, `first_instance` per draw), mirrors compared once per pass, mesh and cloud records, the texture and ramp caches, the sweep, the deferred releases, and the `GPURenderVM` |
| `render.jl` | `setup_render_vm`, the draw loop (`_draw_list!`, runs per root) producing the frame's draw list, the frame's ONE pass (`_frame_pass!`, `_record_frame!`), `draw_scene!`, `render_mobjects`, and `_shared_gpu()` (one GPU per process, shared by every `Scene`) |
| `compositor.jl` | `GPUCompositor`: layers, blend modes, precomps, masks and mattes, windows, the blurs and the editor effects. Seven `rgba16float` slots plus accumulator pairs by depth, one quad pass per effect step, the current-texture discipline (`_scratch`, `live`), the frame as ONE command buffer (`_begin_frame!`, `_flush!`, `_end_frame!`), `draw_composition!` (honouring `flip_y`), `render_composition`, `read_layer_rgba`, and `effect_shader!` for effects of your own |
| `window.jl` | `create_window` (a GLFW window opened without an API) and, for a visible window on Wayland or X11, the `GPUPresenter`: surface from the native handles, plain (non-sRGB) preferred format, `Fifo`; `present!` = acquire, pass, submit, present, `glfwPollEvents`, with every non-success status reconfiguring and skipping the frame except `DeviceLost`; `_blit_image!` and `_paint_strip!` for the live loop |

## Shaders

| file | what |
|---|---|
| `shaders/stroke.wgsl` | the stroke: ManimGL's geometry stage as an instanced vertex stage (the triples arrive by instancing, six vertices per segment), compiled twice with `Z_PASS` for the depth prepass |
| `shaders/stencil.wgsl` | the COUNT of a fill into the stencil aspect: the fan and the Loop-Blinn triangle per curve, no colour written; IncrementWrap on a front face and DecrementWrap on a back face give the nonzero rule; the curved edge's coverage per SAMPLE through `@builtin(sample_mask)`; compiled per sample count and, for gradient runs, without the zero-alpha cull |
| `shaders/cover.wgsl`, `cover_grad.wgsl` | the PAINT: the same triangles under stencil `NotEqual 0`, zeroing the count as they pass; the triangle's own z, tested and written when the mobject depth-tests; the gradient variant samples the ramp per pixel |
| `shaders/true_dot.wgsl`, `surface.wgsl`, `image.wgsl`, `textured_surface.wgsl` | dots, lit uv meshes, textured quads and textured uv meshes |
| `shaders/quad.wgsl`, `effects.wgsl` | the compositor's ten fragments (plus WINDOW) and the eleven editor effects, as two modules over one shared quad |
| `shaders/present.wgsl` | the preview's presentation pass: one triangle over the screen, a nearest sample at level 0 |
| `shaders/inserts/*.wgsl` | spliced by `// #INSERT name.wgsl`: `uniforms`, `frame_units`, `project_point`, `finalize_color`, `thin_triangle` (the fill's thin-triangle cull), `quad_common` (bind group, `QuadParams`, `vs_quad` with the flip on the GEOMETRY), `srgb`, `noise` (lowbias32 in u32), `straight` |

## Design rules

- One render pass per frame; the fill is stencil-then-cover, two draws per
  VMobject inside it. Under MSAA (4 samples by default, `samples = 1` is the
  aliased control) the pass renders into the target's multisample twin and
  resolves with `resolveTarget`.
- The vertex arena's eight buffers are bound once per pass; every arena
  pipeline declares all eight slots (an unconsumed attribute in the ones it
  does not read, because an empty layout is renumbered by this wgpu-native).
- The compositor records every layer and effect into one encoder and
  submits once per frame; what a walk retires is destroyed after the submit.
- Nothing here may call one of the 32 unimplemented functions of wgpu-native
  v24 (a panic aborts Julia); waiting is `wgpuDevicePoll`; WGSL errors are
  read through error scopes; callbacks copy bytes and touch atomics, nothing
  else.
- A closed target, render VM or compositor never reaches wgpu: released
  handles make wgpu-core panic, so the check is in Julia
  (`GPUValidationError`).
- Performance is measured over the whole cycle (draw + copy + harvest +
  encode), never "encode only".
