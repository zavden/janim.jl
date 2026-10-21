# core/functions.jl — ManimGL's `mobject/functions.py`.
#
# A curve sampled from a function, which is what every plot in every lesson is
# built out of. `plot(ax, f)` draws one on axes; this file adds the
# FREE-STANDING curve, the one a Manim script writes before it has any axes:
# `ParametricCurve(lambda t: …)` and `FunctionGraph(f)`.
#
# The sampling is GL's, corner for corner (`functions.py:38-53`), and it has
# one trap worth naming: `np.arange(t1, t2, step)` EXCLUDES `t2`, which is then
# appended, so the last step is short and the endpoint is never dropped.
# Julia's `t1:step:t2` INCLUDES `t2` when it lands exactly, so the range is
# trimmed before the append — otherwise every round number would be doubled.

"GL's `np.arange(t1, t2, step)` plus `t2`: the sample times of one continuous piece."
function _sample_times(t1::Float64, t2::Float64, step::Float64)
    step > 0 || throw(ArgumentError(
        "ParametricCurve: the step of t_range must be > 0, got $step"))
    ts = collect(t1:step:t2)
    isempty(ts) || (last(ts) >= t2 && pop!(ts))   # np.arange stops BEFORE t2
    push!(ts, t2)
    return ts
end

"The polyline through `pts` as béziers, without the first point — what `append_points!` wants."
function _corner_tail(pts::Vector{Point3f})
    out = Vector{Point3f}(undef, 2 * (length(pts) - 1))
    @inbounds for i in 1:length(pts)-1
        out[2i-1] = (pts[i] + pts[i+1]) / 2      # the handle: the midpoint of the side
        out[2i] = pts[i+1]
    end
    return out
end

_curve_point(f, t) = Point3f(Tuple(f(t))...)

function _parametric_curve(tagsym::Symbol, t_func; t_range = (0.0, 1.0, 0.1),
                           epsilon::Real = 1e-8, discontinuities = Float64[],
                           use_smoothing::Bool = true, kw...)
    t_min, t_max, step = Float64.(Tuple(t_range))
    m = vmob(tagsym; kw...)          # GL's VMobject default: stroke GREY_A at 4, no fill

    ε = Float64(epsilon)
    jumps = sort!([Float64(j) for j in discontinuities if t_min < Float64(j) < t_max])
    bounds = sort!([t_min; t_max; (jumps .- ε); (jumps .+ ε)])
    for k in 1:2:length(bounds)-1
        pts = [_curve_point(t_func, t) for t in _sample_times(bounds[k], bounds[k+1], step)]
        start_new_path!(m, pts[1])
        length(pts) > 1 && append_points!(m, _corner_tail(pts))
    end
    use_smoothing && make_smooth!(m)
    has_points(m) || set_points!(m, (_curve_point(t_func, t_min),))
    return m
end

"""
    ParametricCurve(t_func; t_range=(0, 1, 0.1), epsilon=1e-8,
                    discontinuities=[], use_smoothing=true, kw...)

The curve `t → t_func(t)`, sampled over `t_range = (t_min, t_max, step)`
(`functions.py:17`).

```julia
spiral = ParametricCurve(t -> (t * cos(t), t * sin(t), 0); t_range = (0, 4PI, 0.1))
```

`t_func` may return anything three numbers can be read out of — a tuple, a
`Point3f`, a vector.

**`discontinuities` cuts the path** instead of drawing the vertical jump a
naive sampler produces: each listed `t` becomes a pair of boundaries at
`t ± epsilon`, so the curve stops just before the pole and starts again just
after it. That is GL's own recipe, and the subpaths it leaves are first-class
here — the same mechanism [`plot`](@ref) uses.

`use_smoothing = true` (the default) runs [`make_smooth!`](@ref) over the
sampled corners, which moves the HANDLES and leaves every sampled point where
it is. An empty range leaves a single point rather than raising — GL's
`if not self.has_points()`.

Style keywords are the usual ones (`color`, `stroke_width`, `fill_opacity`, …)
and reach the mobject before it has points, so they are its factory style.
"""
ParametricCurve(t_func; kw...) = _parametric_curve(:ParametricCurve, t_func; kw...)

"""
    FunctionGraph(f; x_range=(-8, 8, 0.25), kw...)

The graph of `y = f(x)` in SCENE coordinates — `ParametricCurve(x → (x, f(x), 0))`
(`functions.py:69`). For a graph through a set of axes, use [`plot`](@ref) or
[`get_parametric_curve`](@ref), which map through `c2p`.

```julia
FunctionGraph(x -> sin(x))                       # over the whole default range
FunctionGraph(x -> x^2; x_range = (-2, 2, 0.1), color = BLUE)
```

**`color` really paints here, and in ManimGL it does not.** GL declares
`color: ManimColor = YELLOW` and then never passes it to `super().__init__`
(`functions.py:75`), so every `FunctionGraph` it builds comes out the plain
`#DDDDDD` of a `VMobject` — measured, not read from the signature. The default
is that same grey, so an unpainted graph is what GL's is; the keyword works
because a flag that is accepted and then silently ignored is a defect, not a
contract to copy.
"""
FunctionGraph(f; x_range = (-8.0, 8.0, 0.25), kw...) =
    _parametric_curve(:FunctionGraph, x -> (x, f(x), 0.0); t_range = x_range, kw...)
