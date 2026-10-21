# Layout

**Never write coordinates by hand.** A scene built out of literal positions
breaks the moment a label gets longer or a font changes; one built out of
relationships does not.

Everything below is a mutating call taking the mobject first, and every one of
them returns it.

## Against the frame

```julia
to_edge!(title, UP)                  # against the top, 0.5 of margin
to_edge!(note, DOWN; buff = 0.2)
to_corner!(logo, UR)
center!(m)                           # centre of the frame
align_on_border!(m, LEFT; buff = 1)  # the general form
```

These measure against the NOMINAL frame ([`FRAME_HEIGHT`](@ref) = 8), not
against the camera's current view — so zooming the camera does not drag a title
off the screen. Only the axes the direction names are touched: something sent
`UP` keeps its horizontal position.

## Against another mobject

```julia
next_to!(label, box, UP; buff = 0.3)
next_to!(label, box, UP; aligned_edge = LEFT)   # above AND flush left
next_to!(m, point, RIGHT)                       # a bare point works too
align_to!(a, b, LEFT)                           # a's left edge onto b's
match_x!(a, b)                                  # line them up in a column
match_y!(a, b)                                  # …in a row
```

[`next_to!`](@ref) is the one to reach for by default. `aligned_edge` is what
makes a column of labels line up on their left instead of on their centres, and
`coor_mask = (1, 0, 0)` restricts the move to one axis.

[`move_to!`](@ref) puts a mobject's centre on a target, which may itself be a
mobject:

```julia
move_to!(m, ORIGIN)
move_to!(label, dot)
move_to!(m, box; aligned_edge = LEFT)
```

## Occupying a place

```julia
replace!(m, other)                  # m ends up where other is, at its size
surround!(box, content; buff = 0.25)
match_width!(a, b)
match_height!(a, b)
match_dim_size!(a, b, 1)
```

[`replace!`](@ref) is the mechanism behind [`BackgroundRectangle`](@ref), and
[`surround!`](@ref) behind [`SurroundingRectangle`](@ref).

## Arranging a group

```julia
arrange!(g, RIGHT; buff = 0.5)
arrange!(g, DOWN; buff = 0.4, aligned_edge = LEFT)
arrange_in_grid!(g; n_rows = 3, buff = 0.3)
```

[`arrange!`](@ref) lays the children of a group out along a direction and, by
default, re-centres the result. [`arrange_in_grid!`](@ref) takes `n_rows`,
`n_cols` or both.

## Exact coordinates, when you do want them

```julia
set_x!(m, 2.0)
set_y!(m, -1.5)
set_coord!(m, 2.0, 1; direction = LEFT)   # put its LEFT EDGE at x = 2
shift!(m, 2 * RIGHT + UP)
```

`direction` chooses which point of the mobject lands on the value — the centre
by default.

## Reading positions

```julia
get_center(m)                       # the centre of the bounding box
get_left(m); get_right(m)
get_top(m); get_bottom(m)
get_bounding_box_point(m, UR)       # any of the 27 combinations
get_width(m); get_height(m); get_depth(m)
```

The bounding box is axis-aligned and covers the whole FAMILY, so a group is as
wide as everything in it and a rotated square is wider than its side. It is
measured from the POINTS, so a thick stroke sticking out is not counted.

## Sizes

```julia
set_width!(m, 3)                        # keeps the proportions
set_width!(bar, 5; stretch = true)      # only the width moves
set_height!(m, 2)
scale!(m, 1.5)
scale!(m, 1.5; about_edge = LEFT)       # keeps the left edge nailed down
```

The standard guard against overflowing the screen:

```julia
get_width(g) > FRAME_WIDTH - 1 && set_width!(g, FRAME_WIDTH - 1)
```

## The buffs

The named gaps keep spacing consistent across a film:
[`SMALL_BUFF`](@ref) 0.1, [`MED_SMALL_BUFF`](@ref) 0.25 (the default BETWEEN
mobjects), [`MED_LARGE_BUFF`](@ref) 0.5 (the default against an EDGE),
[`LARGE_BUFF`](@ref) 1.0.

## Layout that follows

Anything above can be put in an updater and it will keep holding:

```julia
add_updater!(label, m -> next_to!(m, dot, UP; buff = 0.2))
```

Now the label follows the dot for as long as the scene runs, through
animations and physics alike. See [Updaters and trackers](updaters.md).

## Reference

[`next_to!`](@ref) · [`to_edge!`](@ref) · [`to_corner!`](@ref) ·
[`align_to!`](@ref) · [`arrange!`](@ref) · [`arrange_in_grid!`](@ref) ·
[`center!`](@ref) · [`move_to!`](@ref) · [`replace!`](@ref) ·
[`surround!`](@ref) · [`match_width!`](@ref) · [`set_x!`](@ref) —
in [the mobject reference](api_mobjects.md).
