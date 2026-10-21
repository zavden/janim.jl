# core/palette.jl — the whole palette of BOTH reference engines.
#
# ManimGL 1.7.2 names 70 colours (manimlib/constants.py, resolved through
# default_config.yml) and Manim CE 0.20.1 names 89 (manim.utils.color.
# manim_colors). Their union is the 94 constants below, all exported, every
# hex probed by running the engines rather than read from documentation.
#
# WHERE THEY DISAGREE, GL WINS. Janim ports ManimGL, so its values are the
# engine's, and CE departs on exactly three names:
#
#     name        ManimGL      Manim CE     what Janim exports
#     BLUE_E      #1C758A      #236B8E      #1C758A   (CE's is DARK_BLUE)
#     YELLOW_C    #FFFF00      #F7D96F      #FFFF00
#     YELLOW      #FFFF00      #F7D96F      #FFFF00
#
# That is the same policy already applied to the default stroke colours, where
# CE differs on three of the four basic shapes (docs/src/from_manim.md).
#
# NOTHING IS UNREACHABLE BECAUSE OF IT. `Janim.ManimCE` holds Manim CE's 89
# colours at CE's own values, so a scene that must match CE to the byte says
# `ManimCE.YELLOW` and gets "#F7D96F". CE's other six catalogues (X11, XKCD,
# SVGNAMES, AS2700, BS381, DVIPSNAMES — 2138 names) are submodules too. Both
# live in palette_catalogs.jl, which is GENERATED from the engine.
#
# The aliases are written as aliases (`const BLUE = BLUE_C`) so a value can
# only be stated once. The one that is NOT an alias is DARK_BLUE: CE defines
# it as its own BLUE_E, and ours is GL's, so it carries the literal.

# ── how a colour is written ────────────────────────────────────────────────

"""
    WHITE

`"#FFFFFF"`.

A colour in Janim is just a `String` of hex, a `Colorant` from Colors.jl, or a
ready-made `Vec4f` — the palette holds no special type, so any hex literal is
as valid as a named constant:

```julia
set_fill!(m; color = WHITE)
set_fill!(m; color = "#D147BD")      # a colour the palette does not name
set_fill!(m; color = colorant"tomato")
```

The exported palette is the UNION of ManimGL's and Manim CE's, 94 names with
the engines' own hex values, so a scene ported from either one keeps its
colours. Where the two disagree Janim follows GL, which is what it ports;
[`YELLOW`](@ref) and [`BLUE_E`](@ref) say where, and `Janim.ManimCE` holds
CE's palette at CE's values for a scene that has to match it exactly.

Beyond the palette: [`color_gradient`](@ref) and [`colormap_colors`](@ref)
build ramps, Colors.jl answers for every CSS name through `colorant"…"`, and
Manim CE's six named catalogues are submodules — `Janim.XKCD.MUDDYGREEN`.
"""
const WHITE  = "#FFFFFF"

"""
    BLACK

`"#000000"`, and the default scene background. See [`WHITE`](@ref) for how
colours are spelled.
"""
const BLACK  = "#000000"

# ── the nine ramps ─────────────────────────────────────────────────────────
# Each family runs A (lightest) → E (darkest), and the bare name is the C.
# Manim's palette is built this way on purpose: a scene picks a family and
# uses the ramp for depth, instead of picking five unrelated colours.

"""
    BLUE_A

`"#C7E9F1"` — the lightest of the blue ramp. See [`BLUE`](@ref).
"""
const BLUE_A = "#C7E9F1"

"""
    BLUE_B

`"#9CDCEB"` — the second lightest of the blue ramp. See [`BLUE`](@ref).
"""
const BLUE_B = "#9CDCEB"

"""
    BLUE_C

`"#58C4DD"`, the middle of the blue ramp and the value of [`BLUE`](@ref).
"""
const BLUE_C = "#58C4DD"

"""
    BLUE_D

`"#29ABCA"` — the second darkest of the blue ramp. See [`BLUE`](@ref).
"""
const BLUE_D = "#29ABCA"

"""
    BLUE_E

`"#1C758A"` — the darkest of the blue ramp.

**One of the three names where the two engines disagree.** ManimGL says
`"#1C758A"` and Manim CE says `"#236B8E"`; Janim follows GL. CE's value is
[`DARK_BLUE`](@ref) here, which is also what CE itself calls it, so a scene
that wants the darker CE blue has a name for it. See [`YELLOW`](@ref) for the
other two.
"""
const BLUE_E = "#1C758A"

"""
    BLUE

`"#58C4DD"` — the blue of 3Blue1Brown, and the most used colour in the
palette. Same value as [`BLUE_C`](@ref); every family's bare name is its C.

The ramp is [`BLUE_A`](@ref), [`BLUE_B`](@ref), [`BLUE_C`](@ref),
[`BLUE_D`](@ref), [`BLUE_E`](@ref), light to dark. See [`WHITE`](@ref) for how
colours are spelled.
"""
const BLUE = BLUE_C

"""
    TEAL_A

`"#ACEAD7"` — the lightest of the teal ramp. See [`TEAL`](@ref).
"""
const TEAL_A = "#ACEAD7"

"""
    TEAL_B

`"#76DDC0"` — the second lightest of the teal ramp. See [`TEAL`](@ref).
"""
const TEAL_B = "#76DDC0"

"""
    TEAL_C

`"#5CD0B3"`, the middle of the teal ramp and the value of [`TEAL`](@ref).
"""
const TEAL_C = "#5CD0B3"

"""
    TEAL_D

`"#55C1A7"` — the second darkest of the teal ramp. See [`TEAL`](@ref).
"""
const TEAL_D = "#55C1A7"

"""
    TEAL_E

`"#49A88F"` — the darkest of the teal ramp. See [`TEAL`](@ref).
"""
const TEAL_E = "#49A88F"

"""
    TEAL

`"#5CD0B3"`, same as [`TEAL_C`](@ref). Sits between [`BLUE`](@ref) and
[`GREEN`](@ref), which is what makes it the natural third colour when two
already read as "the two things being compared".
"""
const TEAL = TEAL_C

"""
    GREEN_A

`"#C9E2AE"` — the lightest of the green ramp. See [`GREEN`](@ref).
"""
const GREEN_A = "#C9E2AE"

"""
    GREEN_B

`"#A6CF8C"` — the second lightest of the green ramp. See [`GREEN`](@ref).
"""
const GREEN_B = "#A6CF8C"

"""
    GREEN_C

`"#83C167"`, the middle of the green ramp and the value of [`GREEN`](@ref).
"""
const GREEN_C = "#83C167"

"""
    GREEN_D

`"#77B05D"` — the second darkest of the green ramp. See [`GREEN`](@ref).
"""
const GREEN_D = "#77B05D"

"""
    GREEN_E

`"#699C52"` — the darkest of the green ramp. See [`GREEN`](@ref).
"""
const GREEN_E = "#699C52"

"""
    GREEN

`"#83C167"`, same as [`GREEN_C`](@ref) — a muted, slightly olive green rather
than a pure one. For the pure channel there is [`PURE_GREEN`](@ref), and for
chroma-keying [`GREEN_SCREEN`](@ref).
"""
const GREEN = GREEN_C

"""
    YELLOW_A

`"#FFF1B6"` — the lightest of the yellow ramp. See [`YELLOW`](@ref).
"""
const YELLOW_A = "#FFF1B6"

"""
    YELLOW_B

`"#FFEA94"` — the second lightest of the yellow ramp. See [`YELLOW`](@ref).
"""
const YELLOW_B = "#FFEA94"

"""
    YELLOW_C

`"#FFFF00"`, the value of [`YELLOW`](@ref).

**One of the three names where the two engines disagree**: Manim CE says
`"#F7D96F"`, a soft gold that continues the ramp, while ManimGL jumps to pure
yellow. Janim follows GL. `Janim.ManimCE.YELLOW_C` is CE's value.
"""
const YELLOW_C = "#FFFF00"

"""
    YELLOW_D

`"#F4D345"` — the second darkest of the yellow ramp. See [`YELLOW`](@ref).
"""
const YELLOW_D = "#F4D345"

"""
    YELLOW_E

`"#E8C11C"` — the darkest of the yellow ramp. See [`YELLOW`](@ref).
"""
const YELLOW_E = "#E8C11C"

"""
    YELLOW

`"#FFFF00"`, same as [`YELLOW_C`](@ref) — pure yellow, and therefore the same
value as [`PURE_YELLOW`](@ref).

**The most visible of the three engine disagreements.** Manim CE's `YELLOW` is
`"#F7D96F"`, a soft gold that continues its own A→E ramp; ManimGL's is pure
`"#FFFF00"`, which breaks the ramp on purpose because it is the highlight
colour. Janim ports GL, so a CE scene rendered here comes out brighter and
more saturated in its yellows than it did in CE.

If a scene has to match CE exactly, `Janim.ManimCE.YELLOW` is `"#F7D96F"`. The
other two divergences are [`YELLOW_C`](@ref) (the same one) and
[`BLUE_E`](@ref).
"""
const YELLOW = YELLOW_C

"""
    GOLD_A

`"#F7C797"` — the lightest of the gold ramp. See [`GOLD`](@ref).
"""
const GOLD_A = "#F7C797"

"""
    GOLD_B

`"#F9B775"` — the second lightest of the gold ramp. See [`GOLD`](@ref).
"""
const GOLD_B = "#F9B775"

"""
    GOLD_C

`"#F0AC5F"`, the middle of the gold ramp and the value of [`GOLD`](@ref).
"""
const GOLD_C = "#F0AC5F"

"""
    GOLD_D

`"#E1A158"` — the second darkest of the gold ramp. See [`GOLD`](@ref).
"""
const GOLD_D = "#E1A158"

"""
    GOLD_E

`"#C78D46"` — the darkest of the gold ramp. See [`GOLD`](@ref).
"""
const GOLD_E = "#C78D46"

"""
    GOLD

`"#F0AC5F"`, same as [`GOLD_C`](@ref). The warm side of [`YELLOW`](@ref), and
what CE's `YELLOW` is close to — which is why a CE scene ported here often
wants `GOLD` where it said `YELLOW`.
"""
const GOLD = GOLD_C

"""
    RED_A

`"#F7A1A3"` — the lightest of the red ramp. See [`RED`](@ref).
"""
const RED_A = "#F7A1A3"

"""
    RED_B

`"#FF8080"` — the second lightest of the red ramp. See [`RED`](@ref).
"""
const RED_B = "#FF8080"

"""
    RED_C

`"#FC6255"`, the middle of the red ramp and the value of [`RED`](@ref).
"""
const RED_C = "#FC6255"

"""
    RED_D

`"#E65A4C"` — the second darkest of the red ramp. See [`RED`](@ref).
"""
const RED_D = "#E65A4C"

"""
    RED_E

`"#CF5044"` — the darkest of the red ramp. See [`RED`](@ref).
"""
const RED_E = "#CF5044"

"""
    RED

`"#FC6255"`, same as [`RED_C`](@ref) — a warm coral rather than a pure red,
and the default stroke of [`Circle`](@ref). For the pure channel there is
[`PURE_RED`](@ref).

Comparing a rendered pixel against `(1, 0, 0)` is how a correct render fails a
careless test; compare against this value.
"""
const RED = RED_C

"""
    MAROON_A

`"#ECABC1"` — the lightest of the maroon ramp. See [`MAROON`](@ref).
"""
const MAROON_A = "#ECABC1"

"""
    MAROON_B

`"#EC92AB"` — the second lightest of the maroon ramp. See [`MAROON`](@ref).
"""
const MAROON_B = "#EC92AB"

"""
    MAROON_C

`"#C55F73"`, the middle of the maroon ramp and the value of [`MAROON`](@ref).
"""
const MAROON_C = "#C55F73"

"""
    MAROON_D

`"#A24D61"` — the second darkest of the maroon ramp. See [`MAROON`](@ref).
"""
const MAROON_D = "#A24D61"

"""
    MAROON_E

`"#94424F"` — the darkest of the maroon ramp. See [`MAROON`](@ref).
"""
const MAROON_E = "#94424F"

"""
    MAROON

`"#C55F73"`, same as [`MAROON_C`](@ref). Reads as a desaturated red, which is
what makes it usable next to [`RED`](@ref) without the two fighting.
"""
const MAROON = MAROON_C

"""
    PURPLE_A

`"#CAA3E8"` — the lightest of the purple ramp. See [`PURPLE`](@ref).
"""
const PURPLE_A = "#CAA3E8"

"""
    PURPLE_B

`"#B189C6"` — the second lightest of the purple ramp. See [`PURPLE`](@ref).
"""
const PURPLE_B = "#B189C6"

"""
    PURPLE_C

`"#9A72AC"`, the middle of the purple ramp and the value of [`PURPLE`](@ref).
"""
const PURPLE_C = "#9A72AC"

"""
    PURPLE_D

`"#715582"` — the second darkest of the purple ramp. See [`PURPLE`](@ref).
"""
const PURPLE_D = "#715582"

"""
    PURPLE_E

`"#644172"` — the darkest of the purple ramp. See [`PURPLE`](@ref).
"""
const PURPLE_E = "#644172"

"""
    PURPLE

`"#9A72AC"`, same as [`PURPLE_C`](@ref).
"""
const PURPLE = PURPLE_C

# ── the greys ──────────────────────────────────────────────────────────────

"""
    GREY_A

`"#DDDDDD"`, the lightest of the grey ramp — and the default stroke colour of
every shape that does not name one ([`Square`](@ref), [`Rectangle`](@ref),
[`Triangle`](@ref), [`Polygon`](@ref)).

Manim CE paints those white and its `Triangle` blue; Janim follows ManimGL,
which is what it ports. Also spelled [`GRAY_A`](@ref) and
[`LIGHTER_GREY`](@ref). See [`WHITE`](@ref).
"""
const GREY_A = "#DDDDDD"

"""
    GREY_B

`"#BBBBBB"` — the second lightest of the grey ramp. Also [`GRAY_B`](@ref) and
[`LIGHT_GREY`](@ref). See [`GREY_A`](@ref).
"""
const GREY_B = "#BBBBBB"

"""
    GREY_C

`"#888888"`, the middle of the grey ramp — and the default FILL colour of a
[`VMobject`](@ref), which is why a shape you never styled is a grey outline
around a transparent middle (the fill is there, at opacity 0).

Also [`GRAY_C`](@ref) and [`GREY`](@ref). See [`GREY_A`](@ref).
"""
const GREY_C = "#888888"

"""
    GREY_D

`"#444444"` — the second darkest of the grey ramp. Also [`GRAY_D`](@ref) and
[`DARK_GREY`](@ref). See [`GREY_A`](@ref).
"""
const GREY_D = "#444444"

"""
    GREY_E

`"#222222"` — the darkest of the grey ramp, and still not black: it reads as a
shadow on a [`BLACK`](@ref) background rather than as a hole. Also
[`GRAY_E`](@ref) and [`DARKER_GREY`](@ref). See [`GREY_A`](@ref).
"""
const GREY_E = "#222222"

"""
    GREY

`"#888888"`, same as [`GREY_C`](@ref). Also spelled [`GRAY`](@ref).
"""
const GREY = GREY_C

# The American spellings. Manim CE carries both because its users write both;
# they are the SAME constants, aliased, not a second set of values.

"""
    GRAY_A

The American spelling of [`GREY_A`](@ref), `"#DDDDDD"`. Manim CE ships both
spellings for every grey; Janim does the same so scenes written for either engine need no editing.
"""
const GRAY_A = GREY_A

"""
    GRAY_B

The American spelling of [`GREY_B`](@ref), `"#BBBBBB"`. See [`GRAY_A`](@ref).
"""
const GRAY_B = GREY_B

"""
    GRAY_C

The American spelling of [`GREY_C`](@ref), `"#888888"`. See [`GRAY_A`](@ref).
"""
const GRAY_C = GREY_C

"""
    GRAY_D

The American spelling of [`GREY_D`](@ref), `"#444444"`. See [`GRAY_A`](@ref).
"""
const GRAY_D = GREY_D

"""
    GRAY_E

The American spelling of [`GREY_E`](@ref), `"#222222"`. See [`GRAY_A`](@ref).
"""
const GRAY_E = GREY_E

"""
    GRAY

The American spelling of [`GREY`](@ref), `"#888888"`. See [`GRAY_A`](@ref).
"""
const GRAY = GREY

"""
    LIGHTER_GREY

`"#DDDDDD"` — Manim CE's descriptive name for [`GREY_A`](@ref). Also
[`LIGHTER_GRAY`](@ref).
"""
const LIGHTER_GREY = GREY_A

"""
    LIGHTER_GRAY

The American spelling of [`LIGHTER_GREY`](@ref), `"#DDDDDD"`.
"""
const LIGHTER_GRAY = GREY_A

"""
    LIGHT_GREY

`"#BBBBBB"` — Manim CE's descriptive name for [`GREY_B`](@ref). Also
[`LIGHT_GRAY`](@ref).
"""
const LIGHT_GREY = GREY_B

"""
    LIGHT_GRAY

The American spelling of [`LIGHT_GREY`](@ref), `"#BBBBBB"`.
"""
const LIGHT_GRAY = GREY_B

"""
    DARK_GREY

`"#444444"` — Manim CE's descriptive name for [`GREY_D`](@ref). Also
[`DARK_GRAY`](@ref).
"""
const DARK_GREY = GREY_D

"""
    DARK_GRAY

The American spelling of [`DARK_GREY`](@ref), `"#444444"`.
"""
const DARK_GRAY = GREY_D

"""
    DARKER_GREY

`"#222222"` — Manim CE's descriptive name for [`GREY_E`](@ref). Also
[`DARKER_GRAY`](@ref).
"""
const DARKER_GREY = GREY_E

"""
    DARKER_GRAY

The American spelling of [`DARKER_GREY`](@ref), `"#222222"`.
"""
const DARKER_GRAY = GREY_E

# ── the named colours outside the ramps ────────────────────────────────────

"""
    DARK_BLUE

`"#236B8E"` — Manim CE's dark blue, and the only palette constant here that is
NOT an alias of the value it duplicates in CE.

CE defines `DARK_BLUE` and its own `BLUE_E` as the same colour. Janim's
[`BLUE_E`](@ref) is ManimGL's `"#1C758A"`, so this one carries the literal
instead, and a CE scene keeps both of its blues.
"""
const DARK_BLUE = "#236B8E"

"""
    PINK

`"#D147BD"`. See [`WHITE`](@ref).
"""
const PINK = "#D147BD"

"""
    LIGHT_PINK

`"#DC75CD"`. See [`PINK`](@ref).
"""
const LIGHT_PINK = "#DC75CD"

"""
    ORANGE

`"#FF862F"`. Between [`GOLD`](@ref) and [`RED`](@ref), and the one warm colour
that is neither. See [`WHITE`](@ref).
"""
const ORANGE = "#FF862F"

"""
    GREY_BROWN

`"#736357"`. Also [`GRAY_BROWN`](@ref). See [`WHITE`](@ref).
"""
const GREY_BROWN = "#736357"

"""
    GRAY_BROWN

The American spelling of [`GREY_BROWN`](@ref), `"#736357"`.
"""
const GRAY_BROWN = GREY_BROWN

"""
    DARK_BROWN

`"#8B4513"` — X11's `saddlebrown`, which is where both engines took it from.
See [`WHITE`](@ref).
"""
const DARK_BROWN = "#8B4513"

"""
    LIGHT_BROWN

`"#CD853F"` — X11's `peru`. See [`DARK_BROWN`](@ref).
"""
const LIGHT_BROWN = "#CD853F"

"""
    GREEN_SCREEN

`"#00FF00"` — the chroma-key green, for a scene meant to be composited into
something else. The same value as [`PURE_GREEN`](@ref), kept as a separate
name because it says what it is for. ManimGL only.
"""
const GREEN_SCREEN = "#00FF00"

# The pure channels. Not decoration: a shader test wants a colour with exactly
# one channel lit, and every named colour in the palette is mixed.

"""
    PURE_RED

`"#FF0000"` — the red CHANNEL, not the palette's [`RED`](@ref) (`"#FC6255"`).
Useful when you need a known channel value rather than a colour that looks
good. See [`WHITE`](@ref).
"""
const PURE_RED = "#FF0000"

"""
    PURE_GREEN

`"#00FF00"` — the green channel. Not the palette's [`GREEN`](@ref). Same value
as [`GREEN_SCREEN`](@ref). See [`PURE_RED`](@ref).
"""
const PURE_GREEN = "#00FF00"

"""
    PURE_BLUE

`"#0000FF"` — the blue channel. Not the palette's [`BLUE`](@ref). See
[`PURE_RED`](@ref).
"""
const PURE_BLUE = "#0000FF"

"""
    PURE_CYAN

`"#00FFFF"` — green plus blue. Manim CE only. See [`PURE_RED`](@ref).
"""
const PURE_CYAN = "#00FFFF"

"""
    PURE_MAGENTA

`"#FF00FF"` — red plus blue. Manim CE only. See [`PURE_RED`](@ref).
"""
const PURE_MAGENTA = "#FF00FF"

"""
    PURE_YELLOW

`"#FFFF00"` — red plus green. Manim CE only.

In Janim this is the same value as [`YELLOW`](@ref), because Janim follows
ManimGL's pure-yellow `YELLOW`. In Manim CE the two differ, and that is the
clearest place to see the divergence. See [`PURE_RED`](@ref).
"""
const PURE_YELLOW = "#FFFF00"

# Manim CE's own logo. No use inside the engine; here so a translated scene compiles.

"""
    LOGO_WHITE

`"#ECE7E2"` — one of the five colours of the Manim CE logo. Manim CE only, and
of no use to the engine: the five are here so a scene that draws the logo
ports without edits. See [`WHITE`](@ref).
"""
const LOGO_WHITE = "#ECE7E2"

"""
    LOGO_GREEN

`"#87C2A5"`. See [`LOGO_WHITE`](@ref).
"""
const LOGO_GREEN = "#87C2A5"

"""
    LOGO_BLUE

`"#525893"`. See [`LOGO_WHITE`](@ref).
"""
const LOGO_BLUE = "#525893"

"""
    LOGO_RED

`"#E07A5F"`. See [`LOGO_WHITE`](@ref).
"""
const LOGO_RED = "#E07A5F"

"""
    LOGO_BLACK

`"#343434"`. See [`LOGO_WHITE`](@ref).
"""
const LOGO_BLACK = "#343434"

# ── the defaults, under the names ManimGL gives them ───────────────────────
# Two of these are the engine's real defaults and are written as aliases of
# the constants the constructors actually read. Two are not: Janim has no
# coloured light source and no colour on a bare Mobject, so they are here for
# scenes that mention them, and the docstring says so rather than implying an
# engine that consults them.

"""
    DEFAULT_VMOBJECT_STROKE_COLOR

`"#DDDDDD"` — ManimGL's name for the default stroke of a [`VMobject`](@ref),
and Janim's real default: an alias of [`GREY_A`](@ref), which is the value the
constructor reads.
"""
const DEFAULT_VMOBJECT_STROKE_COLOR = GREY_A

"""
    DEFAULT_VMOBJECT_FILL_COLOR

`"#888888"` — ManimGL's name for the default fill of a [`VMobject`](@ref), and
Janim's real default: an alias of [`GREY_C`](@ref). The fill is there from the
start, at opacity 0, which is why `set_fill!(m; opacity = 1)` alone shows grey.
"""
const DEFAULT_VMOBJECT_FILL_COLOR = GREY_C

"""
    DEFAULT_MOBJECT_COLOR

`"#FFFFFF"` — ManimGL's default colour for a plain `Mobject`.

Janim has no such default: colour lives on [`VMobject`](@ref) and on the point
clouds, each with its own, and nothing in the engine reads this constant. It
is exported so a ported GL scene that names it still runs. See [`WHITE`](@ref).
"""
const DEFAULT_MOBJECT_COLOR = WHITE

"""
    DEFAULT_LIGHT_COLOR

`"#BBBBBB"` — ManimGL's colour for its light source.

Janim's shading has no coloured light: [`set_shading!`](@ref) takes
reflectiveness, gloss and shadow, and the highlight is the surface's own
colour. Nothing in the engine reads this constant; it is exported so a ported
GL scene that names it still runs. See [`GREY_B`](@ref).
"""
const DEFAULT_LIGHT_COLOR = GREY_B
