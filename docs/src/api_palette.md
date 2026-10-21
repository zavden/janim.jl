# Palette

The 94 exported colour names: **ManimGL 1.7.2's 70 together with Manim CE
0.20.1's 89**, at the engines' own hex values. Every one was taken by running
the engine, not by reading its documentation, and each docstring below quotes
the hex its constant really has.

[Mobjects and style](mobjects.md#The-palette) is the guided tour; this page is
the list. For how a colour is written at all, start at [`WHITE`](@ref).

## Where the two engines disagree

Janim ports ManimGL, so GL's values are the ones exported. CE departs on three
names:

| | ManimGL | Manim CE | Janim exports |
|---|---|---|---|
| [`YELLOW`](@ref) | `#FFFF00` | `#F7D96F` | `#FFFF00` |
| [`YELLOW_C`](@ref) | `#FFFF00` | `#F7D96F` | `#FFFF00` |
| [`BLUE_E`](@ref) | `#1C758A` | `#236B8E` | `#1C758A` |

CE's dark blue keeps a name — [`DARK_BLUE`](@ref), which is what CE calls it
too — and the whole CE palette survives at CE's values in `Janim.ManimCE`.

## The catalogues

Manim CE ships six named colour catalogues besides its palette, and does not
put them in `from manim import *` either. Janim keeps that shape: six
submodules, 2138 names, nothing exported.

```julia
Janim.XKCD.MUDDYGREEN        # "#657432"
using Janim.DVIPSNAMES       # or the whole catalogue, deliberately
```

```@docs
Janim.ManimCE
Janim.AS2700
Janim.BS381
Janim.DVIPSNAMES
Janim.SVGNAMES
Janim.X11
Janim.XKCD
```

Julia already answers for most of `X11` and `SVGNAMES` through Colors.jl —
`colorant"aliceblue"` works wherever a colour is taken — so those two are for
code that spells them Manim's way. `AS2700`, `BS381`, `DVIPSNAMES` and `XKCD`
have no Julia equivalent.

## The names

```@autodocs
Modules = [Janim]
Pages = ["core/palette.jl"]
Public = true
Private = false
```

## Colour space

```@autodocs
Modules = [Janim]
Pages = ["core/colorspace.jl"]
Public = true
Private = false
```
