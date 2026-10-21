# Performance and memory

Every number here was measured, on Linux with 31 GB and 16 cores, at 720p
unless the row says otherwise.

## Memory

Janim keeps a warm daemon, so what you see resident is a working set that
plateaus, not a leak.

| | RSS | processes |
|---|---|---|
| daemon at rest | 547 MB | 1 |
| render, light scene (6000 frames) | ~1150 MB, flat | 1 |
| render, 10 000 particles (3000 frames) | 1126 → 2307 MB, back to 1148 after a full GC | 1 |
| preview | 1384 MB, flat plateau | 1 |
| preview at 4K | 2296 MB, flat plateau | 1 |
| `janim render -j 4` | 4087 MB peak, back to 640 MB | 5 |

**Budget about 1.5 GB for ordinary work and about 4 GB for a `-j 4` render.**
Nothing in daily use comes near a 16 GB machine.

A render stores nothing between frames. What grows during a heavy particle
render is uncollected garbage, and it comes back to the baseline on its own. A
PREVIEW does store frames — that is what makes scrubbing backwards exact — and
its cache is bounded.

### Two limits that are not guarded

- **`-j` is not capped.** Each farm worker costs about 862 MB, and the count
  travels from the CLI to [`render_parallel`](@ref) without a clamp. `-j 16` is
  about 14 GB and `-j 32` exhausts a 32 GB machine, so choose it deliberately —
  `-j 40` instead of `-j 4` is one keystroke.
- **The preview's frame cache costs more than its stated 500 MB above 1080p.**
  It is bounded — `max(60, 500 MB ÷ frame)` — but the 60-frame floor takes over
  once a frame passes about 8 MB: 664 MB at 1440p and 1.49 GB at 4K. `janim
  preview -qk` therefore needs about 2.3 GB for the daemon alone.

### Orphan daemons

They hold their heap: 1.1–1.4 GB each once they have rendered anything, 2.3 GB
if they previewed at 4K. Fourteen of them hold about 12 GB — enough to
move a timing measurement. That is what `janim check` and `janim finish` are
for; see [the CLI](cli.md).

## Start-up

A fresh process doing `using Janim`, building a `Tex` and rendering a frame
measures **1.35 s** on this machine.

The first render pays no JIT bill on top of that: the geometry core, the
animation life cycle and the first formula are exercised at precompile time,
and the draw path is precompiled BY SIGNATURE — which asks for code without
CALLING it, so no display is needed on the build machine.

The way not to pay any of it is the daemon: the CLI is pure bash and
`/dev/tcp`, so a warm frame is about 17 ms.

## When the farm helps

`-j` only pays off when the encoder does not scale across threads anyway —
AV1, 4K, or more cores than the codec can use. **A single process already
saturates 16 cores on 720p h264**, and there `-j 4` is slower than `-j 1`, not
faster.

Measured speed-up where it does apply: 2.1× with 4 encoders.

## What costs what

- **A formula is free.** `Tex` runs MathTeXEngine in 0.2–0.4 ms. `via = :latex`
  is about 1 s, because it is a real LaTeX run, and it caches to disk.
- **Text is not free the FIRST time.** Loading the font pays once per session,
  and precompilation absorbs it.
- **A particle cloud is one draw call.** [`DotCloud`](@ref) holds many points
  in one mobject, which is how a million particles stay tractable; a million
  individual `Dot`s would not.
- **The bounding box is cached** with a dirty flag, and shift/scale/stretch
  update it in place rather than invalidating it. `rotate!` does invalidate it.
- **`get_family` is cached** and invalidated upwards through the parents.

## Writing fast scenes

- **Put the work in a function.** This is Julia's first performance rule and it
  applies to scenes: the top level of a script has no type information, so a
  loop there is slow even when it works. Everything inside `construct` already
  gets this for free.
- **Do not allocate per frame in an updater.** Writing into an existing array
  with `.=` costs nothing; building a new one every frame is where the ~390 MB
  of churn in the particle measurement above came from.
- **Reach for `parallel = true` on an updater only when it truly touches only
  its own mobject** — it is a promise the threaded loop takes literally.
- **Prefer one batched mobject over many small ones** when the count goes past
  a few hundred: a [`DotCloud`](@ref), a [`VectorField`](@ref), one
  [`VMobject`](@ref) with many subpaths.

## Measuring, rather than guessing

A rule worth adopting: **the top of an inference
profile is a suspect, not a verdict.** Instrumented times are inflated per node
and do not convert to wall clock, so an optimisation only earns its place by
moving a measurement you took before and after.

The same goes for memory: `pgrep -f "janim"` from inside a script matches the
script itself. Ask the port who is listening instead.
