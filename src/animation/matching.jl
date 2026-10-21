# animation/matching.jl — TransformMatchingTex.
#
# THE formula animation: pair the parts of two Tex mobjects by their KEYS
# (every :math glyph carries its character, isolate adds substring
# patterns, rules carry _hline/_vline), Transform the matched pairs, fade the
# orphans, and leave the SCENE holding the REAL target.
#
# Three deliberate decisions, all downstream of known traps:
#
#   1. COPIES ONLY. Our draw loop renders every scene root's family with no
#      cross-root dedup, so live glyphs shared between the source and the
#      animation group would be drawn TWICE (winding alpha deepens: 2a−a²).
#      Every animated piece is a copy; the live source is hidden in begin!
#      and removed at the end.
#   2. NO restructuring of either Tex (become!/regrouping with
#      changed structures replaces children with copies and orphans every
#      external reference, key groups included). The source keeps its tree
#      until it leaves the scene; the target enters untouched.
#   3. The scene swap rides `clean_up!` — the same protocol as ReplacementTransform — so animations stay
#      ignorant of the scene and TMT works identically under play!,
#      Timeline, render_frame and the daemon.
#
# TransformMatchingShapes is a separate matcher further down: matching "equal
# shapes" needs a normalised-geometry fingerprint with tolerances, so it is
# not a by-product of the key-based pairing above.

"""
The ink-bearing DESCENDANTS, in family order — GL's `family_members_with_points`
(transform_matching_parts.py:43-44). Not just the direct children: a
grandchild — the circle of `VGroup(Square(), VGroup(Circle()))`,
the glyphs of a matrix's entries — must be paired too, or `begin!` would hide
it with the source and it would come back in one jump at the end, and two
matrices would fall to a cross-fade.
"""
_glyph_children(m::VMobject) =
    VMobject[c for c in Iterators.drop(get_family(m), 1) if c isa VMobject && has_points(c)]

"""
One VMobject of the consumed source and the colour rows
`begin!` hides: `set_fill!`/`set_stroke!` write exactly these four (the rows
and the default a new point would get) and nothing else, so putting them back
is the whole restore — the render mirror (records.jl) compares the rows bit
for bit and re-uploads on its own.
"""
struct _HiddenStyle
    mob::VMobject
    fill_rgba::Vector{Vec4f}
    stroke_rgba::Vector{Vec4f}
    default_fill_rgba::Vec4f
    default_stroke_rgba::Vec4f
end

"key → glyphs carrying it, in reading order. `_via:` metadata keys excluded."
function _parts_by_key(m::VMobject)
    parts = Dict{String,Vector{VMobject}}()
    for c in _glyph_children(m)
        for k in get_keys(c)
            startswith(k, "_via") && continue
            push!(get!(() -> VMobject[], parts, k), c)
        end
    end
    return parts
end

"""
    TransformMatchingTex(src, dst; key_map=Dict(), rate_func=smooth, path_arc=0,
                         path_arc_axis=OUT, run_time=1.0, lag_ratio=0, …)

Glyphs sharing a key morph in pairs (longest keys claim first, so an
isolated "x^2" outranks its own "x"); source-only glyphs FadeOut, target-only
glyphs FadeIn. When the animation finishes the scene holds `dst` itself:
`src` is hidden while the copies animate, removed from the scene at the end,
and handed back with its opacity restored (GL removes it untouched, and so
does this). `key_map` renames on the way: `Dict("a" => "b")`
pairs source a's with target b's. `match_shapes = true` pairs the leftovers
by RESEMBLANCE afterwards (the matcher of [`TransformMatchingShapes`](@ref),
under `threshold`), which is what GL does by default for identical shapes;
here it is opt-in.

`rate_func`, `path_arc` and `path_arc_axis` reach EVERY child animation —
each pair's `Transform`, the fades of the orphans — like GL's `anim_config`;
`run_time` and `lag_ratio` stay with the group. The default
`run_time` is 1.0 where GL's `TransformMatchingParts` asks for 2.0 (a
documented divergence).

Works on any mobjects whose children carry keys — a TextMobject pair matches
by characters out of the box.
"""
mutable struct TransformMatchingTex <: Animation
    base::AnimBase              # shared with `group`: same mobject, same clock
    group::AnimationGroup
    to_remove::Mobject          # the live source (consumed)
    to_add::Mobject             # the real target the scene ends up holding
    hidden::Vector{_HiddenStyle}    # the source's colours: hidden in begin!, back in clean_up!
end

function TransformMatchingTex(
    src::VMobject,
    dst::VMobject;
    key_map::AbstractDict = Dict{String,String}(),
    match_shapes::Bool = false,
    threshold::Real = 0.05,
    rate_func::Function = smooth,
    path_arc::Real = 0.0,
    path_arc_axis = OUT,
    kw...,
)
    smap = _parts_by_key(src)
    dmap = _parts_by_key(dst)
    # longest key first: the most specific pattern claims its glyphs before
    # its own substrings can; ties break lexicographically (A2 determinism)
    skeys = sort(collect(keys(smap)); by = k -> (-length(k), k))
    claimed_s = Set{VMobject}()
    claimed_d = Set{VMobject}()
    anims = Animation[]
    for k in skeys
        dk = String(get(key_map, k, k))
        haskey(dmap, dk) || continue
        sparts = [g for g in smap[k] if !(g in claimed_s)]
        dparts = [g for g in dmap[dk] if !(g in claimed_d)]
        (isempty(sparts) || isempty(dparts)) && continue
        union!(claimed_s, sparts)
        union!(claimed_d, dparts)
        # The keywords of the motion go to EVERY child, as GL's
        # `anim_config` does; the group only gets what belongs to the clock
        push!(
            anims,
            Transform(
                VGroup(copy.(sparts)...),
                VGroup(copy.(dparts)...);
                rate_func,
                path_arc,
                path_arc_axis,
            ),
        )
    end
    # Opt-in: the leftovers pair by resemblance (GL pairs its leftovers by
    # IDENTICAL shape by default; here it is a flag, so the keyed animation
    # stays purely key-based unless asked)
    if match_shapes
        sleft = VMobject[g for g in _glyph_children(src) if !(g in claimed_s)]
        dleft = VMobject[g for g in _glyph_children(dst) if !(g in claimed_d)]
        for (i, j) in _match_by_shape(sleft, dleft; threshold = Float64(threshold))
            push!(claimed_s, sleft[i])
            push!(claimed_d, dleft[j])
            push!(
                anims,
                Transform(
                    copy(sleft[i]),
                    copy(dleft[j]);
                    rate_func,
                    path_arc,
                    path_arc_axis,
                ),
            )
        end
    end
    sorph = VMobject[copy(g) for g in _glyph_children(src) if !(g in claimed_s)]
    dorph = VMobject[copy(g) for g in _glyph_children(dst) if !(g in claimed_d)]
    isempty(sorph) || push!(anims, FadeOut(VGroup(sorph...); rate_func))
    isempty(dorph) || push!(anims, FadeIn(VGroup(dorph...); rate_func))
    # nothing matched and nothing orphaned only when both are childless —
    # degenerate but legal: cross-fade the wholes
    isempty(anims) && push!(anims, FadeTransform(copy(src), dst; rate_func))
    group = AnimationGroup(anims...; kw...)
    return TransformMatchingTex(group.base, group, src, dst, _HiddenStyle[])
end

function begin!(t::TransformMatchingTex)
    # the copies carry 100% of the pixels from frame one; the live source
    # would double-draw underneath (see 1 above), so it goes invisible NOW.
    # It is consumed anyway — clean_up! removes it at the end, and gives it
    # its colours back: every row is photographed BEFORE the
    # first set_fill!, which recurses and would already have zeroed the
    # children by the time the loop reached them.
    # A photograph still pending (a second `begin!` with no `clean_up!` in
    # between, as a frame-by-frame preview does) is the true one: keep it.
    fam = VMobject[sub for sub in get_family(t.to_remove) if sub isa VMobject]
    if isempty(t.hidden)
        for sub in fam
            push!(
                t.hidden,
                _HiddenStyle(
                    sub,
                    copy(sub.fill_rgba),
                    copy(sub.stroke_rgba),
                    sub.default_fill_rgba,
                    sub.default_stroke_rgba,
                ),
            )
        end
    end
    for sub in fam
        set_fill!(sub; opacity = 0)
        set_stroke!(sub; opacity = 0)
    end
    begin!(t.group)
    return t
end

interpolate!(t::TransformMatchingTex, alpha::Real) = interpolate!(t.group, alpha)
finish!(t::TransformMatchingTex) = (finish!(t.group); t)

# The copies drew the animation (cross-root children would draw twice —
# see 1 above); the stage drops the hidden source and the copy soup, and
# holds the REAL target from now on, where the source stood.
function clean_up!(t::TransformMatchingTex, stage)
    remove!(stage, mobject_of(t))
    _stage_replace!(stage, t.to_remove, t.to_add)
    # The source leaves the stage with its colours back — GL removes it
    # untouched; the hidden state only ever kept the copies from double-drawing. The rows go back
    # exactly; a source whose point count changed meanwhile gets its default
    # colour on every row instead of a mismatched copy.
    for hs in t.hidden
        _restore_rows!(hs.mob.fill_rgba, hs.fill_rgba, hs.default_fill_rgba)
        _restore_rows!(hs.mob.stroke_rgba, hs.stroke_rgba, hs.default_stroke_rgba)
        hs.mob.default_fill_rgba = hs.default_fill_rgba
        hs.mob.default_stroke_rgba = hs.default_stroke_rgba
    end
    empty!(t.hidden)
    return t
end

"The photographed rows back in place, or the default on every row when the count moved."
_restore_rows!(dst::Vector{Vec4f}, src::Vector{Vec4f}, default::Vec4f) =
    length(dst) == length(src) ? copyto!(dst, src) : fill!(dst, default)

# ── the shape matcher ─────────────────────────────────────────────────
#
# GL's TransformMatchingShapes pairs pieces whose SHAPES are the same
# (`has_same_shape_as`: both point sets centred and scaled to height 1, the
# same point count, every point within 1% of the width) and fades the rest.
# Janim turns that test into a DISTANCE and lets a Hungarian assignment pick
# the pairs: identical shapes still score 0 and pair first, but a glyph that
# merely RESEMBLES another (a different point count, a slightly different
# outline) gets a number too, and pairs when it is under `threshold`. Keys
# stay the job of TransformMatchingTex; this is the "by resemblance" route,
# and `match_shapes = true` lets TMT fall back to it for its leftovers.

"The outline as GL normalises it for `has_same_shape_as`: centred, height 1."
function _normalised_outline(m::VMobject)
    c = SVector{3,Float64}(get_center(m))
    h = max(Float64(get_height(m)), 1e-9)
    return [(SVector{3,Float64}(p) - c) / h for p in get_points(m)]
end

"The anchors of a Bézier triplet list, resampled to `n` points by arc length."
function _resample(points::Vector{SVector{3,Float64}}, n::Int)
    anchors = points[1:2:end]
    length(anchors) >= 2 || return fill(isempty(anchors) ? zero(SVector{3,Float64}) : anchors[1], n)
    lengths = [norm(anchors[i + 1] - anchors[i]) for i in 1:length(anchors)-1]
    total = sum(lengths)
    total > 0 || return fill(anchors[1], n)
    cumulative = vcat(0.0, cumsum(lengths))
    out = Vector{SVector{3,Float64}}(undef, n)
    k = 1
    for i in 1:n
        s = total * (i - 1) / (n - 1)
        while k < length(lengths) && cumulative[k + 1] < s
            k += 1
        end
        t = lengths[k] > 0 ? (s - cumulative[k]) / lengths[k] : 0.0
        out[i] = anchors[k] + clamp(t, 0.0, 1.0) * (anchors[k + 1] - anchors[k])
    end
    return out
end

"""
GL's `has_same_shape_as` as a distance: the largest deviation between the
two normalised outlines, relative to the first's normalised width — GL's
"same" is < 0.01. Different point counts, where GL simply answers no, are
compared after resampling both outlines to 64 points by arc length.
"""
function _shape_distance(a::VMobject, b::VMobject)
    pa = _normalised_outline(a)
    pb = _normalised_outline(b)
    (isempty(pa) || isempty(pb)) && return Inf
    if length(pa) != length(pb)
        pa = _resample(pa, 64)
        pb = _resample(pb, 64)
    end
    width = max(Float64(get_width(a)) / max(Float64(get_height(a)), 1e-9), 1e-9)
    return maximum(norm(p - q) for (p, q) in zip(pa, pb)) / width
end

"""
The assignment of rows to columns of minimum total cost (Kuhn–Munkres with
potentials, O(n²·m)); `assignment[i]` is row i's column, 0 when there are
more rows than columns and row i is left out. Deterministic for a given
matrix: ties resolve by index order.
"""
function _hungarian(cost::AbstractMatrix{<:Real})
    # A row with no finite cost never satisfies `cur < minv` and the search
    # below would never return (`[Inf Inf; 1 2]` hangs), so refuse at the door.
    all(isfinite, cost) || throw(ArgumentError(
        "TransformMatchingShapes: a shape distance is not finite (Inf or NaN) — " *
        "a part without points, or with NaN coordinates, resembles nothing and " *
        "cannot be assigned"))
    n, m = size(cost)
    if n > m
        transposed = _hungarian(permutedims(cost))
        assignment = zeros(Int, n)
        for (j, i) in enumerate(transposed)
            i > 0 && (assignment[i] = j)
        end
        return assignment
    end
    u = zeros(Float64, n + 1)
    v = zeros(Float64, m + 1)
    p = zeros(Int, m + 1)                # p[j + 1]: the row matched to column j (0 = none)
    way = zeros(Int, m + 1)
    for i in 1:n
        p[1] = i
        j0 = 0
        minv = fill(Inf, m + 1)
        used = falses(m + 1)
        while true
            used[j0 + 1] = true
            i0 = p[j0 + 1]
            delta = Inf
            j1 = 0
            for j in 1:m
                used[j + 1] && continue
                cur = Float64(cost[i0, j]) - u[i0 + 1] - v[j + 1]
                if cur < minv[j + 1]
                    minv[j + 1] = cur
                    way[j + 1] = j0
                end
                if minv[j + 1] < delta
                    delta = minv[j + 1]
                    j1 = j
                end
            end
            for j in 0:m
                if used[j + 1]
                    u[p[j + 1] + 1] += delta
                    v[j + 1] -= delta
                else
                    minv[j + 1] -= delta
                end
            end
            j0 = j1
            p[j0 + 1] == 0 && break
        end
        while true
            j1 = way[j0 + 1]
            p[j0 + 1] = p[j1 + 1]
            j0 = j1
            j0 == 0 && break
        end
    end
    assignment = zeros(Int, n)
    for j in 1:m
        p[j + 1] > 0 && (assignment[p[j + 1]] = j)
    end
    return assignment
end

"Source–target index pairs whose shape distance is under `threshold`, chosen by the Hungarian assignment."
function _match_by_shape(sources::Vector{VMobject}, targets::Vector{VMobject}; threshold::Float64)
    (isempty(sources) || isempty(targets)) && return Tuple{Int,Int}[]
    cost = [_shape_distance(s, t) for s in sources, t in targets]
    assignment = _hungarian(cost)
    return [(i, j) for (i, j) in enumerate(assignment) if j > 0 && cost[i, j] <= threshold]
end

"The ink-bearing parts a shape matcher sees: the children, or the mobject itself when it is a leaf."
_shape_parts(m::VMobject) =
    (isempty(m.submobjects) && has_points(m)) ? VMobject[m] : _glyph_children(m)

"""
    TransformMatchingShapes(src, dst; threshold=0.05, run_time=1.0, lag_ratio=0, …)

GL's TransformMatchingShapes with a matcher instead of a test: the parts of
`src` and `dst` (children with ink, or the mobject itself) are paired by
RESEMBLANCE — the shape distance above, minimised over all pairs by a
Hungarian assignment — and every pair under `threshold` morphs with a
`Transform`; the rest fade out and in. No keys are read, so it works on any
mobjects. Identical shapes at any size or place score 0, like GL's; GL's
own threshold is 0.01 and it never pairs differing point counts. When it
finishes the scene holds `dst` itself, like `TransformMatchingTex` (they
share the machinery, and the animation type): `src` is removed and gets its
opacity back, and `rate_func`/`path_arc`/`path_arc_axis` reach every child
while `run_time`/`lag_ratio` stay with the group.

```julia
play!(scene, TransformMatchingShapes(VGroup(Square(), Circle()), VGroup(Circle(), Square())))
play!(scene, TransformMatchingShapes(Tex("x + y"), Tex("y + x")))   # x→x, +→+, y→y
```
"""
function TransformMatchingShapes(
    src::VMobject,
    dst::VMobject;
    threshold::Real = 0.05,
    rate_func::Function = smooth,
    path_arc::Real = 0.0,
    path_arc_axis = OUT,
    kw...,
)
    sparts = _shape_parts(src)
    dparts = _shape_parts(dst)
    pairs = _match_by_shape(sparts, dparts; threshold = Float64(threshold))
    # The motion's keywords go to every child (GL's `anim_config`)
    anims = Animation[
        Transform(
            copy(sparts[i]),
            copy(dparts[j]);
            rate_func,
            path_arc,
            path_arc_axis,
        ) for (i, j) in pairs
    ]
    matched_s = Set(i for (i, _) in pairs)
    matched_d = Set(j for (_, j) in pairs)
    sorph = VMobject[copy(sparts[i]) for i in eachindex(sparts) if !(i in matched_s)]
    dorph = VMobject[copy(dparts[j]) for j in eachindex(dparts) if !(j in matched_d)]
    isempty(sorph) || push!(anims, FadeOut(VGroup(sorph...); rate_func))
    isempty(dorph) || push!(anims, FadeIn(VGroup(dorph...); rate_func))
    isempty(anims) && push!(anims, FadeTransform(copy(src), dst; rate_func))
    group = AnimationGroup(anims...; kw...)
    return TransformMatchingTex(group.base, group, src, dst, _HiddenStyle[])
end
