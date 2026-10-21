# Text and formulas

`Tex` does NOT run LaTeX. It runs MathTeXEngine, in 0.2–0.4 ms per formula, so
there is no subprocess, no temporary directory and no LaTeX installation to
find.

```julia
f = Tex(raw"x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}"; size = 1.2, color = WHITE)
```

Always `raw"…"`, or Julia eats the backslashes.

## Three routes

| `via =` | engine | cost | for |
|---|---|---|---|
| `:math` (default) | MathTeXEngine | 0.2–0.4 ms | everything, unless it refuses |
| `:latex` | system LaTeX + dvisvgm | ~1 s | environments, `\newcommand` |
| `:typst` | `Typst_jll`, vendored | fast | Typst syntax, not LaTeX |
| `:auto` | `:math`, then falls back | — | warns once per session, on purpose |

When `:math` rejects a formula the error already names the route to fall to.
The three share x-height and baseline — the other two are calibrated against
`:math` — so a formula does not jump when you switch. `center = false` leaves
the baseline at y = 0 instead of centring.

[`config_tex!`](@ref) sets the default for a session. It is a module `Ref`, not
a config file: explicit, visible, and gone when the session ends.

## Real LaTeX, with your own packages

[`LTex`](@ref) and [`LMathTex`](@ref) are Manim CE's `Tex` and `MathTex`: text
mode and math mode, both through the system's LaTeX, both taking a
[`TexTemplate`](@ref) whose preamble you grow.

```julia
tpl = TexTemplate()
add_to_preamble!(tpl, raw"\usepackage{physics}")
LMathTex(raw"\dv{f}{x}"; template = tpl)

LTex(raw"let $z_3 = i \cdot z_1$, with \textbf{negative} real part")
```

There are two because each does what the other cannot, exactly as in Manim:
`x^2` bare is math and fails in `LTex`; a bare `$` inside `LMathTex` closes the
math the body already sits in. `via = :latex` was only ever the second half —
`LMathTex(f)` with the default template compiles the very same document, to
1e-9.

**The base is a constant, not a field.** `\documentclass[preview]{standalone}`
and [`TEX_BASE_PREAMBLE`](@ref) (`amsmath`, `amssymb`) are what every template
inherits, and a `TexTemplate` stores only your additions — so there is nothing
to edit, and no `12pt` to reach. Size lives on this side, as `size =` and
`scale!`. A template is for PACKAGES, which is what unlocks glyphs.

`print(tpl)` shows the document it will compile, frozen part marked;
[`tex_source`](@ref) returns it as a String. Read one from a file with
`TexTemplate(read("mine.tex", String))` — still a value you pass, not a setting
that applies behind your back.

Two measured consequences worth knowing. The x-height calibration is per
template AND per mode: a glyph package (`physics`, `siunitx`) moves it 0.00 %,
but a FONT package moves it (`mathpazo` 8.27 %) and text mode sits 5.20 % under
math, so one shared number would silently mis-size two cases out of three. And
the cost is one compile per distinct document — 0.226 s, then 0.02 ms from the
disk cache.

## A Tex is a parent with one child per glyph

This is load-bearing, not an implementation detail. With every glyph in a
single VMobject, the intermediate blob of a morph flies over its neighbours and
CANCELS their winding — visible as flicker, and the reason the structure is
what it is.

What you get from it:

```julia
tex["x"]                  # a memoised VGroup of every x — tex["x"] === tex["x"]
tex[3]                    # by index
tex[2:4]                  # a range
find_by_key(tex, "e")
Tex(raw"x^2 + y^2"; isolate = ["x^2"])     # label a whole sub-expression
```

`isolate` is a `:math` feature: the other two routes only know font ids.
[`set_key!`](@ref) labels your own mobjects the same way.

## Morphing a formula

```julia
f1 = Tex(raw"a^2 + b^2 = c^2"; size = 1.4)
play!(scene, FadeIn(f1; shift = 0.3 * UP); run_time = 0.8)

f2 = Tex(raw"c = \sqrt{a^2 + b^2}"; size = 1.4)
play!(scene, Transform(f1, f2); run_time = 1.4)
```

[`Transform`](@ref) between two `Tex` pairs glyph with glyph in reading order
and cleans up collapsed subpaths. [`TransformMatchingTex`](@ref) pairs by KEY
instead, which is what you want when the terms move:

```julia
play!(scene, TransformMatchingTex(f1, f2; key_map = Dict("a" => "α")))
```

**When `TransformMatchingTex` ends the scene holds the TARGET.** Carry on with
`f2`.

For a long derivation, morph ONE `Tex` through the steps rather than building a
new mobject per line.

[`Write`](@ref) and [`Unwrite`](@ref) draw and undraw text and formulas glyph
by glyph.

## Plain text

```julia
TextMobject("stable orbit"; font = "DejaVu Sans", size = 0.6,
            t2c = Dict("orbit" => YELLOW, 1:6 => BLUE),
            t2w = Dict("stable" => :bold))
```

FreeType straight through: outlines, advances and kerning become quadratic
Béziers. No LaTeX, no SVG round trip.

`t2c` and `t2w` are applied INSIDE the constructor because that is the only
place that knows which glyph came from which character — **a space produces no
child**, so glyph number ≠ character number, and colouring by index afterwards
is a bug waiting to happen.

**A missing weight is an ERROR, not a silent fallback.** Font lookup is fuzzy
and always answers with something, so an absent `:bold` would quietly hand you
the regular face; Janim checks and complains instead.

**Complex shaping is out, on purpose.** There is no HarfBuzz here: Latin, Greek
and Cyrillic are the honest frontier. Arabic and ligature-heavy scripts are a
project of their own, declared as a concession rather than left as a bug.

The names are `TextMobject` and `MatrixMobject` because `Text` and `Matrix` are
taken in Julia, and exporting ours would force every user to qualify theirs.

## Grids

```julia
MatrixMobject([1 2; 3 4])                 # native stretchable brackets
MatrixMobject(entries; cell = Tex)
Table(entries; row_labels, col_labels, include_outer_lines = true)
```

Read them with [`get_entries`](@ref), [`get_rows`](@ref),
[`get_columns`](@ref), [`get_cell`](@ref), [`get_brackets`](@ref) and
[`get_lines`](@ref), or by the key `"(i,j)"`:

```julia
play!(scene, Indicate(m["(2,1)"]))
```

## Composition that works on a blackboard

- Title: `TextMobject(…; size = 0.6)` and `to_edge!(t, UP; buff = 0.5)`.
- Emphasis: [`SurroundingRectangle`](@ref) with `buff = 0.1` plus
  `ShowCreation`.
- Footnote: a small `TextMobject`, `next_to!(n, formula, DOWN; buff = 0.6)`,
  one `FadeIn`/`FadeOut` per step.
- Too wide: `get_width(f) > FRAME_WIDTH - 1 && set_width!(f, FRAME_WIDTH - 1)`.

## Verify the MIDDLE of a morph

Bad morphs — exploding glyphs, blobs, cancelled winding — are invisible at both
ends and obvious halfway. Render `t` in the middle of every `Transform` and
look at the png.

## Reference

[`Tex`](@ref) · [`TextMobject`](@ref) · [`config_tex!`](@ref) ·
[`TransformMatchingTex`](@ref) · [`MatrixMobject`](@ref) · [`Table`](@ref) —
in [the text reference](api_text.md) and
[the mobject reference](api_mobjects.md).
