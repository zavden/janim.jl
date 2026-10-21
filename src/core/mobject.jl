# The vector mobject — a port of the heart of manimlib/mobject/mobject.py and
# types/vectorized_mobject.py, with two design decisions:
#
#   · Points are a `Vector{Point3f}`: contiguous Float32 memory that the
#     renderer uploads AS IS as a vertex buffer (none of Manim's f64→f32
#     double stack).
#   · There is no class hierarchy: ONE parametric struct `VMobject{S}` where S
#     is the shape (:Circle, :Square, :VGroup…). `const Circle =
#     VMobject{:Circle}` gives real dispatch per shape
#     (`interpolate(::Circle, ::Square, α)` can be a method) without inherited
#     fields or method forwarding.
#   · Style lives PER POINT (like GL's structured array) but as SoA: one
#     Vector per attribute — each one its own vertex buffer.

"""
    Mobject

The abstract supertype of everything that can be put in a scene.

There is no class hierarchy under it: the concrete workhorse is the parametric
[`VMobject`](@ref), whose parameter is the SHAPE (`VMobject{:Circle}`), so
`Circle` and `Square` are types that dispatch rather than classes that inherit.
The other subtypes are the raster and particle mobjects
([`ImageMobject`](@ref), [`Surface`](@ref), [`DotCloud`](@ref)) and
[`CameraFrame`](@ref).

To make a type of your own animatable, implement the interpolation contract
rather than subclassing anything with behaviour: [`is_interpolable`](@ref),
`Base.copy`, [`interpolate!`](@ref) and [`become!`](@ref). [`Transform`](@ref)
then works with it.
"""
abstract type Mobject end

# ── Updater: GL's wrapper (mobject.py:2361) translated to Julia arity ───────
# GL asks `inspect` whether the function accepts (mob, dt); here we ask
# methods() whether a two-argument method exists.
"""
    Updater(f; parallel = false)

A function that runs once per frame, wrapped with what the engine needs to know
about it. You rarely build one by hand — [`add_updater!`](@ref) does it — but
the type is public because a custom mobject holding its own updaters declares a
field of it.

The arity is detected, not declared: a function of `(mob, dt)` is called with
the frame's time step, one of `(mob)` is called without it. That is ManimGL's
`inspect` check, done with `methods` instead.

`parallel = true` is a PROMISE that the updater touches only its own mobject,
which is what lets the update loop run them across threads. Break it and you get a
data race, so the default is `false`.
"""
struct Updater
    func::Any
    takes_dt::Bool
    parallel::Bool   # contract: "you only touch your own mobject" → @threads
end
_takes_dt(f) = any(m -> m.nargs == 3 || (m.isva && m.nargs <= 3), methods(f))
Updater(f; parallel::Bool = false) = Updater(f, _takes_dt(f), parallel)
(u::Updater)(mob, dt) = u.takes_dt ? u.func(mob, dt) : u.func(mob)

# ── per-fragment gradients ────────────────────────────────────────────────
# An OPTIONAL sidecar the SVG importer attaches to a child whose fill paints a
# gradient. The renderer evaluates it PER PIXEL (ramp texture + affine uv per
# point), which is the only correct route: the winding fill's ± cancellation
# demands pixel-wise identical alpha on both sides, and per-vertex varying
# alpha breaks it three ways (base painted with the handle's colour, fan
# cancellation mismatch, clamp knees inside triangles).
#
# The spec is a SELF-VALIDATING cache, never an authority: it is active only
# while `length(uv) == length(points)` and `fill_rgba == baked_rgba` — the
# rows as the importer left them. Touch the rows (set_fill!, an updater, a
# mid-Transform lerp) and the renderer falls back to the per-vertex path with
# no bookkeeping anywhere else. `copy` shares it, `become!` adopts it, and
# `interpolate!` at exact α ∈ {0,1} restores the endpoint's spec.
struct FillGradient
    kind::Symbol                     # :linear | :radial
    uv::Vector{Vec2f}                # per-point gradient-space coordinate:
                                     #   linear → (t, 0), t unclamped
                                     #   radial → (p−c)/r (unit circle at t=1)
    focus::NTuple{2,Float32}         # radial focal point in uv space; (0,0) = centred
    spread::Int32                    # 0 = pad · 1 = reflect · 2 = repeat
    ramp::Vector{Float32}            # 4×RAMP_RESOLUTION RGBA texels, straight alpha
    baked_rgba::Vector{Vec4f}        # fill_rgba as written at bake time (validity check)
end

const RAMP_RESOLUTION = 1024

"""
The scale the rows are a copy of the baked ones AT — `1` when they are
identical, `s` when every alpha is `s·baked` with the colours untouched, and
`nothing` when they have genuinely diverged.

The validity check is widened exactly this far because a fade writes ALPHAS
(`FadeIn`, `Write`, `set_fill!(opacity=…)`): an equality-only check would drop
the whole gradient to the per-vertex fallback on the first faded frame, only
to snap back at α=1. One uniform in the shader covers the whole family of fades,
because a global opacity is exactly what they all are.
"""
function _gradient_alpha_scale(g::FillGradient, rows::Vector{Vec4f})
    length(g.baked_rgba) == length(rows) || return nothing
    s = -1f0
    @inbounds for i in eachindex(rows)
        b, r = g.baked_rgba[i], rows[i]
        (b[1] == r[1] && b[2] == r[2] && b[3] == r[3]) || return nothing
        if b[4] == 0f0
            r[4] == 0f0 || return nothing     # a zero row cannot name a scale
        else
            t = r[4] / b[4]
            if s < 0f0
                s = t
            elseif abs(t - s) > 1f-3          # per-row rounding, not a repaint
                return nothing
            end
        end
    end
    return s < 0f0 ? 1f0 : clamp(s, 0f0, 1f0)
end

"The spec, or nothing when the rows have diverged from their baked state."
function active_fill_gradient(m)
    g = getfield(m, :fill_gradient)
    g === nothing && return nothing
    g = g::FillGradient
    length(g.uv) == length(m.points) || return nothing
    _gradient_alpha_scale(g, m.fill_rgba) === nothing && return nothing
    return g
end

"The global opacity the rows ask the gradient for (1 = exactly as baked)."
function fill_gradient_opacity(m)
    g = getfield(m, :fill_gradient)
    g === nothing && return 1f0
    s = _gradient_alpha_scale(g::FillGradient, m.fill_rgba)
    return s === nothing ? 1f0 : s
end

"""
    VMobject{S} <: Mobject
    VMobject(; color, stroke_color, stroke_width, fill_color, fill_opacity, key)

A shape made of quadratic Bézier curves — the type nearly everything you draw
actually is.

The parameter `S` is the shape as a symbol, and the familiar names are aliases
for it: `Circle === VMobject{:Circle}`, `Square === VMobject{:Square}`,
`VGroup === VMobject{:VGroup}`. One struct, no inheritance, and dispatch still
works per shape — `interpolate(::Circle, ::Square, α)` can be a method.
[`tag`](@ref) reads the parameter back off an instance.

The points are one flat `Vector{Point3f}` in the interleaved quadratic layout
`a, h, a, h, …, a` (anchor, handle, anchor), which is already the layout the
GPU wants. Style is per POINT and stored as one array per attribute, so a
gradient along a curve is just a column of colours.

The bare constructor gives an EMPTY VMobject carrying a "factory" style that
new points inherit — the base you build a custom shape on:

```julia
v = VMobject(; color = BLUE, stroke_width = 6)
start_new_path!(v, ORIGIN)
add_line_to!(v, 2 * RIGHT)
add_quadratic_bezier_to!(v, 2 * RIGHT + UP, UP)
```

That factory style is also the trap of updaters: points created inside an
updater re-stamp it, so a mobject whose points are rebuilt every frame must be
BORN with its final style — a later `set_fill!` writes on water.

Every mobject is a node in a tree ([`add!`](@ref), [`get_family`](@ref)), and
children know their parents, so invalidation travels upwards.
"""
mutable struct VMobject{S} <: Mobject
    # per-point data (interleaved quadratic layout 2n+1: a,h,a,h,…,a)
    points::Vector{Point3f}
    stroke_rgba::Vector{Vec4f}
    fill_rgba::Vector{Vec4f}
    stroke_width::Vector{Float32}
    # the "factory" style that new points of an empty mobject inherit
    default_stroke_rgba::Vec4f
    default_fill_rgba::Vec4f
    default_stroke_width::Float32
    # the tree (children know their parents, as in GL — CE's do not)
    submobjects::Vector{Mobject}
    parents::Vector{Mobject}
    family::Union{Nothing,Vector{Mobject}}          # DFS cache
    draw_family::Union{Nothing,Vector{Mobject}}     # the family in DRAW order (z per level)
    # bounding box cached as [mins, mids, maxs] with a dirty flag (mobject.py:339)
    bounding_box::Vector{Point3f}
    needs_new_bounding_box::Bool
    subpath_end_indices::Union{Nothing,Vector{Int}} # subpath cut cache (expired by `_expire_subpath_cuts!`)
    # updaters
    updaters::Vector{Updater}
    updating_suspended::Bool
    has_updaters_cache::Union{Nothing,Bool}
    has_time_based_cache::Union{Nothing,Bool}
    # 3D (per-mobject uniforms in GL: mobject.uniforms)
    shading::NTuple{3,Float32}      # (reflectiveness, gloss, shadow) — (0,0,0) = flat
    depth_test::Bool                # takes part in the z-buffer (GL's apply_depth_test)
    fixed_in_frame::Bool            # ignores the camera (HUD / billboards)
    # addressing by key: what this mobject REPRESENTS (the substring
    # "x^2", cell (2,3), the <path id=…> element of an SVG).
    # `tag` says what it IS (the shape); `keys` says what it represents.
    keys::Vector{String}
    key_group_cache::Union{Nothing,Vector{Pair{Any,Mobject}}}   # memo for m[key]
    # Where each isolated pattern OCCURS: one list of child indices
    # per occurrence, in reading order. `nothing` on everything that is not a
    # labelled Tex — the keys alone cannot tell two occurrences apart, and
    # ManimGL's `get_parts_by_tex` answers by occurrence.
    key_runs::Union{Nothing,Vector{Pair{String,Vector{Vector{Int}}}}}
    # per-fragment gradient sidecar (see FillGradient above)
    fill_gradient::Union{Nothing,FillGradient}
    # draw order INSIDE a layer. Everything is 0 by default and the sorts are
    # STABLE, so a scene that never touches it draws in add! order.
    z_index::Float64
    # how the stroke turns a corner (:auto, :miter, :bevel, :no_joint). The
    # four come from manimlib's stroke shader — same codes, same default.
    # `:auto` is the default.
    joint_type::Symbol
end

# The tags whose PUBLIC constructor is not spelt like the tag.
# An unknown keyword is reported under the name the user can type, and for
# these the tag would name something else (`Matrix` is Base's).
const PUBLIC_CONSTRUCTOR = Dict{Symbol,String}(:Matrix => "MatrixMobject")

"""
The error every constructor of the VMobject family raises for a keyword it
does not know — `LTex does not take `alignmnt``, never a MethodError on
`vmob`, which the user never wrote. The name is the
tag, which IS the public constructor across the shape and text families
(`PUBLIC_CONSTRUCTOR` covers the exceptions).
"""
@noinline function _unknown_keyword(S::Symbol, kw)
    name = get(PUBLIC_CONSTRUCTOR, S, String(S))
    ks = join(("`" * String(k) * "`" for k in keys(kw)), ", ")
    throw(ArgumentError(
        "$name does not take $ks. The style keywords every VMobject " *
        "constructor shares are color, stroke_color, stroke_opacity, " *
        "stroke_width, fill_color, fill_opacity, key, joint_type and z_index; " *
        "for the ones $name adds, see `?$name`."))
end

"""
    VMobject(:Tag; color, stroke_color, stroke_opacity, stroke_width,
             fill_color, fill_opacity, key, joint_type, z_index)

The base constructor and the extension seam: an EMPTY `VMobject{:Tag}`
carrying the factory style, whose tag is a symbol of your choosing — so
`VMobject{:Spiral}` dispatches as its own type and everything in the engine
(transforms, layout, animations, the renderer) already works on it.

```julia
function Spiral(; turns = 3, kw...)
    m = VMobject(:Spiral; kw...)
    start_new_path!(m, ORIGIN)
    …
end
```

`vmob(:Tag; kw...)` is the same call under the name the engine used
internally; it stays as an alias. A keyword neither
knows is an `ArgumentError` that names the tag — the constructor the user
wrote — because `vmob` is exactly the name manimlib gives a `VMobject`
VARIABLE, and a translated `def __init__(self, vmob, …)` shadows the alias
without a word: the public spelling cannot be shadowed by that.

One trap for a custom shape: `VMobject{:Gear}` still has its positional
field constructor, which this call ends in. A method
`(::Type{Gear})(args...; kw...)` written for your shape INTERCEPTS that
positional call and recurses forever — give the constructor keywords, or a
typed positional argument, never a bare `args...`.
"""
function vmob(S::Symbol; color = nothing,
              stroke_color = nothing, stroke_opacity = 1.0,
              stroke_width = DEFAULT_STROKE_WIDTH,
              fill_color = nothing, fill_opacity = 0.0,
              key = nothing, joint_type::Symbol = :auto,
              z_index::Real = 0.0,      # GL takes it at construction (mobject.py:90)
              kw...)                    # anything else is an error that names S
    isempty(kw) || _unknown_keyword(S, kw)
    joint_type in JOINT_TYPES || throw(ArgumentError(
        "joint_type = :$joint_type — use $(join(":" .* string.(JOINT_TYPES), ", ")). " *
        "There is no :round: this engine joins in a stroke shader ported " *
        "from manimlib, which has no round join either (that is Cairo's, and " *
        "so ManimCE's)."))
    sc = something(stroke_color, something(color, GREY_A))
    fc = something(fill_color, something(color, GREY_C))
    VMobject{S}(
        Point3f[], Vec4f[], Vec4f[], Float32[],
        _rgba(sc, stroke_opacity), _rgba(fc, fill_opacity), Float32(stroke_width),
        Mobject[], Mobject[], nothing, nothing,
        Point3f[ORIGIN, ORIGIN, ORIGIN], true, nothing,
        Updater[], false, nothing, nothing,
        (0f0, 0f0, 0f0), false, false,
        key === nothing ? String[] : [String(key)], nothing, nothing,
        nothing, Float64(z_index), joint_type,
    )
end

"""
    JOINT_TYPES

The four ways a stroke can turn a corner, with manimlib's codes: `:no_joint`
(0), `:auto` (1, the default), `:bevel` (2), `:miter` (3).

**There is no `:round`.** The join is computed in the stroke shader, ported
from manimlib, which has no round join; ManimCE's `LineJointType.ROUND` comes
from its Cairo backend. Asking for one is an error rather than a silent
substitution — see [`set_joint_type!`](@ref).
"""
const JOINT_TYPES = (:no_joint, :auto, :bevel, :miter)

const _JOINT_CODE = Dict(:no_joint => 0f0, :auto => 1f0, :bevel => 2f0, :miter => 3f0)

"""
    set_joint_type!(m, t; recurse = true) → m

How the stroke turns a corner: `:auto` (the default), `:miter`, `:bevel` or
`:no_joint`. See [`JOINT_TYPES`](@ref) — there is no `:round`.

It only shows where a corner is SHARP and the stroke is thick: `:auto` behaves
like `:miter` until the turn passes manimlib's threshold (cos < −0.8) and then
eases towards `:bevel`. MEASURED on a hairpin at width 30, where the tip lands:
`:auto` and `:miter` at x = 522 px, `:bevel` at x = 682 — 19 % of the frame.

```julia
set_joint_type!(Polygon(...), :miter)
```

Leaving it alone keeps `:auto`, the default of manimlib's shader.
"""
function set_joint_type!(m::VMobject, t::Symbol; recurse::Bool = true)
    t in JOINT_TYPES || throw(ArgumentError(
        "joint_type = :$t — use $(join(":" .* string.(JOINT_TYPES), ", ")). " *
        "There is no :round in this engine (nor in manimlib): it is Cairo's, " *
        "and so ManimCE's."))
    for mob in (recurse ? get_family(m) : Mobject[m])
        mob isa VMobject && (mob.joint_type = t)
    end
    return m
end

"The joint type of `m` — see [`set_joint_type!`](@ref)."
get_joint_type(m::VMobject) = m.joint_type

VMobject(; kw...) = vmob(:VMobject; kw...)
VMobject(S::Symbol; kw...) = vmob(S; kw...)     # the public seam

"The mobject's shape as a symbol (:Circle, :VGroup…) — used by describe()."
tag(::VMobject{S}) where {S} = S

Base.show(io::IO, m::VMobject) =
    print(io, tag(m), "(", get_num_points(m), " points, ",
          length(m.submobjects), " children)")

# ── addressing children by key ──────────────────────────────────────────────
#
# Two different axes, on purpose:
#   · `tag(m)`      → what it IS: the shape (:Circle, :Glyph, :VGroup). Fixed.
#   · `get_keys(m)` → what it REPRESENTS: "x^2", "row 2", a <path> id.
# The second is what isolate, TransformMatchingTex, t2c and Matrix consume:
# all of them need "give me the children that are THIS". Building it once
# here is what stops each of them from inventing its own version.

"This mobject's labels (usually 0 or 1) — see `set_key!`."
get_keys(m::VMobject) = m.keys
get_keys(::Mobject) = String[]

"Replace the keys of `m` (`set_key!(g, \"x^2\")`)."
set_key!(m::VMobject, keys::AbstractString...) =
    (empty!(m.keys); append!(m.keys, String.(keys)); _expire_key_memos_above!(m))

"Add one more key without dropping the existing ones."
function add_key!(m::VMobject, key::AbstractString)
    k = String(key)
    k in m.keys || (push!(m.keys, k); _expire_key_memos_above!(m))
    return m
end

# A key change expires the key memos of every ANCESTOR. The memo
# (`_memoized_group` below) indexes the descendants' keys, and `m` is one of
# them, so otherwise `g["a"]` would keep serving the group built before
# `set_key!(g[1], "c")` — the same object, with the wrong contents. Only the entries that index keys go: a String
# (`m["key"]`) and the `(:parts, key)` tuples of `get_parts_by_tex`; the range
# memos (`m[1:2]`, a Vector{Int}) and the table memos (`:rows`, `:columns`)
# do not depend on keys and keep their identity.
function _expire_key_memos_above!(m::Mobject, seen = IdDict{Mobject,Nothing}())
    for p in _parents(m)
        haskey(seen, p) && continue
        seen[p] = nothing
        if p isa VMobject && p.key_group_cache !== nothing
            filter!(pr -> pr.first isa Vector{Int} || pr.first isa Symbol,
                    p.key_group_cache::Vector{Pair{Any,Mobject}})
        end
        _expire_key_memos_above!(p, seen)
    end
    return m
end

"""
    has_key(m, key) → Bool

Whether `m` itself carries `key`. It does NOT look at the children — for that,
ask [`find_by_key`](@ref), which returns the ones that match.
"""
has_key(m::Mobject, key::AbstractString) = String(key) in get_keys(m)

"""
    find_by_key(m, key) → Vector{Mobject}

The descendants of `m` (DFS, `m` itself excluded) labelled with `key`. This is
the primitive; `m[key]` wraps it in a memoized VGroup.
"""
function find_by_key(m::VMobject, key::AbstractString)
    k = String(key)
    out = Mobject[]
    for sub in Iterators.drop(get_family(m), 1)
        has_key(sub, k) && push!(out, sub)
    end
    return out
end

"Every key present in the family, in DFS order and without repeats."
function get_all_keys(m::VMobject)
    out = String[]
    for sub in Iterators.drop(get_family(m), 1), k in get_keys(sub)
        k in out || push!(out, k)
    end
    return out
end

# The memo: `tex["x"]` inside an updater would be called 60 times a second and
# every new VGroup would register itself as a parent of the glyphs (`parents`
# would grow without bound and refresh_bounding_box! would turn quadratic).
# With the memo there is ONE group per key, `tex["x"] === tex["x"]`, and
# determinism holds (no Dict: a vector of pairs in query order).
function _memoized_group(construct::F, m::VMobject, key) where {F}
    if m.key_group_cache !== nothing
        for (k, g) in m.key_group_cache
            isequal(k, key) && return g
        end
    else
        m.key_group_cache = Pair{Any,Mobject}[]
    end
    g = construct()
    push!(m.key_group_cache::Vector{Pair{Any,Mobject}}, key => g)
    return g
end

"""
    m[i] · m[a:b] · m["x^2"]

Addressing children: an integer gives the child; a range gives a VGroup of
those children; a string gives a VGroup of the descendants carrying that key.
Groups are memoized (two identical queries return the SAME group, `===`).
"""
Base.getindex(m::VMobject, i::Integer) = m.submobjects[i]
Base.firstindex(m::VMobject) = 1
Base.lastindex(m::VMobject) = length(m.submobjects)

Base.getindex(m::VMobject, r::AbstractVector{<:Integer}) =
    _memoized_group(() -> VGroup(m.submobjects[r]...), m, collect(Int, r))

# A formula typeset by LaTeX arrives as an SVG of font ids, so a glyph is
# named only by the spans the compile labelled. ManimGL guesses the rest with
# a symbol count (`utils/tex.py`), which is wrong wherever TeX ships boxes out
# of source order — on `\\frac{a}{b}` it answers the fraction BAR for "a" — so
# Janim asks instead of guessing, and says how.
# Only the LaTeX-capable tags get the LaTeX hint; a TextMobject is FreeType
# and names every glyph by its character, so its hint is its own.
const _LABELLED_TAGS = (:Tex, :LTex, :LMathTex)
const _LABELLED_HINT =
    ". Through LaTeX (via = :latex, LTex, LMathTex, TexText) a glyph is named " *
    "only by the `isolate` patterns and `t2c` keys given at construction — the " *
    "SVG carries font ids, not characters. `Tex(f; via = :math)` names every " *
    "glyph by its own character"
const _TEXT_HINT =
    ". A TextMobject names each glyph by its character (`t[\"H\"]`); a " *
    "substring is not a key — colour or weight it with `t2c`/`t2w` at " *
    "construction, or take the glyphs by index (`t[1:2]`)"

function Base.getindex(m::VMobject, key::AbstractString)
    _memoized_group(m, String(key)) do    # the do-block goes as 3rd argument
        parts = find_by_key(m, key)
        isempty(parts) && throw(ArgumentError(
            "no child of this $(tag(m)) carries the key «$key» — " *
            "available keys: $(isempty(get_all_keys(m)) ? "(none)" : join(get_all_keys(m), ", "))" *
            (tag(m) in _LABELLED_TAGS ? _LABELLED_HINT :
             tag(m) === :TextMobject ? _TEXT_HINT : "")))
        VGroup(parts...)
    end
end

Base.haskey(m::VMobject, key::AbstractString) = !isempty(find_by_key(m, key))

"Record where `key` occurs: one list of child indices per occurrence, in reading order."
function _record_key_runs!(m::VMobject, key::AbstractString, runs::Vector{Vector{Int}})
    isempty(runs) && return m
    k = String(key)
    m.key_runs === nothing && (m.key_runs = Pair{String,Vector{Vector{Int}}}[])
    rs = m.key_runs::Vector{Pair{String,Vector{Vector{Int}}}}
    i = findfirst(p -> first(p) == k, rs)
    i === nothing ? push!(rs, k => runs) : (rs[i] = k => runs)
    return m
end

"The recorded occurrences of `key`, or `nothing` when nobody recorded any."
function _key_runs(m::VMobject, key::AbstractString)
    rs = m.key_runs
    rs === nothing && return nothing
    i = findfirst(p -> first(p) == String(key), rs)
    return i === nothing ? nothing : last(rs[i])
end

"""
    get_parts_by_tex(t, selector) → VGroup of VGroups
    get_part_by_tex(t, selector, index = 1) → VGroup

The occurrences of `selector`, ONE GROUP EACH — ManimGL's `get_parts_by_tex`
and `get_part_by_tex` (`tex_mobject.py:201-205`, `select_parts`):

```julia
t = Tex(raw"x^2 + x^2"; isolate = [raw"x^2"])
get_parts_by_tex(t, raw"x^2")        # two groups of two glyphs
get_part_by_tex(t, raw"x^2", 2)      # the SECOND x², as a group
```

**`t[selector]` is a different question and keeps its answer**: it is the flat
union of every glyph the key names (four, above), which is what
`TransformMatchingTex` pairs against. GL has no union form, and these two
verbs are the way to ask GL's question.

An occurrence is where the pattern was ISOLATED — recorded as the formula was
built, by both routes (`:math` matches runs of glyphs, `:latex` reads the
labelled spans), so two occurrences side by side (`x^2x^2`) still split in two,
which counting contiguous children could not do. A key of ONE character is
recorded too, one occurrence per glyph, under `:math` and in a `TextMobject`
(GL's `select_unisolated_substring`): `get_parts_by_tex(Tex("x+x"), "x")` is
two parts of one glyph, with no `isolate` at all. On a mobject whose
keys were set by hand — [`set_key!`](@ref) — there is nothing recorded and the
answer is one group with everything, the same thing `t[selector]` returns.
"""
function get_parts_by_tex(m::VMobject, selector::AbstractString)
    key = String(selector)
    return _memoized_group(m, (:parts, key)) do
        whole = m[key]                    # raises with the message m[…] raises
        runs = _key_runs(m, key)
        runs === nothing && return VGroup(whole)
        return VGroup((VGroup(Mobject[m.submobjects[i] for i in run]...) for run in runs)...)
    end
end

"See [`get_parts_by_tex`](@ref) — `index` is 1-based (GL's is 0-based) and the last occurrence is `index = n`: Julia has no negative indices, so GL's `-1` is an error here."
function get_part_by_tex(m::VMobject, selector::AbstractString, index::Integer = 1)
    parts = get_parts_by_tex(m, selector)
    n = length(parts.submobjects)
    1 <= index <= n || throw(
        ArgumentError(
            "get_part_by_tex: «$selector» occurs $n time(s) in this $(tag(m)) — " *
            "indices are 1-based and the last one is $n (Julia has no negative " *
            "indices), asked for nº $index",
        ),
    )
    return parts[index]
end

"""
    length(m) · for child in m · collect(m)

A mobject is also a collection of its DIRECT children, exactly as in Manim
(in CE and GL, `len(m)` and `iter(m)` are the submobjects).
Points have their own verb, [`get_num_points`](@ref). Iteration yields the
children in draw order, so `collect(m)`, `map(f, m)`, comprehensions and
splatting — `VGroup(m...)`, GL's `VGroup(*m)` idiom — all work,
and `eachindex` follows through `keys`.
"""
Base.length(m::VMobject) = length(m.submobjects)
Base.iterate(m::VMobject, state::Int = 1) =
    state > length(m.submobjects) ? nothing : (m.submobjects[state], state + 1)
Base.eltype(::Type{<:VMobject}) = Mobject
Base.keys(m::VMobject) = Base.OneTo(length(m.submobjects))

# ── points and style ────────────────────────────────────────────────────────

get_points(m::VMobject) = m.points

"""
    get_num_points(m) → Int

How many points `m` holds — its own, not its family's. A curve of `n` quadratic
segments has `2n + 1` points (see [`get_num_curves`](@ref)).
"""
get_num_points(m::VMobject) = length(m.points)

"""
    has_points(m) → Bool

Whether `m` holds any points of its own. A group is a mobject with children and
NO points, so `has_points(VGroup(a, b))` is `false` — which is exactly why
`pointwise_become_partial!` does nothing to a group or to a [`Tex`](@ref), and
why the creation animations walk the family themselves.
"""
has_points(m::VMobject) = !isempty(m.points)

# Fit the style arrays to the point count: growing repeats the last row (or the
# factory one if there is none), like GL's `data[n:] = data[n-1]`.
function _resize_style!(m::VMobject, n::Int)
    for (arr, fallback) in ((m.stroke_rgba, m.default_stroke_rgba),
                            (m.fill_rgba, m.default_fill_rgba),
                            (m.stroke_width, m.default_stroke_width))
        k = length(arr)
        filler = k > 0 ? arr[k] : fallback
        resize!(arr, n)
        @inbounds for i in k+1:n
            arr[i] = filler
        end
    end
    return m
end

"""
    _expire_subpath_cuts!(m)

The subpath cut cache (`get_subpath_end_indices`) follows the points:
whatever rewrites or MOVES them in place expires it here, and the next query
rebuilds it (one pass of comparisons). Three callers, one line:
`_note_data_changed!` (a new point count), `interpolate!` (a morph frame) and
`apply_points_function!` (every transform). Without that, a scale that
carried two subpaths' gap over GL's 1e-4 threshold would answer 1 subpath if
the cuts had been queried before the scale and 2 if not: an answer that
depended on the history of calls.
"""
_expire_subpath_cuts!(m::VMobject) = (m.subpath_end_indices = nothing; m)

function _note_data_changed!(m::VMobject)
    _expire_subpath_cuts!(m)
    refresh_bounding_box!(m)
    return m
end

function set_points!(m::VMobject, pts)
    resize!(m.points, length(pts))
    @inbounds for (i, p) in enumerate(pts)
        m.points[i] = Point3f(p)
    end
    _resize_style!(m, length(pts))
    _note_data_changed!(m)
end

"""
    append_points!(m, pts)

Add `pts` after the points `m` already has, growing the style arrays to match
(new rows repeat the last one, or the factory style if there was none).

This is the raw route. The path builders — [`add_line_to!`](@ref),
[`add_quadratic_bezier_to!`](@ref), [`add_arc_to!`](@ref) — are the ones that
keep the `a, h, a` layout consistent for you.
"""
function append_points!(m::VMobject, pts)
    n = length(m.points)
    resize!(m.points, n + length(pts))
    @inbounds for (i, p) in enumerate(pts)
        m.points[n+i] = Point3f(p)
    end
    _resize_style!(m, n + length(pts))
    _note_data_changed!(m)
end

"""
    clear_points!(m)

Drop every point of `m` and its style rows, leaving the mobject alive, empty
and still carrying its factory style. Its children are untouched.
"""
function clear_points!(m::VMobject)
    empty!(m.points)
    empty!(m.stroke_rgba); empty!(m.fill_rgba); empty!(m.stroke_width)
    _note_data_changed!(m)
end

"Every point in the family, concatenated (for global bboxes, describe…)."
function get_all_points(m::VMobject)
    out = Point3f[]
    for mob in get_family(m)
        mob isa VMobject && append!(out, mob.points)
    end
    return out
end

# With `color = nothing` the ROWS KEEP THEIR OWN COLOUR and only the alpha
# moves (GL's semantics). Overwriting the rows with the factory colour would
# silently destroy every per-point gradient the moment anyone touched the
# opacity — including `FadeIn`, which fades by writing alphas. Gradients
# depend on this, and so does the per-fragment gradient surviving a fade.
"""
    set_stroke!(m; color, opacity, width, recurse = true)

Paint the outline. Every argument is a KEYWORD and every one is optional, so
each call says which part of the style it is changing:

```julia
set_stroke!(m; color = BLUE, width = 6)
set_stroke!(m; opacity = 0.3)          # keeps each row's own colour
set_stroke!(m; width = 0)              # no outline at all
```

`width` is Manim's stroke width (the default is `4`) and is measured against
the SCREEN, not the scene: it is the same fraction of the frame at every
resolution, and zooming the camera in does not thicken the line. `color`
accepts anything [`WHITE`](@ref) describes.

Omitting `color` is not the same as passing the current one: with `color =
nothing` the per-point rows KEEP their own colours and only the alpha moves,
which is what lets a gradient survive a fade. Recurses into the family unless
you say `recurse = false`.
"""
function set_stroke!(m::VMobject; color = nothing, opacity = nothing,
                     width = nothing, recurse::Bool = true)
    for mob in (recurse ? get_family(m) : Mobject[m])
        mob isa VMobject || continue
        if _is_color_list(color) || _is_list(opacity)      # a gradient along the path
            _set_rows_by_list!(mob, :stroke, color, opacity)
        elseif color !== nothing || opacity !== nothing
            base = color === nothing ? nothing : _rgba(color, 1)
            for i in eachindex(mob.stroke_rgba)
                row = mob.stroke_rgba[i]
                rgb = base === nothing ? row : base
                a = opacity === nothing ? row[4] : Float32(opacity)
                mob.stroke_rgba[i] = Vec4f(rgb[1], rgb[2], rgb[3], a)
            end
            a0 = opacity === nothing ? mob.default_stroke_rgba[4] : Float32(opacity)
            b0 = base === nothing ? mob.default_stroke_rgba : base
            mob.default_stroke_rgba = Vec4f(b0[1], b0[2], b0[3], a0)
        end
        if width !== nothing
            fill!(mob.stroke_width, Float32(width))
            mob.default_stroke_width = Float32(width)
        end
    end
    return m
end

"""
    set_fill!(m; color, opacity, recurse = true)

Paint the inside. Like [`set_stroke!`](@ref), everything is a keyword:

```julia
set_fill!(m; color = YELLOW, opacity = 1.0)
```

**A shape is born with `fill_opacity = 0`**, so setting only the colour changes
nothing you can see — the opacity is the half people forget. Manim's positional
`m.set_fill(BLUE, opacity=0.5)` has no positional form here: colour and opacity
are keywords because keywords do not take part in dispatch, and the mobject
being first is what decides which method runs.

The interior is filled by winding rule, so a self-intersecting path fills the
way an SVG would.
"""
function set_fill!(m::VMobject; color = nothing, opacity = nothing, recurse::Bool = true)
    for mob in (recurse ? get_family(m) : Mobject[m])
        mob isa VMobject || continue
        if _is_color_list(color) || _is_list(opacity)      # a gradient along the path
            _set_rows_by_list!(mob, :fill, color, opacity)
            continue
        end
        base = color === nothing ? nothing : _rgba(color, 1)   # see set_stroke!
        for i in eachindex(mob.fill_rgba)
            row = mob.fill_rgba[i]
            rgb = base === nothing ? row : base
            a = opacity === nothing ? row[4] : Float32(opacity)
            mob.fill_rgba[i] = Vec4f(rgb[1], rgb[2], rgb[3], a)
        end
        a0 = opacity === nothing ? mob.default_fill_rgba[4] : Float32(opacity)
        b0 = base === nothing ? mob.default_fill_rgba : base
        mob.default_fill_rgba = Vec4f(b0[1], b0[2], b0[3], a0)
    end
    return m
end

"""
    set_opacity!(m, op; recurse = true)

CE's `set_opacity`: fill AND stroke opacity in one call.
`recurse = false` paints only `m` itself and leaves its children (for
[`fade!`](@ref), which passes GL's keyword through).
"""
set_opacity!(m::VMobject, op::Real; recurse::Bool = true) =
    (set_fill!(m; opacity = op, recurse); set_stroke!(m; opacity = op, recurse); m)

"""
    fade!(m, darkness = 0.5; recurse = true)

Make `m` `darkness` of the way transparent — `set_opacity!(m, 1 - darkness)`,
which is exactly what ManimGL's `fade` is (`mobject.py:1458`) and what a ported
`.py` calls to push something into the background.

```julia
fade!(label, 0.7)          # barely there
fade!(group)               # the default darkness is 0.5
```

It touches BOTH fill and stroke (in GL a square faded by 0.5 comes back with
0.5 in each). GL's returns `None`; this one returns the mobject, so
it chains like every other `!` verb here.
"""
fade!(m::VMobject, darkness::Real = 0.5; recurse::Bool = true) =
    set_opacity!(m, 1.0 - Float64(darkness); recurse)

"""
    set_style!(m; fill_color, fill_opacity, stroke_color, stroke_opacity,
               stroke_width, shading, recurse = true)

Every style keyword in one call (`vectorized_mobject.py:218`), each one
optional: what you do not name is not touched.

```julia
set_style!(box; fill_color = RED, fill_opacity = 0.5, stroke_color = BLUE, stroke_width = 7.0)
```

It is [`set_fill!`](@ref) + [`set_stroke!`](@ref) over the family, which is how
GL builds it too — the value is having ONE call for a style block copied out of
a `.py`, not a new mechanism.

GL's `set_backstroke` is NOT here: it asks for the stroke to be drawn BEHIND
the fill, and this renderer has no such pass (there is no `stroke_behind` in
`backend/gl/`). Faking it with a copy would put a second mobject in the family,
which is a different thing to animate — so it stays out, named in
`docs/divergences.md`.
"""
function set_style!(m::VMobject; fill_color = nothing, fill_opacity = nothing,
                    stroke_color = nothing, stroke_opacity = nothing,
                    stroke_width = nothing, shading = nothing,
                    recurse::Bool = true)
    for mob in (recurse ? get_family(m) : Mobject[m])
        mob isa VMobject || continue
        (fill_color !== nothing || fill_opacity !== nothing) &&
            set_fill!(mob; color = fill_color, opacity = fill_opacity, recurse = false)
        (stroke_color !== nothing || stroke_opacity !== nothing || stroke_width !== nothing) &&
            set_stroke!(mob; color = stroke_color, opacity = stroke_opacity,
                        width = stroke_width, recurse = false)
        shading === nothing || (mob.shading = Float32.(Tuple(shading)))
    end
    return m
end

"The fill's alpha — the counterpart CE reads back."
get_opacity(m::VMobject) = Float64(m.default_fill_rgba[4])

# ── family (GL mobject.py:418-470) ──────────────────────────────────────────
#
# The tree is written ONCE against `Mobject`. Every concrete type has a
# `parents` field — the wrappers (DecimalNumber, the coordinate objects, the
# fields) carry their own and are registered as a parent of the group they
# wrap, so an invalidation climbs group → wrapper → the real parent. The only
# per-type knowledge is which caches a node keeps, and `note_changed_family!`
# dispatches on that; `add!` and `remove!` do not.

"""
    get_family(m) → Vector{Mobject}

Flattens the tree in DFS order (me first, then my children, recursively) — the
order Transform and the key machinery use. It is CACHED: two calls in a row
return the SAME vector (`===`), and any add!/remove! in the subtree invalidates
it upwards through `parents` (GL's note_changed_family).

It is the STRUCTURAL order — the order you added things in. What the renderer
walks is the draw order, which sorts each level by z-index; see
[`set_z_index!`](@ref).
"""
function get_family(m::VMobject)
    if m.family === nothing
        fam = Mobject[m]
        for sm in m.submobjects
            append!(fam, get_family(sm))
        end
        m.family = fam
    end
    return m.family::Vector{Mobject}
end

"Whether `m` can be hooked into a tree: it has the `parents` field of the contract."
_has_tree_links(m::Mobject) = hasfield(typeof(m), :parents)
_parents(m::Mobject) =
    _has_tree_links(m) ? (getfield(m, :parents)::Vector{Mobject}) : Mobject[]
_typename(m::Mobject) = m isa VMobject ? string(tag(m)) : string(nameof(typeof(m)))

function note_changed_family!(m::VMobject)
    m.family = nothing
    m.draw_family = nothing
    # the key memo indexes the family: if the family changes, it expires. The
    # groups already handed out stay alive and working (they are not emptied —
    # the user may be holding them); they simply stop being served from cache.
    m.key_group_cache = nothing
    m.key_runs = nothing        # child INDICES — a changed family makes them stale
    refresh_has_updater_status!(m)
    refresh_bounding_box!(m)
    for p in m.parents
        note_changed_family!(p)
    end
    return m
end

"A node with no caches of its own (a raster mobject, a wrapper) only passes the news upwards."
function note_changed_family!(m::Mobject)
    for p in _parents(m)
        note_changed_family!(p)
    end
    return m
end

"""
Only the DRAW order changed (a z-index moved): the families stay, the
draw families from `m` upwards expire — GL's
`note_changed_family(only_changed_order=True)`.
"""
function _note_changed_order!(m::Mobject)
    hasfield(typeof(m), :draw_family) && setfield!(m, :draw_family, nothing)
    for p in _parents(m)
        _note_changed_order!(p)
    end
    return m
end

"""
An ancestor arriving as a child is a CYCLE, and the family machinery is
correct exactly because there is none: `note_changed_family!` walks `parents`
and `get_family` walks `submobjects`, both without a visited set. So the DAG
is enforced at the only door, BEFORE anything is hooked — the check is the
child's own (cached) family, which is also why sharing stays legal: a child
under two parents never puts a parent inside its own subtree.
"""
function _assert_not_in_family(parent::Mobject, child::Mobject)
    child === parent && throw(ArgumentError(
        "a mobject cannot contain itself — " *
        "did you mean add!(m, copy(other)) or a fresh VGroup?"))
    for mob in get_family(child)
        mob === parent && throw(ArgumentError(
            "adding this child would create a family cycle — " *
            "the parent is already inside the child's subtree"))
    end
    return nothing
end

"""
    add!(parent, mobs...)
    add!(scene, mobs...)

Make `mobs` children of `parent`, or put them on stage when the first argument
is a [`Scene`](@ref).

The two readings are the same operation on two different trees, which is why
they share a name: a scene is a list of roots, a mobject is a node with
children, and both draw their subtree in order. Adding twice does nothing the
second time, and a mobject cannot contain itself (that throws — as does the
larger shape of the same mistake, an ancestor added as a child).

Any mobject can be a child of any group: a `DecimalNumber` or an `Axes`
inside a `VGroup`, an `ImageMobject` inside a `Group`, a type of your own that
implements only the interpolation contract. A child WITH the `parents` field
of the contract is linked back and hears about changes above it; one without
is simply listed. And every check runs BEFORE anything is pushed, so a
refused call (a cycle) leaves the group exactly as it was.

Children are drawn after their parent and inherit nothing — no style, no
transform is copied. What they DO inherit is being moved, scaled and faded
together, because those walk the family.

Draw order is insertion order. A [`set_z_index!`](@ref) changes the DRAWING
order — higher draws later, ties keep insertion order — and never the order of
`submobjects`: `m[2]` is what you added second, and a `Transform` pairs
children by position, as in ManimGL.
"""
add!(m::VMobject, mobs::Mobject...) = _add_children!(m, mobs)

function _add_children!(m::Mobject, mobs)
    # validate EVERYTHING before touching anything: a failed add! must not
    # push the child and THEN die on `mob.parents`
    for mob in mobs
        _assert_not_in_family(m, mob)   # refuse before hooking anything
    end
    subs = m.submobjects
    for mob in mobs
        any(x -> x === mob, subs) || push!(subs, mob)
        # a type of your own without `parents` (one that implements the
        # interpolation contract and nothing else) is still a
        # child — listed, drawn, moved — it just cannot be told when its
        # parent changes, which a leaf that never re-parents never needs
        _has_tree_links(mob) || continue
        ps = _parents(mob)
        any(x -> x === m, ps) || push!(ps, m)
    end
    # No sort. A z-index orders the DRAWING (`_draw_family`), never this
    # list — GL keeps the declaration order, and so does Transform's
    # positional pairing.
    note_changed_family!(m)
    return m
end

"""
The ONE mechanism by which a child forgets a parent. `remove!` and the
unequal branch of `become!` both leave the family through here — emptying
`submobjects` while the orphans kept naming the parent would cause phantom
invalidations if they mutate later, and retention.
"""
_forget_parent!(child, parent) = filter!(x -> x !== parent, _parents(child))

"""
    remove!(parent, mobs...)
    remove!(scene, mobs...)

The inverse of [`add!`](@ref): detach `mobs` from the parent, or take them off
stage. Removing something that is not there is not an error.

The mobject itself survives — this unlinks, it does not destroy — so you can
`add!` it back later, updaters and all.
"""
remove!(m::VMobject, mobs::Mobject...) = _remove_children!(m, mobs)

function _remove_children!(m::Mobject, mobs)
    subs = m.submobjects
    for mob in mobs
        filter!(x -> x !== mob, subs)
        _forget_parent!(mob, m)
    end
    note_changed_family!(m)
    return m
end

# ── updaters (GL mobject.py:827-935) ────────────────────────────────────────

"The updater list a node keeps, or `nothing` for a type that has none."
_updaters(m::Mobject) =
    hasfield(typeof(m), :updaters) ? (getfield(m, :updaters)::Vector{Updater}) : nothing

# A wrapper (DecimalNumber, Axes…) keeps its updaters in the group it
# wraps, but the function the user wrote expects the WRAPPER. `_WrapperCall`
# is that closure with the identity of `f` kept — `remove_updater!(w, f)`
# still finds it — and the arity decided when it was built, because
# `_takes_dt` on a callable with both methods would always say `true`.
struct _WrapperCall{W,F}
    w::W
    f::F
    takes_dt::Bool
end
(c::_WrapperCall)(mob) = c.f(c.w)
(c::_WrapperCall)(mob, dt) = c.takes_dt ? c.f(c.w, dt) : c.f(c.w)
_is_func(u::Updater, f) = u.func === f || (u.func isa _WrapperCall && u.func.f === f)

"""
    add_updater!(m, f; call = true, parallel = false)
    add_updater!(f, m; …)                       # do-block form

Register `f` to run on `m` once per frame, for as long as `m` is on stage.

`f` may take `(mob, dt)` or just `(mob)` — the arity is detected, and a
`dt`-taking updater is what makes a mobject "time based":

```julia
add_updater!(m, (m, dt) -> shift!(m, dt * RIGHT))    # 1 unit per second
add_updater!(label, m -> next_to!(m, dot, UP))       # pure follower
add_updater!(m) do mob, dt                           # do-block reads better
    rotate!(mob, dt * TAU / 4)                       # when it is several lines
end
```

Three things that are worth knowing before the second one you write:

  * **`call = true` runs it immediately, with `dt = 0`.** That is what places a
    follower correctly on the frame it is created. It is also why an updater
    driving a stepped integrator needs `dt > 0 && step!(…)`: registration
    itself hands it a zero.
  * **A mobject whose POINTS are rebuilt inside an updater must be born with
    its final style** — new points re-stamp the factory style of
    [`VMobject`](@ref), so a `set_fill!` afterwards, or a fade, writes on
    water.
  * **Freeze before fading out.** An updater that keeps writing while
    [`FadeOut`](@ref) runs undoes the fade every frame. The idiom is a
    `Ref{Bool}` the updater checks and the scene flips before the `play!`.

`parallel = true` promises the updater touches only its own mobject; see
[`Updater`](@ref). Undo with [`remove_updater!`](@ref) or
[`clear_updaters!`](@ref), pause with [`suspend_updating!`](@ref).
"""
function add_updater!(m::VMobject, f; call::Bool = true, parallel::Bool = false)
    push!(m.updaters, Updater(f; parallel))
    refresh_has_updater_status!(m)
    call && update!(m, 0.0)
    return m
end
add_updater!(f, m::VMobject; kw...) = add_updater!(m, f; kw...)  # do-block form

"""
    remove_updater!(m, f)

Unregister exactly the function `f` from `m` — compared by identity, so you
need the same object you passed to [`add_updater!`](@ref). An anonymous
function written inline twice is two different objects; keep the reference if
you mean to remove it:

```julia
follow = (mob, dt) -> next_to!(mob, dot, UP)
add_updater!(label, follow)
remove_updater!(label, follow)
```

Removing one that was never there is not an error.
"""
function remove_updater!(m::VMobject, f)
    filter!(u -> !_is_func(u, f), m.updaters)
    refresh_has_updater_status!(m)
    return m
end

"""
    clear_updaters!(m; recurse = true)

Drop every updater from `m` and, by default, from its whole family. The blunt
instrument — it does not need the function objects back, so it is what you
reach for at the end of a section.

To stop them temporarily and keep them, use [`suspend_updating!`](@ref).
"""
function clear_updaters!(m::VMobject; recurse::Bool = true)
    for mob in (recurse ? get_family(m) : Mobject[m])
        _clear_own_updaters!(mob)
    end
    refresh_has_updater_status!(m)
    return m
end

"Empty ONE node's updaters and its caches, whatever the type."
function _clear_own_updaters!(mob::Mobject)
    u = _updaters(mob)
    u === nothing || empty!(u)
    hasfield(typeof(mob), :has_updaters_cache) && setfield!(mob, :has_updaters_cache, nothing)
    hasfield(typeof(mob), :has_time_based_cache) && setfield!(mob, :has_time_based_cache, nothing)
    return mob
end

"""
    update!(m, dt=0) — run the updaters of the whole family.

This is what the scene's game loop calls once per frame (GL's
Scene.update_mobjects). Without a Scene it works by hand.
"""
function update!(m::VMobject, dt::Real = 0.0; recurse::Bool = true)
    (has_updaters(m) && !m.updating_suspended) || return m
    if recurse
        for sm in m.submobjects
            update!(sm, dt)
        end
    end
    _run_updaters!(m, m.updaters, dt)
    return m
end

"""
Run a node's updaters by INDEX, re-checking the slot after each call:
an updater that removes ITSELF (turn_animation_into_updater's exit) shifts
the rest down, and a `for` over the vector would skip the next one that
frame. One that removes an earlier sibling shifts too — the slot check
covers both. Allocates nothing.
"""
function _run_updaters!(m::Mobject, ups::Vector{Updater}, dt::Real)
    i = 1
    while i <= length(ups)
        u = ups[i]
        u(m, dt)
        (i <= length(ups) && ups[i] === u) && (i += 1)
    end
    return m
end

"""
    suspend_updating!(m; recurse = true)

Stop running `m`'s updaters without forgetting them. The mobject freezes where
it is and stays drawable; [`resume_updating!`](@ref) starts it again.

Use it when an animation needs to own a mobject that is normally driven by an
updater — a `Transform` of something that an updater keeps repositioning fights
itself otherwise.
"""
function suspend_updating!(m::Mobject; recurse::Bool = true)
    hasfield(typeof(m), :updating_suspended) && setfield!(m, :updating_suspended, true)
    if recurse && hasfield(typeof(m), :submobjects)
        for sm in getfield(m, :submobjects)::Vector{Mobject}
            suspend_updating!(sm; recurse)
        end
    end
    return m
end

"""
    resume_updating!(m; recurse = true, call_updater = true)

Undo [`suspend_updating!`](@ref). It also wakes the ancestors — a suspended
parent would otherwise never reach this mobject — and by default calls the
updaters once with `dt = 0`, so the mobject is correctly placed on the frame it
resumes rather than one frame later.
"""
function resume_updating!(m::Mobject; recurse::Bool = true, call_updater::Bool = true)
    _resume_own!(m)
    if recurse && hasfield(typeof(m), :submobjects)
        for sm in getfield(m, :submobjects)::Vector{Mobject}
            resume_updating!(sm; recurse, call_updater = false)
        end
    end
    _wake_parents!(m)
    call_updater && update!(m, 0.0)
    return m
end
_resume_own!(m::Mobject) =
    (hasfield(typeof(m), :updating_suspended) && setfield!(m, :updating_suspended, false); m)
# a suspended ancestor would never reach this mobject again: wake the chain
# UPWARDS only (a wrapper sits between its group and the real parent, and
# going down again from it would loop)
function _wake_parents!(m::Mobject)
    for p in _parents(m)
        _resume_own!(p)
        _wake_parents!(p)
    end
    return m
end

"""
    get_updaters(m) → Vector{Updater}

`m`'s own updaters, in the order they were added — the live vector, not a copy.
Its elements are [`Updater`](@ref)s, so the function you registered is
`u.func`.
"""
get_updaters(m::VMobject) = m.updaters

"""
    has_updaters(m) → Bool

Whether `m` OR anything in its family carries an updater. Cached, and the cache
is invalidated upwards through the parents when the tree changes.
"""
function has_updaters(m::VMobject)
    if m.has_updaters_cache === nothing
        m.has_updaters_cache = !isempty(m.updaters) ||
                               any(has_updaters, m.submobjects)
    end
    return m.has_updaters_cache::Bool
end

"""
    has_time_based_updaters(m) → Bool

Whether anything in `m`'s family has an updater that takes `dt`.

The distinction matters to the scene: a mobject driven only by
position-following updaters is a function of the current state, while one with
a `dt` updater INTEGRATES and therefore depends on how it got here.
"""
function has_time_based_updaters(m::VMobject)
    if m.has_time_based_cache === nothing
        m.has_time_based_cache = any(get_family(m)) do mob
            u = _updaters(mob)
            u !== nothing && any(x -> x.takes_dt, u)
        end
    end
    return m.has_time_based_cache::Bool
end

function refresh_has_updater_status!(m::VMobject)
    m.has_updaters_cache = nothing
    m.has_time_based_cache = nothing
    for p in m.parents
        refresh_has_updater_status!(p)
    end
    return m
end

"A node without the caches only passes the news upwards."
function refresh_has_updater_status!(m::Mobject)
    for p in _parents(m)
        refresh_has_updater_status!(p)
    end
    return m
end


# ═══════════════════════════════════════════════════════════════════════
# Draw order
# ═══════════════════════════════════════════════════════════════════════
#
# The draw order is the order of the lists: `scene.mobjects` first, then each
# family in DFS. So ordering is REORDERING — no renderer change, no z-buffer
# for 2D (that is what `depth_test` is for in 3D), and a stable sort means
# equal z-indices keep the order they were added in.

"This mobject's draw order inside its layer (0 unless someone set it)."
get_z_index(m::VMobject) = m.z_index
get_z_index(m::Mobject) =
    hasfield(typeof(m), :z_index) ? (getfield(m, :z_index)::Float64) : 0.0

"Sort a list of mobjects by z-index, stably (used by the scene and by the draw family)."
_by_z(mobs) = sort(mobs; by = get_z_index, alg = MergeSort)

"""
    set_z_index!(m, z; recurse=true)

Set the draw order of `m` inside its layer: higher draws LATER, so it lands on
top. Ties keep the order they were added in.

Every mobject that draws carries one: a `Surface`, an `ImageMobject`, a
`DotCloud`, a `Group` used as a root — a z-index is an attribute of the
object, as in ManimGL, and the scene sorts its roots by it. It changes what
the renderer sorts and NEVER the order of `submobjects`, so a group's children
keep the order you gave them and a `Transform` still pairs them by position.
A `ValueTracker` or a `CameraFrame` draws nothing and refuses; inside a
recursive call over a family they are simply skipped.

It REACHES THE FAMILY, as ManimGL's does (`mobject.py:1260`,
`recurse=True`), so setting a group's draw order does not leave its children
at zero; `recurse = false` sets the group alone.

A recursive set expires the cached draw order from EVERY member it touches
upwards, not only from `m`: a child that had sorted its own children by their
old z would keep that order while every z said otherwise, and so would a
parent OUTSIDE the family that shares one of the members (a diamond) — so
each member climbs, as a direct set does.
"""
function set_z_index!(m::Mobject, z::Real; recurse::Bool = true)
    _set_z!(m, Float64(z)) || throw(ArgumentError(
        "a $(_typename(m)) draws nothing, so it has no draw order to set"))
    if recurse
        for sub in Iterators.drop(get_family(m), 1)
            _set_z!(sub, Float64(z)) || continue   # what cannot be drawn is skipped
            # Its own children's z changed too, so the draw order it cached is
            # stale, and so is every ancestor's — including a parent outside
            # this family that shares it (a diamond), which the climb from `m`
            # below never reaches. Expiring the node alone would fall short:
            # the external parent would keep its order.
            _note_changed_order!(sub)
        end
    end
    _note_changed_order!(m)
    return m
end
_set_z!(m::VMobject, z::Float64) = (m.z_index = z; true)
_set_z!(m::Mobject, z::Float64) =
    hasfield(typeof(m), :z_index) ? (setfield!(m, :z_index, z); true) : false

"""
    _draw_family(m) → Vector{Mobject}

The family in DRAW order: at every level the children sorted stably by
z-index, so a z decides who covers whom without touching `submobjects` (GL
writes an attribute and sorts when it draws). Cached like the family and
expired with it, from [`set_z_index!`](@ref) upwards and, when that set
recurses, from every member it touches upwards; when no member has a
z-index it IS the family (`===`), so a scene that never sets one allocates
nothing here.
"""
function _draw_family(m::VMobject)
    m.draw_family === nothing || return m.draw_family::Vector{Mobject}
    fam = get_family(m)
    if !any(x -> get_z_index(x) != 0.0, fam)
        m.draw_family = fam
        return fam
    end
    out = Mobject[m]
    for child in _by_z(m.submobjects)
        append!(out, _draw_family(child))
    end
    m.draw_family = out
    return out
end
_draw_family(m::Mobject) = get_family(m)

"Move `child` to the END of `parent`'s children, so it draws last (on top)."
function bring_to_front!(parent::VMobject, child::Mobject)
    i = findfirst(x -> x === child, parent.submobjects)
    i === nothing && throw(ArgumentError(
        "bring_to_front!: that mobject is not a child of this $(tag(parent))"))
    deleteat!(parent.submobjects, i)
    push!(parent.submobjects, child)
    note_changed_family!(parent)
    return parent
end

"Move `child` to the FRONT of the list, so it draws first (underneath)."
function bring_to_back!(parent::VMobject, child::Mobject)
    i = findfirst(x -> x === child, parent.submobjects)
    i === nothing && throw(ArgumentError(
        "bring_to_back!: that mobject is not a child of this $(tag(parent))"))
    deleteat!(parent.submobjects, i)
    pushfirst!(parent.submobjects, child)
    note_changed_family!(parent)
    return parent
end

# ═══════════════════════════════════════════════════════════════════════
# A LIST of colours or opacities: a gradient along the points
# ═══════════════════════════════════════════════════════════════════════

"Whether `c` names SEVERAL colours (a gradient) rather than one: a vector or tuple whose entries are colours, not numbers — a `Vec4f` is one colour."
_is_color_list(c) = c isa Union{AbstractVector,Tuple} && !(eltype(c) <: Real)
"Whether `o` is SEVERAL opacities: a vector or tuple of numbers."
_is_list(o) = o isa Union{AbstractVector,Tuple} && eltype(o) <: Real

"""
GL's `resize_with_interpolation` (iterables.py:108): `rows` stretched or
squeezed to `k` entries by LINEAR interpolation between neighbours — one
entry repeats, two make a gradient. Linear in the stored floats on purpose:
that is what GL's per-point `set_fill(color=[…])` does, unlike
[`interpolate_color`](@ref), which mixes squares.
"""
function _resize_with_interpolation(rows::AbstractVector{T}, k::Int) where {T}
    n = length(rows)
    n == k && return collect(rows)
    k <= 0 && return T[]
    (n == 1 || k == 1 || all(r -> r == rows[1], rows)) && return fill(rows[1], k)
    out = Vector{T}(undef, k)
    @inbounds for i in 1:k
        ci = (i - 1) * (n - 1) / (k - 1)          # np.linspace(0, n - 1, k)
        lh = floor(Int, ci)
        rh = ceil(Int, ci)
        a = ci - lh
        out[i] = T((1 - a) * rows[lh + 1] + a * rows[rh + 1])
    end
    return out
end

"""
GL's `set_rgba_array_by_color` (mobject.py:1383) for a list: the colours (or
opacities) are stretched over the mobject's points by
[`_resize_with_interpolation`](@ref), so `set_fill!(m; color = [RED, BLUE])`
paints a gradient along the path, and EVERY member of the family gets the
whole gradient, as in GL. A mobject with points keeps its factory colour — GL
writes `data`, not `_data_defaults` — while one without points, which has
only the factory row, takes the first colour, which is what GL's resize to a
single row gives. A scalar opacity beside a colour list moves the factory
alpha, as the scalar path does.
"""
function _set_rows_by_list!(mob::VMobject, which::Symbol, color, opacity)
    rows = which === :fill ? mob.fill_rgba : mob.stroke_rgba
    default = which === :fill ? mob.default_fill_rgba : mob.default_stroke_rgba
    n = length(rows)
    rgbs = nothing
    if color !== nothing
        cols = _is_color_list(color) ? Vec4f[_rgba(c, 1) for c in color] : Vec4f[_rgba(color, 1)]
        isempty(cols) && throw(ArgumentError("a colour list needs at least one colour"))
        rgbs = _resize_with_interpolation(cols, max(n, 1))
    end
    alphas = nothing
    if opacity !== nothing
        ops = _is_list(opacity) ? Float32[Float32(o) for o in opacity] : Float32[Float32(opacity)]
        isempty(ops) && throw(ArgumentError("an opacity list needs at least one entry"))
        alphas = _resize_with_interpolation(ops, max(n, 1))
    end
    @inbounds for i in 1:n
        row = rows[i]
        rgb = rgbs === nothing ? row : rgbs[i]
        a = alphas === nothing ? row[4] : alphas[i]
        rows[i] = Vec4f(rgb[1], rgb[2], rgb[3], a)
    end
    d_rgb = (rgbs === nothing || n > 0) ? default : rgbs[1]
    d_a = alphas === nothing ? default[4] :
          (n > 0 && _is_list(opacity)) ? default[4] : alphas[1]
    newdef = Vec4f(d_rgb[1], d_rgb[2], d_rgb[3], d_a)
    if which === :fill
        mob.default_fill_rgba = newdef
    else
        mob.default_stroke_rgba = newdef
    end
    return mob
end
