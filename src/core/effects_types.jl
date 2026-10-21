# core/effects_types.jl — editor-style per-layer effects: the shared piece
# (the noise and the frame clock) and the eleven effects as TYPES. Their
# passes are the backend's (`backend/wgpu/compositor.jl` and
# `shaders/effects.wgsl`).
#
# THE SHARED PIECE, built once and before any effect that needs it.
# Every effect that has randomness (Glitch, Grain) or a per-frame pattern
# (Wave) hangs from exactly two things:
#
#   1. a deterministic noise source — an integer hash of (pixel, frame, seed),
#      never rand() and never a wall clock, because determinism (same code →
#      same bytes) is what scrubbing, the frame cache and the render farm are
#      built on;
#   2. a frame CLOCK: the index of the frame being composited, handed to the
#      effects that asked for it just before compositing.
#
# Why one piece and not one per effect: two effects with randomness on the
# same layer must not draw the SAME pattern. If each one invents its own hash
# they either collide (same seed → same numbers → the grain lines up with the
# glitch) or they drift apart in a way nobody can verify. Here the hash is
# one function, identical bit-for-bit to its WGSL counterpart
# (`shaders/inserts/noise.wgsl`), and the domain separation is automatic: an
# effect's noise is keyed by its TYPE NAME, so a new effect gets a
# decorrelated pattern without declaring anything.
#
# The hash is Wellons' `lowbias32` (5 ops, bias 0.17), run once per input.
# Its output has 24 significant bits, which is exactly what a Float32 holds
# without rounding — so the CPU and the GPU do not merely agree to some
# tolerance, they return THE SAME Float32.

# ── the noise, in Julia ────────────────────────────────────────────────

"GLSL's `uint(int)`: reinterpretation mod 2^32, the same on both sides."
@inline _u32(n::Integer) = n % UInt32

@inline function _hash32(x::UInt32)
    x ⊻= x >> 16
    x *= 0x7feb352d
    x ⊻= x >> 15
    x *= 0x846ca68b
    x ⊻= x >> 16
    return x
end

"""
    _noise_hash(x, y, frame, seed) -> Float32 ∈ [0,1)

The engine's ONLY source of randomness. Bit-for-bit identical to
`janim_noise` in [`NOISE_GLSL`](@ref) — the two agree pixel by pixel, with
`==` and not with a tolerance.

`x`/`y` are PIXEL indices, so the pattern re-rolls when the resolution
changes: that is what film grain does, and an effect that wants a pattern
independent of resolution has to quantise the coordinate itself.
"""
@inline function _noise_hash(x::Integer, y::Integer, frame::Integer, seed::Integer)
    h = _hash32(_u32(seed) ⊻ 0x9e3779b9)
    h = _hash32(_u32(x) + h)
    h = _hash32(_u32(y) + h)
    h = _hash32(_u32(frame) + h)
    return Float32(h >> 8) * Float32(2.0^-24)   # 24 bits: exact in Float32
end

"""
    _noise_steps(x, y, frame, seed, levels) -> Float32

The hash in STEPS: `floor(noise · levels) / levels`, with `levels` a power of
two so every level is exact in binary. Prefer this over the raw hash for
anything that multiplies a colour, and keep `levels` small.

Why: a continuous factor over a colour puts a fraction of the pixels closer
than one half-float ULP to the 8-bit rounding edge, and in a video those
pixels are where a ±1 instability in the compositor becomes visible. Few,
widely spaced levels give that instability less to bite on.

**It is a mitigation, not a fix, and it was measured as such**: with 8 levels
six processes produced identical mp4s and with 16 they did not, which is the
signature of a lottery over where each level lands, not of a property. The
instability itself lives in the compositor.
"""
@inline function _noise_steps(x::Integer, y::Integer, frame::Integer,
                              seed::Integer, levels::Integer)
    L = Float32(max(Int(levels), 1))
    return floor(_noise_hash(x, y, frame, seed) * L) / L
end

"""
    _frame_step(frame, every) -> Int

The frame clock quantised: `every` = how many FRAMES a pattern is held for.
A glitch that re-rolls every frame reads as television snow, not as a glitch.
Truncating division, the same as GLSL's `/` on ints (frame indices are ≥ 0).
"""
@inline _frame_step(frame::Integer, every::Integer) = div(Int(frame), max(Int(every), 1))

"FNV-1a over the bytes: stable across sessions and versions (objectid is not)."
function _fnv1a(s::AbstractString)
    h = 0x811c9dc5
    for b in codeunits(s)
        h = (h ⊻ UInt32(b)) * 0x01000193
    end
    return h
end

"""
    _noise_seed(ef, seed) -> Int32

The seed an effect actually hands to its shader: the user's seed mixed with a
DOMAIN derived from the effect's type name. That is what makes
`Glitch(seed=1)` and `Grain(seed=1)` on the same layer produce
uncorrelated patterns, and neither of them had to think about it.

It costs one small allocation per effect per frame (the type's name), which
is nothing next to a fullscreen pass, and it buys a rule nobody can forget.
"""
_noise_seed(ef, seed::Integer) =
    reinterpret(Int32, _hash32(_fnv1a(String(nameof(typeof(ef)))) ⊻
                               (_u32(seed) * 0x9e3779b9)))

# ── the frame clock ────────────────────────────────────────────────────

"""
    _tick!(x, frame)

Pre-pass, the sibling of [`_focus!`](@ref): hands the index of the frame
being composited to every effect that asked for it.

**The contract**: an effect that needs the frame declares a field
`current_frame::Int`. That field IS the declaration — there is no registry to
keep in sync, and an effect without it is not touched.

The index is the SCENE's frame counter, not a counter local to whatever is
being rendered. That is the whole point: a video can be rendered in segments
across processes and loose frames are cached, so a pattern keyed to a local
counter would visibly re-roll at every segment seam and
`render_frame(construct, t)` would disagree with the video it is supposed to
be inspecting.
"""
function _tick!(ef, frame::Int)
    hasfield(typeof(ef), :current_frame) || return ef
    ismutable(ef) || throw(ArgumentError(
        "$(typeof(ef)) declares `current_frame` but is not a `mutable struct` — " *
        "an effect is mutable both to receive the clock and to be animated"))
    setproperty!(ef, :current_frame, frame)
    return ef
end

function _tick!(layer::Layer, frame::Int)
    layer.content isa Composition && _tick!(layer.content, frame)
    for ef in layer.effects
        _tick!(ef, frame)
    end
    return layer
end

function _tick!(comp::Composition, frame::Int)
    for layer in comp.layers
        _tick!(layer, frame)
    end
    return comp
end

# ── Glitch ──────────────────────────────────────────────────────

"""
    Glitch(; intensity=0.5, seed=1, rate=3, rgb_shift=0.05, slices=12, block=0.3)

Per-layer digital glitch: three ingredients over one pass — horizontal bands
displaced, a few blocks jumping harder, and the RGB channels pulled apart.

- `intensity` — the master dial. **0 is an exact no-op**: the pass is skipped
  entirely, so the layer comes out bit for bit as it went in.
- `rate` — how many FRAMES the pattern is held for. Re-rolling it every frame
  reads as television snow; 2–4 reads as a glitch.
- `rgb_shift`, `block` — in SCENE UNITS, so the effect looks the same at 480p
  and at 1080p (as `Blur`'s σ does). The defaults were MEASURED, not guessed:
  0.01 and 0.04 come out as 0.34 px and 1.35 px at 480p — an invisible
  separation and one-pixel "blocks" that read as salt-and-pepper. The
  defaults give ~1.7 px and ~10 px there.
- `seed` — the pattern. It is mixed with this type's name before reaching the
  shader, so a `Glitch(seed=1)` and a `Grain(seed=1)` on the same layer do not
  draw the same numbers.

Mutable, therefore animatable: drive `intensity` from an updater and the
glitch swells and dies. Deterministic by construction — the randomness is a
hash of (pixel, frame, seed), never `rand()`, so two renders agree byte for
byte (with `strict_gl()` on).
"""
mutable struct Glitch
    intensity::Float64
    seed::Int
    rate::Int
    rgb_shift::Float64      # scene units
    slices::Int
    block::Float64          # scene units
    current_frame::Int      # ← the frame clock fills this in
end
Glitch(; intensity::Real = 0.5, seed::Integer = 1, rate::Integer = 3,
       rgb_shift::Real = 0.05, slices::Integer = 12, block::Real = 0.3) =
    Glitch(Float64(intensity), Int(seed), Int(rate), Float64(rgb_shift),
           Int(slices), Float64(block), 0)

"""
    CRT(; intensity=1.0, scanlines=240, scan_depth=0.35, mask=0.3,
          curvature=0.15, vignette=0.35, roll=0.0)

Cathode-ray television: barrel curvature, scanlines, an aperture-grille mask
and a vignette, in one pass.

- `scanlines` — how many visible lines fit in the frame height. The shader
  puts EXACTLY that many minima there.
- `mask` — depth of the aperture grille: a 3-pixel RGB stripe, the period of
  a real shadow mask.
- `curvature` — barrel distortion; what falls outside the tube is transparent,
  not black, so the layer below still shows through.
- `roll` — vertical offset with a dark sync bar at the seam. **This is the
  "television losing sync"**: animate it from an updater and the picture rolls.
  No internal clock is needed, so `CRT` does not declare `current_frame` —
  a good illustration that `_tick!` only touches what asks for it.
- `intensity` — master dial; **0 is an exact no-op** (the pass is skipped).

Sizes that are geometric (`curvature`, `roll`) are fractions of the frame, and
`scanlines` is a count, because that is how a television is specified — not in
scene units like a blur radius.
"""
mutable struct CRT
    intensity::Float64
    scanlines::Float64
    scan_depth::Float64
    mask::Float64
    curvature::Float64
    vignette::Float64
    roll::Float64
end
CRT(; intensity::Real = 1.0, scanlines::Real = 240, scan_depth::Real = 0.35,
    mask::Real = 0.3, curvature::Real = 0.15, vignette::Real = 0.35,
    roll::Real = 0.0) =
    CRT(Float64(intensity), Float64(scanlines), Float64(scan_depth),
        Float64(mask), Float64(curvature), Float64(vignette), Float64(roll))

"""
    VHS(; intensity=0.5, seed=1, rate=2, chroma_bleed=0.15, jitter=0.04,
          noise=0.12, head_switch=0.08)

Video tape: per-LINE horizontal jitter, chroma smearing, tape noise, and the
torn band at the bottom of the picture where the head switches.

- `chroma_bleed`, `jitter` — in SCENE UNITS, and their defaults were MEASURED
  rather than guessed: 0.06 and 0.004 come out as 2 px and **0.13 px** at
  480p, i.e. an invisible wobble. The defaults give ~5 px and ~1.4 px there,
  and scale up with the resolution.
- `head_switch` — height of the torn band as a fraction of the frame; the tear
  starts exactly at that row.
- `rate` — frames the pattern is held for (the frame clock).
- `intensity` — master dial; **0 is an exact no-op**.

The chroma smear keeps each pixel's OWN luma and takes only the neighbours'
colour, which is what a tape does — and it means that over a **greyscale**
image the smear changes nothing at all, exactly.
"""
mutable struct VHS
    intensity::Float64
    seed::Int
    rate::Int
    chroma_bleed::Float64   # scene units
    jitter::Float64         # scene units
    noise::Float64
    head_switch::Float64    # fraction of the height
    current_frame::Int      # ← the frame clock
end
VHS(; intensity::Real = 0.5, seed::Integer = 1, rate::Integer = 2,
    chroma_bleed::Real = 0.15, jitter::Real = 0.04, noise::Real = 0.12,
    head_switch::Real = 0.08) =
    VHS(Float64(intensity), Int(seed), Int(rate), Float64(chroma_bleed),
        Float64(jitter), Float64(noise), Float64(head_switch), 0)

"""
    ColorAdjust(; brightness=1.0, contrast=1.0, saturation=1.0, hue=0.0)

The colour corrector of any editor, as ONE struct with four dials rather than
four structs: they are always used together and each one alone would pay for
its own fullscreen pass.

- `brightness` multiplies, `contrast` pivots about 0.5, `saturation` mixes
  towards the luma, `hue` rotates in radians about the grey axis (Rodrigues),
  which leaves greys exactly where they are and is exactly periodic in 2π.
- All four at their identity value → the pass is skipped, bit for bit.
"""
mutable struct ColorAdjust
    brightness::Float64
    contrast::Float64
    saturation::Float64
    hue::Float64
end
ColorAdjust(; brightness::Real = 1.0, contrast::Real = 1.0,
            saturation::Real = 1.0, hue::Real = 0.0) =
    ColorAdjust(Float64(brightness), Float64(contrast), Float64(saturation),
                Float64(hue))

"""
    Pixelate(size=0.2)

Mosaic: every cell takes the colour of its CENTRE, so a cell is exactly one
colour and the number of distinct colours across a row is ⌈width/cell⌉.
`size` is in scene units — the "zoom until you see the pixels" of a teaching
video looks the same at any resolution.
"""
mutable struct Pixelate
    size::Float64
end
Pixelate(size::Real = 0.2) = Pixelate(Float64(size))

"""
    Vignette(; amount=0.5, radius=0.5, feather=0.4)

Darken towards the edges. `radius` is where the darkening starts and `feather`
how far it takes to reach `amount`, both as fractions of the half-diagonal —
so the centre is untouched exactly and the corner falls by exactly `amount`.
"""
mutable struct Vignette
    amount::Float64
    radius::Float64
    feather::Float64
end
Vignette(; amount::Real = 0.5, radius::Real = 0.5, feather::Real = 0.4) =
    Vignette(Float64(amount), Float64(radius), Float64(feather))

"""
    Grain(; amount=0.15, seed=1, rate=1, levels=8)

Film grain, straight off the shared noise. `levels` quantises the factor to exact
binary steps — see `_noise_steps` for why a continuous factor over a colour is
the thing that costs byte-for-byte reproducibility.
"""
mutable struct Grain
    amount::Float64
    seed::Int
    rate::Int
    levels::Int
    current_frame::Int
end
Grain(; amount::Real = 0.15, seed::Integer = 1, rate::Integer = 1,
      levels::Integer = 8) =
    Grain(Float64(amount), Int(seed), Int(rate), Int(levels), 0)

"""
    ChromaticAberration(amount=0.1)

The clean cousin of `Glitch`'s RGB split: RADIAL separation, zero at the
centre and growing with the distance to it, like a real lens. `amount` is in
scene units and is the separation AT THE CORNER — measured, not guessed:
0.05 puts 1.1 px there at 320p and nothing at all near the middle.
"""
mutable struct ChromaticAberration
    amount::Float64
end
ChromaticAberration(amount::Real = 0.1) = ChromaticAberration(Float64(amount))

"""
    Sharpen(amount=0.6; sigma=0.05)

Unsharp mask: `src + amount·(src − blur)`, reusing `_blur_hv!` for the blur
instead of writing a second Gaussian. Over a UNIFORM region blur == src, so
the effect is the exact identity there.
`sigma` is in scene units.
"""
mutable struct Sharpen
    amount::Float64
    sigma::Float64
end
Sharpen(amount::Real = 0.6; sigma::Real = 0.05) =
    Sharpen(Float64(amount), Float64(sigma))

"""
    Wave(; amplitude=0.1, wavelength=1.5, angle=0.0, phase=0.0)

Ripples, heat haze, water: the uv are displaced by a sine. `amplitude` and
`wavelength` are in SCENE UNITS; `phase` is a plain field, so animating it
from an updater is what makes the wave travel — no internal clock, no
wall time, and the wave stays as deterministic as everything else. The phase
is reduced mod 2π on its way to the shader, so `phase + 2π` is bit-for-bit
the same wave and an animation that runs for minutes does not drift.
"""
mutable struct Wave
    amplitude::Float64
    wavelength::Float64
    angle::Float64
    phase::Float64
end
Wave(; amplitude::Real = 0.1, wavelength::Real = 1.5, angle::Real = 0.0,
     phase::Real = 0.0) =
    Wave(Float64(amplitude), Float64(wavelength), Float64(angle), Float64(phase))

"""
    EdgeDetect(; amount=1.0, color=nothing, thickness=1.0)

Sobel over luma: the silhouette of whatever is on the layer. With
`color=nothing` the edges keep the original colour; give it a colour and the
layer becomes a line drawing on transparency — the pedagogical use, showing
the outline of a shape.
"""
mutable struct EdgeDetect
    amount::Float64
    color::Any
    thickness::Float64
end
EdgeDetect(; amount::Real = 1.0, color = nothing, thickness::Real = 1.0) =
    EdgeDetect(Float64(amount), color, Float64(thickness))
