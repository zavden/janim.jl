# core/colors.jl — colour by gradient.
#
# No engine work at all: the style is SoA BY ROW (one rgba per point), so
# "this shape fades from blue to yellow along its path" is a matter of writing
# the rows. This file is the API for that — and the colour maps, so a heat map
# does not need a table by hand.

"""
    interpolate_color(c1, c2, alpha) → Vec4f

The colour `alpha` of the way from `c1` to `c2` — manim's `interpolate_color`.
Either colour may be written any way the engine takes one: a hex `String`, a
`Colorant`, or a ready-made `Vec4f`.

```julia
interpolate_color(RED, BLUE, 0.0)      # RED
interpolate_color(RED, BLUE, 0.5)      # "#BD9BA7", the halfway mauve
```

Opacity is interpolated too, so fading a translucent colour towards an opaque
one does what it looks like. A colour written as hex or as a `Colorant` comes
in opaque; a `Vec4f` keeps the alpha it has.

**The two reference engines disagree on the formula, and Janim follows
ManimGL's**:

| α = 0.5, RED → BLUE | |
|---|---|
| ManimGL, and Janim | `#BD9BA7` |
| Manim CE | `#AA9399` |

GL interpolates the SQUARES of the three colour channels,
`sqrt(lerp(c₁², c₂², α))` (`manimlib/utils/color.py:115`), which is a cheap
stand-in for mixing in linear light and gives a midpoint that is lighter and
less muddy; CE interpolates them straight. Both [`color_gradient`](@ref) and
this function follow GL, so a ramp translated from a GL scene comes out with
GL's colours.
CE's formula is one keyword away: `interpolate_color(a, b, α; by = :channels)`
mixes the channels straight, and `by = :squares` (the default) is GL's. The
keyword is on [`color_gradient`](@ref) and [`interpolate_gradient`](@ref) too,
so a whole ramp can be CE's — which is the form a translation of a CE scene
wants.

**Opacity stays LINEAR.** The squares are a stand-in for light, and alpha is
not light: it is the fraction of the pixel the colour covers. GL never faced
the question — its `interpolate_color` has no alpha channel at all — and
squaring it would make a half-faded overlay read as 71 % covered.

`alpha` is NOT clamped, exactly as in both engines: pass 1.5 and you get an
extrapolation with channels outside 0…1, which the shader then clips.
[`interpolate_gradient`](@ref) does clamp, because there α also chooses which
pair of colours to read.

**The ends are pinned rather than computed**, and that is worth a line. The
engine's [`interpolate`](@ref) is the fused form `a + α(b - a)`, which is the
fast one and the one every animation runs on — but `a + 1(b - a)` is not
always exactly `b` in Float32 (measured: it misses on 32 of 144 palette pairs,
by up to one ulp). Manim's `(1-α)a + αb` cannot miss. Rather than slow the hot
path down for everyone, this function short-circuits `α ≤ 0` and `α ≥ 1` to
the endpoint itself, so a ramp really arrives at the colour you asked for.
"""
function interpolate_color(c1, c2, alpha::Real; by::Symbol = :squares)
    _check_mix(by)
    a, b = _as_rgba(c1), _as_rgba(c2)
    alpha <= 0 && return a
    alpha >= 1 && return b
    return _mix_color(a, b, alpha, by)
end

const _MIXES = (:squares, :channels)
"`:squares` is ManimGL's mix, `:channels` is Manim CE's. Anything else is a typo."
_check_mix(by::Symbol) = by in _MIXES || throw(ArgumentError(
    "by = :$by — a colour mixes :squares (ManimGL, the default) or " *
    ":channels (Manim CE)"))

"""
ManimGL's colour mix (`utils/color.py:115`): the three colour channels
interpolate as SQUARES and come back through a square root, the opacity
interpolates straight. The engine's own [`interpolate`](@ref) is the fused
`a + α(b − a)`, and it is what the alpha channel and every animated rgba row
still use — this one exists for the places where a colour is MIXED rather
than animated: [`interpolate_color`](@ref), [`color_gradient`](@ref) and
[`interpolate_gradient`](@ref).
"""
@inline function _mix_color(a::Vec4f, b::Vec4f, alpha::Real, by::Symbol = :squares)
    by === :channels && return interpolate(a, b, alpha)
    t = Float32(alpha)
    # the ends are PINNED for the same reason the straight lerp's are: in
    # Float32 `sqrt(a*a)` does not always give `a` back, so a ramp sample that
    # lands exactly on a reference colour would drift off it by an ulp — and
    # `color_gradient` and `interpolate_gradient` would stop agreeing bit for
    # bit on 256-sample ramps. GL computes in float64, where the round trip
    # holds, so this costs nothing in fidelity.
    t <= 0 && return a
    t >= 1 && return b
    # `fma`, not `muladd`: `muladd` lets LLVM decide whether to fuse, and it
    # decides differently per specialisation — with a `Vec4f` second colour
    # the inner product fuses, with a `String` it does not, and
    # `interpolate_color(RED, BLUE, 0.5)` would come out `3f281651` or
    # `3f281652` on its blue channel depending on the TYPE of the argument.
    # `fma` is one rounding, always, on every machine with hardware FMA and by
    # IEEE elsewhere; it is also what the render path already contracts to,
    # where the unfused `a·a + t·(b·b − a·a)` would shift rendered frames.
    rgb = sqrt.(fma.(t, fma.(b, b, .-(a .* a)), a .* a))
    return Vec4f(rgb[1], rgb[2], rgb[3], muladd(t, b[4] - a[4], a[4]))
end

"""
    interpolate_gradient(colors, alpha) → Vec4f

One colour from a ramp of any length: `alpha = 0` gives the first, `alpha = 1`
gives the last, and in between it lands inside the right pair and
[`interpolate_color`](@ref)s within it.

```julia
interpolate_gradient([RED, YELLOW, BLUE], 0.0)    # RED
interpolate_gradient([RED, YELLOW, BLUE], 0.25)   # halfway RED → YELLOW
interpolate_gradient([RED, YELLOW, BLUE], 1.0)    # BLUE
interpolate_gradient(:viridis, 0.7)               # a colour map works too
```

This is [`color_gradient`](@ref) asked one α at a time instead of `n` at once,
and the two share their core: for `n ≥ 2`,
`color_gradient(cs, n)` and `interpolate_gradient.(Ref(cs), range(0, 1; length = n))`
agree element for element. Reach for this one when α comes from somewhere
else: a [`ValueTracker`](@ref), a normalised speed, the height of a bar.

The reference colours are spaced EVENLY: with three of them the middle one
sits at α = 0.5 whatever the colours are. `alpha` is clamped to 0…1, since
outside that range there is no pair to read.

Two small print items, both measured:

  * **`α = 1` returns the last colour EXACTLY**, and `α = 0` the first. The
    ends are short-circuited for the reason [`interpolate_color`](@ref)
    explains — the engine's fused lerp can miss an endpoint by an ulp.
    [`color_gradient`](@ref) does NOT do this: it reproduces manim's
    arithmetic including that rounding, so that it matches it bit for bit.
    So the two can differ on the LAST element of a ramp, by
    up to one Float32 ulp (3e-8 measured, ~1e-5 of a byte — it has never
    changed a pixel).
  * `range(0, 1; length = 1)` throws in Julia, which is why the agreement
    above is stated for `n ≥ 2`. `interpolate_gradient(cs, α)` itself is happy
    with a single reference colour: it returns it for every α.

**Neither ManimGL nor Manim CE has this function** — CE declares
`ManimColor.gradient` and leaves it unimplemented, pointing at
`color_gradient`. The name is Janim's, chosen to sit next to
[`interpolate_color`](@ref).
"""
function interpolate_gradient(colors, alpha::Real; by::Symbol = :squares)
    _check_mix(by)
    cols = _expand_colors(colors)
    isempty(cols) && throw(ArgumentError("interpolate_gradient needs at least one colour"))
    alpha <= 0 && return @inbounds cols[1]
    alpha >= 1 && return @inbounds cols[end]
    pos = Float64(alpha) * (length(cols) - 1)
    i = floor(Int, pos) + 1
    return @inbounds interpolate_color(cols[i], cols[i+1], Float32(pos - (i - 1)); by)
end

"""
    color_gradient(colors, n) → Vector{Vec4f}

`n` colours interpolated through the given reference colours (manim's
`color_gradient`). One reference colour repeats; `n = 0` gives an empty list.

```julia
color_gradient([RED, BLUE], 5)      # the ramp, five steps
color_gradient(:viridis, 256)       # a colour map, resampled
```

For a single α instead of the whole ramp, [`interpolate_gradient`](@ref). The
two agree element for element for `n ≥ 2`, save for the LAST one, where this
function keeps manim's arithmetic bit for bit
and the other pins the endpoint exactly. One Float32 ulp apart at most.
"""
function color_gradient(colors, n::Integer; by::Symbol = :squares)
    _check_mix(by)
    cols = _expand_colors(colors)
    isempty(cols) && throw(ArgumentError("color_gradient needs at least one colour"))
    n <= 0 && return Vec4f[]
    (n == 1 || length(cols) == 1) && return fill(cols[1], n)
    last_i = length(cols) - 1
    # manim's alphas: linspace(0, len-1, n). The arithmetic is written HERE, in
    # this order, and not as `(α of range) * last_i`: the two differ in the last
    # bit and this one is the order that reproduces manim's result.
    return @inbounds [_gradient_at(cols, (k - 1) * last_i / (n - 1), by) for k in 1:n]
end

# it goes through `interpolate_color` and not straight to `_mix_color` so that
# this and `interpolate_gradient` are ONE code path: with `muladd` the compiler
# may contract to an FMA in one inlining context and not in another, and the
# two functions would drift by an ulp on some samples of a 256-sample ramp.
# The contraction is explicit (`fma`), so the one code path is belt and the
# arithmetic is braces.
"""
The shared core of the two gradient functions: `pos` already lives in
`0 … length(cols)-1`, so this only has to pick the pair and lerp.

`pos >= last_i` is the end of the ramp, and it needs its own branch — the
generic one would index `cols[last_i + 2]`. It is also what pins the last
colour so the gradient really ARRIVES instead of stopping a rounding short.
"""
@inline function _gradient_at(cols::Vector{Vec4f}, pos::Real, by::Symbol = :squares)
    last_i = length(cols) - 1
    if pos >= last_i
        return @inbounds interpolate_color(cols[last_i], cols[last_i+1], 1.0f0; by)
    end
    i = floor(Int, pos) + 1
    return @inbounds interpolate_color(cols[i], cols[i+1], Float32(pos - (i - 1)); by)
end

"""
One colour as the `Vec4f` the engine works in. A `Vec4f` keeps the alpha it
already carries; hex and `Colorant`s have none to keep, so they come in opaque.
This is the single place that answers "how is a colour read", and
`_expand_colors` goes through it so the two can never drift.
"""
_as_rgba(c::Vec4f) = c
_as_rgba(c) = _rgba(c, 1)

"Accept colours as names, Colorants, Vec4f or a colour-map symbol."
_expand_colors(c::Symbol) = colormap_colors(c)
_expand_colors(c::Vec4f) = Vec4f[_as_rgba(c)]
_expand_colors(c::AbstractString) = Vec4f[_as_rgba(c)]
_expand_colors(c::Colorant) = Vec4f[_as_rgba(c)]     # `colorant"tomato"` — the
                                                     # rest of the API took these
                                                     # all along and this did not
function _expand_colors(cs)
    out = Vec4f[]
    for c in cs
        append!(out, _expand_colors(c))
    end
    return out
end

# ── colour maps ───────────────────────────────────────────────────────────
# Eleven anchors sampled from matplotlib's own 256-entry tables (BSD, public
# data): interpolating them reproduces the map to well under a JND, and the
# alternative — a new dependency for four arrays — is not worth it at release
# time. `Colors.colormap` (already a dependency) covers the ColorBrewer names.

const COLORMAPS = Dict{Symbol,Vector{String}}(
    :viridis => ["#440154", "#482475", "#414487", "#355f8d", "#2a788e",
                 "#21918c", "#22a884", "#43bf71", "#7ad151", "#bddf26", "#fde725"],
    :magma   => ["#000004", "#100b2d", "#2c115f", "#51127c", "#721f81",
                 "#932b80", "#b73779", "#d8456c", "#f1605d", "#fc9366", "#fcfdbf"],
    :plasma  => ["#0d0887", "#3a049a", "#5c01a6", "#7e03a8", "#9c179e",
                 "#b52f8c", "#cc4778", "#de5f65", "#ed7953", "#f89540", "#f0f921"],
    :inferno => ["#000004", "#110a30", "#320a5e", "#57157e", "#781c6d",
                 "#9a2865", "#bc3754", "#d84c3e", "#ed6925", "#fb9b06", "#fcffa4"],
)

"""
    colormap_colors(name; n=nothing) → Vector{Vec4f}

The anchors of a colour map (`:viridis`, `:magma`, `:plasma`, `:inferno`), or
`n` colours sampled from it. Any other symbol is looked up in `Colors.colormap`
(`:Blues`, `:RdBu`…), which comes with the Colors dependency.
"""
function colormap_colors(name::Symbol; n = nothing)
    cols = if haskey(COLORMAPS, name)
        Vec4f[_rgba(h, 1) for h in COLORMAPS[name]]
    else
        try
            Vec4f[_rgba(c, 1) for c in Colors.colormap(String(name), 32)]
        catch
            throw(ArgumentError(
                "unknown colour map :$name — built in: " *
                join(sort(String.(collect(keys(COLORMAPS)))), ", ") *
                "; the rest go through Colors.colormap (:Blues, :RdBu, :Greens…)"))
        end
    end
    return n === nothing ? cols : color_gradient(cols, n)
end

# ── painting with a gradient ──────────────────────────────────────────────

"Write one gradient across a row vector, keeping every alpha untouched."
function _paint_rows!(rows::Vector{Vec4f}, cols::Vector{Vec4f}, keep_alpha::Bool)
    isempty(rows) && return rows
    grad = color_gradient(cols, length(rows))
    @inbounds for i in eachindex(rows)
        a = keep_alpha ? rows[i][4] : grad[i][4]
        rows[i] = Vec4f(grad[i][1], grad[i][2], grad[i][3], a)
    end
    return rows
end

"The members of the family that actually carry ink."
_inked_members(m::VMobject) =
    VMobject[s for s in get_family(m) if s isa VMobject && has_points(s)]

"""
    set_fill_by_gradient!(m, colors...)

Paint the FILL with a gradient. On a mobject with points the gradient runs
along its own points (one shape, many colours); on a parent without points —
a `Tex`, a `VGroup` — it runs across the CHILDREN, one colour each, which is
what manim does and what you want for a formula.

Opacities are left exactly as they were: this changes colour, not visibility.
"""
function set_fill_by_gradient!(m::VMobject, colors...)
    cols = _expand_colors(colors)
    if has_points(m)
        _paint_rows!(m.fill_rgba, cols, true)
        m.default_fill_rgba = Vec4f(cols[end][1], cols[end][2], cols[end][3],
                                    m.default_fill_rgba[4])
    else
        kids = _inked_members(m)
        each = color_gradient(cols, max(length(kids), 1))
        for (k, c) in zip(kids, each)
            set_fill!(k; color = c, recurse = false)
        end
    end
    return m
end

"`set_fill_by_gradient!`'s counterpart for the stroke."
function set_stroke_by_gradient!(m::VMobject, colors...)
    cols = _expand_colors(colors)
    if has_points(m)
        _paint_rows!(m.stroke_rgba, cols, true)
        m.default_stroke_rgba = Vec4f(cols[end][1], cols[end][2], cols[end][3],
                                      m.default_stroke_rgba[4])
    else
        kids = _inked_members(m)
        each = color_gradient(cols, max(length(kids), 1))
        for (k, c) in zip(kids, each)
            set_stroke!(k; color = c, recurse = false)
        end
    end
    return m
end

"""
    set_color_by_gradient!(m, colors...)

Fill AND stroke by gradient — the everyday one:

    set_color_by_gradient!(circle, BLUE, YELLOW)
    set_color_by_gradient!(tex, :viridis)          # a colour map by name
"""
set_color_by_gradient!(m::VMobject, colors...) =
    (set_fill_by_gradient!(m, colors...); set_stroke_by_gradient!(m, colors...); m)

# ═══════════════════════════════════════════════════════════════════════
# The conversions of `manimlib/utils/color.py` (lines 22-76)
# ═══════════════════════════════════════════════════════════════════════
#
# Eight one-liners that a Manim script reaches for constantly. `_rgba` takes a
# colour IN; these are the WAY OUT: a colour back to numbers, and numbers back
# to a hex a human reads.
#
# The rounding rule is measured, not guessed. GL's two hex writers agree on
# `int(c * 255 + 0.5 - FLOAT_ERROR)` (`colour.rgb2hex`, and `Color.get_hex_l`
# through it): 0.5 becomes 7F, not 80, because the epsilon eats the tie. Half
# a level is invisible; getting it wrong on the ROUND TRIP is not — with plain
# truncation, `rgb_to_hex(color_to_rgb(RED))` answers #FB6255, one off.

"The 0…1 rgb triple of a colour — GL's `color_to_rgb` (`color.py:22`), in Float64."
color_to_rgb(c) = (v = _as_rgba(c); (Float64(v[1]), Float64(v[2]), Float64(v[3])))

"""
    color_to_rgba(c, alpha = 1.0) → Vec4f

The colour as the engine stores it: an rgba row ready for `fill_rgba`
(`color.py:30`). `alpha` REPLACES whatever the colour carried.
"""
color_to_rgba(c, alpha::Real = 1.0) = _rgba(c, alpha)

"""
    rgb_to_color(rgb) → Vec4f

An rgb triple back to a colour, opaque (`color.py:34`). GL builds a `Color`
here; the engine's own colour value is the `Vec4f`, so that is what comes back
— and it goes straight into `set_fill!(m; color = …)`.
"""
rgb_to_color(rgb) = Vec4f(Float32(rgb[1]), Float32(rgb[2]), Float32(rgb[3]), 1f0)

"""
    rgba_to_color(rgba) → Vec4f

The colour of an rgba row, OPAQUE: GL's `rgba_to_color` slices the alpha off
(`color.py:41`), and this one keeps that — `rgba_to_color(row)` is the colour,
not the row. Pass the row itself where the alpha matters.
"""
rgba_to_color(rgba) = rgb_to_color(rgba)

"GL's rounding: `int(c·255 + 0.5 - ε)`, so 0.5 writes 7F. Clamped, unlike GL's."
_hex_level(c::Real) = floor(Int, clamp(Float64(c), 0.0, 1.0) * 255 + 0.5 - 1e-5)

"""
    rgb_to_hex(rgb) → String

An rgb triple as `"#RRGGBB"`, UPPERCASE like GL's (`color.py:44`, which forces
the long form and upper-cases it).

```julia
rgb_to_hex((0.5, 0.5, 0.5))          # "#7F7F7F"
rgb_to_hex(color_to_rgb(RED))        # "#FC6255" — the round trip is exact
```
"""
rgb_to_hex(rgb) = "#" * uppercase(string(_hex_level(rgb[1]); base = 16, pad = 2)) *
                        uppercase(string(_hex_level(rgb[2]); base = 16, pad = 2)) *
                        uppercase(string(_hex_level(rgb[3]); base = 16, pad = 2))

"""
    hex_to_rgb(hex) → NTuple{3,Float64}

`"#FC6255"` → `(0.988235, 0.384314, 0.333333)` (`color.py:48`). The inverse of
[`rgb_to_hex`](@ref); three or six digits, with or without the `#`.
"""
hex_to_rgb(hex::AbstractString) = color_to_rgb(String(hex))

"""
    color_to_hex(c) → String

Any colour as `"#RRGGBB"`, uppercase (`color.py:64`) — a hex string, a
`Colorant`, a `Vec4f` or one of the palette's names all answer. The alpha is
not part of a hex colour and is dropped.
"""
color_to_hex(c) = rgb_to_hex(color_to_rgb(c))

"""
    invert_color(c) → Vec4f

`1 - c` on each channel (`color.py:53`): `invert_color(RED)` is `#039DAA`,
`invert_color(WHITE)` is black. The alpha is not inverted (GL's does not have
one to invert).
"""
invert_color(c) = (v = _as_rgba(c); Vec4f(1f0 - v[1], 1f0 - v[2], 1f0 - v[3], v[4]))
