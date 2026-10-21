# core/tables.jl — MatrixMobject and Table.
#
# Both are pure composition over what already exists: entries built by a
# constructor the caller chooses (Tex for a matrix, TextMobject for a table),
# placed by the grid layout, addressed by keys — plus brackets and
# rules drawn as NATIVE paths.
#
# Why native brackets: the same reasoning as for `Brace`. A `[` that is
# really a LaTeX glyph has to be compiled and then stretched, which distorts
# its strokes; four corners and a stroke width give a bracket that fits ANY
# height exactly and needs no LaTeX installed. The rule stands: LaTeX is for
# the MATHS the user writes, never for the engine's own decorations.

"""
    matrix_bracket(height, width; left=true)

One bracket of the `[ ]` pair as a stroked path: serif, spine, serif.
"""
function matrix_bracket(height::Real, width::Real; left::Bool = true,
                        color = WHITE, stroke_width::Real = 4.0)
    h = Float32(height) / 2
    w = Float32(width) * (left ? 1 : -1)
    br = vmob(:Bracket)
    set_points_as_corners!(br, (Point3f(w, h, 0), Point3f(0, h, 0),
                                Point3f(0, -h, 0), Point3f(w, -h, 0)))
    set_stroke!(br; color, width = stroke_width)
    set_fill!(br; opacity = 0)
    return br
end

"An entry: a mobject passes through, anything else goes through `cell`."
_as_cell(x::Mobject, cell) = x
_as_cell(x, cell) = cell(x isa AbstractString ? String(x) : string(x))

"""
    MatrixMobject(entries; cell=Tex, h_buff=1.3, v_buff=0.8, …)

A matrix with brackets:

    m = MatrixMobject([1 2; 3 4])
    m = MatrixMobject(["a" "b"; "c" "d"]; cell = s -> Tex(s; size = 0.9))

`entries` is any 2D array — of strings, of numbers, or of mobjects you have
already built. Each entry is labelled with the key `"(i,j)"`, so `m["(1,2)"]`
is the top-right one and `TransformMatchingTex` can pair entries between two
matrices for free.

The name: Julia's `Matrix` is its own 2D array type, so shadowing it would
break every `Matrix{Float64}` in the user's code. `TextMobject` carries the
same suffix for the same reason.

Reading it back: `get_entries`, `get_rows`, `get_columns`, `get_brackets`.
"""
const MatrixMobject = VMobject{:Matrix}

function (::Type{MatrixMobject})(entries::AbstractMatrix; cell = s -> Tex(s),
                                 h_buff::Real = 1.3, v_buff::Real = 0.8,
                                 bracket_h_buff::Real = 0.2,
                                 bracket_v_buff::Real = 0.25,
                                 bracket_width::Real = 0.22,
                                 color = WHITE, stroke_width::Real = 4.0, kw...)
    nrows, ncols = size(entries)
    (nrows > 0 && ncols > 0) || throw(ArgumentError(
        "a matrix needs at least one entry (got $(nrows)×$(ncols))"))
    m = vmob(:Matrix; kw...)
    body = VGroup()
    for i in 1:nrows, j in 1:ncols
        e = _as_cell(entries[i, j], cell)
        # a DecimalNumber cell is keyed too (through its group)
        (e isa VMobject || e isa _Wrapper) && set_key!(e, "($i,$j)")
        # manim's pitch grid: entries sit on fixed centres, so columns line up
        # by their MIDDLE even when one entry is much wider than the rest
        move_to!(e, Point3f((j - 1) * h_buff, -(i - 1) * v_buff, 0))
        add!(body, e)
    end
    center!(body)
    add!(m, body)

    h = get_height(body) + 2 * bracket_v_buff
    left = matrix_bracket(h, bracket_width; left = true, color, stroke_width)
    right = matrix_bracket(h, bracket_width; left = false, color, stroke_width)
    next_to!(left, body, LEFT; buff = bracket_h_buff)
    next_to!(right, body, RIGHT; buff = bracket_h_buff)
    brackets = VGroup(left, right)
    add!(m, brackets)
    center!(m)
    return m
end

"The entries of a matrix or table, in reading order (row-major)."
get_entries(m::VMobject) = m.submobjects[1]

"""
Every cell as ((i,j) => mobject), read back from the keys rather than
from the child order — that way a Table with an empty corner and a Matrix
with none are read by the same code.
"""
function _cells_by_index(m::VMobject)
    out = Tuple{Int,Int,Mobject}[]
    for sub in Iterators.drop(get_family(m), 1)
        for k in get_keys(sub)
            (startswith(k, "(") && endswith(k, ")")) || continue
            parts = split(k[2:end-1], ',')
            length(parts) == 2 || continue
            i = tryparse(Int, parts[1]); j = tryparse(Int, parts[2])
            (i === nothing || j === nothing) && continue
            push!(out, (i, j, _cell_node(sub)))    # the number, not its glyphs
        end
    end
    sort!(out; by = t -> (t[1], t[2]))
    return out
end

"The rows of a matrix or table, as a VGroup of VGroups (memoised)."
function get_rows(m::VMobject)
    _memoized_group(m, :rows) do
        cells = _cells_by_index(m)
        isempty(cells) && throw(ArgumentError(
            "this $(tag(m)) has no cells labelled \"(i,j)\""))
        rows = VGroup()
        for i in 1:maximum(c -> c[1], cells)
            add!(rows, VGroup([c[3] for c in cells if c[1] == i]...))
        end
        rows
    end
end

"The columns of a matrix or table, as a VGroup of VGroups (memoised)."
function get_columns(m::VMobject)
    _memoized_group(m, :columns) do
        cells = _cells_by_index(m)
        isempty(cells) && throw(ArgumentError(
            "this $(tag(m)) has no cells labelled \"(i,j)\""))
        cols = VGroup()
        for j in 1:maximum(c -> c[2], cells)
            add!(cols, VGroup([c[3] for c in cells if c[2] == j]...))
        end
        cols
    end
end

"The two brackets, as a VGroup."
get_brackets(m::VMobject) = m.submobjects[2]

"""
    Table(entries; cell=TextMobject, row_labels=nothing, col_labels=nothing,
          h_buff=0.9, v_buff=0.6, include_outer_lines=false, …)

A grid with rules:

    t = Table(["a" "b"; "c" "d"]; col_labels = ["x", "y"])

Entries can be strings, numbers or mobjects; labels are entries too. The lines
are drawn BETWEEN cells from the laid-out geometry (nothing is placed
before the layout exists), so a table with a very wide cell still has
straight, full-width rules.

`get_cell(t, i, j)`, `get_rows`, `get_columns` and the key `"(i,j)"` all
address it; with labels, row 1 / column 1 are the labels themselves.
"""
const Table = VMobject{:Table}

function (::Type{Table})(entries::AbstractMatrix; cell = s -> TextMobject(s; size = 0.5),
                         row_labels = nothing, col_labels = nothing,
                         h_buff::Real = 0.9, v_buff::Real = 0.6,
                         include_outer_lines::Bool = false,
                         line_color = GREY_B, line_width::Real = 2.0,
                         label_color = YELLOW, kw...)
    nr, nc = size(entries)
    (nr > 0 && nc > 0) || throw(ArgumentError("a table needs at least one cell"))
    row_labels === nothing || length(row_labels) == nr || throw(ArgumentError(
        "row_labels has $(length(row_labels)) entries and the table has $nr rows"))
    col_labels === nothing || length(col_labels) == nc || throw(ArgumentError(
        "col_labels has $(length(col_labels)) entries and the table has $nc columns"))

    # the full grid INCLUDING labels — the corner cell stays empty
    off_r = col_labels === nothing ? 0 : 1
    off_c = row_labels === nothing ? 0 : 1
    R, C = nr + off_r, nc + off_c
    grid = Matrix{Union{Nothing,Mobject}}(nothing, R, C)
    for i in 1:nr, j in 1:nc
        grid[i+off_r, j+off_c] = _as_cell(entries[i, j], cell)
    end
    if col_labels !== nothing
        for j in 1:nc
            lab = _as_cell(col_labels[j], cell)
            lab isa VMobject && set_color!(lab; color = label_color)
            grid[1, j+off_c] = lab
        end
    end
    if row_labels !== nothing
        for i in 1:nr
            lab = _as_cell(row_labels[i], cell)
            lab isa VMobject && set_color!(lab; color = label_color)
            grid[i+off_r, 1] = lab
        end
    end

    # column widths and row heights from the real mobjects (layout FIRST)
    colw = [maximum((grid[i, j] === nothing ? 0.0 : Float64(get_width(grid[i, j])))
                    for i in 1:R) for j in 1:C]
    rowh = [maximum((grid[i, j] === nothing ? 0.0 : Float64(get_height(grid[i, j])))
                    for j in 1:C) for i in 1:R]
    xs = zeros(C); ys = zeros(R)
    acc = 0.0
    for j in 1:C
        xs[j] = acc + colw[j] / 2
        acc += colw[j] + h_buff
    end
    acc = 0.0
    for i in 1:R
        ys[i] = -(acc + rowh[i] / 2)
        acc += rowh[i] + v_buff
    end

    t = vmob(:Table; kw...)
    body = VGroup()
    for i in 1:R, j in 1:C
        e = grid[i, j]
        e === nothing && continue
        (e isa VMobject || e isa _Wrapper) && set_key!(e, "($i,$j)")
        move_to!(e, Point3f(xs[j], ys[i], 0))
        add!(body, e)
    end
    add!(t, body)

    # the rules, from the laid-out geometry
    x0, x1 = xs[1] - colw[1] / 2 - h_buff / 2, xs[C] + colw[C] / 2 + h_buff / 2
    y0, y1 = ys[R] - rowh[R] / 2 - v_buff / 2, ys[1] + rowh[1] / 2 + v_buff / 2
    lines = VGroup()
    rows_from = include_outer_lines ? (1:R+1) : (2:R)
    cols_from = include_outer_lines ? (1:C+1) : (2:C)
    for i in rows_from
        y = i <= R ? ys[i] + rowh[i] / 2 + v_buff / 2 : y0
        ln = Line(Point3f(x0, y, 0), Point3f(x1, y, 0))
        set_stroke!(ln; color = line_color, width = line_width)
        add!(lines, ln)
    end
    for j in cols_from
        x = j <= C ? xs[j] - colw[j] / 2 - h_buff / 2 : x1
        ln = Line(Point3f(x, y0, 0), Point3f(x, y1, 0))
        set_stroke!(ln; color = line_color, width = line_width)
        add!(lines, ln)
    end
    add!(t, lines)
    center!(t)
    return t
end

"The (i,j) cell of a table or matrix — 1-based, labels included when present."
function get_cell(t::VMobject, i::Integer, j::Integer)
    key = "($i,$j)"
    hits = find_by_key(t, key)
    isempty(hits) && throw(ArgumentError(
        "there is no cell $key — the keys present are: " *
        join(filter(k -> startswith(k, "("), get_all_keys(t)), ", ")))
    return _cell_node(first(hits))
end

"""
The cell a key hit stands for. A wrapper cell (a
`DecimalNumber`) is keyed through its group, and a family holds that group,
never the wrapper — so the hit climbs to the wrapper that names it as
its group, and anything else is its own cell.
"""
function _cell_node(hit::Mobject)
    ps = _parents(hit)
    k = findfirst(p -> p isa _Wrapper && _inner(p) === hit, ps)
    return k === nothing ? hit : ps[k]
end

"The rules of a table, as a VGroup (empty when it was built without them)."
get_lines(t::VMobject) = t.submobjects[2]

# ═══════════════════════════════════════════════════════════════════════
# The typed constructors over Matrix and Table
# ═══════════════════════════════════════════════════════════════════════
# ManimGL's TexMatrix and Manim CE's four Table subclasses. Not one of them
# adds a mechanism: each fixes what a cell is made of, which is the argument
# `MatrixMobject` and `Table` already take. They earn their place by naming
# the intent at the call site and by failing EARLY when the entries are not
# what the name promises — see `MobjectTable`.

"""
    TexMatrix(entries; tex_config = (;), …)

A [`MatrixMobject`](@ref) whose entries are typeset as formulas, with one
place to configure all of them:

```julia
TexMatrix([raw"a_{11}" raw"a_{12}"; raw"a_{21}" raw"a_{22}"])
TexMatrix([1 2; 3 4]; tex_config = (size = 0.9, color = BLUE))
```

Janim's `MatrixMobject` already builds its cells with [`Tex`](@ref), so this
is the same mobject — measured in ManimGL 1.7.2, where `Matrix` and
`TexMatrix` come out identical to the last float, `TexMatrix` being only the
spelling that lets you pass options through. `tex_config` is a NamedTuple of
`Tex` keywords; the long way round (`cell = s -> Tex(s; size = 0.9)`) is still
there and still works.
"""
function TexMatrix(entries::AbstractMatrix; tex_config = (;), kw...)
    return MatrixMobject(entries; cell = s -> Tex(s; tex_config...), kw...)
end

"""
    MathTable(entries; …)

A [`Table`](@ref) whose cells are formulas instead of text:

```julia
MathTable([raw"\\frac{1}{2}" raw"\\sqrt{2}"; raw"\\pi" raw"e"];
          col_labels = [raw"x", raw"y"])
```

The plain `Table` builds cells with [`TextMobject`](@ref), which is right for
words and wrong for `\\frac`; this one uses [`Tex`](@ref) for every cell,
labels included. Everything else — `row_labels`, `include_outer_lines`,
`get_cell`, the `"(i,j)"` keys — behaves exactly as in `Table`.

The cells are built at `size = 0.5`, which is `Table`'s size and not `Tex`'s
default of 1: a `MathTable` sitting next to a `Table` has to be the same
table. At `Tex`'s default the grid would come out 1.66× the other one's. At
equal `size` a formula still measures 0.831× a word's height (measured, and
constant across sizes); that residue is the two typefaces, not the
constructor, and passing `cell` yourself is how you overrule any of it.
"""
function MathTable(entries::AbstractMatrix; cell = s -> Tex(s; size = 0.5), kw...)
    return Table(entries; cell, kw...)
end

"""
    MobjectTable(entries; …)

A [`Table`](@ref) of mobjects you built yourself:

```julia
MobjectTable([Circle() Square(); Square() Circle()])
```

`Table` already lets a mobject through as a cell, so what this constructor
adds is the CHECK: hand it a number or a string and it says so, naming the
offending cell, instead of quietly running it through `TextMobject` and
producing a table that is subtly not the one you meant.
"""
function MobjectTable(entries::AbstractMatrix; kw...)
    for i in axes(entries, 1), j in axes(entries, 2)
        entries[i, j] isa Mobject || throw(ArgumentError(
            "MobjectTable takes mobjects, and cell ($i,$j) is a " *
            "$(typeof(entries[i, j])) — use Table for text or numbers, or " *
            "build that cell into a mobject first"))
    end
    return Table(entries; kw...)
end

"Format a table of numbers the way a DecimalNumber would, then hand it to Table."
function _numeric_table(entries::AbstractMatrix, places::Int, cell, kw)
    formatted = map(entries) do e
        e isa Mobject ? e :
        e isa Real ? _decimal_string(e, places, false, nothing) : string(e)
    end
    return Table(formatted; cell, kw...)
end

"""
    IntegerTable(entries; …)

A [`Table`](@ref) of whole numbers, rounded and printed without a decimal
point:

```julia
IntegerTable([0 30 45; 90 60 45]; col_labels = ["a", "b", "c"])
```

The rounding is the point: `2.6` is shown as `3`, not as `2.6`, so a column of
computed values lines up instead of ragging. For a fixed number of decimals
use [`DecimalTable`](@ref); for the raw string, plain `Table`.
"""
function IntegerTable(entries::AbstractMatrix;
                      cell = s -> TextMobject(s; size = 0.5), kw...)
    return _numeric_table(entries, 0, cell, kw)
end

"""
    DecimalTable(entries; num_decimal_places = 1, …)

A [`Table`](@ref) of numbers printed to a fixed number of decimals:

```julia
xs = -2:2
DecimalTable([xs'; exp.(xs)']; row_labels = ["x", "eˣ"], num_decimal_places = 2)
```

Fixed-point, not `round`: every cell comes out with the same number of
CHARACTERS, so the column reads as a column. (`round` would stringify
`1.7e-9` in exponent form and the padding would eat the exponent.)

Same characters is not same width: the face is proportional, so `1.23` is
narrower than `4.50` — measured, 0.690 against 0.727 scene units. If you need
the digits to line up exactly, pass a `cell` that builds a monospaced
`TextMobject`.

A cell that is already a mobject passes through untouched, so a
[`DecimalNumber`](@ref) you want to animate later can sit in the grid beside
the static ones.
"""
function DecimalTable(entries::AbstractMatrix; num_decimal_places::Int = 1,
                      cell = s -> TextMobject(s; size = 0.5), kw...)
    return _numeric_table(entries, num_decimal_places, cell, kw)
end
