# Coordinate objects: NumberLine, Axes, NumberPlane.
#
# What makes these useful in Manim is not how they look: it is the AFFINE MAP
# they carry. `c2p` (coords → scene point) is consulted by every tick, label,
# graph and area downstream, so if the map is right everything placed through
# it is right, and if it drifts everything drifts together.
#
# THE DESIGN DECISION, and it is the one that matters:
#
#     the map is DERIVED FROM THE LIVE GEOMETRY, never stored as numbers.
#
# `number_to_point` reads the axis line's CURRENT start and end. So
# `shift!(axes, 2RIGHT)`, `scale!(axes, 0.5)` and even `rotate!` move the
# whole coordinate world coherently, for free, with no invalidation logic and
# nothing to keep in sync. A cached map would need every transform to know
# about it — which is exactly the kind of coupling this design avoids.
#
# Hierarchy: FLAT (composition), not Manim's deep inheritance. A NumberLine
# HAS a line; an Axes HAS two NumberLines. The one abstract type below is not
# a hierarchy: it exists so the delegating methods at the bottom of this file
# can be written ONCE (see the note there — writing them five times costs the
# zero-allocation guarantee).

"""
    CoordinateObject <: Mobject

What NumberLine, Axes, NumberPlane, PolarPlane and ThreeDAxes have in common:
each one IS a `group` of vector geometry plus a map read off that geometry.
Everything a scene asks of them (family, updaters, bbox, transforms) is
delegated to the group, once, here.
"""
abstract type CoordinateObject <: Mobject end

# ═══════════════════════════════════════════════════════════════════════
# NumberLine
# ═══════════════════════════════════════════════════════════════════════

"""
    NumberLine(x_range=(-8,8,1); width=nothing, unit_size=1.0,
               include_ticks=true, include_numbers=false, tick_size=0.1,
               color=GREY_B, stroke_width=2.0,
               line_to_number_direction=DOWN, line_to_number_buff=0.25,
               num_decimal_places=0, numbers_to_exclude=Float64[],
               big_tick_numbers=Float64[], longer_tick_multiple=1.5,
               label_size=0.4)

A number line: the axis, its ticks and (optionally) its numbers.

`x_range` is `(min, max, step)`. `width` fixes the total length (and
therefore the unit size); without it, `unit_size` fixes the scale.

`big_tick_numbers` lists the values whose tick is drawn `longer_tick_multiple`
times the usual size — the landmarks you want the eye to find. Empty by
default, which is manimlib's default too, so an axis you do not ask about
looks exactly as it always did. [`UnitInterval`](@ref) is the preset that uses
it.
"""
mutable struct NumberLine <: CoordinateObject
    # Concrete field types: `VMobject` written bare is a UnionAll, so a field
    # of that type makes every `m.group` access type-unstable.
    group::VGroup
    axis::Line                    # the bare line: ITS points define the map
    ticks::VGroup
    labels::VGroup
    x_min::Float64
    x_max::Float64
    x_step::Float64
    parents::Vector{Mobject}      # the node contract (the geometry lives in `group`)
end
# the old-arity constructor links the object as the parent of its group
# (wrappers.jl), so an invalidation climbs group → object → the real parent
NumberLine(g, axis, ticks, labels, x_min, x_max, x_step) =
    _link_wrapper!(NumberLine(g, axis, ticks, labels, Float64(x_min), Float64(x_max),
                              Float64(x_step), Mobject[]))

"The tick values of a range, as manimlib's get_tick_range computes them."
function tick_range(x_min::Real, x_max::Real, x_step::Real)
    x_step == 0 && return Float64[]
    n = floor(Int, (x_max - x_min) / x_step + 1e-6)
    return [x_min + k * x_step for k in 0:n]
end

function NumberLine(x_range = (-8.0, 8.0, 1.0); width = nothing,
                    unit_size::Real = 1.0, include_ticks::Bool = true,
                    include_numbers::Bool = false, tick_size::Real = 0.1,
                    color = GREY_B, stroke_width::Real = 2.0,
                    line_to_number_direction = DOWN,
                    line_to_number_buff::Real = 0.25,
                    num_decimal_places::Int = 0,
                    numbers_to_exclude = Float64[],
                    big_tick_numbers = Float64[],
                    longer_tick_multiple::Real = 1.5,
                    label_size::Real = 0.4)
    x_min, x_max, x_step = Float64.(Tuple(x_range))
    us = width === nothing ? Float64(unit_size) : Float64(width) / (x_max - x_min)
    half = 0.5 * us * (x_max - x_min)

    axis = Line(Point3f(-half, 0, 0), Point3f(half, 0, 0))
    set_stroke!(axis; color, width = stroke_width)

    ticks = VGroup()
    if include_ticks
        for x in tick_range(x_min, x_max, x_step)
            px = (x - 0.5 * (x_min + x_max)) * us
            # `np.isclose` has an absolute floor (1e-8): a tick born
            # as -0.9 + 3·0.3 = -1.1e-16 IS the zero, and `≈` alone said no
            sz = any(y -> isapprox(x, y; atol = 1e-8), big_tick_numbers) ? tick_size * longer_tick_multiple : tick_size
            t = Line(Point3f(px, -sz, 0), Point3f(px, sz, 0))
            set_stroke!(t; color, width = stroke_width)
            add!(ticks, t)
        end
    end

    labels = VGroup()
    nl = NumberLine(VGroup(), axis, ticks, labels, x_min, x_max, x_step)
    add!(nl.group, axis, ticks, labels)

    if include_numbers
        dir = Point3f(line_to_number_direction)
        for x in tick_range(x_min, x_max, x_step)
            any(y -> isapprox(x, y; atol = 1e-8), numbers_to_exclude) && continue
            # TextMobject, not Tex: digits need no math typesetting and the
            # text path is cheaper.
            txt = _decimal_string(x, num_decimal_places, false, nothing)
            lab = TextMobject(txt; size = label_size, color)
            move_to!(lab, number_to_point(nl, x) + Float32(line_to_number_buff) * dir)
            add!(labels, lab)
        end
    end
    return nl
end

"""
    UnitInterval(; unit_size=10, big_tick_numbers=[0,1], num_decimal_places=1, …)

The interval [0, 1] as a number line: eleven ticks every 0.1, with the two
ends drawn long so you can find them, and ten scene units from 0 to 1.

```julia
ui = UnitInterval(; include_numbers = true)
p = number_to_point(ui, 0.35)           # where a probability lives
```

It is the axis you want for a probability, a proportion or an animation's own
α, which is why both engines ship it as a preset. Everything
[`NumberLine`](@ref) takes still works — `width`, `include_numbers`, `color` —
and overriding `unit_size` or `x_range` is how you stop it being a unit
interval.

The long ticks are `1.5×` the others, ManimGL's `longer_tick_multiple`. Manim
CE draws them at `2×` instead (measured: 0.4 against GL's 0.3 in total
height); Janim ports GL.
"""
function UnitInterval(; unit_size::Real = 10.0, big_tick_numbers = [0.0, 1.0],
                      num_decimal_places::Int = 1, kw...)
    return NumberLine((0.0, 1.0, 0.1); unit_size, big_tick_numbers,
                      num_decimal_places, kw...)
end

"""
    number_to_point(nl, x) → Point3f

The map, read from the axis's CURRENT endpoints — which is what makes it
survive shift!/scale!/rotate! without any bookkeeping.
"""
function number_to_point(nl::NumberLine, x::Real)
    a, b = get_start(nl.axis), get_end(nl.axis)
    α = (Float64(x) - nl.x_min) / (nl.x_max - nl.x_min)
    return Point3f(a + Float32(α) * (b - a))
end

"""
    point_to_number(nl, p) → Float64

The inverse: project `p` onto the axis and read off the coordinate. Points
off the line project onto it, which is what makes `p2c` total.
"""
function point_to_number(nl::NumberLine, p)
    a, b = get_start(nl.axis), get_end(nl.axis)
    d = SVector{3,Float64}(b - a)
    len2 = sum(d .* d)
    len2 == 0 && return nl.x_min
    α = sum((SVector{3,Float64}(Point3f(p)) - SVector{3,Float64}(a)) .* d) / len2
    return nl.x_min + α * (nl.x_max - nl.x_min)
end

"""
    get_unit_size(nl) → Float64

How many SCENE units one unit of the number line is worth — the scale factor
between data space and the screen.

It is what you multiply by to convert a distance in data into a distance you
can hand to [`shift!`](@ref), and it is not 1 unless the axis was built that
way: an `Axes` given a `width` computes the size that makes the range fit.
"""
get_unit_size(nl::NumberLine) =
    Float64(norm(SVector{3,Float64}(get_end(nl.axis) - get_start(nl.axis)))) /
    (nl.x_max - nl.x_min)

"""
    get_tick_range(nl) → Vector

The data values where this line's ticks fall — the ones its labels sit on.
Iterate it to put something of your own at every tick.
"""
get_tick_range(nl::NumberLine) = tick_range(nl.x_min, nl.x_max, nl.x_step)

"""
    get_vector(nl::NumberLine) → Point3f

The axis as a vector, from its low end to its high end. A number line IS a
`Line` in ManimGL, so this is `Line.get_vector` (`geometry.py:193`): over
`(-4, 4)` at unit size 1 it is `(8, 0, 0)` — the WHOLE line, not one unit.
`number_to_point(nl, 1) - number_to_point(nl, 0)` is the unit; they are
different questions, and the y axis of an [`Axes`](@ref) answers this one
rotated, because it is.
"""
get_vector(nl::NumberLine) = get_vector(nl.axis)

# ═══════════════════════════════════════════════════════════════════════
# Axes
# ═══════════════════════════════════════════════════════════════════════

"""
    Axes(x_range=(-8,8,1), y_range=(-4,4,1); width=nothing, height=nothing,
         unit_size=1.0, include_numbers=false, axis_config=(;), kw...)

Two NumberLines and the map they define together. `width`/`height` set each
axis's scale INDEPENDENTLY — a plot of `0:10` against `0:1` needs very
different unit sizes, and assuming one is a classic source of squashed graphs.
"""
mutable struct Axes <: CoordinateObject
    group::VGroup
    x_axis::NumberLine
    y_axis::NumberLine
    parents::Vector{Mobject}      # the node contract
end
Axes(g, x, y) = _link_wrapper!(Axes(g, x, y, Mobject[]))

"A block of NumberLine keywords, written as a NamedTuple, a Dict or pairs."
_axis_kw(x::NamedTuple) = x
_axis_kw(x) = NamedTuple(Symbol(k) => v for (k, v) in pairs(x))

function Axes(x_range = (-8.0, 8.0, 1.0), y_range = (-4.0, 4.0, 1.0);
              width = nothing, height = nothing, unit_size::Real = 1.0,
              include_numbers::Bool = false,
              axis_config = NamedTuple(), x_axis_config = NamedTuple(),
              y_axis_config = NamedTuple(), kw...)
    # ManimGL's merge order (`coordinate_systems.py:462-480`): the shared
    # defaults, then the per-axis default, then `axis_config`, then the
    # per-axis block — most specific last. Janim's own direct keyword form
    # (`Axes(…; stroke_width = 5)`) sits with the shared defaults, so a config
    # block always wins over it, and there is exactly ONE splat per axis: a
    # keyword repeated in a splat is a Julia error, not a silent override.
    # `z_index` is the Axes' own (ManimGL's Mobject keyword), not a NumberLine
    # keyword, so it is taken out of `kw` before the axes are built.
    z_index = get(kw, :z_index, nothing)
    kw = (; (k => v for (k, v) in pairs(kw) if k !== :z_index)...)
    common = merge((; width, unit_size, include_numbers), NamedTuple(kw), _axis_kw(axis_config))
    xcfg = merge(common, _axis_kw(x_axis_config))
    ycfg = merge((line_to_number_direction = LEFT,), common, (width = height,),
                 _axis_kw(y_axis_config))
    xa = NumberLine(x_range; xcfg...)
    # The y axis is built WITHOUT its numbers and gets them once it stands:
    # each beside the rotated line, in `line_to_number_direction` (LEFT), the
    # way GL's `add_coordinate_labels` places them (`next_to` in
    # `NumberLine.get_number_mobject`, the 0 excluded — the x axis already
    # labels the origin), whichever way `include_numbers` arrived: the direct
    # keyword, `axis_config` or `y_axis_config` (CE's semantics). Numbers born
    # on the horizontal line would rotate with it and end up ON the axis.
    y_numbers = get(ycfg, :include_numbers, false)
    ya = NumberLine(y_range; merge(ycfg, (include_numbers = false,))...)
    rotate!(ya.group, PI / 2)                       # stand it up
    y_numbers && _add_axis_numbers!(ya, ycfg)
    # manimlib's placement, and it is NOT "centre each axis on its own range":
    # each axis is shifted so that COORDINATE ZERO sits at the group's origin,
    # and only then is the whole thing centred by bounding box (ticks
    # included). With symmetric ranges the two recipes agree — which is why a
    # (-4,4)×(-3,3) axes would never have caught the difference — but with
    # 0..10 × 0..1 they are 5 units apart. The reference did catch it.
    shift!(xa.group, -number_to_point(xa, 0))
    shift!(ya.group, -number_to_point(ya, 0))
    ax = Axes(VGroup(), xa, ya)
    add!(ax.group, xa.group, ya.group)
    center!(ax.group)
    # the z is the AXES' own, not the family's: GL sorts roots only, so a graph
    # added later draws over the axes it belongs to
    # (with the recursive set, an `add!(ax, graph)` landed underneath)
    z_index === nothing || set_z_index!(ax.group, z_index; recurse = false)
    return ax
end

# The label keywords a NumberLine takes, with NumberLine's own defaults, for
# the numbers placed AFTER the line stood up; they match NumberLine's signature.
const _AXIS_NUMBER_DEFAULTS = (line_to_number_direction = DOWN, line_to_number_buff = 0.25,
                               num_decimal_places = 0, numbers_to_exclude = Float64[],
                               label_size = 0.4, color = GREY_B)

"""
GL's `NumberLine.add_numbers` (number_line.py: `get_number_mobject`,
`next_to(number_to_point(x), direction, buff)`) over a line that already
stands where it will: one label per tick, beside its point in
`line_to_number_direction`, the excluded values and the zero skipped — the
zero stays with `skip_zero = false` (the x axis of a `ThreeDAxes` labels the
origin, as the x axis of an `Axes` does).
"""
function _add_axis_numbers!(nl::NumberLine, cfg; skip_zero::Bool = true)
    c = merge(_AXIS_NUMBER_DEFAULTS, cfg)
    dir = Point3f(c.line_to_number_direction)
    for x in get_tick_range(nl)
        skip_zero && abs(x) < 1e-8 && continue
        any(y -> isapprox(x, y; atol = 1e-8), c.numbers_to_exclude) && continue
        txt = _decimal_string(x, c.num_decimal_places, false, nothing)
        lab = TextMobject(txt; size = c.label_size, color = c.color)
        next_to!(lab, number_to_point(nl, x), dir; buff = c.line_to_number_buff)
        add!(nl.labels, lab)
    end
    return nl
end

"""
    get_x_axis(ax) → NumberLine

The horizontal axis as its own mobject — to restyle it, label it, or ask it for
[`get_unit_size`](@ref).
"""
get_x_axis(ax::Axes) = ax.x_axis

"""
    get_y_axis(ax) → NumberLine

The vertical axis as its own mobject. See [`get_x_axis`](@ref).
"""
get_y_axis(ax::Axes) = ax.y_axis

"""
    get_origin(ax) → Point3f

Where the coordinate `(0, 0)` of these axes lands on screen.

NOT the centre of the frame, and not the centre of the axes either, unless the
ranges happen to be symmetric: `Axes((0, 10, 1), (0, 5, 1))` has its origin at
the bottom-left corner of the grid. Equivalent to `c2p(ax, 0, 0)`.
"""
get_origin(ax::Axes) = number_to_point(ax.x_axis, 0)

"""
    coords_to_point(ax, x, y) → Point3f     (alias: `c2p`)

origin + (x_axis(x) − origin) + (y_axis(y) − origin), exactly as manimlib
composes it. Everything placed on axes — ticks, labels, graphs, areas, braces
on graphs — goes through here, so the map has one definition and one bug surface.
"""
function coords_to_point(ax::Axes, x::Real, y::Real)
    o = get_origin(ax)
    return Point3f(o + (number_to_point(ax.x_axis, x) - o) +
                   (number_to_point(ax.y_axis, y) - o))
end
"""
    c2p(ax, x, y) → Point3f

Manim's short name for [`coords_to_point`](@ref) — the same function, and the
one you actually type, because everything placed on a plot goes through it.
"""
const c2p = coords_to_point

"""
    point_to_coords(ax, p) → (x, y)         (alias: `p2c`)

The inverse. `p2c ∘ c2p` is the identity to machine precision even after the
axes have been shifted, scaled or rotated — the verifier checks exactly that
over a seeded random grid.
"""
point_to_coords(ax::Axes, p) =
    # each axis projects the point onto ITSELF, so this is still right after a
    # rotation — reading off p[1] and p[2] would not be.
    (point_to_number(ax.x_axis, p), point_to_number(ax.y_axis, p))
"""
    p2c(ax, point) → (x, y)

Manim's short name for [`point_to_coords`](@ref) — scene point back to data
coordinates, the inverse of [`c2p`](@ref).
"""
const p2c = point_to_coords

# ═══════════════════════════════════════════════════════════════════════
# Graphs over an Axes
# ═══════════════════════════════════════════════════════════════════════

"""
    plot(ax, f; x_range=nothing, n=100, color=GREY_A, stroke_width=4.0,
         discontinuities=Float64[])

Sample `f` and draw it through the axes' map.

The curve is born `GREY_A` (`#DDDDDD`) at width `4.0`, which is what
ManimGL's `get_graph`/`FunctionGraph` produce — they set no colour, so the
curve keeps the `VMobject` default. Pass `color = BLUE, stroke_width = 3.0`
for a blue curve; on axes that already carry colour, naming the curve's
colour is the readable thing to do anyway.

`discontinuities` CUTS the path into subpaths instead of drawing the vertical
jump a naive sampler produces. Subpath indices are first-class in the
engine, so this is three lines here; in Manim it is a documented hack.
"""
function plot(ax::Axes, f; x_range = nothing, n::Int = 100, color = GREY_A,
              stroke_width::Real = 4.0, discontinuities = Float64[])
    xa = ax.x_axis
    x0, x1 = x_range === nothing ? (xa.x_min, xa.x_max) :
             (Float64(x_range[1]), Float64(x_range[2]))
    step = x_range !== nothing && length(x_range) >= 3 ?
           Float64(x_range[3]) : (x1 - x0) / n
    xs = collect(x0:step:x1)
    isempty(xs) && throw(ArgumentError("plot: the x range is empty"))
    last(xs) < x1 - 1e-9 && push!(xs, x1)

    cuts = sort(Float64.(collect(discontinuities)))
    graph = VMobject()
    set_stroke!(graph; color, width = stroke_width)
    set_fill!(graph; opacity = 0)

    segment = Point3f[]
    flush_segment! = () -> begin
        length(segment) >= 2 || (empty!(segment); return)
        if has_points(graph)
            start_new_path!(graph, segment[1])
            append_points!(graph, get_points(_as_corners(segment))[2:end])
        else
            set_points_as_corners!(graph, segment)
        end
        empty!(segment)
    end
    for (i, x) in enumerate(xs)
        # a cut BETWEEN this sample and the previous one closes the segment
        if i > 1 && any(c -> xs[i-1] < c <= x, cuts)
            flush_segment!()
        end
        push!(segment, coords_to_point(ax, x, f(x)))
    end
    flush_segment!()
    return graph
end

_as_corners(ps) = (v = VMobject(); set_points_as_corners!(v, ps); v)

"""
    plot!(graph, ax, f; x_range=nothing, n=100)

Re-sample `f` INTO an existing graph, reusing its point buffer.

`always_redraw(() -> plot(ax, f))` is the readable way to write a live graph,
but it builds a whole mobject per frame: ~14 KB for 60 samples. The bar here
is stricter — "no more allocations than a Transform" — and this is how it is
met: the anchors are overwritten in place, so a graph animating
inside an updater at 60 fps costs the same as any other per-frame maths.

Use `plot` when you write the scene once; use `plot!` in the hot loop.
"""
function plot!(graph::VMobject, ax::Axes, f; x_range = nothing, n::Int = 100)
    xa = ax.x_axis
    x0, x1 = x_range === nothing ? (xa.x_min, xa.x_max) :
             (Float64(x_range[1]), Float64(x_range[2]))
    pts = get_points(graph)
    np = length(pts)
    np >= 3 || throw(ArgumentError(
        "plot!: the graph has no points yet — build it once with `plot` first"))
    # a corner path is 2k+1 points: anchors on the odd indices, handles at the
    # midpoints. Rewriting both in one pass keeps this allocation-free.
    nanchor = (np + 1) ÷ 2
    @inbounds for i in 1:nanchor
        x = x0 + (x1 - x0) * (i - 1) / (nanchor - 1)
        pts[2i-1] = coords_to_point(ax, x, f(x))
    end
    @inbounds for i in 1:(nanchor - 1)
        pts[2i] = Point3f(0.5f0 * (pts[2i-1] + pts[2i+1]))
    end
    refresh_bounding_box!(graph)
    return graph
end

"""
    get_parametric_curve(ax, f; t_range=(0, 1, 0.1), use_smoothing=true, kw...)

A [`ParametricCurve`](@ref) drawn through the axes' map
(`coordinate_systems.py:215`): `f(t)` returns DATA coordinates and the curve
comes out where [`c2p`](@ref) puts them.

```julia
circle = get_parametric_curve(ax, t -> (cos(t), sin(t)); t_range = (0, TAU, 0.1))
```

The difference from [`plot`](@ref) is what the function is of: `plot` takes
`y = f(x)` and samples x, this one takes any `t → (x, y)`, so it draws loops
and curves that double back. Only the first two components are read, as in GL.
"""
get_parametric_curve(ax::Axes, f; kw...) =
    ParametricCurve(t -> (p = f(t); coords_to_point(ax, p[1], p[2])); kw...)

"""
    get_area(ax, graph_f, x0, x1; color=BLUE, opacity=0.35, n=100)

The exact area under a curve as a FILLED POLYGON: the samples of the curve,
closed along the x axis.

Manim approximates this with a stack of rectangles because its fill cannot be
trusted on a self-touching outline. Ours is filled by real winding, so
the exact polygon just works — this is one of the places where the renderer
being ours pays off directly.
"""
function get_area(ax::Axes, f, x0::Real, x1::Real; color = BLUE,
                  opacity::Real = 0.35, n::Int = 100)
    xs = range(Float64(x0), Float64(x1); length = max(n, 2))
    pts = [coords_to_point(ax, x, f(x)) for x in xs]
    push!(pts, coords_to_point(ax, x1, 0.0))
    push!(pts, coords_to_point(ax, x0, 0.0))
    # `push!`, not `[pts; pts[1]]`: a Point3f IS a StaticVector, so vcat
    # SPLATS it into three scalars and the closing anchor becomes three bogus
    # ones at (x,x,x), (y,y,y), (z,z,z). Invisible while the axes sit at the
    # origin and f(x0)=0, and a spike across the
    # frame as soon as they do not.
    push!(pts, pts[1])
    area = VMobject()
    set_points_as_corners!(area, pts)
    set_fill!(area; color, opacity)
    set_stroke!(area; width = 0, opacity = 0)
    return area
end

"""
    get_graph_label(ax, graph, text; x=nothing, direction=UR, buff=0.2, via=:text, …)

A label pinned to a point of the graph, placed through the map so it follows
the axes. `via` is the label's route: `:text` (FreeType), or `:math`,
`:latex`, `:typst`, `:auto` for a [`Tex`](@ref) by that route.
"""
function get_graph_label(ax::Axes, graph::VMobject, text::AbstractString;
                         x = nothing, direction = UR, buff::Real = 0.2,
                         size::Real = 0.5, color = WHITE, via::Symbol = :text)
    lab = _label_via(text, via; size, color)
    anchor = x === nothing ? get_points(graph)[end] :
             coords_to_point(ax, x, point_to_coords(ax, get_points(graph)[end])[2])
    if x !== nothing
        # place at the graph's own height at that x, found by sampling the path
        best = argmin([abs(point_to_coords(ax, p)[1] - Float64(x))
                       for p in get_points(graph)])
        anchor = get_points(graph)[best]
    end
    move_to!(lab, anchor + Float32(buff) * Point3f(direction))
    return lab
end

"Vertical line from the x axis up to a point of the graph (Manim's get_v_line)."
function get_v_line(ax::Axes, x::Real, y::Real; color = GREY_B, stroke_width::Real = 2.0)
    l = Line(coords_to_point(ax, x, 0), coords_to_point(ax, x, y))
    set_stroke!(l; color, width = stroke_width)
    return l
end

"Horizontal line from the y axis across to a point (Manim's get_h_line)."
function get_h_line(ax::Axes, x::Real, y::Real; color = GREY_B, stroke_width::Real = 2.0)
    l = Line(coords_to_point(ax, 0, y), coords_to_point(ax, x, y))
    set_stroke!(l; color, width = stroke_width)
    return l
end

# ═══════════════════════════════════════════════════════════════════════
# NumberPlane
# ═══════════════════════════════════════════════════════════════════════

"""
    _np_arange(start, stop, step) → Vector{Float64}

numpy's `arange`, to the bit. ManimGL samples the faded grid with
`np.arange(x_min, x_max + step, step)` (`coordinate_systems.py:700`), and
numpy does NOT compute `start + i·step`: its length is `ceil((stop − start) /
step)` and its fill takes the delta from the first two buffer entries,
`(start + step) − start`, which is the step with one rounding on it. With a
step of 1/3 that drift puts the 4th value at -2.9999999999999996 and the 25th
at 4.0000000000000036 — past the end, so a sample the closed form would never
produce. This reproduces GL's samples (14 rows on the default plane). Never
`range`/`:`:
Julia's TwicePrecision corrects exactly the drift GL has.
"""
function _np_arange(start::Float64, stop::Float64, step::Float64)
    len = ceil(Int, (stop - start) / step)
    len <= 0 && return Float64[]
    delta = (start + step) - start
    return [start + i * delta for i in 0:len-1]
end

"""
    NumberPlane(x_range=(-8,8,1), y_range=(-4,4,1); width, height,
                background_line_color=BLUE, background_stroke_width=2.0,
                faded_line_ratio=4, faded_stroke_width=1.0,
                faded_opacity=0.25, z_index, kw...)

Axes plus their grid: the background lines (one per tick, minus the two that
would sit on the axes themselves) and `faded_line_ratio` fainter ones between
each pair — ManimGL's count (`coordinate_systems.py:689-711`):
the grid is sampled at `1 + faded_line_ratio` lines per unit with numpy's
`arange` (`_np_arange`), and the samples on a tick (every
`1 + faded_line_ratio`-th one) and on the zero line (|x| < 1e-8) are skipped,
so the faded lines are the INTERIOR ones. `faded_line_ratio = 0` draws none.

The faded lines are drawn at stroke width 1: a hairline grid behind a small blur σ
disappears entirely, so if you plan to blur the background, thicken these
rather than wondering where the grid went.
"""
mutable struct NumberPlane <: CoordinateObject
    group::VGroup
    axes::Axes
    background_lines::VGroup
    faded_lines::VGroup
    parents::Vector{Mobject}      # the node contract
end
NumberPlane(g, ax, bg, fd) = _link_wrapper!(NumberPlane(g, ax, bg, fd, Mobject[]))

function NumberPlane(x_range = (-8.0, 8.0, 1.0), y_range = (-4.0, 4.0, 1.0);
                     width = nothing, height = nothing,
                     background_line_color = BLUE,
                     background_stroke_width::Real = 2.0,
                     faded_line_ratio::Int = 4,
                     faded_stroke_width::Real = 1.0,
                     faded_opacity::Real = 0.25, z_index = nothing, kw...)
    ax = Axes(x_range, y_range; width, height, kw...)
    bg, faded = VGroup(), VGroup()
    xr = get_tick_range(ax.x_axis)
    yr = get_tick_range(ax.y_axis)
    ymin, ymax = ax.y_axis.x_min, ax.y_axis.x_max
    xmin, xmax = ax.x_axis.x_min, ax.x_axis.x_max

    mkline!(group, p, q, w, op) = begin
        l = Line(p, q)
        set_stroke!(l; color = background_line_color, width = w, opacity = op)
        add!(group, l)
    end

    # the lines ON the axes are the axes: excluding them is what makes the
    # count 14 and not 16 on the default range (manimlib does the same).
    # GL's test is `abs(x) < 1e-8` (`coordinate_systems.py:696`),
    # not `≈ 0` — a tick born as -0.3 + 3·0.1 = 5.6e-17 IS the zero line.
    for x in xr
        abs(x) < 1e-8 && continue
        mkline!(bg, coords_to_point(ax, x, ymin), coords_to_point(ax, x, ymax),
                background_stroke_width, 1.0)
    end
    for y in yr
        abs(y) < 1e-8 && continue
        mkline!(bg, coords_to_point(ax, xmin, y), coords_to_point(ax, xmax, y),
                background_stroke_width, 1.0)
    end
    # GL's faded grid, operation by operation (`coordinate_systems.py:689-711`):
    # `1 + ratio` samples per unit from
    # numpy's arange over `[min, max + step]`, skipping the ones on a tick
    # (index % density == 0) and on the zero line. The order `(1 / density) *
    # step` is kept: it is where the bits come from.
    if faded_line_ratio > 0
        density = 1 + faded_line_ratio
        dx = (1.0 / density) * ax.x_axis.x_step
        dy = (1.0 / density) * ax.y_axis.x_step
        for (i, x) in enumerate(_np_arange(xmin, xmax + dx, dx))
            (abs(x) < 1e-8 || (i - 1) % density == 0) && continue
            mkline!(faded, coords_to_point(ax, x, ymin), coords_to_point(ax, x, ymax),
                    faded_stroke_width, faded_opacity)
        end
        for (i, y) in enumerate(_np_arange(ymin, ymax + dy, dy))
            (abs(y) < 1e-8 || (i - 1) % density == 0) && continue
            mkline!(faded, coords_to_point(ax, xmin, y), coords_to_point(ax, xmax, y),
                    faded_stroke_width, faded_opacity)
        end
    end
    pl = NumberPlane(VGroup(), ax, bg, faded)
    add!(pl.group, faded, bg, ax.group)      # grid behind, axes on top
    z_index === nothing || set_z_index!(pl.group, z_index; recurse = false)   # the root only
    return pl
end

coords_to_point(pl::NumberPlane, x::Real, y::Real) = coords_to_point(pl.axes, x, y)
point_to_coords(pl::NumberPlane, p) = point_to_coords(pl.axes, p)
get_origin(pl::NumberPlane) = get_origin(pl.axes)

# ═══════════════════════════════════════════════════════════════════════
# Extensions: ComplexPlane, PolarPlane, ThreeDAxes
# ═══════════════════════════════════════════════════════════════════════

"""
    ComplexPlane(x_range, y_range; kw...)

A NumberPlane that speaks complex numbers: `n2p(plane, 2+3im)` and
`p2n(plane, point)`.
"""
const ComplexPlane = NumberPlane
number_to_point(pl::NumberPlane, z::Complex) = coords_to_point(pl, real(z), imag(z))
function point_to_number(pl::NumberPlane, p)
    x, y = point_to_coords(pl, p)
    return complex(x, y)
end

"""
    PolarPlane(; r_max=4.0, n_radii=8, n_circles=4, kw...)

Radial grid: `n_radii` spokes and `n_circles` concentric circles, plus
`polar_to_point(θ, r)`.
"""
mutable struct PolarPlane <: CoordinateObject
    group::VGroup
    axis::Line          # the θ=0 radius: the LIVE map, like NumberLine's axis
    r_max::Float64
    parents::Vector{Mobject}      # the node contract
end
PolarPlane(g, axis, r_max) = _link_wrapper!(PolarPlane(g, axis, Float64(r_max), Mobject[]))

function PolarPlane(; r_max::Real = 4.0, n_radii::Int = 8, n_circles::Int = 4,
                    radius::Real = 3.0, color = BLUE, stroke_width::Real = 1.5,
                    opacity::Real = 0.6)
    g = VGroup()
    # The θ=0 radius always exists — it is the geometry the map is read off
    # With n_radii=0 it stays invisible.
    axis = Line(ORIGIN, Point3f(radius, 0, 0))
    set_stroke!(axis; color, width = stroke_width,
                opacity = n_radii > 0 ? opacity : 0.0)
    add!(g, axis)
    for k in 1:(n_radii - 1)
        θ = k * TAU / n_radii
        l = Line(ORIGIN, Point3f(radius * cos(θ), radius * sin(θ), 0))
        set_stroke!(l; color, width = stroke_width, opacity)
        add!(g, l)
    end
    for k in 1:n_circles
        c = Circle(radius = radius * k / n_circles)
        set_stroke!(c; color, width = stroke_width, opacity)
        set_fill!(c; opacity = 0)
        add!(g, c)
    end
    return PolarPlane(g, axis, Float64(r_max))
end

"""
    polar_to_point(plane, θ, r) → the scene point at that angle and radius.

Read off the LIVE θ=0 radius, like `c2p` reads its axes. Shift, scale and
in-plane rotation of the plane are all honoured.
"""
function polar_to_point(pp::PolarPlane, θ::Real, r::Real)
    o = get_start(pp.axis)
    ux = (get_end(pp.axis) - o) / pp.r_max
    uy = rotate_vector(ux, TAU / 4)
    return Point3f(o + r * (cos(θ) * ux + sin(θ) * uy))
end

"""
    ThreeDAxes(x_range, y_range, z_range; width, height, depth, kw...)

Three NumberLines and a 3-D map. `c2p(ax, x, y, z)` composes the same way as
in 2-D, so everything that placed things through `c2p` keeps working.
"""
mutable struct ThreeDAxes <: CoordinateObject
    group::VGroup
    x_axis::NumberLine
    y_axis::NumberLine
    z_axis::NumberLine
    parents::Vector{Mobject}      # the node contract
end
ThreeDAxes(g, x, y, z) = _link_wrapper!(ThreeDAxes(g, x, y, z, Mobject[]))

function ThreeDAxes(x_range = (-4.0, 4.0, 1.0), y_range = (-4.0, 4.0, 1.0),
                    z_range = (-3.0, 3.0, 1.0); width = nothing, height = nothing,
                    depth = nothing, kw...)
    # the numbers are placed once each axis STANDS, as `Axes` places its y
    # numbers (GL's `add_coordinate_labels`: `next_to` the tick, unrotated, the
    # 0 left to the x axis). Born inside the NumberLine they would rotate with
    # it: the y labels on their side, the z labels edge-on to the camera, and
    # the 0 drawn three times.
    numbers = get(kw, :include_numbers, false)
    cfg = merge(NamedTuple(kw), (include_numbers = false,))
    xa = NumberLine(x_range; width, cfg...)
    ya = NumberLine(y_range; width = height, cfg...)
    za = NumberLine(z_range; width = depth, cfg...)
    rotate!(ya.group, PI / 2)                       # into +y
    rotate!(za.group, -PI / 2; axis = UP)           # into +z
    if numbers
        _add_axis_numbers!(xa, cfg; skip_zero = false)
        # LEFT of the standing line, upright in the xy plane (the z labels
        # face the camera too); an explicit direction in `kw` wins, as in Axes
        _add_axis_numbers!(ya, merge((line_to_number_direction = LEFT,), cfg))
        _add_axis_numbers!(za, merge((line_to_number_direction = LEFT,), cfg))
    end
    for a in (xa, ya, za)                           # coordinate zero at the origin
        shift!(a.group, -number_to_point(a, 0))
    end
    ax = ThreeDAxes(VGroup(), xa, ya, za)
    add!(ax.group, xa.group, ya.group, za.group)
    center!(ax.group)
    return ax
end

get_origin(ax::ThreeDAxes) = number_to_point(ax.x_axis, 0)
function coords_to_point(ax::ThreeDAxes, x::Real, y::Real, z::Real)
    o = get_origin(ax)
    return Point3f(o + (number_to_point(ax.x_axis, x) - o) +
                   (number_to_point(ax.y_axis, y) - o) +
                   (number_to_point(ax.z_axis, z) - o))
end

# ═══════════════════════════════════════════════════════════════════════
# Living in a scene: every coordinate object IS its group
# ═══════════════════════════════════════════════════════════════════════
# Delegating these is what gives shift!/scale!/rotate!/next_to! for free —
# they all go through apply_points_function! and the bbox.

# ONE set of methods over the abstract type, not five sets over the concrete
# ones. That is not tidiness — it is correctness of a measured kind.
#
# `rotate!(m::VMobject, angle; axis, about_point, kw...)` is a KEYWORD
# function. With a single method Julia constant-folds the empty keyword tuple
# and `rotate!(circle, θ)` allocates nothing; adding five more keyword methods
# to the same generic function pushes every call — including the VMobject one
# that has nothing to do with coordinates — onto the dynamic keyword path.
# The hot loop's zero allocations become 272 bytes per call, and spelling the
# keywords out does NOT fix it: only having fewer methods does.

# The delegation itself (family, updaters, box, transforms, style, flags,
# draw order) lives in core/wrappers.jl, where it is written ONCE for every
# type that wraps a group — this one, DecimalNumber and the fields —
# over a Union, which is still ONE method per verb (the rule above).
Base.copy(m::CoordinateObject) = _copy_coord(m)

# The interpolation contract — the other four lines. Without them
# `animate(axes, (shift!, RIGHT))` throws, which is a perfectly ordinary thing
# to want. Everything delegates to the group: interpolating an Axes IS
# interpolating its geometry, and the map follows because the map is read off
# that geometry.
is_interpolable(::CoordinateObject) = true
interpolate!(dst::CoordinateObject, a::CoordinateObject, b::CoordinateObject,
             alpha::Real) = (interpolate!(dst.group, a.group, b.group, alpha); dst)
become!(dst::CoordinateObject, src::CoordinateObject) =
    (become!(dst.group, src.group); dst)
align_data!(a::CoordinateObject, b::CoordinateObject) = (align_data!(a.group, b.group); a)
_align_pair!(a::CoordinateObject, b::CoordinateObject, padding::Symbol) =
    (align_data!(a.group, b.group; padding); a)

# copy has to rebuild the wrapper around the COPIED group, so that the copy's
# map reads the copy's geometry and not the original's.
#
# The OUTER group is copied too, and the wrappers are rebuilt around the
# copy's children: its updaters (re-aimed at the copy, wrappers.jl), its
# suspension, its z and anything added to it later (`add!(ax, graph)`) travel
# with the copy, as in GL.
"A NumberLine wrapper around an already-copied group: its axis, ticks and labels are that group's first three children."
function _numberline_over(g::VGroup, m::NumberLine)
    nl = NumberLine(g, g.submobjects[1], g.submobjects[2], g.submobjects[3],
                    m.x_min, m.x_max, m.x_step)
    _rebind_wrapper_calls!(g, m, nl)
    return nl
end
_copy_coord(m::NumberLine) = _numberline_over(copy(m.group), m)
"An Axes wrapper around an already-copied group: the x and y axes are its first two children."
function _axes_over(g::VGroup, m::Axes)
    x = _numberline_over(g.submobjects[1]::VGroup, m.x_axis)
    y = _numberline_over(g.submobjects[2]::VGroup, m.y_axis)
    ax = Axes(g, x, y)
    _rebind_wrapper_calls!(g, m, ax)
    return ax
end
_copy_coord(m::Axes) = _axes_over(copy(m.group), m)
function _copy_coord(m::NumberPlane)
    g = copy(m.group)                       # children: faded, background, axes
    fd, bg = g.submobjects[1]::VGroup, g.submobjects[2]::VGroup
    ax = _axes_over(g.submobjects[3]::VGroup, m.axes)
    pl = NumberPlane(g, ax, bg, fd)
    _rebind_wrapper_calls!(g, m, pl)
    return pl
end
function _copy_coord(m::PolarPlane)
    g = copy(m.group)
    pp = PolarPlane(g, g.submobjects[1], m.r_max)   # child 1 IS the θ=0 axis
    _rebind_wrapper_calls!(g, m, pp)
    return pp
end
function _copy_coord(m::ThreeDAxes)
    g = copy(m.group)
    x = _numberline_over(g.submobjects[1]::VGroup, m.x_axis)
    y = _numberline_over(g.submobjects[2]::VGroup, m.y_axis)
    z = _numberline_over(g.submobjects[3]::VGroup, m.z_axis)
    ax = ThreeDAxes(g, x, y, z)
    _rebind_wrapper_calls!(g, m, ax)
    return ax
end
