# Scenes

A scene is a function called `construct` that takes one argument and puts
things on stage.

```julia
using Janim

function construct(scene)
    c = Circle()
    add!(scene, c)
    play!(scene, Transform(c, Square()); run_time = 1.5)
    wait!(scene, 0.5)
end
```

## `construct` is a contract

The name is fixed and the file is the unit of address. `janim render`, the
daemon, the render farm and the live window all look up exactly `construct` in
the file you name, so there is nothing to name a scene AFTER — one scene per
file.

That is the translation of Manim's `class MyScene(Scene)`. There is no class
here to carry a name, and the file already has one.

The argument is a [`Scene`](@ref). Everything that happens to it happens
through it: `add!`, `play!`, `wait!`, `checkpoint!`.

## Building a scene by hand

`Scene` builds the camera, the render context and, if you asked for one, the
video pipeline:

```julia
Scene(construct; output = "out.mp4", fps = 30, resolution = (1280, 720))
```

Passing the function makes it a one-liner that runs and closes itself. The
do-block form is the same thing:

```julia
Scene(; output = "out.mp4") do scene
    construct(scene)
end
```

The keywords:

| keyword | default | |
|---|---|---|
| `output` | `nothing` | the file to write; `nothing` means render nothing |
| `fps` | `60` | frames per second |
| `resolution` | `(1920, 1080)` | pixels |
| `preview` | `false` | open a window as it renders |
| `crf` | `23` | h264 quality, lower is better |
| `preset` | `"medium"` | x264 speed/size trade-off |
| `encoder_threads` | `nothing` | pin to `1` when the mp4's BYTES are the promise, not just its frames (4.3× slower at 1080p60) |
| `transparent` | `false` | alpha channel out (ProRes 4444 `.mov`) |
| `composition` | `nothing` | mount a [`Composition`](@ref) |
| `motion_blur` | `1` | must stay `1`: there is no in-loop motion blur (for a blurred still see [`render_frame_motion`](@ref)) |
| `shutter` | `0.5` | fraction of the frame the shutter is open (180°); inert while `motion_blur` is `1` |
| `anim_range` | `nothing` | draw only animations `3:5` |
| `progress` | `:auto` | the per-animation bar; `:auto` means "on a TTY" |

Note the defaults differ from the CLI's: `Scene()` on its own is 1080p at 60
fps, while `janim render` with no preset is 720p at 30. The CLI is for working,
the constructor is for finishing.

### There is no config file

Precedence is **CLI flag > the `Scene` kwargs in your script > engine
defaults**, and it is resolved by BUILDING the scene with those kwargs. There
is no `manim.cfg`, no `config` object, no environment leaking between runs and
nothing to un-set. A setting you want to keep lives in your scene's source,
where you can see it.

## The clock is fixed

A frame is one step of a fixed clock. `run_time = 2` at 30 fps is exactly 60
steps of `dt = 1/30`, and nothing is ever measured against the wall clock. That
is what makes two renders of the same code produce byte-identical frames, and
it is what scrubbing, frame caching and the render farm are all built on.

The αs handed to an animation are the MIDPOINTS `(k + ½)/n`, so no frame ever
sees `α = 0` or `α = 1` exactly. Frame `K` is the instant `t = (K − ½)/fps` —
worth knowing when you ask for one by number.

The exception is a preview with no output file, which runs on a real clock so
that playback happens at the speed you will watch it.

## `play!` and `wait!`

```julia
play!(scene, anim; run_time = 2)         # run an animation
play!(scene, a, b, c)                    # several, together
wait!(scene, 0.5)                        # hold for half a second
wait!(scene)                             # the default, 1 second
```

`play!` owns TIME. How progress is spread over that time belongs to the
animation, as its `rate_func` — see [Rate functions](rate_functions.md). This
split is why the same animation behaves identically under `play!`, under a
[`Timeline`](@ref) and under [`render_frame`](@ref).

Both are numbered, and `wait!` counts: that is what `-n 3,5` selects and what
`animation_map` reports. Insert one `play!` in the middle and every number
after it shifts, which is why the numbers are for exploring and checkpoints are
for keeping.

## Dropping the receiver: `@scene`

Manim writes `self.play(…)` because the scene is a method's receiver. Here it
is a function's first argument, and after thirty lines that argument is noise —
the file IS one scene, so there is never a second one to point at. Name it once
and the macros take it from there:

```julia
function construct(sc)
    @scene sc

    c = Circle()
    add!(sc, c)
    @play FadeIn(c)
    @play(Transform(c, Square()); run_time = 1.2)
    @wait 0.5
end
```

[`@scene`](@ref) binds an ordinary variable, so `sc` keeps working next to the
macros and anything they do not cover is written the long way in the same file.
There are three — [`@scene`](@ref), [`@play`](@ref), [`@wait`](@ref) — and each
is exactly one substitution:

```julia
@play(a, b; run_time = 2)      # is exactly  play!(sc, a, b; run_time = 2)
```

so everything `play!` documents still holds. Keywords pass with or without the
semicolon, and a [`Timeline`](@ref) works too, since it also answers `play!`
and `wait!`.

What this deliberately is NOT is a "current scene" global. The binding is
lexical: nothing to set, nothing to forget, and nothing that can leak from a
render into the preview that follows it — the same reason there is no config
object. Forget the `@scene` line and the error says so by name.

Two boundaries, both worth knowing before you reach for them:

**Write `@scene` inside the function.** At file level it writes a module
global, and then a function in that file that forgets its own finds it instead
of failing — 60 frames into the file-level scene and none into the one it was
handed, with no error. Nothing leaks across files (one module per scene file),
but inside one it does.

**There is no `@add`/`@remove`, on purpose.** `add!` is also a mobject's verb,
so `@add(g, c)` would mean `add!(sc, g, c)`: `g` ends childless, both land on
stage, and nothing complains. `play!` and `wait!` have no such double meaning —
their first argument can only be a scene or a timeline — which is exactly why
they got sugar and `add!` did not.

## Where the output goes

`Scene(construct; output = "x.mp4")` writes `x.mp4` — unless the scene never
animated.

**A scene with no `play!` and no `wait!` is written as an image.** It writes
`x.png` instead, and says so. That is Manim's rule and the same reasoning:
there is no video to make. Under `transparent = true` it is an RGBA png.

The test is `scene.frames == 0` — SIMULATED frames, so it means "the clock
never moved". It is a statement about the scene, not about your selection: an
empty `-n` or `--from`/`--to` range on a scene that DID animate still reports
an error rather than quietly handing you a still.

## Checkpoints

A long scene does not have to be re-simulated from the top every time you look
at its end.

```julia
function construct(scene)
    build_the_setup(scene)
    checkpoint!(scene, "setup")
    the_part_i_am_working_on(scene)
end
```

Then `janim render scene.jl --from setup` resumes from the snapshot. Put
`checkpoint!` at the TOP LEVEL of `construct`, not inside a loop or an `if`:
the prefix has to be a prefix.

The snapshot stores the SIMULATION, not pixels, which is why a transparent
render can resume from a checkpoint an opaque one left behind and still produce
correct alpha. See [`checkpoint_states`](@ref), [`checkpoint_valid`](@ref) and
[`clear_checkpoints!`](@ref).

## Inspecting a scene without rendering it

```julia
starts, total = animation_map(construct)   # where each animation begins
render_frame(construct, 1.4; png = "f.png")
```

[`animation_map`](@ref) simulates everything and draws nothing.
[`render_frame`](@ref) draws exactly one frame — the same simulation the video
does, so the frame is the frame. [`describe`](@ref) prints the tree as stable,
diffable text; it takes the scene, so call it from inside `construct`.

## Reference

[`Scene`](@ref) · [`play!`](@ref) · [`wait!`](@ref) · [`add!`](@ref) ·
[`remove!`](@ref) · [`describe`](@ref) · [`render_frame`](@ref) ·
[`animation_map`](@ref) · [`use_composition!`](@ref) · [`checkpoint!`](@ref) ·
[`render_from`](@ref) — all of them in
[the scene reference](api_scene.md).
