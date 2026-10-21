# Relative layout.
#
# EVERY Manim scene has a `next_to`, a `to_edge` or an `arrange`. All of it is
# bounding-box arithmetic (`get_bounding_box_point`), so this is pure core: no
# state, no touching the renderer.
#
# Port of manimlib/mobject/mobject.py (the "Positioning methods" and "Match
# other mobject properties" blocks) with two adjustments:
#   · `dim` is 1-based (1=x, 2=y, 3=z), like length_over_dim/stretch!.
#   · degenerate grids do not divide by zero (GL crashes with n_rows=0).
#
# Axes, Brace, Table and the rest are built on top of it: everything that is
# placed gets placed with this.

_as_point(x::Mobject, direction) = get_bounding_box_point(x, direction)
_as_point(x, _) = Point3f(x)

# ── single coordinates ──────────────────────────────────────────────────────

"Coordinate `dim` of the bbox point in `direction` (GL's get_coord)."
get_coord(m::Mobject, dim::Int; direction = ORIGIN) =
    get_bounding_box_point(m, direction)[dim]

"""
    set_coord!(m, value, dim; direction=ORIGIN)

Move `m` along axis `dim` until its `direction` point equals `value`.
`set_x!/set_y!/set_z!` are the shortcuts.
"""
function set_coord!(m::Mobject, value::Real, dim::Int; direction = ORIGIN)
    1 <= dim <= 3 || throw(ArgumentError("dim=$dim does not exist: 1=x, 2=y, 3=z"))
    delta = Float32(value) - get_coord(m, dim; direction)
    return shift!(m, Point3f(ntuple(i -> i == dim ? delta : 0f0, 3)))
end

"""
    set_x!(m, x; direction = ORIGIN)

Move `m` horizontally until its centre sits at `x`. The whole mobject moves —
this is a translation, not a stretch.

`direction` chooses WHICH point of `m` lands on `x`: the default is the centre,
`direction = LEFT` puts its left edge there. See [`set_coord!`](@ref).
"""
set_x!(m::Mobject, x::Real; direction = ORIGIN) = set_coord!(m, x, 1; direction)

"""
    set_y!(m, y; direction = ORIGIN)

Move `m` vertically until its centre sits at `y`. See [`set_x!`](@ref).
"""
set_y!(m::Mobject, y::Real; direction = ORIGIN) = set_coord!(m, y, 2; direction)

"""
    set_z!(m, z; direction = ORIGIN)

Move `m` along the depth axis until its centre sits at `z`. See
[`set_x!`](@ref). Depth only shows with a moved camera or with
[`apply_depth_test!`](@ref); it does not change the drawing order, which is
[`set_z_index!`](@ref)'s business.
"""
set_z!(m::Mobject, z::Real; direction = ORIGIN) = set_coord!(m, z, 3; direction)

"""
    get_x(m, direction = ORIGIN) → Float32

The x of `m`'s centre — or, with a `direction`, of that point of its box:
`get_x(m, LEFT)` is its left edge (GL's `get_x`, mobject.py:1618). The
keyword form [`set_x!`](@ref) uses, `get_x(m; direction = LEFT)`, works too.
"""
get_x(m::Mobject, dir = nothing; direction = ORIGIN) =
    get_coord(m, 1; direction = dir === nothing ? direction : dir)
"The y of `m`'s centre, or of its `direction` point — see [`get_x`](@ref)."
get_y(m::Mobject, dir = nothing; direction = ORIGIN) =
    get_coord(m, 2; direction = dir === nothing ? direction : dir)
"The z of `m`'s centre, or of its `direction` point — see [`get_x`](@ref)."
get_z(m::Mobject, dir = nothing; direction = ORIGIN) =
    get_coord(m, 3; direction = dir === nothing ? direction : dir)

"Bring the centre of `m` to the origin."
center!(m::Mobject) = shift!(m, -get_center(m))

"""
    get_corner(m, direction) → Point3f
    get_edge_center(m, direction) → Point3f

That point of `m`'s bounding box: `get_corner(m, UL)` its upper-left corner,
`get_edge_center(m, UP)` the middle of its top edge.

They are the SAME function in ManimGL (`mobject.py:1542-1545`, both call
`get_bounding_box_point`) and here — the two names say which kind of direction
you are passing, and neither checks: `get_corner(m, ORIGIN)` is the centre,
which is GL's sign trick working as designed rather than an error.
"""
get_corner(m::Mobject, direction) = get_bounding_box_point(m, direction)

"See [`get_corner`](@ref) — the same function under GL's other name."
get_edge_center(m::Mobject, direction) = get_bounding_box_point(m, direction)

# ── against the frame ───────────────────────────────────────────────────────

"""
    align_on_border!(m, direction; buff=0.5)

Push `m` against the border of the NOMINAL frame (FRAME_X_RADIUS/
FRAME_Y_RADIUS) in the given direction, leaving `buff` of margin. It only
moves the axes where `direction` is non-zero.
"""
function align_on_border!(m::Mobject, direction; buff::Real = DEFAULT_MOBJECT_TO_EDGE_BUFF)
    d = Point3f(direction)
    s = Point3f(sign(d[1]), sign(d[2]), sign(d[3]))
    target = Point3f(s[1] * FRAME_X_RADIUS, s[2] * FRAME_Y_RADIUS, 0)
    shift_val = target - get_bounding_box_point(m, d) - Float32(buff) * d
    return shift!(m, shift_val .* abs.(s))
end

"""
    to_edge!(m, edge = LEFT; buff = 0.5)

Push `m` against one edge of the frame, leaving `buff` of margin.

```julia
to_edge!(title, UP)                  # the standard title position
to_edge!(note, DOWN; buff = 0.2)
```

It only moves the axis the edge names, so a mobject sent `UP` keeps its
horizontal position. The frame it measures against is the NOMINAL one
([`FRAME_HEIGHT`](@ref)), not the camera's current view — zooming does not drag
a title off the screen.
"""
to_edge!(m::Mobject, edge = LEFT; buff::Real = DEFAULT_MOBJECT_TO_EDGE_BUFF) =
    align_on_border!(m, edge; buff)

"""
    to_corner!(m, corner = DL; buff = 0.5)

Push `m` into one corner of the frame — `UL`, `UR`, `DL` or `DR` — leaving
`buff` of margin on both edges. [`to_edge!`](@ref) with a diagonal, and it
moves both axes because a corner names both.
"""
to_corner!(m::Mobject, corner = DL; buff::Real = DEFAULT_MOBJECT_TO_EDGE_BUFF) =
    align_on_border!(m, corner; buff)

# ── against another mobject ─────────────────────────────────────────────────

"""
    next_to!(m, reference, direction=RIGHT; buff=0.25, aligned_edge=ORIGIN,
             coor_mask=(1,1,1))

Place `m` next to `reference` (a Mobject or a point) along `direction`, with
`buff` of separation. `aligned_edge` also aligns by that edge:
`next_to!(label, box, UP; aligned_edge=LEFT)` puts it above and flush with the
left side. `coor_mask` switches axes off (e.g. `(1,0,0)` = only in x).
"""
function next_to!(m::Mobject, reference, direction = RIGHT;
                  buff::Real = DEFAULT_MOBJECT_TO_MOBJECT_BUFF,
                  aligned_edge = ORIGIN, coor_mask = (1, 1, 1))
    d = Point3f(direction)
    ae = Point3f(aligned_edge)
    target = _as_point(reference, ae + d)
    anchor = get_bounding_box_point(m, ae - d)
    return shift!(m, (target - anchor + Float32(buff) * d) .* Point3f(coor_mask))
end

"""
    align_to!(m, reference, direction=ORIGIN)

`align_to!(a, b, UP)` moves `a` vertically until its top edge matches b's. It
only touches the axes where `direction` is non-zero.
"""
function align_to!(m::Mobject, reference, direction = ORIGIN)
    d = Point3f(direction)
    p = _as_point(reference, d)
    for dim in 1:3
        d[dim] == 0 || set_coord!(m, p[dim], dim; direction = d)
    end
    return m
end

"""
    match_coord!(m, reference, dim; direction = ORIGIN)

Move `m` along axis `dim` until that coordinate equals the reference's.
`reference` may be a mobject or a bare point. [`match_x!`](@ref),
[`match_y!`](@ref) and `match_z!` are the readable spellings.
"""
function match_coord!(m::Mobject, reference, dim::Int; direction = ORIGIN)
    c = reference isa Mobject ? get_coord(reference, dim; direction) :
        Point3f(reference)[dim]
    return set_coord!(m, c, dim; direction)
end

"""
    match_x!(m, reference; direction = ORIGIN)

Move `m` horizontally onto the reference's x, leaving its height alone — the
"line these two up in a column" call. See [`match_coord!`](@ref).
"""
match_x!(m::Mobject, r; direction = ORIGIN) = match_coord!(m, r, 1; direction)

"""
    match_y!(m, reference; direction = ORIGIN)

Move `m` vertically onto the reference's y — "line these two up in a row". See
[`match_coord!`](@ref).
"""
match_y!(m::Mobject, r; direction = ORIGIN) = match_coord!(m, r, 2; direction)

"""
    match_z!(m, reference; direction = ORIGIN)

Move `m` onto the reference's depth. See [`match_coord!`](@ref).
"""
match_z!(m::Mobject, r; direction = ORIGIN) = match_coord!(m, r, 3; direction)

"""
    match_dim_size!(m, other, dim; stretch = false, about_point, about_edge)

Resize `m` so that its extent along axis `dim` equals `other`'s. Uniform by
default — the other two axes follow — unless `stretch = true`.
[`match_width!`](@ref) and friends name the axis for you.
"""
match_dim_size!(m::Mobject, other::Mobject, dim::Int; kw...) =
    rescale_to_fit!(m, length_over_dim(other, dim), dim; kw...)

"""
    match_width!(m, other; stretch = false)

Scale `m` until it is as wide as `other`. Uniform by default, so the height
follows and the shape is preserved. See [`match_dim_size!`](@ref).
"""
match_width!(m::Mobject, other::Mobject; kw...) = match_dim_size!(m, other, 1; kw...)

"""
    match_height!(m, other; stretch = false)

Scale `m` until it is as tall as `other`. See [`match_width!`](@ref).
"""
match_height!(m::Mobject, other::Mobject; kw...) = match_dim_size!(m, other, 2; kw...)

"""
    match_depth!(m, other; stretch = false)

Scale `m` until its depth matches `other`'s. See [`match_width!`](@ref).
"""
match_depth!(m::Mobject, other::Mobject; kw...) = match_dim_size!(m, other, 3; kw...)

"""
    replace!(m, other; dim_to_match=1, stretch=false)

Resize and centre `m` so it OCCUPIES the place of `other` (Manim's `replace`:
the basis of BackgroundRectangle). With `stretch=true` it matches all three
dimensions; otherwise it scales uniformly by `dim_to_match`.
"""
function Base.replace!(m::VMobject, other::VMobject; dim_to_match::Int = 1,
                       stretch::Bool = false)
    if !has_points(other) && isempty(other.submobjects)
        return scale!(m, 0)
    end
    if stretch
        for i in 1:3
            rescale_to_fit!(m, length_over_dim(other, i), i; stretch = true)
        end
    else
        rescale_to_fit!(m, length_over_dim(other, dim_to_match), dim_to_match;
                        stretch = false)
    end
    return shift!(m, get_center(other) - get_center(m))
end

"""
    surround!(m, other; dim_to_match=1, stretch=false, buff=0.25)

Like `replace!` but slightly bigger — the mechanism behind
SurroundingRectangle.
"""
function surround!(m::VMobject, other::VMobject; dim_to_match::Int = 1,
                   stretch::Bool = false, buff::Real = MED_SMALL_BUFF)
    replace!(m, other; dim_to_match, stretch)
    len = length_over_dim(other, dim_to_match)
    len == 0 && return m
    return scale!(m, (len + buff) / len)
end

# ── borrowed style ──────────────────────────────────────────────────────────

"""
    get_color(m) → Vec4f

The mobject's "main" colour: the fill's when it has visible fill, the stroke's
otherwise (GL's get_color).
"""
function get_color(m::VMobject)
    has_fill = !isempty(m.fill_rgba) && m.fill_rgba[1][4] > 0
    if has_fill
        return m.fill_rgba[1]
    elseif !isempty(m.stroke_rgba)
        return m.stroke_rgba[1]
    end
    return m.default_stroke_rgba
end

"""
    set_color!(m; color, opacity=nothing, recurse=true)

Paint stroke AND fill the same colour (Manim's `set_color`). To touch just one
there are still `set_fill!` and `set_stroke!`.
"""
function set_color!(m::VMobject; color = nothing, opacity = nothing,
                    recurse::Bool = true)
    set_fill!(m; color, opacity, recurse)
    set_stroke!(m; color, opacity, recurse)
    return m
end

"""
    match_color!(m, other)

Paint `m` the colour [`get_color`](@ref) reads off `other` — its fill if that
is visible, its stroke otherwise. Colour only; for weights and opacities too,
use [`match_style!`](@ref).
"""
match_color!(m::VMobject, other::VMobject) = set_color!(m; color = get_color(other))

"""
    match_style!(m, other)

Copy `other`'s style: fill and stroke colour and opacity, width and shading.
It takes the FIRST row of the SoA style (per-point style that is not uniform
gets flattened — like GL's match_style).
"""
function match_style!(m::VMobject, other::VMobject)
    fr = isempty(other.fill_rgba) ? other.default_fill_rgba : other.fill_rgba[1]
    sr = isempty(other.stroke_rgba) ? other.default_stroke_rgba : other.stroke_rgba[1]
    sw = isempty(other.stroke_width) ? other.default_stroke_width : other.stroke_width[1]
    set_fill!(m; color = fr, opacity = fr[4])
    set_stroke!(m; color = sr, opacity = sr[4], width = sw)
    for sub in get_family(m)
        sub isa VMobject && (sub.shading = other.shading)
    end
    return m
end

# ── organising children ─────────────────────────────────────────────────────

"""
    arrange!(group, direction=RIGHT; center=true, buff=0.25, aligned_edge=ORIGIN)

Chain the children with `next_to!` along the given direction (a row with
RIGHT, a column with DOWN) and re-centre the group.
"""
function arrange!(group::Mobject, direction = RIGHT; center::Bool = true, kw...)
    # Everything with a box and a `shift!` gets placed — an ImageMobject, a
    # DecimalNumber, a nested Group (GL places them all; an `isa VMobject`
    # test would skip them in silence). What has
    # neither (a ValueTracker) is skipped, and the chain goes on from the
    # last member that was placed.
    prev = nothing
    for sub in group.submobjects
        _placeable(sub) || continue
        prev === nothing || next_to!(sub, prev, direction; kw...)
        prev = sub
    end
    center && center!(group)
    return group
end

"Has a bounding box and answers `shift!` — what `arrange!` can lay out."
_placeable(m::Mobject) =
    applicable(get_bounding_box_point, m, ORIGIN) && applicable(shift!, m, ORIGIN)

"""
    arrange_in_grid!(group; n_rows=nothing, n_cols=nothing, buff=nothing,
                     h_buff=nothing, v_buff=nothing, buff_ratio=nothing,
                     h_buff_ratio=0.5, v_buff_ratio=0.5,
                     aligned_edge=ORIGIN, fill_rows_first=true)

A grid: each child in its cell, cells as big as the widest/tallest child plus
the buff. Without `n_rows`/`n_cols` it uses √n rows. The default buffs are
proportional to the FIRST child (that is how GL does it).
"""
function arrange_in_grid!(group::VMobject; n_rows = nothing, n_cols = nothing,
                          buff = nothing, h_buff = nothing, v_buff = nothing,
                          buff_ratio = nothing,
                          h_buff_ratio::Real = 0.5, v_buff_ratio::Real = 0.5,
                          aligned_edge = ORIGIN, fill_rows_first::Bool = true)
    subs = group.submobjects
    n = length(subs)
    n == 0 && return group
    # GL divides by n_rows unguarded: with fewer children than columns it gets
    # n_rows=0 and crashes. Here the minimum is 1 (an honest fix).
    nr = n_rows === nothing ?
         (n_cols === nothing ? max(1, Int(floor(sqrt(n)))) : max(1, n ÷ n_cols)) :
         Int(n_rows)
    nc = n_cols === nothing ? max(1, n ÷ nr) : Int(n_cols)
    hb, vb = if buff !== nothing
        (Float64(buff), Float64(buff))
    else
        hr = buff_ratio === nothing ? h_buff_ratio : buff_ratio
        vr = buff_ratio === nothing ? v_buff_ratio : buff_ratio
        (h_buff === nothing ? hr * get_width(subs[1]) : Float64(h_buff),
         v_buff === nothing ? vr * get_height(subs[1]) : Float64(v_buff))
    end
    x_unit = hb + maximum(get_width, subs)
    y_unit = vb + maximum(get_height, subs)
    for (k, sm) in enumerate(subs)
        idx = k - 1
        x, y = fill_rows_first ? (idx % nc, idx ÷ nc) : (idx ÷ nr, idx % nr)
        move_to!(sm, ORIGIN; aligned_edge)
        shift!(sm, x * x_unit * RIGHT + y * y_unit * DOWN)
    end
    return center!(group)
end
