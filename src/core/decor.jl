# core/decor.jl — composed text, holes, and the small ornaments.
#
# Compositions over the core mobjects. The one with a mechanism worth naming
# is `Cutout`, and the mechanism is not new: it is the WINDING rule the
# renderer uses for every fill. A hole is not a second
# mobject drawn in the background colour — it is a contour wound the other way
# inside the same path, so it stays a hole over any background and through any
# transform.

"""
    Paragraph(lines...; size = 0.5, line_spacing = 0.3, alignment = LEFT, …)

Several lines of text as one mobject:

```julia
Paragraph("primera línea",
          "segunda línea",
          "y una tercera")
```

The lines are laid out with [`arrange!`](@ref) and aligned on the edge you
name — `LEFT` (the default), `RIGHT` or `ORIGIN` for centred. Each line is its
own child, so `p[2]` is the second line and animations can stagger them with
`lag_ratio`.

A blank line (`""`, or only spaces) keeps its place: it is an EMPTY child, so
`p[k]` is still line `k`, and it opens a gap of one line box of the font at
this `size` — ascender to descender, the line box FreeType reports for the
face — plus one more `line_spacing`. It has no points, so it takes no part in
the paragraph's box or its centring. (Manim CE's Pango paragraph advances by
its baseline pitch instead: measured, its blank line adds 1.12× its
own line pitch, this one 1.38× — the pitches are not the same thing.)

Manim CE's `Paragraph`. Text with a newline in it would be one mobject with no
seam to grab; this gives you the seams.
"""
function Paragraph(lines::AbstractString...; size::Real = 0.5,
                   line_spacing::Real = 0.3, alignment = LEFT,
                   color = WHITE, font = nothing, kw...)
    isempty(lines) && throw(ArgumentError("a paragraph needs at least one line"))
    g = VGroup()
    blank = Bool[]
    for line in lines
        # `TextMobject("")` has no geometry; a blank line is an empty child
        # instead, and `_stack_lines!` leaves its gap
        push!(blank, isempty(strip(line)))
        if last(blank)
            add!(g, VGroup())
            continue
        end
        t = font === nothing ? TextMobject(String(line); size, color) :
            TextMobject(String(line); size, color, font)
        add!(g, t)
    end
    _stack_lines!(
        g,
        line_spacing,
        alignment,
        blank,
        any(blank) ? _line_box(font, size) : 0.0,
    )
    return VGroup(g.submobjects...; kw...)
end

"""
    BulletedList(items...; size = 0.5, line_spacing = 0.35, dot_buff = 0.25, …)

A bulleted list, with the dots placed for you:

```julia
lista = BulletedList("lo primero",
                     "lo segundo",
                     "lo tercero")
play!(scene, LaggedStartMap(FadeIn, lista))
```

Each item is a child holding its dot and its text, so `lista[2]` is the whole
second bullet — which is what you want when highlighting one line or fading
the rest.

A blank item (`""`, or only spaces) is an EMPTY child with no dot, so
`lista[k]` is still item `k`; it leaves the same gap a blank line leaves in a
[`Paragraph`](@ref) — one line box of the font at this `size`, plus one more
`line_spacing`.

Manim CE has `BulletedList` as LaTeX `\\item`s; this builds it out of
[`SmallDot`](@ref) and [`TextMobject`](@ref) instead, so it needs no LaTeX and
the dots are mobjects you can restyle.
"""
function BulletedList(items::AbstractString...; size::Real = 0.5,
                      line_spacing::Real = 0.35, dot_buff::Real = 0.25,
                      dot_color = GREY_B, color = WHITE, kw...)
    isempty(items) && throw(ArgumentError("a bulleted list needs at least one item"))
    g = VGroup()
    blank = Bool[]
    for item in items
        push!(blank, isempty(strip(item)))     # as in `Paragraph`
        if last(blank)
            add!(g, VGroup())
            continue
        end
        txt = TextMobject(String(item); size, color)
        dot = Dot(; radius = 0.045 + 0.05 * size)
        set_fill!(dot; color = dot_color, opacity = 1.0)
        next_to!(dot, txt, LEFT; buff = dot_buff)
        add!(g, VGroup(dot, txt))
    end
    # Align on the DOTS, not on the group boxes: a line whose text is taller
    # (a parenthesis, an accent) would otherwise pull its bullet out of the
    # column, and a column of bullets that wobbles is the thing you notice.
    _stack_lines!(
        g,
        line_spacing,
        LEFT,
        blank,
        any(blank) ? _line_box(nothing, size) : 0.0,
    )
    return VGroup(g.submobjects...; kw...)
end

"""
    _line_box(font, size) → Float64

The height one blank line takes: the face's line box —
`(ascender − descender) / units_per_EM`, read from FreeType — at `size`, in
scene units (a glyph's em is `size` long in `TextMobject`). `font = nothing`
is `TextMobject`'s own default face.
"""
function _line_box(font, size::Real)
    name = font === nothing ? "DejaVu Sans" : String(font)
    f = _findfont(name)
    f === nothing && throw(ArgumentError("cannot find the font «$name»"))
    rec = unsafe_load(f.ft_ptr)
    return (Float64(rec.ascender) - Float64(rec.descender)) /
           Float64(rec.units_per_EM) * size
end

"""
    _stack_lines!(g, line_spacing, aligned_edge, blank, line_box) → g

`arrange!(g, DOWN; buff = line_spacing, aligned_edge)` for lines
some of which are blank. Every ink line goes under the previous INK line with
the same `next_to!` call `arrange!` makes — so lines with no blank between
them land on the same bits as `arrange!` gives — at `line_spacing` plus, for each blank
line in between, one `line_box` and one more `line_spacing`. The blank lines
are never moved (they have no points), and `center!` centres the ink, as
`arrange!` does.
"""
function _stack_lines!(g::VMobject, line_spacing::Real, aligned_edge,
                       blank::AbstractVector{Bool}, line_box::Real)
    prev = nothing
    gap = 0                              # blank lines since the last ink line
    for (sub, b) in zip(g.submobjects, blank)
        if b
            gap += 1
            continue
        end
        buff = gap == 0 ? line_spacing : line_spacing + gap * (line_box + line_spacing)
        prev === nothing || next_to!(sub, prev, DOWN; buff, aligned_edge)
        prev = sub
        gap = 0
    end
    center!(g)
    return g
end

"""
    TexText(text; font_size = 48, …)

ManimGL's name for text typeset by LaTeX in TEXT mode — the same mobject as
[`LTex`](@ref), under the name a translated ManimGL scene uses (as
`ShowCreation` is `Create`):

```julia
TexText(raw"un \\emph{angulo} \$\\angle BAC\$")
```

Prose keeps its spaces, `\\emph`/`\\textbf` work, and `\$…\$` switches to maths
INSIDE it. Reach for it when you need LaTeX's typesetting for prose:
emphasis, small caps, a `\\newcommand` you defined in the template. For plain
words [`TextMobject`](@ref) is faster by three orders of magnitude (FreeType
directly, no subprocess), and for maths [`Tex`](@ref)'s default route needs no
LaTeX at all.

It is [`LTex`](@ref): LaTeX text mode, which is what the name means in
ManimGL, not maths mode.
"""
TexText(texts::AbstractString...; kw...) = LTex(texts...; kw...)

"""
    Cutout(shape, holes...; …)

A shape with holes in it:

```julia
queso = Cutout(Square(; side_length = 3),
               Circle(; radius = 0.5),
               Circle(; radius = 0.3, arc_center = RIGHT))
set_fill!(queso; color = YELLOW, opacity = 1.0)
```

The holes are REAL: whatever is behind shows through, at any angle and over
any background, because this is not a shape painted in the background colour.
Each hole's contour is added to the same path wound the OPPOSITE way, and the
renderer's winding rule then leaves it empty — the same mechanism that gives
an [`Annulus`](@ref) its middle, and the reason the fill is built that way.

The consequences worth knowing: a hole that sticks out past the shape cuts a
bite out of its edge rather than floating; two overlapping holes make one; and
a hole inside a hole is solid again, because the winding turns back.

Manim CE's `Cutout`.
"""
function Cutout(shape::VMobject, holes::VMobject...; kw...)
    has_points(shape) || throw(ArgumentError(
        "Cutout needs a shape with points — a group has none of its own"))
    isempty(holes) && throw(ArgumentError(
        "Cutout with no holes is just the shape — pass at least one"))
    m = vmob(:Cutout; kw...)
    set_points!(m, get_points(shape))
    match_style!(m, shape)
    for h in holes
        has_points(h) || throw(ArgumentError(
            "one of the holes has no points of its own"))
        # REVERSED, and that is the whole trick: same path, opposite winding.
        # Contour by contour: a glyph with a counter — «P»,
        # «e» — is two subpaths, and taking the hole whole fused them.
        for sp in get_subpaths(h)
            add_subpath!(m, reverse(collect(sp)))
        end
    end
    return m
end

"""
    Checkmark(; size = 0.5, color = GREEN, stroke_width = 6)

A tick. Two strokes, no LaTeX:

```julia
next_to!(Checkmark(), answer, RIGHT; buff = 0.3)
```

[`Exmark`](@ref) is the other half of the pair.
"""
function Checkmark(; size::Real = 0.5, color = GREEN, stroke_width::Real = 6.0, kw...)
    m = vmob(:Checkmark; kw...)
    set_points_as_corners!(m, (Point3f(-0.5, 0.1, 0), Point3f(-0.15, -0.35, 0),
                               Point3f(0.5, 0.45, 0)))
    scale!(m, size)
    set_stroke!(m; color, width = stroke_width)
    set_fill!(m; opacity = 0.0)
    return m
end

"""
    Exmark(; size = 0.5, color = RED, stroke_width = 6)

A cross, as the counterpart to [`Checkmark`](@ref) — two strokes through the
middle.

Not to be confused with [`Cross`](@ref), which is drawn ACROSS an existing
mobject to strike it out; this one is a mark of its own size that you place.
"""
function Exmark(; size::Real = 0.5, color = RED, stroke_width::Real = 6.0, kw...)
    a = Line(Point3f(-0.4, -0.4, 0), Point3f(0.4, 0.4, 0))
    b = Line(Point3f(-0.4, 0.4, 0), Point3f(0.4, -0.4, 0))
    g = VGroup(a, b; kw...)
    scale!(g, size)
    set_stroke!(g; color, width = stroke_width)
    return g
end

"""
    Clock(; radius = 1, hour = 12, minute = 0, …)

A clock face with two hands:

```julia
reloj = Clock(; hour = 3, minute = 30)
```

The hands are children, so `reloj[2]` is the hour hand and `reloj[3]` the
minute one — animate them with `Rotating` or by pointing them at a
[`ValueTracker`](@ref) through an updater.

The hour hand accounts for the minutes, as a real clock does: at 3:30 it sits
halfway between 3 and 4, not on the 3.
"""
function Clock(; radius::Real = 1.0, hour::Real = 12, minute::Real = 0,
               color = WHITE, stroke_width::Real = 3.0, n_ticks::Int = 12, kw...)
    face = Circle(; radius)
    set_stroke!(face; color, width = stroke_width)
    set_fill!(face; opacity = 0.0)

    ticks = VGroup()
    for k in 0:(n_ticks - 1)
        θ = PI / 2 - k * TAU / n_ticks
        outer = Point3f(radius * cos(θ), radius * sin(θ), 0)
        inner = Point3f(0.86radius * cos(θ), 0.86radius * sin(θ), 0)
        t = Line(inner, outer)
        set_stroke!(t; color, width = stroke_width * 0.7)
        add!(ticks, t)
    end

    # A real clock's hour hand moves WITH the minutes: 3:30 is halfway to 4.
    h_angle = PI / 2 - (mod(Float64(hour), 12) + Float64(minute) / 60) * TAU / 12
    m_angle = PI / 2 - Float64(minute) * TAU / 60
    hour_hand = Line(ORIGIN, Point3f(0.5radius * cos(h_angle),
                                     0.5radius * sin(h_angle), 0))
    minute_hand = Line(ORIGIN, Point3f(0.8radius * cos(m_angle),
                                       0.8radius * sin(m_angle), 0))
    set_stroke!(hour_hand; color, width = stroke_width * 1.4)
    set_stroke!(minute_hand; color, width = stroke_width)

    return VGroup(face, hour_hand, minute_hand, ticks; kw...)
end

"""
    VHighlight(m; n = 5, max_stroke = 15, color = YELLOW)

A soft glow around a mobject, built out of concentric copies of its own
outline with growing stroke width and falling opacity:

```julia
add!(scene, VHighlight(formula), formula)     # the glow FIRST, so it is behind
```

There is no blur here and no compositor — it is `n` copies of the shape, and
the halo is the stroke widths overlapping. That makes it cheap and it makes it
work in a plain render; for a real bloom, mount a
[`Composition`](@ref) with [`Bloom`](@ref).

**The numbers were chosen by looking at the render**: with `n = 5`
and 15 units of stroke the halo is about 7 px wide at 480p, which reads. A
`max_stroke` of 2 or 3 would be arithmetically fine and invisible.

ManimGL's.
"""
function VHighlight(m::VMobject; n::Int = 5, max_stroke::Real = 15.0,
                    color = YELLOW, max_opacity::Real = 0.5, kw...)
    n >= 1 || throw(ArgumentError("VHighlight needs at least one layer, got $n"))
    # NOT `has_points(m)`. A Tex or a TextMobject is a parent with no points
    # of its own — its glyphs carry them — and highlighting a formula is the
    # main thing this is for. `set_stroke!` recurses over the family, so a
    # copy of the parent gets the halo on every glyph. The first version
    # demanded points and refused exactly the case it exists to serve; found
    # by rendering it on `e^{iπ}`.
    (has_points(m) || !isempty(m.submobjects)) && true ||
        throw(ArgumentError(
            "VHighlight needs a shape with points, or a parent with children " *
            "that have them — this one has neither"))
    g = VGroup()
    for k in 1:n
        # WIDEST and FAINTEST first, so the copies drawn later sit on top and
        # the halo reads as a gradient outwards rather than as n rings.
        frac = (n - k + 1) / n
        layer = copy(m)
        set_stroke!(layer; color, width = max_stroke * frac,
                    opacity = max_opacity * (1 - frac) + 0.05)
        set_fill!(layer; opacity = 0.0)
        add!(g, layer)
    end
    return VGroup(g.submobjects...; kw...)
end

"""
    TracingTail(point_func; time_traced = 1.0, taper = true, …)

A trail behind a moving point that FADES as it ages:

```julia
cometa = Dot(); add!(scene, cometa)
add!(scene, TracingTail(() -> get_center(cometa); time_traced = 1.5))
```

[`TracedPath`](@ref) draws the whole path at one width; this one keeps only
the last `time_traced` seconds and lets the old end thin out and fade, which
is what makes it read as motion rather than as a drawing.

ManimGL's. It is `TracedPath` with a taper, and the taper is applied per
point, so the trail's own stroke carries the gradient.

**Watch the draw order**, and this is the trap: [`bring_to_back!`](@ref) also
moves a mobject's UPDATE order, so a tail sent to the back reads LAST FRAME's
position and lags exactly one frame behind the thing it follows. Use
[`set_z_index!`](@ref) to put it behind instead.
"""
function TracingTail(point_func; time_traced::Real = 1.0, stroke_width::Real = 6.0,
                     color = WHITE, taper::Bool = true, smooth::Bool = true, kw...)
    time_traced > 0 || throw(ArgumentError(
        "time_traced must be positive, got $time_traced — a tail of no " *
        "duration is TracedPath with nothing in it"))
    tail = TracedPath(point_func; time_traced, smooth,
                      stroke_color = color, stroke_width, kw...)
    taper || return tail
    # The taper rides on the SAME updater the path already has: after the
    # points are set, the per-point stroke arrays are re-weighted from the old
    # end to the new one. Adding a second updater would race with the first.
    add_updater!(tail, function (mob, dt)
        np = get_num_points(mob)
        np >= 2 || return mob
        for k in 1:np
            frac = (k - 1) / (np - 1)          # 0 at the old end, 1 at the new
            c = mob.stroke_rgba[k]
            mob.stroke_rgba[k] = Vec4f(c[1], c[2], c[3], Float32(frac))
            mob.stroke_width[k] = Float32(stroke_width * frac)
        end
        return mob
    end)
    return tail
end
