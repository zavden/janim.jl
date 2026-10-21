# The shape zoo

Every shape is a [`VMobject`](@ref) with a different tag, and every one of them
takes the style keywords `color`, `stroke_color`, `stroke_width`, `fill_color`,
`fill_opacity` and `key` on top of its own.

Sizes are in SCENE UNITS: the nominal frame is [`FRAME_HEIGHT`](@ref) = 8 tall
and [`FRAME_WIDTH`](@ref) ≈ 14.22 wide, whatever resolution you render at.

## Round

```julia
Circle(; radius = 1, arc_center = ORIGIN, start_angle = 0)
Arc(; start_angle = 0, angle = TAU/4, radius = 1, arc_center = ORIGIN)
Ellipse(; width = 2, height = 1, arc_center = ORIGIN)
ArcBetweenPoints(start, stop; angle = TAU/4)
Sector(; angle = TAU/4, radius = 1, start_angle = 0)
AnnularSector(; angle = TAU/4, inner_radius = 1, outer_radius = 2)
Annulus(; inner_radius = 1, outer_radius = 2, center = ORIGIN)
```

[`Circle`](@ref) is the one shape whose default stroke is not grey: it is
[`RED`](@ref), manimlib's coral. It is a full [`Arc`](@ref) underneath, so it
carries 16 quadratic components, and `start_angle` decides where the path
begins — which is where [`ShowCreation`](@ref) starts drawing.

[`Annulus`](@ref) is two subpaths turning in OPPOSITE directions. With a
winding fill, that IS the hole: no mask, no boolean operation.
[`ArcBetweenPoints`](@ref) with `angle = 0` gives the straight line, which
makes it safe to interpolate the bend.

## Straight

```julia
Polygon(vertices...)
RegularPolygon(n = 6; radius = 1, start_angle = nothing)
Triangle(; radius = 1)
Rectangle(; width = 4, height = 2)
Square(; side_length = 2)
RoundedRectangle(; width = 4, height = 2, corner_radius = 0.5)
Star(n = 5; outer_radius = 1, density = 2, start_angle = TAU/4)
Elbow(; width = 0.2, angle = 0)
```

The radius of [`RegularPolygon`](@ref), [`Triangle`](@ref) and [`Star`](@ref)
is the distance to a VERTEX, so the default `Triangle()` is 1.7321 wide and 1.5
tall rather than 1 × 1.

[`round_corners!`](@ref) rounds any polygon after the fact, and a NEGATIVE
radius curves the corners inwards for a bite.

## Lines, arrows and dots

```julia
Line(start = LEFT, stop = RIGHT; buff = 0, path_arc = 0)
Arrow(start = LEFT, stop = RIGHT; buff = 0.25, path_arc = 0, thickness = 3.0)
Dot(point = ORIGIN; radius = 0.08)
```

**The endpoints may be MOBJECTS**, and then their facing edges are used:

```julia
Arrow(box_a, box_b; buff = 0.15)
```

That, with `buff`, is what keeps an arrow from burying its head in the thing it
points at when either box moves. `path_arc` bends it.

Read a line back with [`get_start`](@ref), [`get_end`](@ref),
[`get_vector`](@ref), [`get_unit_vector`](@ref), [`get_angle`](@ref) and
[`get_arc_length`](@ref). An [`Arrow`](@ref) answers `get_end` with its TIP,
not with a literal last point.

## Annotations

```julia
Brace(m, direction = DOWN; buff = 0.2)
BraceLabel(m, text, direction = DOWN; buff = 0.2, label_buff = 0.15)
SurroundingRectangle(m; buff = 0.1, color = YELLOW, stroke_width = 2)
BackgroundRectangle(m; color = BLACK, opacity = 0.75, buff = 0.1)
Underline(m; buff = 0.1, stroke_width = 3.0)
Cross(m; color = RED, stroke_width = 6.0)
DashedLine(p1, p2; dash_length = 0.1, positive_space_ratio = 0.5)
DashedVMobject(m; num_dashes = 15, positive_space_ratio = 0.5)
Angle(line1, line2; radius = nothing, quadrant = (1, 1), other_angle = false)
RightAngle(line1, line2; length = 0.4)
```

These MEASURE the thing they annotate, so they are placed by giving them the
mobject rather than coordinates. [`DashedVMobject`](@ref) dashes any path, not
just a straight one. [`angle_value`](@ref) reads an [`Angle`](@ref) back as a
number, and [`line_intersection`](@ref) finds where two lines cross.

## Groups

```julia
VGroup(mobs...)          # vector mobjects only
Group(mobs...)           # anything: a Surface, an ImageMobject, a ValueTracker
```

## Grids and tables

```julia
MatrixMobject([1 2; 3 4])                       # native stretchable brackets
Table(entries; row_labels, col_labels, include_outer_lines = true)
```

Read them with [`get_entries`](@ref), [`get_rows`](@ref),
[`get_columns`](@ref), [`get_cell`](@ref), [`get_brackets`](@ref) and
[`get_lines`](@ref) — or by the key `"(i,j)"`. See [Text and
formulas](text.md).

## Particles

```julia
DotCloud(points; color, radius, glow_factor)
TrueDot(point; radius)
GlowDot(point; radius, glow_factor = 2)
GlowDots(points; radius, glow_factor = 2)
```

A cloud is ONE mobject holding many points, drawn through the GPU's point
pipeline — which is how a million particles stay a single draw call. Their
radii are their own array ([`set_radii!`](@ref), [`get_radii`](@ref)), so an
updater can drive size and position independently.

Careful with the pair of names: [`scale!`](@ref) on a cloud moves the POINTS
(the particles spread apart) while [`scale_radii!`](@ref) makes the dots
bigger.

## Fields

```julia
VectorField(f; x_range, y_range)
TimeVaryingVectorField(f; …)
StreamLines(f; …)
AnimatedStreamLines(f; …)
```

One batched VMobject per field rather than one mobject per arrow, integrated
with RK4. [`update_vectors!`](@ref) re-evaluates a field whose function moved,
and [`ode_solution_points`](@ref) gives you the raw trajectory.

## 3D

```julia
Surface(uv_func; u_range, v_range, resolution = (101, 101))
Sphere(; radius = 1, resolution = (101, 51))
Torus(; …)
PlaneXY(; …)
Cylinder(; radius = 1, height = 2, direction = OUT)
Cone(; base_radius = 1, height = 1, direction = OUT)
Dot3D(point = ORIGIN; radius = 0.08)
Line3D(start = LEFT, stop = RIGHT; thickness = 0.02)
Arrow3D(start = LEFT, stop = RIGHT; thickness = 0.02, height = 0.3)
```

See [3D and the camera](three_d.md).

## From outside

```julia
SVGMobject("logo.svg")               # paths, groups, gradients, <text>
ImageMobject("photo.png")            # a textured quad
TexturedSurface(surface, "map.png")  # an image mapped onto a mesh
```

[`clip_layers`](@ref) turns an SVG's clip paths into the compositor's layers
and masks.

## Building your own

The base constructor IS the extension seam:

```julia
v = VMobject(:MyShape; color = BLUE, stroke_width = 6)
start_new_path!(v, ORIGIN)
add_line_to!(v, 2 * RIGHT)
add_quadratic_bezier_to!(v, 2 * RIGHT + UP, UP)
```

`VMobject(:Tag; kw...)` gives an empty VMobject whose tag is yours, which
means it dispatches as its own type (`vmob(:Tag)` is an alias for the same
call). See [Extending the engine](extending.md) and, for
the path API, [`set_points_as_corners!`](@ref),
[`set_points_smoothly!`](@ref), [`add_subpath!`](@ref) and
[`start_new_path!`](@ref).

## Reference

[The mobject reference](api_mobjects.md) has all of them with their full
signatures.
