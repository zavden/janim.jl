# The shape zoo — a port of manimlib/mobject/geometry.py.
#
# Every shape is an ALIAS of VMobject{S} plus its constructor: real dispatch
# per type without inheritance. The chain Circle → Arc → rotate/scale/
# shift goes through the SAME transform machinery the whole engine uses (as in
# GL).

"""
    VGroup(mobs...; kw...)

A mobject with no points of its own whose job is to hold others, so that a
transform, a fade or an animation applies to all of them at once.

```julia
g = VGroup(Circle(), Square(), Triangle())
arrange!(g, RIGHT; buff = 0.5)
play!(scene, FadeIn(g))          # one animation, three shapes
```

Julia has no `*` splat, so Manim's `VGroup(*mobs)` is `VGroup(mobs...)` — and
watch out for the comprehension that feeds it: `[Dot() for i in 1:3, j in 1:3]`
is a MATRIX, not a flat list. Two separate `for` clauses give the flat one.

Index it like a list (`g[1]`, `g[end]`, `g[2:3]`) or by key (`g["label"]`, see
[`set_key!`](@ref)). Add and remove later with [`add!`](@ref) and
[`remove!`](@ref). For a group that must also hold non-vector mobjects (an
[`ImageMobject`](@ref), a [`Surface`](@ref)) use [`Group`](@ref).
"""
const VGroup = VMobject{:VGroup}
function (::Type{VGroup})(mobs::Mobject...; kw...)
    g = vmob(:VGroup; kw...)
    isempty(mobs) || add!(g, mobs...)
    return g
end

# ── arcs ────────────────────────────────────────────────────────────────────

function _init_arc!(m::VMobject, start_angle, angle, radius, n_components, arc_center)
    # CAREFUL: parenthesise as GL does — `15*angle/TAU` associates as
    # (15·angle)/TAU and with angle=TAU gives 14.999999999999998 → floor 14 →
    # 15 components instead of 16!
    nc = n_components === nothing ? Int(floor(15 * (abs(angle) / TAU))) + 1 : n_components
    set_points!(m, quadratic_bezier_points_for_arc(angle; n_components = nc))
    rotate!(m, start_angle; about_point = ORIGIN)
    scale!(m, radius; about_point = ORIGIN)
    shift!(m, arc_center)
    return m
end

"""
    Arc(; start_angle = 0, angle = TAU/4, radius = 1, n_components = nothing,
          arc_center = ORIGIN)

A piece of a circle, from `start_angle` and spanning `angle` radians
(counter-clockwise for a positive angle).

```julia
Arc(; angle = TAU / 2)                      # a half circle
Arc(; start_angle = PI, angle = -TAU / 4)   # clockwise, starting on the left
```

The arc is a Bézier approximation, and `n_components` says with how many
quadratic pieces: `floor(15·angle/TAU) + 1` by default, which is where a full
circle's 16 components come from. It is the primitive under [`Circle`](@ref),
[`Sector`](@ref) and [`AnnularSector`](@ref).
"""
const Arc = VMobject{:Arc}
function (::Type{Arc})(; start_angle = 0.0, angle = TAU / 4, radius = 1.0,
                       n_components = nothing, arc_center = ORIGIN, kw...)
    _init_arc!(vmob(:Arc; kw...), start_angle, angle, radius, n_components, arc_center)
end

"""
    Circle(; radius = 1, arc_center = ORIGIN, start_angle = 0)

A circle of `radius` scene units, centred on `arc_center`.

```julia
c = Circle()                                  # radius 1, coral outline
c = Circle(; radius = 2, color = BLUE)
set_fill!(c; color = BLUE, opacity = 0.5)     # a shape is born unfilled
```

Its default stroke is [`RED`](@ref) — manimlib's coral, and the one colour in
the zoo that is not [`GREY_A`](@ref). It is a full [`Arc`](@ref) underneath, so
it carries 16 quadratic components, and `start_angle` decides WHERE the path
begins, which is what [`ShowCreation`](@ref) draws from.
"""
const Circle = VMobject{:Circle}
function (::Type{Circle})(; start_angle = 0.0, radius = 1.0, arc_center = ORIGIN,
                          stroke_color = RED, kw...)
    m = vmob(:Circle; stroke_color, kw...)
    _init_arc!(m, start_angle, TAU, radius, nothing, arc_center)  # 16 components
end

# ── polygons ────────────────────────────────────────────────────────────────

function _init_polygon!(m::VMobject, vertices)
    length(vertices) >= 3 || throw(ArgumentError(
        "a polygon needs at least 3 vertices (got $(length(vertices)))"))
    vs = Point3f[Point3f(v) for v in vertices]
    set_points_as_corners!(m, push!(vs, vs[1]))   # closed: back to the first
    return m
end

"""
    Polygon(vertices...)

The closed polygon through the given vertices, in order. At least three, and
the path is closed for you — do not repeat the first point.

```julia
Polygon(ORIGIN, 2 * RIGHT, 2 * RIGHT + UP)
Polygon(UL, UR, DR, DL; color = BLUE)
```

A vertex may be a `Point3f`, a 3-tuple or any 3-element vector. Read them back
with [`get_vertices`](@ref), and round the corners with
[`round_corners!`](@ref). For the regular case use
[`RegularPolygon`](@ref).
"""
const Polygon = VMobject{:Polygon}
# CAREFUL: the varargs are TYPED as point-like — untyped varargs here would
# also intercept the default 17-field constructor that vmob() uses and cause
# infinite recursion.
# `Tuple{Real,Real,Real}`, not `NTuple{3,<:Real}` — the latter wants
# ONE element type and refused `(1, 0.5, 0)`, which every Manim user writes.
const _PointLike = Union{Point3f,Tuple{Real,Real,Real},AbstractVector{<:Real}}
(::Type{Polygon})(vertices::_PointLike...; kw...) =
    _init_polygon!(vmob(:Polygon; kw...), collect(vertices))

"""
    get_vertices(m) → Vector{Point3f}

The corners of a polygon: its anchors WITHOUT the repeated closing point, so a
triangle gives three and not four.

Meant for the closed shapes ([`Polygon`](@ref), [`Square`](@ref),
[`Star`](@ref)) — on an open path the last anchor is a real endpoint and
dropping it is not what you want; ask [`get_anchors`](@ref) there.
"""
get_vertices(m::VMobject) = get_anchors(m)[1:end-1]

_regular_vertices(n, radius, start_angle) =
    compass_directions(n, rotate_vector(Point3f(radius, 0, 0), start_angle))

"""
    RegularPolygon(n = 6; radius = 1, start_angle = nothing)

The regular `n`-gon inscribed in a circle of `radius` — so `radius` is the
distance to a VERTEX, not to an edge.

```julia
RegularPolygon(6)                    # a hexagon
RegularPolygon(5; radius = 1.5)
```

With no `start_angle` it follows ManimGL's rule: an odd `n` starts at 90° (a
vertex pointing up, which is what you expect of a pentagon) and an even one at
0°.
"""
const RegularPolygon = VMobject{:RegularPolygon}
function (::Type{RegularPolygon})(n::Int = 6; radius = 1.0, start_angle = nothing, kw...)
    sa = something(start_angle, (n % 2) * 90 * DEG)   # GL: odd→90°, even→0°
    _init_polygon!(vmob(:RegularPolygon; kw...), _regular_vertices(n, radius, sa))
end

"""
    Triangle(; radius = 1, start_angle = nothing)

The equilateral triangle inscribed in a circle of `radius`, pointing up — so
the default one is 1.7321 wide and 1.5 tall, not 1 × 1.

Its stroke is [`GREY_A`](@ref) like the rest of the zoo. Manim CE paints this
one BLUE, because there it descends from `Polygram`; Janim follows ManimGL,
and it is the most visible of the three constructor differences between the
two references.
"""
const Triangle = VMobject{:Triangle}
function (::Type{Triangle})(; radius = 1.0, start_angle = nothing, kw...)
    sa = something(start_angle, 90 * DEG)
    _init_polygon!(vmob(:Triangle; kw...), _regular_vertices(3, radius, sa))
end

"""
    Rectangle(; width = 4, height = 2)

An axis-aligned rectangle, centred on the origin, in scene units. Manim's
defaults: 4 × 2.

```julia
Rectangle(; width = 6, height = 3)
Rectangle(; width = FRAME_WIDTH, height = FRAME_HEIGHT)   # the whole frame
```

To wrap something that already exists, [`SurroundingRectangle`](@ref) measures
it for you; for soft corners, [`RoundedRectangle`](@ref).
"""
const Rectangle = VMobject{:Rectangle}
function (::Type{Rectangle})(; width = 4.0, height = 2.0, kw...)
    m = _init_polygon!(vmob(:Rectangle; kw...), (UR, UL, DL, DR))
    set_width!(m, width; stretch = true)
    set_height!(m, height; stretch = true)
    return m
end

"""
    Square(; side_length = 2)

A square of side `side_length` scene units, centred on the origin. The default
2 means the plain `Square()` reaches from -1 to 1 on both axes — the same size
as the plain [`Circle`](@ref)'s diameter, which is why the two morph into each
other so cleanly.
"""
const Square = VMobject{:Square}
function (::Type{Square})(; side_length = 2.0, kw...)
    m = _init_polygon!(vmob(:Square; kw...), (UR, UL, DL, DR))
    set_width!(m, side_length; stretch = true)
    set_height!(m, side_length; stretch = true)
    return m
end

# ═══════════════════════════════════════════════════════════════════════
# The rest of the zoo
# ═══════════════════════════════════════════════════════════════════════
# Ports of manimlib/mobject/geometry.py, except `Star`, which lives only in
# CE. Every one of them is built out of arcs, corners and
# subpaths — which is why they are shapes and not machinery.

"""
    Ellipse(; width=2, height=1, arc_center=ORIGIN)

A circle stretched to fit `width` × `height` (manim builds it exactly so, and
that is why an Ellipse keeps a circle's 16 arc components).
"""
const Ellipse = VMobject{:Ellipse}
function (::Type{Ellipse})(; width = 2.0, height = 1.0, arc_center = ORIGIN,
                           stroke_color = RED, kw...)
    m = vmob(:Ellipse; stroke_color, kw...)
    _init_arc!(m, 0.0, TAU, 1.0, nothing, arc_center)
    set_width!(m, width; stretch = true)
    set_height!(m, height; stretch = true)
    return m
end

"""
    AnnularSector(; angle=TAU/4, start_angle=0, inner_radius=1, outer_radius=2,
                    arc_center=ORIGIN)

The slice of a ring: the inner arc REVERSED, a straight jump out, the outer
arc, and the jump back. One closed contour — the second `add_subpath!` finds
its first point already under the pen, so it continues instead of cutting
(the same detail that keeps an Arrow in one piece).
"""
function _init_annular_sector!(m::VMobject, angle, start_angle, inner_radius,
                               outer_radius, arc_center)
    outer = Arc(; start_angle, angle, radius = outer_radius, arc_center)
    # radius 0 is a legitimate inner arc (that is what a Sector is), and
    # `scale!` refuses to multiply by exactly 0 (min_scale_factor) — so the
    # degenerate case is built directly instead of scaled into existence.
    inner_pts = inner_radius == 0 ?
        fill(Point3f(arc_center), get_num_points(outer)) :
        get_points(Arc(; start_angle, angle, radius = inner_radius, arc_center))
    set_points!(m, reverse(inner_pts))
    add_line_to!(m, get_points(outer)[1])
    add_subpath!(m, get_points(outer))
    add_line_to!(m, inner_pts[end])
    return m
end

"""
    AnnularSector(; angle = TAU/4, start_angle = 0, inner_radius = 1,
                    outer_radius = 2, arc_center = ORIGIN)

The slice of a ring — a pie slice with a bite taken out of the point. Filled by
default, with no outline, since it is nearly always used as a solid wedge.

It is ONE closed contour — the inner arc reversed, a jump out, the outer arc,
the jump back — so the hole comes from the winding rule and not from a mask.
[`Sector`](@ref) is this with `inner_radius = 0`, and [`Annulus`](@ref) is the
whole ring.
"""
const AnnularSector = VMobject{:AnnularSector}
(::Type{AnnularSector})(; angle = TAU / 4, start_angle = 0.0, inner_radius = 1.0,
                        outer_radius = 2.0, arc_center = ORIGIN,
                        fill_opacity = 1.0, stroke_width = 0.0, kw...) =
    _init_annular_sector!(vmob(:AnnularSector; fill_opacity, stroke_width, kw...),
                          angle, start_angle, inner_radius, outer_radius, arc_center)

"""
    Sector(; angle=TAU/4, radius=1, start_angle=0, arc_center=ORIGIN)

The pie slice — an `AnnularSector` with no hole.
"""
const Sector = VMobject{:Sector}
(::Type{Sector})(; angle = TAU / 4, radius = 1.0, start_angle = 0.0,
                 arc_center = ORIGIN, fill_opacity = 1.0, stroke_width = 0.0, kw...) =
    _init_annular_sector!(vmob(:Sector; fill_opacity, stroke_width, kw...),
                          angle, start_angle, 0.0, radius, arc_center)

"""
    Annulus(; inner_radius=1, outer_radius=2, center=ORIGIN)

The ring. Two subpaths turning in OPPOSITE directions: with winding fill that
IS the hole — no mask, no boolean op (that is how the fill works).
"""
const Annulus = VMobject{:Annulus}
function (::Type{Annulus})(; inner_radius = 1.0, outer_radius = 2.0,
                           center = ORIGIN, fill_opacity = 1.0,
                           stroke_width = 0.0, kw...)
    m = vmob(:Annulus; fill_opacity, stroke_width, kw...)
    add_subpath!(m, [Float32(outer_radius) * p
                     for p in quadratic_bezier_points_for_arc(TAU)])
    add_subpath!(m, [Float32(inner_radius) * p
                     for p in quadratic_bezier_points_for_arc(-TAU)])
    shift!(m, Point3f(center))
    return m
end

"""
    ArcBetweenPoints(start, stop; angle=TAU/4)

The arc that joins two points subtending `angle` at its centre — the curve
`round_corners!` rounds with, and the one to reach for when a straight line
would cross something. `angle=0` gives the straight line.
"""
const ArcBetweenPoints = VMobject{:ArcBetweenPoints}
function (::Type{ArcBetweenPoints})(start, stop; angle = TAU / 4,
                                    n_components = nothing, kw...)
    m = vmob(:ArcBetweenPoints; kw...)
    if angle == 0
        set_points_as_corners!(m, (LEFT, RIGHT))
    else
        _init_arc!(m, 0.0, angle, 1.0, n_components, ORIGIN)
    end
    put_start_and_end_on!(m, Point3f(start), Point3f(stop))
    return m
end

"""
    Elbow(; width=0.2, angle=0)

The little L that marks a right angle (`RightAngle` is this, placed).
"""
const Elbow = VMobject{:Elbow}
function (::Type{Elbow})(; width = 0.2, angle = 0.0, kw...)
    m = vmob(:Elbow; kw...)
    set_points_as_corners!(m, (UP, UR, RIGHT))
    set_width!(m, width; about_point = ORIGIN)
    rotate!(m, angle; about_point = ORIGIN)
    return m
end

"2D cross product — the sign says which way a corner turns."
_cross2d(a, b) = a[1] * b[2] - a[2] * b[1]

"""
    round_corners!(m, radius=nothing)

Replace every corner of a polygon with an arc tangent to both edges. With no
radius it uses a quarter of the shortest edge (manim's rule). A NEGATIVE
radius curves the corners inwards, which is manim's trick for a "bite".
"""
function round_corners!(m::VMobject, radius = nothing)
    verts = collect(get_vertices(m))
    n = length(verts)
    n >= 3 || throw(ArgumentError(
        "round_corners! needs a polygon with at least 3 vertices (got $n)"))
    if radius === nothing
        lens = [norm(verts[i] - verts[mod1(i + 1, n)]) for i in 1:n]
        radius = 0.25 * minimum(l for l in lens if l > _POINT_ATOL)
    end
    arcs = VMobject[]
    for i in 1:n
        v1, v2, v3 = verts[i], verts[mod1(i + 1, n)], verts[mod1(i + 2, n)]
        u1 = normalize(v2 - v1)
        u2 = normalize(v3 - v2)
        ang = angle_between_vectors(u1, u2)
        cut = radius * tan(ang / 2)
        s = sign(radius * _cross2d(u1, u2))
        push!(arcs, ArcBetweenPoints(v2 - Float32(cut) * u1, v2 + Float32(cut) * u2;
                                     angle = s * ang, n_components = 2))
    end
    clear_points!(m)
    arcs = [arcs[end]; arcs[1:end-1]]      # start from the LAST one, as manim does
    for i in 1:n
        add_subpath!(m, get_points(arcs[i]))
        add_line_to!(m, get_start(arcs[mod1(i + 1, n)]))
    end
    return m
end

"A rectangle with its corners rounded — `Rectangle` + `round_corners!`."
const RoundedRectangle = VMobject{:RoundedRectangle}
function (::Type{RoundedRectangle})(; width = 4.0, height = 2.0,
                                    corner_radius = 0.5, kw...)
    m = _init_polygon!(vmob(:RoundedRectangle; kw...), (UR, UL, DL, DR))
    set_width!(m, width; stretch = true)
    set_height!(m, height; stretch = true)
    return round_corners!(m, corner_radius)
end

"""
    Star(n=5; outer_radius=1, inner_radius=nothing, density=2, start_angle=TAU/4)

The n-pointed star: outer and inner vertices interleaved. With no
`inner_radius`, `density` picks the one whose edges lie on the lines of the
regular {n/density} polygram — that is what makes a 5-pointed star look like
the one you would draw without lifting the pen.
"""
const Star = VMobject{:Star}
function (::Type{Star})(n::Int = 5; outer_radius = 1.0, inner_radius = nothing,
                        density::Int = 2, start_angle = TAU / 4, kw...)
    inner_angle = TAU / (2n)
    if inner_radius === nothing
        0 < density < n / 2 || throw(ArgumentError(
            "density=$density does not work with n=$n points: it has to be in " *
            "[1, n/2). Or pass inner_radius= and choose the shape yourself."))
        outer_angle = TAU * density / n
        inverse_x = 1 - tan(inner_angle) * ((cos(outer_angle) - 1) / sin(outer_angle))
        inner_radius = outer_radius / (cos(inner_angle) * inverse_x)
    end
    outer_v = _regular_vertices(n, outer_radius, start_angle)
    inner_v = _regular_vertices(n, inner_radius, start_angle + inner_angle)
    vertices = Point3f[]
    for (o, i) in zip(outer_v, inner_v)
        push!(vertices, Point3f(o), Point3f(i))
    end
    return _init_polygon!(vmob(:Star; kw...), vertices)
end

# ═══════════════════════════════════════════════════════════════════════
# The screen rectangles and the keyed group
# ═══════════════════════════════════════════════════════════════════════
# Ports of manimlib/mobject/frame.py and of CE's VDict. Both engines were
# MEASURED rather than remembered.

"""
    ScreenRectangle(; aspect_ratio = 16/9, height = 4)

A rectangle with a screen's proportions — the frame you draw around a picture
in a picture, or the outline of a second camera's view.

```julia
box = ScreenRectangle()                          # 7.1111 × 4
box = ScreenRectangle(; height = 2, color = BLUE)
```

`width` is not a parameter: it is `aspect_ratio * height`, which is the whole
point of the shape. For the frame's own proportions at its own size use
[`FullScreenRectangle`](@ref). Manim CE and ManimGL agree on this one exactly.
"""
const ScreenRectangle = VMobject{:ScreenRectangle}
function (::Type{ScreenRectangle})(; aspect_ratio::Real = 16 / 9, height::Real = 4.0,
                                   kw...)
    m = _init_polygon!(vmob(:ScreenRectangle; kw...), (UR, UL, DL, DR))
    set_width!(m, aspect_ratio * height; stretch = true)
    set_height!(m, height; stretch = true)
    return m
end

"""
    FullScreenRectangle(; height = FRAME_HEIGHT, fill_color = GREY_E,
                          fill_opacity = 1, stroke_width = 0)

A [`ScreenRectangle`](@ref) the size of the whole frame, filled in near-black:
the backdrop you put BEHIND everything so the scene sits on a surface instead
of on the void.

```julia
add!(scene, FullScreenRectangle())          # first, so it stays at the back
```

It is `FRAME_WIDTH × FRAME_HEIGHT` and covers the nominal frame exactly.

**Manim CE's is a different mobject with the same name**: measured on 0.20.1,
CE's is white, unfilled and stroked (it only stretches the height and keeps
`Rectangle`'s style), while ManimGL's is a filled `GREY_E` panel with no
stroke. Janim ports ManimGL. For CE's behaviour ask for the shape you want:
`ScreenRectangle(; height = FRAME_HEIGHT)`.
"""
const FullScreenRectangle = VMobject{:FullScreenRectangle}
function (::Type{FullScreenRectangle})(; height::Real = FRAME_HEIGHT,
                                       aspect_ratio::Real = 16 / 9,
                                       fill_color = GREY_E, fill_opacity::Real = 1.0,
                                       stroke_width::Real = 0.0, kw...)
    m = _init_polygon!(vmob(:FullScreenRectangle; fill_color, fill_opacity,
                            stroke_width, kw...), (UR, UL, DL, DR))
    set_width!(m, aspect_ratio * height; stretch = true)
    set_height!(m, height; stretch = true)
    return m
end

"""
    FullScreenFadeRectangle(; fill_color = BLACK, fill_opacity = 0.7,
                              stroke_width = 0)

The dimmer: a full-frame black panel at 70% that you fade in over everything
to push the scene back and bring one thing forward.

```julia
veil = FullScreenFadeRectangle()
play!(scene, FadeIn(veil))              # everything behind it dims
play!(scene, FadeIn(highlight))
```

**Only ManimGL has this shape**; there is no CE equivalent. One deliberate
difference from GL: ManimGL's constructor drops the `**kwargs` it was given
on the floor (measured — asking for `height = 2` still returns a rectangle 8
units tall), so here they are forwarded and `FullScreenFadeRectangle(; height
= 2)` means what it says. Silently ignoring an argument is a defect.
"""
const FullScreenFadeRectangle = VMobject{:FullScreenFadeRectangle}
function (::Type{FullScreenFadeRectangle})(; height::Real = FRAME_HEIGHT,
                                           aspect_ratio::Real = 16 / 9,
                                           fill_color = BLACK,
                                           fill_opacity::Real = 0.7,
                                           stroke_width::Real = 0.0, kw...)
    m = _init_polygon!(vmob(:FullScreenFadeRectangle; fill_color, fill_opacity,
                            stroke_width, kw...), (UR, UL, DL, DR))
    set_width!(m, aspect_ratio * height; stretch = true)
    set_height!(m, height; stretch = true)
    return m
end

# ── VDict ───────────────────────────────────────────────────────────────────
#
# A group whose children answer to a NAME. CE keeps a parallel `submob_dict`;
# Janim does not need one, because addressing a child by key is a mechanism
# the engine already has (`set_key!`/`find_by_key`, the same one Tex,
# Matrix and TransformMatchingTex consume). So a VDict is a VGroup whose
# children carry their key, and the order is the `submobjects` vector's —
# insertion order, by construction.
#
# That matters for more than tidiness: a real `Dict` on a render path breaks
# determinism (A2), because iteration order is not the insertion order and is
# not stable across runs. There is no Dict here to break.

"""
    VDict("a" => circle, "b" => square)
    VDict(["a" => circle, "b" => square])

A [`VGroup`](@ref) whose children are addressed by name:

```julia
d = VDict("body" => Circle(), "hat" => Triangle())
d["hat"]                       # the Triangle itself
d["tail"] = Line()             # add one later
delete!(d, "hat")              # and take one out
keys(d)                        # ["body", "tail"] — insertion order
haskey(d, "body")              # true
```

It draws, transforms and animates exactly like a `VGroup`; the names are the
only difference, and they are the engine's own keys — so
[`find_by_key`](@ref) and `TransformMatchingTex` see them too.

Two rules worth knowing, both of them measured against Manim CE:

  - **The dictionary owns the label.** Putting a mobject in under `"hat"`
    calls [`set_key!`](@ref) on it, which REPLACES any key it carried. A
    mobject belongs to one dictionary under one name.
  - **Re-assigning an existing key moves the value to the end**, as CE does:
    the old child is removed and the new one appended, so `keys(d)` changes
    order. Drawing order follows.

CE's debug-only `show_keys` is not ported: it works by adding a text child to
the mobject you stored, which quietly changes YOUR mobject. `keys(d)` answers
the same question from the REPL and mutates nothing; if you want the names on
screen, put them there yourself with a `TextMobject` next to each value.
"""
const VDict = VMobject{:VDict}

function (::Type{VDict})(pairs::Pair...; kw...)
    d = vmob(:VDict; kw...)
    for (k, v) in pairs
        d[String(k)] = v
    end
    return d
end
(::Type{VDict})(pairs::AbstractVector{<:Pair}; kw...) = VDict(pairs...; kw...)
(::Type{VDict})(; kw...) = vmob(:VDict; kw...)

"The child stored under `key` — the mobject itself, not a group around it."
function Base.getindex(d::VMobject{:VDict}, key::AbstractString)
    k = String(key)
    for child in d.submobjects
        child isa VMobject && has_key(child, k) && return child
    end
    throw(KeyError(k))
end

"Store `mob` under `key`, replacing (and moving to the end) if it was taken."
function Base.setindex!(d::VMobject{:VDict}, mob::VMobject, key::AbstractString)
    k = String(key)
    haskey(d, k) && delete!(d, k)
    set_key!(mob, k)
    add!(d, mob)
    return mob
end

"Take the child stored under `key` out of the dictionary."
function Base.delete!(d::VMobject{:VDict}, key::AbstractString)
    k = String(key)
    for child in copy(d.submobjects)
        if child isa VMobject && has_key(child, k)
            remove!(d, child)
            return d
        end
    end
    throw(KeyError(k))
end

"""
    keys(d::VDict) → Vector{String}

The names in the dictionary, in insertion order. This is the one mobject whose
`keys` are names rather than indices, because it is the one mobject that IS a
dictionary; every other `keys(m)` still gives `1:length(m)`.
"""
Base.keys(d::VMobject{:VDict}) =
    String[first(get_keys(c)) for c in d.submobjects
           if c isa VMobject && !isempty(get_keys(c))]

Base.haskey(d::VMobject{:VDict}, key::AbstractString) =
    any(c -> c isa VMobject && has_key(c, String(key)), d.submobjects)

# ═══════════════════════════════════════════════════════════════════════
# Shapes built from a list of vertices
# ═══════════════════════════════════════════════════════════════════════
# Manim CE's Polygram family and ManimGL's Polyline/CubicBezier. Every one of
# them is a path over existing primitives; what they add is a
# name for a shape you would otherwise assemble by hand each time.

"""
    Polygram(group1, group2, ...)

Several closed outlines in ONE mobject:

```julia
Polygram([ORIGIN, RIGHT, UR], [2RIGHT, 3RIGHT, 3RIGHT + UP])
```

Each argument is a list of vertices and becomes its own closed subpath, so a
single `set_fill!` or `Transform` acts on the whole figure. Where a
[`VGroup`](@ref) of [`Polygon`](@ref)s gives you N mobjects that happen to
travel together, a `Polygram` is one mobject with N contours — which is what
makes the winding rule see them as one shape, holes included (the same
mechanism [`Annulus`](@ref) and `Cutout` ride).

[`RegularPolygram`](@ref) is the star-shaped case.
"""
const Polygram = VMobject{:Polygram}

function (::Type{Polygram})(groups::AbstractVector...; kw...)
    isempty(groups) && throw(ArgumentError("a Polygram needs at least one group"))
    m = vmob(:Polygram; kw...)
    for (i, g) in enumerate(groups)
        length(g) >= 3 || throw(ArgumentError(
            "group $i has $(length(g)) vertices and a closed outline needs 3"))
        vs = Point3f[Point3f(v) for v in g]
        push!(vs, vs[1])                       # closed, like Polygon
        i == 1 ? set_points_as_corners!(m, vs) : add_subpath!(m, _corner_points(vs))
    end
    return m
end

"The corner-path points of a vertex list, as `set_points_as_corners!` lays them."
function _corner_points(anchors::Vector{Point3f})
    pts = Vector{Point3f}(undef, 2 * length(anchors) - 1)
    pts[1:2:end] .= anchors
    pts[2:2:end] .= [(anchors[i] + anchors[i+1]) / 2 for i in 1:length(anchors)-1]
    return pts
end

"""
    RegularPolygram(n; density = 2, radius = 1, start_angle = nothing)

The star polygon {n/density} — join every `density`-th vertex of a regular
n-gon and keep going until you are back where you started:

```julia
RegularPolygram(5)              # the pentagram, one unbroken stroke
RegularPolygram(6)              # the star of David: TWO triangles
RegularPolygram(7; density = 3)
```

When `n` and `density` share a factor the path closes early and the figure
needs several copies, rotated between them — `gcd(6, 2) = 2` is why the
hexagram comes out as two triangles rather than one contour. That is Manim
CE's construction.

`start_angle` defaults to the same rule [`RegularPolygon`](@ref) uses, applied
to the REDUCED vertex count: odd → 90° (a point at the top), even → 0°.
Measured in CE, whose default agrees.

Not to be confused with [`Star`](@ref), which has 2n vertices and a real inner
radius; a polygram's crossings are the stroke passing over itself.
"""
const RegularPolygram = VMobject{:RegularPolygram}

function (::Type{RegularPolygram})(n::Int = 5; density::Int = 2, radius = 1.0,
                                   start_angle = nothing, kw...)
    n >= 3 || throw(ArgumentError("a polygram needs at least 3 vertices (got $n)"))
    0 < density < n || throw(ArgumentError(
        "density = $density does not work with n = $n: it has to be in [1, n)"))
    gons = gcd(n, density)
    nv, d = n ÷ gons, density ÷ gons
    nv >= 3 || throw(ArgumentError(
        "n = $n with density = $density reduces to a $nv-gon, which is not a shape"))
    sa = something(start_angle, (nv % 2) * 90 * DEG)
    groups = Vector{Vector{Point3f}}()
    for g in 0:(gons - 1)
        base = _regular_vertices(nv, radius, sa + (g / gons) * TAU / nv)
        idx, order = 1, Int[]
        while true
            push!(order, idx)
            idx = mod1(idx + d, nv)
            idx == 1 && break
        end
        push!(groups, Point3f[Point3f(base[i]) for i in order])
    end
    return Polygram(groups...; kw...)
end

"""
    ConvexHull(points...)

The smallest convex outline containing every point:

```julia
ConvexHull(ORIGIN, 2RIGHT, 2RIGHT + 2UP, 2UP, RIGHT + UP)   # a square
```

Points inside the hull are dropped — the one at the centre above contributes
nothing. Useful for drawing the boundary of a cloud, the reachable set of a
construction, or the outline of a scatter.

Andrew's monotone chain, ~30 lines and no dependency: sort by (x, y), sweep
the lower hull and then the upper one. Manim CE reaches for scipy's QuickHull
for the same answer; the hull of a point set is unique, so the two agree on
WHICH vertices — the order may start elsewhere or run the other way round,
which no shape can tell apart.

The z coordinate is ignored: this is a 2D hull, as CE's is.
"""
const ConvexHull = VMobject{:ConvexHull}

"""
Andrew's monotone chain over the xy plane. Collinear points are kept out.

Duplicates are merged by `==`, first occurrence kept: `unique` compares
with `isequal`, which tells 0.0 from -0.0 and then sorts the -0.0 twin first,
so the hull's corner would carry the sign of whichever copy sorted lower. A
dict-based merge (`dict.fromkeys`) merges them and keeps the first; so does
this.
"""
function _monotone_chain(pts::Vector{Point3f})
    firsts = Point3f[]
    for p in pts
        any(q -> q == p, firsts) || push!(firsts, p)
    end
    ps = sort(firsts; by = p -> (p[1], p[2]))
    length(ps) <= 2 && return ps
    cross(o, a, b) = (a[1] - o[1]) * (b[2] - o[2]) - (a[2] - o[2]) * (b[1] - o[1])
    half(seq) = begin
        out = Point3f[]
        for p in seq
            while length(out) >= 2 && cross(out[end-1], out[end], p) <= 0
                pop!(out)
            end
            push!(out, p)
        end
        out
    end
    lower, upper = half(ps), half(reverse(ps))
    return vcat(lower[1:end-1], upper[1:end-1])
end

# TYPED varargs, and not by taste: untyped ones also intercept the 17-field
# constructor `vmob()` calls, which recurses forever. Same trap Polygon's
# `_PointLike` was written for, and it bit again here.
function (::Type{ConvexHull})(points::_PointLike...; kw...)
    pts = Point3f[Point3f(p) for p in points]
    length(pts) >= 3 || throw(ArgumentError(
        "a hull needs at least 3 points (got $(length(pts)))"))
    hull = _monotone_chain(pts)
    length(hull) >= 3 || throw(ArgumentError(
        "those $(length(pts)) points are collinear, so their hull is a segment " *
        "and not a shape — use Line for that"))
    return _init_polygon!(vmob(:ConvexHull; kw...), hull)
end

"""
    Polyline(vertices...)

An OPEN path through the points, in order:

```julia
Polyline(ORIGIN, RIGHT + UP, 2RIGHT, 3RIGHT + DOWN)
```

The one difference from [`Polygon`](@ref) is that it does not close, which
makes it the right shape for a route, a trace or a profile. ManimGL's;
Manim CE has no such class.

Each segment is a degenerate quadratic (the handle at the midpoint), so
`point_from_proportion`, `ShowCreation` and `make_smooth!` all read it like
any other path.
"""
const Polyline = VMobject{:Polyline}

function (::Type{Polyline})(vertices::_PointLike...; kw...)
    length(vertices) >= 2 || throw(ArgumentError(
        "a polyline needs at least 2 points (got $(length(vertices)))"))
    m = vmob(:Polyline; kw...)
    set_points_as_corners!(m, Point3f[Point3f(v) for v in vertices])
    return m
end

"""
    CubicBezier(a0, h0, h1, a1)

One cubic Bézier from `a0` to `a1`, pulled towards the handles `h0` and `h1`:

```julia
CubicBezier(ORIGIN, UP + RIGHT, DOWN + 2RIGHT, 3RIGHT)
```

The engine's paths are QUADRATIC (manimlib's, and the shader's), so the cubic
is split at t = ½ and each half approximated by the quadratic through its
midpoint — `_cubic_to_two_quadratics`, the same conversion the font loader and
the SVG importer use. The result is two curves, not one, and the endpoints and
tangents are exact.

Present in both engines with this signature.
"""
const CubicBezier = VMobject{:CubicBezier}

function (::Type{CubicBezier})(a0::_PointLike, h0::_PointLike,
                               h1::_PointLike, a1::_PointLike; kw...)
    p0, c1, c2, p1 = Point3f(a0), Point3f(h0), Point3f(h1), Point3f(a1)
    q1, mid, q2 = _cubic_to_two_quadratics(p0, c1, c2, p1)
    m = vmob(:CubicBezier; kw...)
    set_points!(m, (p0, Point3f(q1), Point3f(mid), Point3f(q2), p1))
    return m
end

"""
    ArcPolygon(corners...; radius = nothing, angle = PI/4)

A closed figure whose SIDES ARE ARCS instead of straight lines:

```julia
ArcPolygon(ORIGIN, 2RIGHT, RIGHT + 2UP; angle = PI / 3)
ArcPolygon(ORIGIN, 2RIGHT, RIGHT + 2UP; radius = 2)
```

Say how much each side bows with `angle` (the arc's own angle, positive =
bulging left of travel) or with `radius`, which is the same thing said as a
circle. A `radius` smaller than half a side's length has no arc that reaches —
Manim CE raises there and so does this.

One mobject with one closed contour, so it fills and transforms as a unit.
Manim CE's; ManimGL has no equivalent.
"""
const ArcPolygon = VMobject{:ArcPolygon}

function (::Type{ArcPolygon})(corners::_PointLike...; radius = nothing,
                              angle = PI / 4, kw...)
    n = length(corners)
    n >= 3 || throw(ArgumentError("an arc polygon needs at least 3 corners (got $n)"))
    # An Int radius would make `2 * radius` an Int and `d / (2r)` a
    # Float32 (d is Float32), so the sweep would come out in single precision and
    # `radius = 3` would differ from `radius = 3.0` by an ulp. Radii are Float64.
    radius === nothing || (radius = Float64(radius))
    pts = Point3f[Point3f(c) for c in corners]
    m = vmob(:ArcPolygon; kw...)
    for i in 1:n
        a, b = pts[i], pts[mod1(i + 1, n)]
        # `radius` is said in angles here. Janim's ArcBetweenPoints takes only
        # the central angle, so the circle is converted rather than the shape
        # being taught a second way in: a chord d on a circle of radius r
        # subtends 2·asin(d / 2r), and no arc reaches when r < d/2 — which is
        # where Manim CE raises too.
        θ = angle
        if radius !== nothing
            d = sqrt(sum(abs2, b - a))
            2 * radius >= d || throw(ArgumentError(
                "radius $radius is smaller than half the distance between " *
                "corners $i and $(mod1(i + 1, n)) ($(round(d / 2; digits = 4))): " *
                "no circular arc joins them"))
            θ = 2 * asin(d / (2 * radius))
        end
        arc = ArcBetweenPoints(a, b; angle = θ)
        i == 1 ? set_points!(m, get_points(arc)) : add_subpath!(m, get_points(arc))
    end
    return m
end

# ═══════════════════════════════════════════════════════════════════════
# The arc centre read off the curve, a point by angle, and the
# one-point VMobject
# ═══════════════════════════════════════════════════════════════════════

"GL's `find_intersection` (space_ops.py:298) for one pair of rays: the point on `p0 + t·v0` closest to `p1 + s·v1` — their crossing, in the plane."
function _find_intersection(p0, v0, p1, v1; threshold::Real = 1e-5)
    P0 = SVector{3,Float64}(p0[1], p0[2], p0[3])
    V0 = SVector{3,Float64}(v0[1], v0[2], v0[3])
    P1 = SVector{3,Float64}(p1[1], p1[2], p1[3])
    V1 = SVector{3,Float64}(v1[1], v1[2], v1[3])
    d = P1 - P0
    if P0[3] != 0 || V0[3] != 0 || P1[3] != 0 || V1[3] != 0
        cp1 = cross(V1, d)
        cp2 = cross(V1, V0)
        numer, denom = dot(cp1, cp1), dot(cp1, cp2)
    else
        numer = V1[1] * d[2] - V1[2] * d[1]      # cross2d(v1, p1 - p0)
        denom = V1[1] * V0[2] - V1[2] * V0[1]    # cross2d(v1, v0)
    end
    abs(denom) < threshold && (denom = Inf)
    return Point3f(P0 + (numer / denom) * V0)
end

"""
    get_arc_center(m) → Point3f

Where the arc `m` was drawn around, read off the curve itself: the normals at
its first two anchors meet there (GL's `get_arc_center`, geometry.py:247).
Being derived from the points it survives every shift and rotation; on a full
circle it is the centre.
"""
function get_arc_center(m::VMobject)
    length(m.points) >= 3 || throw(ArgumentError(
        "get_arc_center needs a curve to read: this $(tag(m)) has $(length(m.points)) points"))
    a1, h, a2 = m.points[1], m.points[2], m.points[3]
    n1 = rotate_vector(h - a1, TAU / 4)
    n2 = rotate_vector(h - a2, TAU / 4)
    return _find_intersection(a1, n1, a2, n2)
end

"The angle of `m`'s first point around [`get_arc_center`](@ref), in `[0, 2π)` (GL's `get_start_angle`, geometry.py:262)."
get_start_angle(m::VMobject) = mod(angle_of_vector(get_start(m) - get_arc_center(m)), TAU)

"""
    point_at_angle(c, angle) → Point3f

The point of the circle `c` at `angle` radians from its centre, counter-
clockwise from the x axis (GL's `Circle.point_at_angle`, geometry.py:413). It
walks the Bézier — `point_from_proportion` at the matching fraction of the
turn — so it lands ON the drawn curve, 0.0014–0.0018 units off the analytic
`centre + r·(cos, sin)`; and it measures from the circle's own start, so a
rotated circle still answers with the absolute angle. GL gives it to `Circle`
and to what descends from it (`Dot`, `Ellipse`), not to an `Arc`.
"""
point_at_angle(c::Union{VMobject{:Circle},VMobject{:Dot},VMobject{:Ellipse}}, angle::Real) =
    point_from_proportion(c, mod(angle - get_start_angle(c), TAU) / TAU)

"""
    VectorizedPoint(location = ORIGIN; color = BLACK, fill_opacity = 0, stroke_width = 0, kw...)

A VMobject with a single point and nothing to draw (GL's `VectorizedPoint`,
vectorized_mobject.py:1366): a place-holder to add, move, animate, or aim a
`Transform` at. It measures 1e-6 across, like GL's `Point`, so that
`set_width!`-style rescaling never divides by zero.
"""
const VectorizedPoint = VMobject{:VectorizedPoint}
function (::Type{VectorizedPoint})(location = ORIGIN; color = BLACK,
                                   fill_opacity::Real = 0.0, stroke_width::Real = 0.0,
                                   kw...)
    m = vmob(:VectorizedPoint; fill_color = color, fill_opacity, stroke_color = color,
             stroke_width, kw...)
    set_points!(m, (Point3f(location),))
    return m
end
function length_over_dim(m::VMobject{:VectorizedPoint}, dim::Int)
    1 <= dim <= 3 || throw(ArgumentError(
        "dim=$dim does not exist: 1=width(x), 2=height(y), 3=depth(z)"))
    return 1.0f-6                        # GL's Point: artificial_width/height
end
