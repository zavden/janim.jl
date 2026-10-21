# The Janim course

Four courses, 89 runnable scenes. Every lesson is a real file you can render,
preview, edit and break — the explanation lives in the comments at the top,
next to the code it is about.

| Course | What it covers | Lessons |
|---|---|---|
| [Course 1 — Foundations](course1.md) | mobjects, animations, configuration, assets, groups, text and formulas, rate functions, the utility belt, plots, updaters, fields and particles | 33 |
| [Course 2 — Going deeper](course2.md) | advanced updaters, custom mobjects, custom animations, the camera, simulations, coming from Manim, writing shaders | 14 |
| [Course 3 — Only in Janim](course3.md) | the layer compositor, blur and glow, masks, glitch and the editor effects, motion blur, and a capstone | 40 |
| [Course 4 — The complete reference](course4.md) | the shape zoo: every flat shape and the group base, one runnable lesson each | 2 |

Courses 1 and 2 follow the shape of a ManimCE/ManimGL course, so if you know
Manim you will recognise the syllabus. Where Janim does the same thing
differently, the lesson says so; where it does not do it at all, the lesson
says that too.

Course 3 is the part with no Manim equivalent at all: a real compositor of
layers, which is a consequence of Janim's architecture and not a feature that
could be bolted onto Manim's.

## Running a lesson

Every lesson defines `construct(scene)` — the contract the daemon, the render
farm and the live window all look up — and renders itself when run directly:

**Stand in the repository root** — the directory with `Project.toml`, `src/` and
`bin/` in it — instantiate that environment once, then use `--project=.`:

```bash
cd path/to/Janim.jl                                # the repository root
julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'
julia --project=. examples/tutorial/c1_01_basics/02_mobjects_and_animations.jl
# → examples/tutorial/output/c1_01_basics/02_mobjects_and_animations.mp4
```

Run `Pkg.instantiate()` again after pulling a changed `Manifest.toml`. In
particular, `failed to find source of parent package` means that an exact
transitive version listed there is absent from the local Julia depot; adding a
newer version to another environment is not a substitute for instantiating
this one.

`--project=` names a DIRECTORY, so the two things have to agree: from the
directory above the repository root, the same run is

```bash
julia --project=Janim.jl Janim.jl/examples/tutorial/c1_01_basics/02_mobjects_and_animations.jl
```

and from anywhere at all, absolute paths work:
`julia --project=/abs/path/Janim.jl /abs/path/Janim.jl/examples/tutorial/…`. What does NOT
work is mixing them (`--project=Janim.jl examples/tutorial/…`): Julia looks for a project
in `./Janim.jl`, does not find one, and reports *«Package Janim not found in
current path»*.

The same file works with everything else in the toolbox:

```bash
bin/janim daemon start                                   # once per session
bin/janim frame   examples/tutorial/c1_01_basics/06_layers.jl 40 f.png
bin/janim render  examples/tutorial/c1_01_basics/06_layers.jl -o out.mp4 -r 1280x720
bin/janim preview examples/tutorial/c1_01_basics/06_layers.jl     # live, hot reload; Esc/q quits
```

## Checking a lesson

Rendering a lesson only gets you as far as "it ran". **A lesson that renders is
not a lesson that is right** — the house rule is that you verify by looking:

```bash
bin/janim frame examples/tutorial/c3_04_glitch/01_glitch_basics.jl 40 f.png
```

A lesson may declare `PREVIEW_T` (the second worth looking at, default 1.0) and,
in the motion-blur lessons, `PREVIEW_MOTION` (sub-exposures, because their subject
is invisible in an instantaneous frame). They are hints for whoever looks at a
still frame; the scene itself ignores them.

## Conventions used throughout

- **Code, comments and on-screen text are in English.** The engine's own
  examples (`../demo/`) keep their Spanish prose; this course is written in
  English on purpose.
- **Sizes are in scene units.** The nominal frame is 8 units tall and
  8·16/9 ≈ 14.22 wide, whatever the pixel resolution is.
- **Nothing is placed by hand-written pixel coordinates** where a layout call
  would do (`next_to!`, `arrange!`, `to_edge!`), except where a lesson is
  deliberately showing the arithmetic.
- **Numbers in the comments were measured**, not remembered. Where a lesson
  claims a figure, it usually prints it too.

## Where the rest of the documentation is

- [`../../README.md`](../../README.md) — what Janim is and how to install it
- `../../llms.txt` — the operational summary of the whole API, for agents
- `../../docs/src/` — the manual
- `../scenes/`, `../gallery/`, `../demo/` — complete scenes, ported Manim classics and demos
