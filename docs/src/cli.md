# The CLI

`bin/janim` is pure bash and `/dev/tcp`. It **never starts Julia**: it talks to
a warm daemon over a socket, so the start-up cost belongs to the daemon and not
to every invocation.

```bash
./bin/janim help
```

Put it on your `PATH` with a symlink and it works from anywhere — it resolves
its own location with `readlink -f`, and relative scene paths are resolved
against your current directory:

```bash
ln -s /path/to/Janim/bin/janim ~/.local/bin/janim
```

## The verbs

```
janim scene.jl [flags]          no verb = preview; -w writes the video,
                                -p writes AND opens it, -s is the still
janim render  scene.jl [-qm] [-r WxH] [--fps N] [-o out.mp4] [-j 4] [-p] [-t]
                       [--from X] [--to Y] [-n X,Y]
                       [--samples N] [-s [--to Y]] [--out_dir DIR]
                       [--no-tui] [--only-cli]
janim frame   scene.jl K out.png [-qm] [-r WxH] [--fps N] [-t] [--samples N]
janim preview scene.jl [-c]
janim states  scene.jl
janim daemon  start|stop|status
janim check
janim finish  [-f]
janim codecs
janim ping
```

The verbless form is manimgl's: `manimgl scene.py` opens a window, and so
does `janim scene.jl`. `-w` writes the video instead (render), `-p` writes
it and opens it, `-s` writes the still. An explicit `preview` **refuses**
`-w`/`-p` out loud rather than accepting a flag it would drop.

## Start here: `check` and `finish`

**Run `janim check` before you start working, and `janim finish` if it
complains.**

A daemon that outlives whoever started it is not idle noise — it is a source of
wrong answers, in two different ways. One that is still LISTENING holds the
port: the next daemon dies of `EADDRINUSE`, your commands quietly talk to the
stale one, and the results have nothing to do with your code. One that is NOT
listening answers nothing and still holds its heap — fourteen of them add up
to about 12 GB, which is enough to move a timing measurement.

`check` lists every Janim daemon on the machine with its port, memory and
whether it is listening, marks the one this CLI talks to as `yours`, and exits
1 when there are orphans — so it works as a gate in a script. `finish` closes
the orphans, never yours, and refuses outright while a test run is in progress
(its daemons look exactly like orphans and are not) unless you insist with
`-f`.

## Quality presets

Each sets BOTH the resolution and the frame rate:

| | | | |
|---|---|---|---|
| `-qs` | 640×360 · 10 fps | `-qh` | 1920×1080 · 60 fps |
| `-ql` | 854×480 · 15 fps | `-qq` | 2560×1440 · 60 fps |
| `-qm` | 1280×720 · 30 fps | `-qk` | 3840×2160 · 60 fps |

`-r` and `--fps` still win over whichever component they name, and the LAST
flag wins: `-qh -r 640x360` is 640×360 at 60 fps. Without a preset: 1280×720 at
30.

The letters read as a scale — s · l · m · h · q · k. Two deliberate departures
from Manim CE: `-qs` (360p10) is ours, for the draft pass CE has no name for,
and 1440p is `-qq` rather than CE's `-qp`, so that no letter means
"production".

## The golden rule: the engine reads no config

**Nothing global ever reaches the engine.** Precedence is

    CLI flag  >  the Scene kwargs in your script  >  engine defaults

and it is resolved by BUILDING the scene with those kwargs. There is no
engine config file, no environment leaking between runs, and nothing to
un-set on a machine where someone once changed something.

## `janim.cfg` and the panel — a CLI shortener

What DOES exist lives entirely in the bash client: a
`janim.cfg` of CLI flags, one per line, looked up beside the scene and then
in the current directory.

```
# janim.cfg
-ql
--samples 4
```

The client prepends it to your argv and **announces it on every use**
(`← janim.cfg: -ql --samples 4`) — an announced file is not hidden state,
which was the objection to `manim.cfg`. Your explicit flags always win,
because they parse after it.

On a TTY, `render` and `preview` open a small panel over those merged
values:

```
  janim render scene.jl
   FROM         ·
   TO           ·
   QUALITY      l
   WIDTH        ·
   HEIGHT       ·
   FPS          ·
   SAMPLES      4
  ─────────────────────
   …
  → janim render scene.jl -ql --samples 4
  ENTER render · Ctrl+S save+render · ESC quit
```

`↑/↓` move, typing edits, `←/→` cycle QUALITY and toggle yes/no fields —
and the vim hands do the same: `Ctrl+J/K` are `↓/↑`, `Ctrl+H/L` are `←/→`.
QUALITY is the compound preset (`s/l/m/h/q/k`); WIDTH, HEIGHT and FPS
inherit from it while empty and OVERRIDE it when written; OUTPUT empty
derives from the scene's name. The bottom line always shows the exact
command ENTER will run. Ctrl+S writes `janim.cfg` and renders — everything
except `-o`, which is never auto-persisted (a fixed output in a shared cfg
would send every scene in the directory to the same file; writing an `-o`
line by hand still works). `--out_dir` IS persisted: a shared destination
directory is exactly what a per-directory cfg means.

The escapes, mainly for scripts and agents: a pipe (no TTY) never sees the
panel; `--no-tui` skips it while keeping the cfg and flags; `--only-cli`
skips BOTH — flags and defaults alone, the fully predictable call; and
`JANIM_NO_CFG=1` is the environment spelling of that, so a forgotten cfg
cannot steer a scripted run.

## `render`

```bash
janim render scene.jl                     # 720p30 → scene.mp4
janim render scene.jl -qh -o final.mp4 -p # 1080p60, and open it
janim render scene.jl -j 4                # the farm, 4 processes
janim render scene.jl -n 3,5              # only animations 3 to 5
janim render scene.jl --from act2         # resume from a checkpoint
janim render scene.jl -t                  # → scene.mov, ProRes 4444
janim render scene.jl -s --to 1.5s        # one frame, as a png
janim render scene.jl --out_dir videos/   # → videos/scene.mp4 (mkdir -p'd)
```

`-n X,Y` means an ANIMATION range, as a Manim user expects. The farm is
`-j`/`--jobs` (make's convention; `--nprocs` also works).

`--out_dir DIR` puts the output in `DIR`, creating it — subdirectories
included — like Manim's media dir but with no policy in the engine: the
CLI joins the path and hands the engine one plain `-o`. An empty output
becomes `DIR/scene.mp4` (`.mov` under `-t`), a relative `-o` joins as
`DIR/out.mp4`, and an absolute `-o` already says where, so it wins with a
warning. It reaches `frame`'s positional output too, and (`.tex` users)
there is nothing else to redirect: `via = :latex` compiles inside a
self-cleaning temp dir and only its SVG survives, in `~/.cache/janim/tex/`.

**`-j` has no upper limit.** Each worker costs about 862 MB, so `-j 32` will
exhaust a 32 GB machine and `-j 40` instead of `-j 4` is one keystroke. See
[Performance and memory](performance.md).

## `frame`

```bash
janim frame scene.jl 51 out.png -qm
```

**`frame` is the single-frame verb; `render` renders the whole video.** Getting
them the wrong way round costs a full render instead of about 17 ms.

Warm, it is around 17 ms, cached by `(path, scene name, mtime, frame, fps,
resolution, transparent, samples)`. Editing the scene invalidates the cache by mtime — do NOT
restart the daemon to pick up an edit.

## `preview`

```bash
janim preview scene.jl        # opens IN the warm daemon when one is up
janim preview scene.jl -c     # start with "stop at checkpoints" on
```

| key | |
|---|---|
| `Esc` / `q` | quit |
| `space` | pause |
| `,` `.` | step one frame |
| `←` `→` | ±1 second |
| `[` `]` | previous / next animation |
| `PgUp` `PgDn` | previous / next checkpoint |
| `Home` | back to the start |
| `c` | stop at checkpoints |

`Ctrl-C` on the client also closes the window. See [the interactive
session](interactive.md).

## `states`, `codecs`, `ping`

```bash
janim states scene.jl     # the checkpoints in it, and whether each is valid
janim codecs              # what this ffmpeg build can do
janim ping                # is the daemon alive?
```

## The daemon

```bash
janim daemon start
janim daemon status
janim daemon stop
```

The port is `$JANIM_PORT`, 7318 by default. `daemon start` captures its
start-up in `~/.cache/janim/daemon.log` and detects a death, so a daemon that
fails to come up says so instead of leaving you waiting.

## Progress

`render` and `preview` STREAM a CE-style per-animation bar (`PROG`/`PROGN`
lines before the final OK) and the CLI draws it. In a script, `progress =
false` on the `Scene` turns it off; `:auto` — the default — shows it only on a
TTY.
