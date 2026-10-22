# Open items

What is known to be unresolved at version 1.0.0 (2026-10-22). Each entry says
what is wrong, where it lives and what settling it would take. Most of them
were found while porting to macOS and Windows and re-checking Linux; the
guides that record those sessions are in [`history/2026-10/`](history/2026-10/).
An item leaves this file when it is settled.

## Documentation and examples

- **Motion blur in video is described but does not exist.** `Scene` refuses
  `motion_blur > 1` and the CLI rejects `--motion-blur`; what exists is
  `render_frame_motion`, which averages several exposures into one still. The
  lessons in `examples/tutorial/c3_05_motion_blur/` and the demos
  `examples/demo/04_lorenz_glow.jl`, `10_motion_blur.jl` and
  `12_motion_blur.jl` still narrate the in-video version, and the CLI's TTY
  panel still shows `MOTION BLUR` and `SHUTTER` fields (the panel labels in
  `bin/janim`). Either bring the feature back or rewrite the lessons and the
  demos and drop the two fields.
- **Fonts the README does not install.** `c1_03_groups_and_text/03_text.jl`,
  `c3_05_motion_blur/05_physics_warning.jl` and `06_cli_and_farm.jl` ask for
  Liberation Serif and Liberation Mono; the README's requirements and its
  `dnf`/`apt`/`brew` lines only name DejaVu Sans. `examples/demo/12_motion_blur.jl`
  asks for «Fredoka Expanded», which no platform ships by default, so that
  demo fails on Windows and macOS (and on any Linux without the font).
  Options: add the fonts to the install lines (`liberation-fonts`,
  `fonts-liberation`, `font-liberation`), substitute DejaVu in the lessons,
  or ship them (both families are published under the SIL Open Font License).
- **The clone line still says `<user>`.** Both READMEs clone
  `https://github.com/<user>/Janim.jl.git` and then `cd Janim.jl`; the
  repository is `zavden/janim.jl`, so the directory a clone creates is
  `janim.jl`.
- **«One scene per file» is no longer the whole truth.**
  `docs/src/getting_started.md` and `docs/src/from_manim.md` say so, while
  the CLI addresses several `construct` functions in one file as
  `file.jl:name` (`examples/scenes/08_tux_wild.jl` has `construct_a`,
  `construct_b` and `construct_c`). Reword the two passages.
- **`SHA = "0.7.0"` in `[compat]`.** SHA is a standard library; developing
  the package into `docs/` makes Pkg print «Ignoring incompatible compat
  entry». Drop the entry or make it match the stdlib's version.

## Behaviour

- **A scene path with spaces fails on Linux and macOS.** The daemon splits
  the request line on blanks. The Windows client encodes each space as `|`
  and `_serve` decodes it, both behind a platform gate (`_send` in
  `bin/janim`; `_serve` in `src/interactive/daemon.jl`). Removing the two
  gates fixes the other platforms at the cost of a `|` in a path, which Unix
  allows. Decide, then test with `mkdir "/tmp/con espacio"` and a scene
  inside.
- **GLFW 3.4.0 on Wayland can spin at 100 % CPU when a window closes fast.**
  Destroying the live window within milliseconds of its first presented frame
  can dispatch a queued `wp_fractional_scale_v1.preferred_scale` after
  `wl_surface.destroy`; the compositor answers `wl_display error: invalid
  object` and `glfwPollEvents` in `close_context`
  (`src/backend/glfw.jl`) never returns; SIGINT does not stop it. It
  reproduces on the code before the Windows port, not with sessions of 10 s
  or more, not on X11 and not in Janim.py (no JIT delay). Left as is for
  now; the Wayland trace is described in `history/2026-10/LINUX.md`.
- **No CPU route on macOS.** `JANIM_HEADLESS=1` fails with the adapter list
  on Metal, because there is no lavapipe or WARP equivalent there. By design,
  but the error could say so.
- **Windows needs Git Bash.** `bin/janim` is bash and has no PowerShell or
  `cmd` equivalent (Janim.py ships `bin/janim.cmd`).
- **Routes differ by a pixel at some edges.** Frames are reproducible within
  a route (RADV, lavapipe, Metal, DX12, WARP), not across them. Reference
  hashes, when they exist, have to be per route.

## Janim.jl against Janim.py

- **`Tex` glyph spacing.** Janim.jl's default route (MathTeXEngine) spreads
  the glyphs; Janim.py composes them with LaTeX's kerning. That alone makes
  demos `02`, `05` and `06` differ between the two libraries, while `01`,
  `03`, `04`, `07`, `10` and `11` are frame-identical on Linux and macOS
  (`08` and `09` differ only because their on-screen text names the
  language). Decide whether the spacing is intended.
- **Comparing mp4s across the libraries measures the encoder.** Janim.jl
  writes through FFMPEG_jll's ffmpeg (x264 core 164); Janim.py through the
  `PATH`'s (core 165 on Fedora and Homebrew). `11_chase_camera` differs in 28
  frames at 54–58 dB with identical raw frames. Compare raw frames (the
  `_FRAME_TAP` harness), or pin the encoder on both sides.

## Testing and release

- **No test suite ships with the repository.** The release was verified with
  session harnesses: per-frame SHA-256 of every example and demo at 640×360
  and 10 fps, before and after each port (`history/2026-10/LINUX.md`, §6).
  Turn that into a `test/` suite with per-route reference hashes, and run it
  on the three platforms.
- **Not in the General registry.** Installation is a clone plus
  `Pkg.instantiate()`; using Janim from another environment needs `] dev`.
  Registering needs the `[compat]` review above and a decision on the
  wgpu-native artifact (`Artifacts.toml` points at a GitHub release).
- **`examples/assets/linux.svg` has mixed line endings** (90 CRLF lines out
  of 91). Harmless; normalize it or declare it in `.gitattributes`.
