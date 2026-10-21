# The interactive session

Rendering a whole video to check one detail is the slow way round. There are
three warm paths, and the live window is the one worth learning.

## The live window

```julia
live("scene.jl")
```

```bash
janim preview scene.jl
```

The file is tracked with Revise, so saving an edit shows up in about 80 ms
without restarting anything. Playback is REAL TIME: `construct` runs ONCE as a
coroutine and each frame costs O(1), rather than the scene being re-simulated
from the top on every frame.

The window is opened by GLFW without a graphics API and WebGPU presents on
it through a surface made from the window's native handles — Wayland on a
Wayland session, X11 with `JULIA_GLFW_PLATFORM=x11` — with one render pass
that samples the frame nearest at 1:1 and `Fifo` as the vsync. A hidden session
(`setup_live(visible = false)`) or `JANIM_HEADLESS=1` draws into the frame's
target and presents nothing.

| key | |
|---|---|
| `Esc` / `q` | quit |
| `space` | pause |
| `,` `.` | step one frame back / forward |
| `←` `→` | jump ∓1 second |
| `[` `]` | previous / next animation |
| `PgUp` `PgDn` | previous / next checkpoint |
| `Home` | back to the start |
| `c` | stop at checkpoints |

Dragging pans and the wheel zooms; hold `d` while dragging to rotate in 3D and
`f` to pan. Those are DELTAS composed on top of the scene's own camera, so
exploring a preview never edits your scene — and the rotation is manimgl's
turntable to the letter: a horizontal drag turns θ and only θ, however
tilted the scene's camera is, and the horizon never rolls. The pan follows
the view plane, like manimgl's, rather than the world's xy.

**Jumping backwards re-simulates exactly.** What you scrub through is the film,
not an approximation of it — which is a consequence of the render being
deterministic.

### It survives your errors

Break `construct` and the window does not die: it freezes on the last good
frame and watches the file until your fix lands. A session can outlive a dozen
syntax errors.

Edits are detected by the WORLD AGE of `construct`, not by the file's mtime.
Revise applies a change a tick after the file changes, so an mtime gate would
rebuild the state with the OLD code under the NEW mtime — a poisoned state a
paused session never leaves.

### Driving the loop yourself

```julia
v = setup_live("scene.jl"; fps = 30, resolution = (1280, 720), visible = false)
for _ in 1:100
    live_step!(v)
end
println(live_status(v))
```

[`setup_live`](@ref) is `live` without the event loop, for a test, an editor
integration, or a headless session that only wants the pixels.

On a Wayland session the preview window is native Wayland: GLFW's Wayland
platform is chosen before GLFW.jl loads, so Xwayland leaves the path.
`JULIA_GLFW_PLATFORM=x11` brings X11 back and `Janim.gl_platform()` says which
platform this process got.

## The daemon

```bash
janim daemon start
janim frame scene.jl 51 out.png       # ~17 ms warm
janim daemon stop
```

A Julia process with Janim already loaded, listening on local TCP (port
`$JANIM_PORT`, 7318 by default). The CLI is pure bash and `/dev/tcp`, so the
start-up cost is paid once by the daemon instead of on every invocation.
The daemon holds ONE GPU for the whole process: a `frame` request builds a
render VM on it and no window at all.

The protocol is one line per request, answered `OK …` or `ERR …`:

```
ping
status
render  <scene.jl> <frame> <out.png> [fps] [WxH]
mp4     <scene.jl> <out.mp4> [fps] [WxH] [jobs] [from] [motion_blur] …
preview <scene.jl> [fps] [WxH] [stop_at_checkpoints]
states  <scene.jl>
codecs
stop
```

`mp4` and `preview` STREAM progress before the final line. Start one from
Julia with [`daemon`](@ref).

Two properties worth knowing:

- **Each scene is loaded into its own module.** Julia makes a single generic
  `Main.construct` rather than two functions, so sharing one module would let
  loading a second scene REPLACE the first one's method — rendering `a.jl`,
  then `b.jl`, then `a.jl` again would silently give you `b`.
- **Frames are cached by `(path, scene name, mtime, frame, fps, resolution,
  transparent, samples)`.**
  Editing the scene invalidates the cache by mtime, so there is never a reason
  to restart the daemon to pick up an edit.

**Run `janim check` before you start, and `janim finish` if it complains** — an
orphan daemon gives wrong answers and holds its heap. See [the CLI](cli.md).

## Checkpoints

```julia
function construct(scene)
    build_the_setup(scene)
    checkpoint!(scene, "setup")
    the_part_i_am_working_on(scene)
end
```

```bash
janim states scene.jl                 # what checkpoints it has, and their validity
janim render scene.jl --from setup    # resume from one
janim preview scene.jl -c             # stop at each of them
```

The snapshot lives in the warm daemon, which is where it earns its keep: a
`--from` on an unchanged prefix skips the expensive part outright.

It stores the SIMULATION rather than pixels, so a transparent render can resume
from a snapshot an opaque one left behind and still produce correct alpha.
Put `checkpoint!` at the TOP LEVEL of `construct` — the prefix has to be a
prefix.

[`checkpoint_states`](@ref), [`checkpoint_valid`](@ref) and
[`clear_checkpoints!`](@ref) are the same thing from Julia.

## Choosing what to look at

```julia
starts, total = animation_map(construct)
render_frame(construct, 1.4; png = "check.png")
```

[`animation_map`](@ref) simulates everything and draws nothing, so it can tell
you which frame animation 4 begins at without rendering. Frames worth looking
at, in the order they catch things:

1. **the middle of every `Transform`** — morphs fail here and nowhere else;
2. `t = 0 + ε` — is the opening state clean?
3. **just after every `FadeOut`** — leftovers, ghosts, half-faded children;
4. the last frame — does it settle?

## Reference

[`live`](@ref) · [`setup_live`](@ref) · [`live_step!`](@ref) ·
[`live_status`](@ref) · [`daemon`](@ref) · [`Controls`](@ref) ·
[`checkpoint!`](@ref) — in [the backend reference](api_backend.md).
