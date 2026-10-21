# core/fields.jl — VectorField / TimeVaryingVectorField / StreamLines /
# AnimatedStreamLines, following ManimGL's `vector_field.py`: the layout, the
# widths, the colormap, the tanh clamp, the taper ramp and the integrator's
# radius envelope all match it. The design:
#
#   · ONE batched VMobject per field: 8 points per arrow (8n−1 total, the
#     interleaved anchor/handle layout Janim already speaks). The arrow HEAD
#     is a per-point stroke-width trick — [1,1,1,1,4,2,0,0]·w — and the
#     separator between arrows is a duplicated anchor with width 0, which
#     the stroke shader skips as a degenerate curve. No polygons.
#   · Long vectors clamp with tanh: drawn = L·tanh(‖v‖/L), L = 0.8·step.
#   · Colour comes from a colormap over the COORDINATE-space magnitude
#     (lengths clamp in scene space; colours don't — GL's exact split).
#   · Our integrator is a FIXED-STEP RK4 (no ODE dependency): judged
#     against the CLOSED FORM (the rotation field's solutions are circles),
#     with GL's own RK45 radius spread (0.08%) as the fairness envelope.
#   · Seed jitter and flow phases come from a COUNTER HASH (splitmix64),
#     never from a random stream: the same scene gives the same bytes in
#     any process, which is what scrubbing and the render farm run on. GL
#     uses np.random here — a deliberate divergence.

# ── the 3b1b colormap, hex for hex (GL's default_config.yml) ────────────

const _CMAP_3B1B = (
    (0x1C / 255f0, 0x75 / 255f0, 0x8A / 255f0),   # BLUE_E
    (0x83 / 255f0, 0xC1 / 255f0, 0x67 / 255f0),   # GREEN
    (0xFF / 255f0, 0xFF / 255f0, 0x00 / 255f0),   # YELLOW
    (0xFC / 255f0, 0x62 / 255f0, 0x55 / 255f0),   # RED
)

"get_colormap_from_colors: clip to [0,1], lerp between adjacent colours."
function _colormap_3b1b(v::Real)
    a = clamp(Float32(v), 0f0, 1f0) * (length(_CMAP_3B1B) - 1)
    i = min(floor(Int, a), length(_CMAP_3B1B) - 2)
    t = a - i
    lo, hi = _CMAP_3B1B[i + 1], _CMAP_3B1B[i + 2]
    return ((1 - t) * lo[1] + t * hi[1],
            (1 - t) * lo[2] + t * hi[2],
            (1 - t) * lo[3] + t * hi[3])
end

# ── deterministic jitter: splitmix64, stable across processes AND Julia
#    versions (Base.hash promises neither) ───────────────────────────────

function _splitmix64(x::UInt64)
    x += 0x9e3779b97f4a7c15
    x = (x ⊻ (x >> 30)) * 0xbf58476d1ce4e5b9
    x = (x ⊻ (x >> 27)) * 0x94d049bb133111eb
    return x ⊻ (x >> 31)
end

"A uniform in [0,1) from a counter tuple — the A2 replacement for np.random."
function _hash01(k1::Integer, k2::Integer = 0, k3::Integer = 0)
    h = _splitmix64(_splitmix64(_splitmix64(UInt64(k1) + 0x9e37) ⊻
                                UInt64(k2) * 0x85eb) ⊻ UInt64(k3) * 0xc2b2)
    return Float64(h >> 11) * 0x1p-53
end

# ── sampling the coordinate system (get_sample_coords, order included) ──

_axis_range(ax::NumberLine) = (ax.x_min, ax.x_max, ax.x_step)
_all_ranges(cs::Axes) = [_axis_range(cs.x_axis), _axis_range(cs.y_axis)]
_all_ranges(cs::NumberPlane) = _all_ranges(cs.axes)
_all_ranges(cs::ThreeDAxes) =
    [_axis_range(cs.x_axis), _axis_range(cs.y_axis), _axis_range(cs.z_axis)]

"""
GL's get_sample_coords: per axis, arange(min, max+step, step) with the step
divided by `density`; then the cartesian product with the LAST axis fastest
(itertools.product order — the dump's first samples pin it).
"""
function _sample_coords(cs, density::Real)
    axes_vals = map(_all_ranges(cs)) do (lo, hi, step)
        s = step / density
        collect(lo:s:(hi + s / 2))         # arange(lo, hi+s, s): hi included
    end
    coords = NTuple{length(axes_vals),Float64}[]
    if length(axes_vals) == 2
        for x in axes_vals[1], y in axes_vals[2]
            push!(coords, (x, y))
        end
    else
        for x in axes_vals[1], y in axes_vals[2], z in axes_vals[3]
            push!(coords, (x, y, z))
        end
    end
    return coords
end

_c2p(cs, c::NTuple{2,Float64}) = coords_to_point(cs, c[1], c[2])
_c2p(cs, c::NTuple{3,Float64}) = coords_to_point(cs, c[1], c[2], c[3])

# ── the fixed-step RK4 (ode_solution_points) ────────────────────────────

"""
    ode_solution_points(f, state0, time; dt=0.01) → Vector{NTuple{D,Float64}}

States at t = 0, dt, …, < time (GL's t_eval grid), integrated with a
fixed-step RK4. `f` is pointwise: an NTuple in, an indexable out. No
adaptive solver and no dependency: the result is judged against the CLOSED
FORM, and GL's own RK45 spread is the fairness bar.
"""
function ode_solution_points(f, state0::NTuple{D,Float64}, time::Real;
                              dt::Real = 0.01) where {D}
    n = max(ceil(Int, time / dt), 1)       # arange(0, time, dt) length
    out = Vector{NTuple{D,Float64}}(undef, n)
    s = state0
    out[1] = s
    h = Float64(dt)
    for k in 2:n
        k1 = f(s)
        k2 = f(ntuple(i -> s[i] + h / 2 * k1[i], D))
        k3 = f(ntuple(i -> s[i] + h / 2 * k2[i], D))
        k4 = f(ntuple(i -> s[i] + h * k3[i], D))
        s = ntuple(i -> s[i] + h / 6 * (k1[i] + 2k2[i] + 2k3[i] + k4[i]), D)
        out[k] = s
    end
    return out
end

# ═══════════════════════════════════════════════════════════════════════
# VectorField
# ═══════════════════════════════════════════════════════════════════════

"""
    VectorField(func, coordinate_system; density=2.0, magnitude_range=nothing,
                stroke_width=3.0, tip_width_ratio=4.0, tip_len_to_width=0.01,
                max_vect_len=nothing, max_vect_len_to_step_size=0.8,
                color=nothing)

A whole field as ONE VMobject. `func` is pointwise over COORDINATES:
`c -> (fx, fy)` (an NTuple in, an indexable out). Colours follow the
3b1b colormap over `magnitude_range` unless a flat `color` is given.
`update_vectors!(vf)` re-reads `vf.func` — mutate it (or the parameters it
closes over) from an updater and call it, or use `TimeVaryingVectorField`.
"""
mutable struct VectorField <: Mobject
    mob::VMobject
    func::Any
    coordinate_system::Any
    sample_coords::Vector
    sample_points::Vector{Point3f}
    stroke_width::Float64
    tip_width_ratio::Float64
    tip_len_to_width::Float64
    max_displayed_vect_len::Float64
    magnitude_range::Union{Nothing,Tuple{Float64,Float64}}   # nothing = flat colour
    base_width::Vector{Float32}
    time::Float64                       # driven by TimeVaryingVectorField
    parents::Vector{Mobject}            # the node contract (the arrows live in `mob`)
end
VectorField(mob, func, cs, coords, pts, sw, twr, tlw, mdl, mr, bw, time) =
    _link_wrapper!(VectorField(mob, func, cs, coords, pts, sw, twr, tlw, mdl, mr, bw,
                               time, Mobject[]))

function VectorField(func, coordinate_system;
                     density::Real = 2.0,
                     magnitude_range = nothing,
                     color = nothing,
                     stroke_width::Real = 3.0,
                     stroke_opacity::Real = 1.0,
                     tip_width_ratio::Real = 4.0,
                     tip_len_to_width::Real = 0.01,
                     max_vect_len = nothing,
                     max_vect_len_to_step_size::Real = 0.8,
                     sample_coords = nothing)
    coords = sample_coords === nothing ?
             _sample_coords(coordinate_system, density) : sample_coords
    n = length(coords)
    pts = [Point3f(_c2p(coordinate_system, c)) for c in coords]

    max_len = if max_vect_len === nothing
        Float64(max_vect_len_to_step_size) * sqrt(sum(abs2, pts[2] - pts[1]))
    else
        Float64(max_vect_len) * get_unit_size(coordinate_system.x_axis)
    end

    if magnitude_range === nothing && color === nothing
        magnitude_range = (0.0, maximum(c -> sqrt(sum(abs2, func(c))), coords))
    end

    # [1,1,1,1,4,2,0,0] per arrow, trailing separator dropped (8n−1)
    base = ones(Float32, 8n - 1)
    for k in 0:(n - 1)
        base[8k + 5] = Float32(tip_width_ratio)
        base[8k + 6] = Float32(tip_width_ratio / 2)
        base[8k + 7] = 0f0
        8k + 8 <= 8n - 1 && (base[8k + 8] = 0f0)
    end

    mob = vmob(:VectorField; stroke_color = something(color, GREY_A),
               stroke_opacity = stroke_opacity, stroke_width = stroke_width)
    set_points!(mob, zeros(Point3f, 8n - 1))

    vf = VectorField(mob, func, coordinate_system, coords, pts,
                     Float64(stroke_width), Float64(tip_width_ratio),
                     Float64(tip_len_to_width), max_len,
                     magnitude_range === nothing ? nothing :
                     (Float64(magnitude_range[1]), Float64(magnitude_range[2])),
                     base, 0.0)
    update_vectors!(vf)
    return vf
end

"""
    update_vectors!(vf)

GL's update_vectors, line for line: sample the field in COORDS, map the
outputs through the axes into scene vectors, clamp the drawn length with
tanh, lay the 8-point arrows, scale the width pattern (collapsing arrows
shorter than their head), and colour by coordinate-space magnitude.
"""
function update_vectors!(vf::VectorField)
    tip_width = vf.tip_width_ratio * vf.stroke_width
    tip_len = vf.tip_len_to_width * tip_width
    origin = Point3f(get_origin(vf.coordinate_system))
    max_len = vf.max_displayed_vect_len
    pts = vf.mob.points
    widths = vf.mob.stroke_width
    rgba = vf.mob.stroke_rgba
    lo, hi = vf.magnitude_range === nothing ? (0.0, 1.0) : vf.magnitude_range

    @inbounds for (k, c) in enumerate(vf.sample_coords)
        out = vf.func(c)
        coord_norm = sqrt(sum(i -> abs2(Float64(out[i])), eachindex(c)))
        v = Point3f(_c2p(vf.coordinate_system,
                         ntuple(i -> Float64(out[i]), length(c)))) - origin
        norm_v = sqrt(sum(abs2, v))
        unit = norm_v > 0 ? v / norm_v : zero(Point3f)
        drawn = max_len < Inf ? max_len * tanh(norm_v / max_len) : norm_v
        to_head_base = max(drawn - tip_len, 0.0)

        b = pts[8k - 7] = vf.sample_points[k]
        hb = pts[8k - 5] = b + Float32(to_head_base) * unit
        pts[8k - 3] = hb
        tip = pts[8k - 1] = b + Float32(drawn) * unit
        pts[8k - 6] = (b + hb) / 2
        pts[8k - 4] = hb
        pts[8k - 2] = (hb + tip) / 2
        8k <= length(pts) && (pts[8k] = tip)     # the separator anchor

        scalar = Float32(clamp(drawn / tip_len, 0.0, 1.0))
        w = Float32(vf.stroke_width)
        if vf.magnitude_range === nothing
            for j in (8k - 7):min(8k, length(pts))
                widths[j] = scalar * w * vf.base_width[j]
            end
        else
            r, g, bch = _colormap_3b1b((coord_norm - lo) / (hi - lo))
            for j in (8k - 7):min(8k, length(pts))
                widths[j] = scalar * w * vf.base_width[j]
                rgba[j] = Vec4f(r, g, bch, rgba[j][4])
            end
        end
    end
    _note_data_changed!(vf.mob)
    return vf
end

"""
    TimeVaryingVectorField(time_func, coordinate_system; kw...)

`time_func(coords, t)`; an updater advances `vf.time` and re-lays the
arrows every frame.
"""
function TimeVaryingVectorField(time_func, coordinate_system; kw...)
    t = Ref(0.0)      # a Ref, not the struct: the constructor already samples
    vf = VectorField(c -> time_func(c, t[]), coordinate_system; kw...)
    add_updater!(vf.mob, (m, dt) -> (t[] += dt; vf.time = t[]; update_vectors!(vf)))
    return vf
end

# the scene interface, delegated to the batched mobject: it is core/wrappers.jl's,
# once for every wrapped type

# ═══════════════════════════════════════════════════════════════════════
# StreamLines / AnimatedStreamLines
# ═══════════════════════════════════════════════════════════════════════

"""
    StreamLines(func, coordinate_system; density=1.0, n_repeats=1,
                noise_factor=nothing, solution_time=3.0, dt=0.05,
                stroke_width=1.0, stroke_color=GREY_A, stroke_opacity=1.0,
                color_by_magnitude=true, magnitude_range=(0,2),
                taper_stroke_width=false, jitter_seed=0)

Field lines: seeds on the sample grid (jittered by counter hash — GL
jitters with np.random, which no farm can replay), integrated with the
fixed-step RK4 and smoothed (2k−1 points per line, like GL's
set_points_smoothly). Colour per point by coordinate-space magnitude, or a
flat style; `taper_stroke_width` is GL's [0, w, 0] ramp.
"""
mutable struct StreamLines <: Mobject
    group::VGroup
    func::Any
    coordinate_system::Any
    virtual_time::Float64
    stroke_width::Float64
    parents::Vector{Mobject}            # the node contract
end
StreamLines(g, func, cs, vt, sw) = _link_wrapper!(StreamLines(g, func, cs, vt, sw, Mobject[]))

function StreamLines(func, coordinate_system;
                     density::Real = 1.0, n_repeats::Int = 1,
                     noise_factor = nothing,
                     solution_time::Real = 3.0, dt::Real = 0.05,
                     stroke_width::Real = 1.0, stroke_color = GREY_A,
                     stroke_opacity::Real = 1.0,
                     color_by_magnitude::Bool = true,
                     magnitude_range::Tuple = (0.0, 2.0),
                     taper_stroke_width::Bool = false,
                     jitter_seed::Integer = 0)
    cs = coordinate_system
    base_coords = _sample_coords(cs, density)
    D = length(first(base_coords))
    nf = noise_factor === nothing ?
         (get_unit_size(cs.x_axis) / density) * 0.5 : Float64(noise_factor)

    g = VGroup()
    counter = 0
    for rep in 1:n_repeats, c in base_coords
        counter += 1
        seed = ntuple(i -> c[i] + nf * _hash01(jitter_seed, counter, i), D)
        sol = ode_solution_points(func, seed, solution_time; dt)
        line = VMobject()
        set_points_smoothly!(line, [Point3f(_c2p(cs, s)) for s in sol])
        if color_by_magnitude
            lo, hi = Float64(magnitude_range[1]), Float64(magnitude_range[2])
            for (i, p) in enumerate(line.points)
                pc = point_to_coords(cs, p)
                out = func(ntuple(j -> Float64(pc[j]), D))
                nrm = sqrt(sum(j -> abs2(Float64(out[j])), 1:D))
                r, gg, b = _colormap_3b1b((nrm - lo) / (hi - lo))
                line.stroke_rgba[i] = Vec4f(r, gg, b, Float32(stroke_opacity))
            end
        else
            set_stroke!(line; color = stroke_color, opacity = stroke_opacity)
        end
        if taper_stroke_width
            # GL's width=[0, w, 0]: a linear ramp over the points
            np_ = length(line.points)
            for i in 1:np_
                t = np_ == 1 ? 0.0 : (i - 1) / (np_ - 1)
                line.stroke_width[i] = Float32(stroke_width * (1 - abs(2t - 1)))
            end
        else
            for i in eachindex(line.stroke_width)
                line.stroke_width[i] = Float32(stroke_width)
            end
        end
        add!(g, line)
    end
    return StreamLines(g, func, cs, Float64(solution_time), Float64(stroke_width))
end

# (the scene interface is core/wrappers.jl's)
Base.length(m::StreamLines) = length(m.group.submobjects)
Base.getindex(m::StreamLines, i::Int) = m.group.submobjects[i]

"""
    AnimatedStreamLines(sl; lag_range=4.0, rate_multiple=1.0,
                        time_width=1.0, taper_width=0.05, phase_seed=1)

GL's flow: each line carries a VShowPassingFlash — a GAUSSIAN width mask
(σ = time_width/6, zeroed beyond 3σ) sliding along tapered base widths,
looping every `virtual_time/rate_multiple` seconds. The points never move;
only the per-point widths do. Phase offsets are −lag_range·hash(i) (GL
draws them from np.random — the same A2 divergence as the seeds).
"""
mutable struct AnimatedStreamLines <: Mobject
    group::VGroup
    stream_lines::StreamLines
    times::Vector{Float64}
    base_widths::Vector{Vector{Float32}}
    run_time::Float64
    time_width::Float64
    parents::Vector{Mobject}            # the node contract
end
AnimatedStreamLines(g, sl, times, base, rt, tw) =
    _link_wrapper!(AnimatedStreamLines(g, sl, times, base, rt, tw, Mobject[]))

function AnimatedStreamLines(sl::StreamLines;
                             lag_range::Real = 4.0,
                             rate_multiple::Real = 1.0,
                             time_width::Real = 1.0,
                             taper_width::Real = 0.05,
                             phase_seed::Integer = 1)
    lines = sl.group.submobjects
    tw = Float64(taper_width)
    kern(x) = x < tw ? x : (x > 1 - tw ? 1.0 - x : 1.0)
    base = Vector{Vector{Float32}}(undef, length(lines))
    for (i, line) in enumerate(lines)
        n = length(line.stroke_width)
        base[i] = Float32[line.stroke_width[j] *
                          kern(n == 1 ? 0.0 : (j - 1) / (n - 1)) for j in 1:n]
    end
    times = [-Float64(lag_range) * _hash01(phase_seed, i) for i in 1:length(lines)]
    g = VGroup()
    for line in lines
        add!(g, line)
    end
    asl = AnimatedStreamLines(g, sl, times, base,
                              sl.virtual_time / Float64(rate_multiple),
                              Float64(time_width))
    add_updater!(g, (m, dt) -> _advance_flow!(asl, dt))
    _advance_flow!(asl, 0.0)               # frame 0 already flows
    return asl
end

function _advance_flow!(asl::AnimatedStreamLines, dt::Real)
    tw = asl.time_width
    σ = tw / 6
    for (i, line) in enumerate(asl.group.submobjects)
        asl.times[i] += dt
        α = (max(asl.times[i], 0.0) % asl.run_time) / asl.run_time
        μ = -tw / 2 + (1 + tw) * α
        ws = line.stroke_width
        bw = asl.base_widths[i]
        n = length(ws)
        @inbounds for j in 1:n
            x = n == 1 ? 0.0 : (j - 1) / (n - 1)
            z = (x - μ) / σ
            ws[j] = abs(x - μ) > 3σ ? 0f0 : bw[j] * Float32(exp(-0.5 * z * z))
        end
        _note_data_changed!(line)
    end
    return asl
end

# (the scene interface is core/wrappers.jl's)
