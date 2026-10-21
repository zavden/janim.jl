# Mobjects

A *mobject* is anything that can be put on stage. Everything you draw is one,
and so is the camera.

## One type, no hierarchy

The abstract supertype is [`Mobject`](@ref), and under it sits the workhorse:
[`VMobject`](@ref), a shape made of quadratic Bézier curves. The familiar names
are not subclasses — they are the same struct with a different type parameter:

```julia
Circle === VMobject{:Circle}
Square === VMobject{:Square}
VGroup === VMobject{:VGroup}
```

One struct, no inherited fields, no method forwarding, and dispatch still works
per shape: `interpolate(::Circle, ::Square, α)` can be a method. [`tag`](@ref)
reads the parameter back off an instance.

The other mobjects are the ones a Bézier path cannot describe:
[`ImageMobject`](@ref) and [`TexturedSurface`](@ref) (raster),
[`Surface`](@ref) (a uv mesh), [`DotCloud`](@ref) (particles),
[`ValueTracker`](@ref) (a number), [`CameraFrame`](@ref) (the camera).

## Points and style

A `VMobject` holds its points in one flat vector, in the interleaved layout
`anchor, handle, anchor, handle, …, anchor` — already the layout the GPU wants,
with no conversion step anywhere.

Style lives **per point**, one array per attribute, which is what makes a
gradient along a curve a column of colours rather than a special case:

```julia
set_fill!(m; color = YELLOW, opacity = 1.0)
set_stroke!(m; color = WHITE, width = 4)
set_color!(m; color = BLUE)               # both at once
set_opacity!(m, 0.5)                      # both opacities
```

**A shape is born with `fill_opacity = 0`.** Setting only the colour changes
nothing you can see; the opacity is the half people forget.

Colour is a hex `String`, a `Colorant`, or a `Vec4f`. There is no colour type
to construct, so `"#D147BD"` is as valid as [`BLUE`](@ref).

### The palette

The 94 exported colour names are **ManimGL's 70 together with Manim CE's 89**,
at the engines' own hex values, so a scene ported from either keeps its
colours. They come in nine families of five, lightest to darkest, and the bare
name is the middle one:

```julia
BLUE_A, BLUE_B, BLUE_C, BLUE_D, BLUE_E        # and BLUE === BLUE_C
```

The families are `BLUE`, `TEAL`, `GREEN`, `YELLOW`, `GOLD`, `RED`, `MAROON`,
`PURPLE` and `GREY`, plus [`WHITE`](@ref), [`BLACK`](@ref), the browns, the
pinks, [`ORANGE`](@ref), the pure channels ([`PURE_RED`](@ref) and friends) and
Manim CE's logo colours. Every grey answers to both spellings — [`GREY_B`](@ref)
and [`GRAY_B`](@ref) are the same constant.

**On three names the two engines disagree, and Janim follows ManimGL**, which
is what it ports:

| | ManimGL | Manim CE | Janim |
|---|---|---|---|
| [`YELLOW`](@ref) / [`YELLOW_C`](@ref) | `#FFFF00` | `#F7D96F` | `#FFFF00` |
| [`BLUE_E`](@ref) | `#1C758A` | `#236B8E` | `#1C758A` |

Neither CE value is lost: `#236B8E` is [`DARK_BLUE`](@ref), the name CE itself
also gives it, and the whole CE palette lives at CE's values in
`Janim.ManimCE` for a scene that has to match a CE render:

```julia
set_fill!(m; color = Janim.ManimCE.YELLOW)     # "#F7D96F", CE's soft gold
```

Beyond the named palette, `colorant"tomato"` reaches every CSS name through
Colors.jl, [`color_gradient`](@ref) and [`colormap_colors`](@ref) build ramps,
and Manim CE's six catalogues are submodules of their own — `Janim.X11`,
`Janim.XKCD`, `Janim.SVGNAMES`, `Janim.AS2700`, `Janim.BS381`,
`Janim.DVIPSNAMES`, 2138 names that are deliberately NOT exported:

```julia
set_fill!(m; color = Janim.XKCD.MUDDYGREEN)    # "#657432"
using Janim.DVIPSNAMES                         # or bring one in whole
```

The full list with every hex is [the palette reference](api_palette.md).

Ask, rather than remember:

```julia
get_color(m)          # the fill's if it is visible, the stroke's otherwise
get_opacity(m)
get_num_points(m)
has_points(m)         # false for a group: it has children, not points
```

### The factory style, and the updater trap

Every mobject also carries a *factory* style that NEW points inherit. That is
the mechanism behind the most common Janim bug:

> A mobject whose points are rebuilt inside an updater must be born with its
> final style. New points re-stamp the factory style, so a `set_fill!`
> afterwards — or a fade — writes on water.

```julia
trail = VMobject(; color = YELLOW, stroke_width = 3)   # born right
add_updater!(trail, m -> set_points_smoothly!(m, history))
```

## The family

Mobjects form a tree. [`add!`](@ref) makes children, [`remove!`](@ref) unlinks
them, and children know their parents, so invalidation travels upwards.

```julia
g = VGroup(a, b, c)
add!(g, d)
get_family(g)          # g first, then every descendant, depth first
```

[`get_family`](@ref) is what almost everything walks: a transform, a fade, a
bounding box, the renderer. It is cached, and any change in the subtree
invalidates it up through the parents.

Two consequences worth holding on to:

- **Transforms and style recurse by default.** `shift!(g, RIGHT)` moves
  everything in `g`; `set_fill!(g; color = RED)` paints everything in `g`.
  Pass `recurse = false` to touch only the node.
- **Children inherit nothing at creation.** Adding a child does not give it the
  parent's colour or position. What it joins is being moved and faded together.

### Groups

[`VGroup`](@ref) holds vector mobjects; [`Group`](@ref) holds anything,
including a `Surface` or a `ValueTracker`. Julia has no `*` splat:

```julia
g = VGroup(mobs...)                # Manim: VGroup(*mobs)
```

Watch the comprehension that feeds it — `[Dot() for i in 1:3, j in 1:3]` is a
`Matrix`, not a flat list. Two separate `for` clauses give the flat one, and
`vec(...)` flattens a matrix you already have.

## Addressing children by key

A mobject can carry labels saying what it REPRESENTS, as opposed to what it IS:

```julia
set_key!(m, "highlight")
add_key!(m, "row 2")            # one more, keeping the others
find_by_key(g, "highlight")     # the children that match
g["highlight"]                  # the same, memoised, as a VGroup
```

This is one mechanism, not four: it is what `tex["x"]`,
[`TransformMatchingTex`](@ref), a [`Table`](@ref)'s `"(2,3)"` cells and an
imported SVG's element ids all use. Indexing also works positionally — `g[1]`,
`g[end]`, `g[2:4]`.

## Copies, and becoming something else

```julia
b = copy(a)             # a deep copy: points, style, children
become!(a, b)           # a takes on b's shape and style, keeping its identity
match_style!(a, b)      # style only
```

[`become!`](@ref) is recursive over the children. When the two structures
differ it REPLACES the children with copies of the other's — so a reference you
were holding to an old child is left orphaned. That is the price of the
identity staying stable, and identity stability is what lets a group, the
scene and the compositor keep pointing at the same object across a rebuild.

[`pointwise_become_partial!`](@ref) is NOT recursive: on a parent with no
points of its own — a [`Tex`](@ref), a group — it does nothing at all. The
creation animations walk the family themselves for exactly this reason.

## Draw order

The order is the order of the lists, and it is stable.

```julia
set_z_index!(m, 1)         # higher draws later, i.e. on top
bring_to_front!(g, child)
bring_to_back!(g, child)
```

Equal z keeps insertion order, so a scene that never sets one draws exactly as
it always did.

**`bring_to_back!` also moves the UPDATE order.** A [`TracedPath`](@ref) sent
to the back reads last frame's position and lags exactly one frame behind. When
a mobject's updater reads state another updater writes, use
[`set_z_index!`](@ref) instead — it changes what is drawn on top without
touching who runs first.

## How a stroke turns a corner

```julia
set_joint_type!(m, :miter)     # :auto (default), :miter, :bevel, :no_joint
get_joint_type(m)
```

[`JOINT_TYPES`](@ref) are manimlib's four codes with manimlib's default, so a
scene that never calls this renders exactly as it did before the setting
existed. It only shows where a corner is SHARP and the stroke thick: `:auto`
behaves like `:miter` until the turn passes the threshold and then eases
towards `:bevel`.

**There is no `:round`**, and asking for one is an error rather than a silent
substitution. The join is computed in a geometry shader ported from manimlib,
which has no round join; ManimCE's `LineJointType.ROUND` comes from its Cairo
backend — so a scene ported from CE is exactly the case that would otherwise
get something else without being told.

One measured divergence from manimlib, kept on purpose: at a hairpin, `:bevel`
extends less here (tip at 555 px against manimlib's 687 on the same frame),
because the miter shift is clamped to ±4. Unclamped, that shift opened real
holes in a helix under a grazing view, and a truncated spike is the cheaper
price. `:auto` and `:miter` agree with manimlib to the pixel.

An imported SVG's `stroke-linejoin` is honoured when the document states it
(`miter`, `bevel`); absent, the engine's `:auto` stands — SVG's own default is
`miter`, and taking it literally would retag every path ever imported.

## Reference

The whole mobject API is in [the mobject reference](api_mobjects.md).
Starting points: [`Mobject`](@ref), [`VMobject`](@ref), [`VGroup`](@ref),
[`add!`](@ref), [`get_family`](@ref), [`set_fill!`](@ref),
[`set_stroke!`](@ref), [`set_key!`](@ref), [`become!`](@ref),
[`set_z_index!`](@ref).
