# Engine constants: directions, angles and palette.
# Mirrors the subset of manimlib/constants.py that the core needs.

using GeometryBasics: Point3f, Vec4f, Vec2f
using Colors: RGB, Colorant, red, green, blue

# ── directions (Point3f is already the GPU layout) ──────────────────────

"""
    ORIGIN

The centre of the frame, `Point3f(0, 0, 0)`.

`move_to!(m, ORIGIN)` and [`center!`](@ref) do the same thing; the constant is
there so that a scene never has to spell a literal `(0, 0, 0)`.
"""
const ORIGIN = Point3f(0, 0, 0)

"""
    RIGHT

The unit vector towards the right edge, `Point3f(1, 0, 0)`.

Directions are ordinary points, so they scale and add like any vector:
`2 * RIGHT` is two scene units, `-RIGHT` is [`LEFT`](@ref), and `UP + RIGHT`
is [`UR`](@ref). They are the second argument of [`shift!`](@ref),
[`next_to!`](@ref), [`to_edge!`](@ref) and [`align_to!`](@ref).

Scene units, not pixels: the nominal frame is [`FRAME_WIDTH`](@ref) wide
whatever resolution you render at.
"""
const RIGHT  = Point3f(1, 0, 0)

"""
    LEFT

The unit vector towards the left edge, `Point3f(-1, 0, 0)`. See [`RIGHT`](@ref).
"""
const LEFT   = Point3f(-1, 0, 0)

"""
    UP

The unit vector towards the top edge, `Point3f(0, 1, 0)`.

Y grows upwards, as in Manim and in mathematics — not downwards as in most
screen coordinate systems. See [`RIGHT`](@ref).
"""
const UP     = Point3f(0, 1, 0)

"""
    DOWN

The unit vector towards the bottom edge, `Point3f(0, -1, 0)`. See [`UP`](@ref).
"""
const DOWN   = Point3f(0, -1, 0)

"""
    OUT

The unit vector towards the viewer, `Point3f(0, 0, 1)`.

The axis a flat scene rotates about: `rotate!(m, TAU / 4)` spins in the plane
of the screen because [`rotate!`](@ref) defaults to this axis.
"""
const OUT    = Point3f(0, 0, 1)

"""
    IN

The unit vector away from the viewer, `Point3f(0, 0, -1)`. See [`OUT`](@ref).
"""
const IN     = Point3f(0, 0, -1)

"""
    UR

Up and right, `UP + RIGHT`. The corner directions are sums, not new axes, so
they are the diagonal of the unit square and NOT of length 1.

Where they read best is [`to_corner!`](@ref) and the `aligned_edge` of
[`next_to!`](@ref).
"""
const UR = UP + RIGHT

"""
    UL

Up and left, `UP + LEFT`. See [`UR`](@ref).
"""
const UL = UP + LEFT

"""
    DR

Down and right, `DOWN + RIGHT`. See [`UR`](@ref).
"""
const DR = DOWN + RIGHT

"""
    DL

Down and left, `DOWN + LEFT`. See [`UR`](@ref).
"""
const DL = DOWN + LEFT

# ── angles ──────────────────────────────────────────────────────────────────

"""
    TAU

A full turn in radians, `2π` — the angle unit the engine narrates in.

Angles are `Float64` on purpose: geometry is COMPUTED in 64 bits and STORED in
`Float32`, the same split GL forces on you. A quarter turn is `TAU / 4`, which
says what it means better than `PI / 2` does.
"""
const TAU = 2π            # Float64: geometry is COMPUTED in 64 bits

"""
    PI

`Float64(π)`, exported for parity with Manim's `PI`.

Julia's own `π` is an `Irrational` that adapts to the precision around it;
this one is a plain `Float64`, which is what the geometry works in. Prefer
[`TAU`](@ref) when writing new scenes.
"""
const PI  = Float64(π)    # and STORED in Float32 (like GL: numpy → f32 data)

"""
    DEG

One degree in radians, `TAU / 360`.

Written as a multiplier rather than a conversion function, so an angle reads
as a quantity: `rotate!(m, 30 * DEG)`.
"""
const DEG = TAU / 360

"""
    DEGREES

ManimGL's long spelling of [`DEG`](@ref), kept because "many older animations
use the full name" (`constants.py:65`) — `rotate!(m, 30 * DEGREES)` is the form
most `.py` files carry.
"""
const DEGREES = DEG

# ── the frame and the buffs (layout.jl consumes these) ──────────────────
# Same numbers as manimlib/constants.py: the default frame is 8 units tall and
# 16/9 of that wide. `to_edge!` uses them as the screen border — like Manim,
# this is the NOMINAL frame, not the current camera's (zooming the camera does
# not move where to_edge! lands).
"""
    FRAME_HEIGHT

The height of the nominal frame in scene units: `8.0`.

Scene units are resolution-independent — 720p and 4K render the same 8 units,
with more pixels each. The frame is NOMINAL: moving or zooming the camera
([`CameraFrame`](@ref)) does not change it, which is why [`to_edge!`](@ref)
lands in the same place after a zoom.
"""
const FRAME_HEIGHT   = 8.0

"""
    FRAME_WIDTH

The width of the nominal frame in scene units: `8 · 16/9 ≈ 14.2222`.

Manim's number, so a scene ported from it lands identically. See
[`FRAME_HEIGHT`](@ref). The usual guard against overflowing the screen:

```julia
get_width(g) > FRAME_WIDTH - 1 && set_width!(g, FRAME_WIDTH - 1)
```
"""
const FRAME_WIDTH    = 8.0 * 16 / 9

"""
    FRAME_Y_RADIUS

Half of [`FRAME_HEIGHT`](@ref): the distance from the centre to the top edge,
`4.0`. The y coordinate of the top of the frame.
"""
const FRAME_Y_RADIUS = FRAME_HEIGHT / 2

"""
    FRAME_X_RADIUS

Half of [`FRAME_WIDTH`](@ref): the distance from the centre to the right edge,
`≈ 7.1111`. The x coordinate of the right of the frame.
"""
const FRAME_X_RADIUS = FRAME_WIDTH / 2

"""
    SMALL_BUFF

`0.1` scene units. The named gaps exist so that spacing is consistent across a
film instead of being re-invented per call; they are what the `buff` keyword of
[`next_to!`](@ref), [`to_edge!`](@ref) and [`arrange!`](@ref) takes.

The ladder: `SMALL_BUFF` 0.1, [`MED_SMALL_BUFF`](@ref) 0.25,
[`MED_LARGE_BUFF`](@ref) 0.5, [`LARGE_BUFF`](@ref) 1.0.
"""
const SMALL_BUFF      = 0.1

"""
    MED_SMALL_BUFF

`0.25` scene units, and the default gap BETWEEN two mobjects
([`next_to!`](@ref), [`arrange!`](@ref)). See [`SMALL_BUFF`](@ref).
"""
const MED_SMALL_BUFF  = 0.25

"""
    MED_LARGE_BUFF

`0.5` scene units, and the default gap between a mobject and the EDGE of the
frame ([`to_edge!`](@ref), [`to_corner!`](@ref)). See [`SMALL_BUFF`](@ref).
"""
const MED_LARGE_BUFF  = 0.5

"""
    LARGE_BUFF

`1.0` scene units. See [`SMALL_BUFF`](@ref).
"""
const LARGE_BUFF      = 1.0

const DEFAULT_MOBJECT_TO_EDGE_BUFF   = MED_LARGE_BUFF
const DEFAULT_MOBJECT_TO_MOBJECT_BUFF = MED_SMALL_BUFF

"""
    DEFAULT_DOT_RADIUS

`0.05` scene units — the radius a disc of a [`DotCloud`](@ref) gets, and the
value `DEFAULT_DOT_RADIUS` HAS in ManimGL once the library is imported.

This is a trap worth the paragraph. ManimGL defines this name
TWICE: `geometry.py:38` says `0.08` and `dot_cloud.py` says `0.05`, and
`from manimlib import *` imports the second over the first — so a user who
reads the constant gets `0.05` while `Dot()` still measures `0.08`, because
`geometry.py` closes over its own local. Janim does exactly that: the constant
is `0.05`, and [`Dot`](@ref)'s default radius is the literal `0.08`.
"""
const DEFAULT_DOT_RADIUS = 0.05

"""
    DEFAULT_SMALL_DOT_RADIUS

`0.04` scene units — half of a [`Dot`](@ref)'s `0.08`, and the radius a
[`SmallDot`](@ref) gets. Manim's value (`geometry.py`), measured rather than
assumed: a `SmallDot` comes out exactly half the width of a `Dot`. Only
`geometry.py` defines this one, so no import shadows it and GL exports the
same `0.04` (unlike [`DEFAULT_DOT_RADIUS`](@ref)).
"""
const DEFAULT_SMALL_DOT_RADIUS = 0.04

"""
    DEFAULT_FONT_SIZE

`48` — the size every piece of text is born at, in ManimGL's units
(`Text`/`Tex`'s `font_size`), and the meaning of `font_size` everywhere in
Janim.

It is a POINT size in name only: what it really names is GL's default, and
the routes are calibrated against it so that `Tex(s)`, `TextMobject(s)` and
`LTex(s)` come out the width ManimGL gives them. Twice this is twice as big.

The other knob, `size`, is Janim's own, and the two are mutually exclusive so
that a line of code says which system it is speaking.
"""
const DEFAULT_FONT_SIZE = 48.0

# ── palette ────────────────────────────────────────────────────────────────
# The 94 colours of ManimGL and Manim CE live in core/palette.jl; what stays
# here is the STYLE default they feed, and `_rgba`, which is what turns any of
# them into what the GPU wants.

const DEFAULT_STROKE_WIDTH = 4.0f0

# Color → Vec4f. Accepts hex ("#FC6255"), a Colorant, or a ready-made Vec4f.
_rgba(c::AbstractString, opacity) = begin
    col = parse(RGB{Float32}, c)
    Vec4f(red(col), green(col), blue(col), Float32(opacity))
end
_rgba(c::Colorant, opacity) = begin
    col = RGB{Float32}(c)
    Vec4f(red(col), green(col), blue(col), Float32(opacity))
end
_rgba(c::Vec4f, opacity) = Vec4f(c[1], c[2], c[3], Float32(opacity))
