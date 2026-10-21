# core/svg.jl — the full SVG importer. No GPU work: produces pure
# VMobjects, exactly like Tex does.
#
# The document model is two passes over a tiny in-house XML tree (the SVG
# subset is regular; a dependency like EzXML would cost more startup than this
# whole file):
#
#   pass 1  index every `id`, compile `<style>` CSS, remember the viewBox
#   pass 2  walk the tree with an explicit STATE STACK — the classic
#           matrix stack: entering <g> composes (transform, style,
#           opacity); leaving it pops. <use> replays the referenced subtree
#           under the current state (SVG's "shadow tree").
#
# Design, stated once:
#   · ONE flip. SVG's y grows downward; ours grows upward. The root context
#     starts with diag(1,−1) and NOTHING else ever flips (a single
#     place). Everything — nested transforms, arcs, text — composes
#     over it and comes out upright.
#   · One VMobject child per graphic element, FLAT (like manimlib): groups
#     contribute transform+style, not hierarchy. `svg[3]` addresses pieces,
#     `svg["my-id"]` addresses by the file's own ids (keys), and
#     Transform aligns child-with-child.
#   · The cascade is the spec's, in spec order: presentation attributes <
#     `<style>` rules (by specificity, then document order) < inline
#     `style="…"`. Inheritance passes the inheritable subset down the stack.
#   · Group `opacity` is NOT inheritable in the spec (it is a compositing op
#     on the group's rendered result). Flattening it multiplicatively into the
#     children is the standard approximation (svgelements does the same); it
#     only diverges where siblings of one group OVERLAP each other.
#   · Gradients are evaluated PER STYLE ROW (the SoA style) — Manim
#     rasterizes them away or ignores them. For a linear gradient on straight
#     edges the per-vertex interpolation is EXACT (a linear function sampled
#     linearly); on curved interiors it is an approximation, stated here.
#   · `clipPath` maps to the compositor's real per-pixel Mask: the clip
#     shapes ride along as INVISIBLE children (key "_clip") so transforms keep
#     them aligned, and `clip_layers(svg)` turns the whole mobject into
#     Layers with their masks — drawn flat, clips are ignored (that is what a
#     single framebuffer can do; the layers are one call away).
#   · Unknown things NEVER throw: they are collected and reported in ONE
#     warning per import (the Inkscape acid test). Pure editor metadata
#     (sodipodi:*, inkscape:*, xmlns…) is ignored silently — warning about
#     it would bury the warnings that matter.
#
# Order inside each element: points FIRST, style AFTER (set_points…! re-stamps
# style rows from factory defaults as points grow).

using StaticArrays: SVector, SMatrix
using LinearAlgebra: det          # a singular transform is asked, not caught
using Colors: color_names         # the CSS name table

# ═══════════════════════════════════════════════════════════════════════
# 1 · a small XML tree (elements, attributes in order, text nodes)
# ═══════════════════════════════════════════════════════════════════════

struct _XMLNode
    name::String
    attrs::Vector{Pair{String,String}}
    children::Vector{Any}              # _XMLNode | String (text)
end

const _ENTITIES = Pair{String,Char}["lt" => '<', "gt" => '>', "quot" => '"',
                                    "apos" => '\'', "amp" => '&']

# ONE pass with ONE regex: what a replacement wrote is never read again, so
# `&#38;lt;` is `&lt;` (successive numeric-then-named passes would make it
# `<`), and a code point no Char can hold — past U+10FFFF, a surrogate, or
# too long for UInt32 — becomes U+FFFD instead of a CodePointError, an
# OverflowError or an invalid Char. expat refuses those references; here they
# are written as U+FFFD.
const _ENTITY_RE = r"&(#[xX]([0-9A-Fa-f]+)|#([0-9]+)|lt|gt|quot|apos|amp);"

"The character one `&…;` reference stands for (`ref` is the whole match, ASCII)."
function _entity_char(ref::AbstractString)
    body = SubString(ref, 2, lastindex(ref) - 1)       # without '&' and ';'
    if startswith(body, '#')
        hex = length(body) > 1 && (body[2] == 'x' || body[2] == 'X')
        v = hex ? tryparse(UInt32, SubString(body, 3); base = 16) :
                  tryparse(UInt32, SubString(body, 2); base = 10)
        (v === nothing || v > 0x10FFFF || 0xD800 <= v <= 0xDFFF) && return '\uFFFD'
        return Char(v)
    end
    for (name, c) in _ENTITIES
        body == name && return c
    end
    return '\uFFFD'                                   # unreachable: the regex names only these five
end

function _decode_entities(s::AbstractString)
    occursin('&', s) || return String(s)
    return replace(s, _ENTITY_RE => _entity_char)
end

"Scan the attributes inside a tag body (between the name and the closing >)."
function _parse_attrs(body::AbstractString)
    attrs = Pair{String,String}[]
    for m in eachmatch(r"([\w:.-]+)\s*=\s*(\"([^\"]*)\"|'([^']*)')", body)
        val = m[3] === nothing ? m[4] : m[3]
        push!(attrs, String(m[1]) => _decode_entities(val))
    end
    return attrs
end

"""
The whole document as a tree under a virtual root. Tolerant on purpose: junk
that is not a well-formed tag is skipped, mismatched closes pop to the nearest
matching ancestor — an exported-from-anywhere file must LOAD (the acid test),
the single warning reports what was not understood.
"""
function _xml_parse(s::String)
    root = _XMLNode("#root", Pair{String,String}[], Any[])
    stack = [root]
    i = firstindex(s)
    n = lastindex(s)
    while i <= n
        lt = findnext('<', s, i)
        if lt === nothing
            break
        end
        if lt > i
            text = _decode_entities(s[i:prevind(s, lt)])
            isempty(strip(text)) || push!(stack[end].children, text)
        end
        if startswith(SubString(s, lt), "<!--")
            stop = findnext("-->", s, lt)
            i = stop === nothing ? n + 1 : nextind(s, stop[end])
        elseif startswith(SubString(s, lt), "<![CDATA[")
            stop = findnext("]]>", s, lt)
            last_c = stop === nothing ? n : prevind(s, stop[1])
            push!(stack[end].children, s[lt+9:last_c])
            i = stop === nothing ? n + 1 : nextind(s, stop[end])
        elseif startswith(SubString(s, lt), "<?")
            stop = findnext("?>", s, lt)
            i = stop === nothing ? n + 1 : nextind(s, stop[end])
        elseif startswith(SubString(s, lt), "<!")
            # DOCTYPE, possibly with an internal [...] subset
            j = lt
            depth = 0
            while j <= n
                c = s[j]
                c == '[' && (depth += 1)
                c == ']' && (depth -= 1)
                c == '>' && depth <= 0 && break
                j = nextind(s, j)
            end
            i = j > n ? n + 1 : nextind(s, j)
        else
            gt = _find_tag_end(s, lt)
            gt === nothing && break
            body = s[nextind(s, lt):prevind(s, gt)]
            if startswith(body, "/")                       # </name>
                name = String(strip(body[2:end]))
                k = findlast(nd -> nd.name == name, stack)
                (k !== nothing && k > 1) && resize!(stack, k - 1)
            else
                selfclosing = endswith(body, "/")
                selfclosing && (body = body[1:end-1])
                mname = match(r"^[\w:.-]+", body)
                if mname !== nothing
                    node = _XMLNode(String(mname.match),
                                    _parse_attrs(body[mname.offset+lastindex(mname.match):end]),
                                    Any[])
                    push!(stack[end].children, node)
                    selfclosing || push!(stack, node)
                end
            end
            i = nextind(s, gt)
        end
    end
    return root
end

"The `>` that closes this tag, ignoring any `>` inside quoted attributes."
function _find_tag_end(s::String, lt::Int)
    i = lt
    quote_char = '\0'
    n = lastindex(s)
    while i <= n
        c = s[i]
        if quote_char != '\0'
            c == quote_char && (quote_char = '\0')
        elseif c == '"' || c == '\''
            quote_char = c
        elseif c == '>'
            return i
        end
        i = nextind(s, i)
    end
    return nothing
end

_local_name(name::String) = (k = findlast(':', name); k === nothing ? name : name[k+1:end])
_prefix(name::String) = (k = findlast(':', name); k === nothing ? "" : name[1:k-1])

function _attr(node::_XMLNode, name::String, default = nothing)
    for (k, v) in node.attrs
        (k == name || _local_name(k) == name) && return v
    end
    return default
end

# ═══════════════════════════════════════════════════════════════════════
# 2 · numbers, lengths, transforms, colors
# ═══════════════════════════════════════════════════════════════════════

const _UNIT_TO_PX = Pair{String,Float64}["px" => 1.0, "pt" => 96 / 72,
    "pc" => 16.0, "mm" => 96 / 25.4, "cm" => 96 / 2.54, "in" => 96.0]

"A CSS length → user units (px). Returns nothing if unparseable."
function _flt(v::Union{Nothing,AbstractString})
    v === nothing && return nothing
    t = strip(v)
    m = match(r"^[-+]?(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?", t)
    m === nothing && return nothing
    x = parse(Float64, m.match)
    rest = lowercase(strip(t[m.offset+lastindex(m.match):end]))
    for (u, f) in _UNIT_TO_PX
        rest == u && return x * f
    end
    return x         # unitless, %, em… — % is resolved by _length, em by callers
end

"All the numbers in a list attribute (`points`, `viewBox`, transform args)."
_floats(v::AbstractString) =
    [parse(Float64, m.match) for m in
     eachmatch(r"[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?", v)]

_affine(a, b, c, d, e, f) = SMatrix{3,3,Float64}(a, b, 0, c, d, 0, e, f, 1)
const _EYE3 = _affine(1, 0, 0, 1, 0, 0)
_translation(tx, ty) = _affine(1, 0, 0, 1, tx, ty)

"transform list → composed matrix (spec order: left-to-right composition)."
function _parse_transform(b, v::Union{Nothing,AbstractString})
    v === nothing && return _EYE3
    M = _EYE3
    for m in eachmatch(r"(\w+)\s*\(([^)]*)\)", v)
        fn = m[1]
        a = _floats(m[2])
        T = if fn == "matrix" && length(a) == 6
            _affine(a...)
        elseif fn == "translate" && !isempty(a)
            _translation(a[1], length(a) > 1 ? a[2] : 0.0)
        elseif fn == "scale" && !isempty(a)
            _affine(a[1], 0, 0, length(a) > 1 ? a[2] : a[1], 0, 0)
        elseif fn == "rotate" && !isempty(a)
            θ = deg2rad(a[1])
            R = _affine(cos(θ), sin(θ), -sin(θ), cos(θ), 0, 0)
            length(a) >= 3 ? _translation(a[2], a[3]) * R * _translation(-a[2], -a[3]) : R
        elseif fn == "skewX" && !isempty(a)
            _affine(1, 0, tan(deg2rad(a[1])), 1, 0, 0)
        elseif fn == "skewY" && !isempty(a)
            _affine(1, tan(deg2rad(a[1])), 0, 1, 0, 0)
        else
            _note!(b, "transform:$fn")
            _EYE3
        end
        M = M * T
    end
    return M
end

"""
A paint value, resolved. Returns `:none`, `(:url, id)`, or
`(:rgb, (r,g,b), alpha)` — the alpha is the COLOR's own (rgba()/#rrggbbaa),
which multiplies fill-/stroke-opacity per spec.
"""
function _svg_paint(b, v::AbstractString, computed::Dict{String,String})
    t = strip(v)
    low = lowercase(t)
    (low == "none" || low == "transparent") && return :none
    if startswith(low, "url(")
        m = match(r"url\(\s*['\"]?#([^'\")\s]+)", t)
        m === nothing && (_note!(b, "paint:$t"); return (:rgb, (0f0, 0f0, 0f0), 1f0))
        return (:url, String(m[1]))
    end
    low == "currentcolor" &&
        return _svg_paint(b, get(computed, "color", "black"), Dict{String,String}())
    if (m = match(r"^rgba?\(([^)]*)\)$", low)) !== nothing
        parts = strip.(split(m[1], r"[,\s/]+"; keepempty = false))
        vals = Float32[]
        for p in parts
            x = endswith(p, "%") ? something(tryparse(Float64, p[1:end-1]), 0.0) * 2.55 :
                something(tryparse(Float64, p), 0.0)
            push!(vals, Float32(x))
        end
        length(vals) < 3 && (_note!(b, "paint:$t"); return (:rgb, (0f0, 0f0, 0f0), 1f0))
        a = length(vals) >= 4 ? clamp(vals[4] > 1 ? vals[4] / 255 : vals[4], 0, 1) : 1f0
        return (:rgb, (clamp(vals[1] / 255, 0, 1), clamp(vals[2] / 255, 0, 1),
                       clamp(vals[3] / 255, 0, 1)), Float32(a))
    end
    if (m = match(r"^#([0-9a-f]{4}|[0-9a-f]{8})$", low)) !== nothing   # hex+alpha
        h = m[1]
        h = length(h) == 4 ? join(c^2 for c in h) : h
        c = [parse(Int, h[i:i+1], base = 16) / 255 for i in 1:2:7]
        return (:rgb, (Float32(c[1]), Float32(c[2]), Float32(c[3])), Float32(c[4]))
    end
    # What is left is `#rgb`/`#rrggbb` and the NAMES of Colors.jl's table,
    # lower-cased and verbatim. Handing anything else to `parse(RGB, …)` would
    # also take `hsl()`, `hsla()` (losing its alpha), `0xff8000` and
    # `light blue`: forms that are not SVG paint. They warn `paint:…` and
    # paint black.
    if startswith(low, "#") || haskey(color_names, low)
        col = try
            _rgba(low, 1.0)
        catch
            _note!(b, "paint:$t")
            return (:rgb, (0f0, 0f0, 0f0), 1f0)
        end
        return (:rgb, (col[1], col[2], col[3]), 1f0)
    end
    _note!(b, "paint:$t")
    return (:rgb, (0f0, 0f0, 0f0), 1f0)
end

# ═══════════════════════════════════════════════════════════════════════
# 3 · CSS (<style>): simple selectors, spec specificity
# ═══════════════════════════════════════════════════════════════════════

struct _CSSRule
    tagname::String                    # "" = any ("*" too)
    classes::Vector{String}
    id::String                         # "" = any
    specificity::Tuple{Int,Int,Int}    # (ids, classes, tags) — the spec triple
    order::Int
    decls::Vector{Pair{String,String}}
end

function _parse_declarations(body::AbstractString)
    decls = Pair{String,String}[]
    for part in split(body, ';')
        k = findfirst(':', part)
        k === nothing && continue
        prop = strip(part[1:k-1])
        val = strip(part[k+1:end])
        (isempty(prop) || isempty(val)) && continue
        push!(decls, lowercase(prop) => String(val))
    end
    return decls
end

function _parse_css!(b, text::AbstractString)
    clean = replace(text, r"/\*.*?\*/"s => "")
    for m in eachmatch(r"([^{}]+)\{([^}]*)\}", clean)
        decls = _parse_declarations(m[2])
        isempty(decls) && continue
        for sel in split(m[1], ',')
            sel = strip(sel)
            isempty(sel) && continue
            sm = match(r"^(\*|[A-Za-z][\w-]*)?((?:[.#][\w-]+)*)$", sel)
            if sm === nothing
                _note!(b, "css-selector:$sel")     # combinators etc: out of subset
                continue
            end
            tagname = sm[1] === nothing || sm[1] == "*" ? "" : String(sm[1])
            classes = String[]
            id = ""
            for pm in eachmatch(r"([.#])([\w-]+)", something(sm[2], ""))
                pm[1] == "." ? push!(classes, pm[2]) : (id = pm[2])
            end
            push!(b.css, _CSSRule(tagname, classes, id,
                                  (id == "" ? 0 : 1, length(classes), tagname == "" ? 0 : 1),
                                  length(b.css), decls))
        end
    end
end

function _css_matches(rule::_CSSRule, node::_XMLNode)
    rule.tagname == "" || rule.tagname == _local_name(node.name) || return false
    if rule.id != ""
        _attr(node, "id", "") == rule.id || return false
    end
    if !isempty(rule.classes)
        cls = split(something(_attr(node, "class"), ""))
        all(c -> c in cls, rule.classes) || return false
    end
    return true
end

# ═══════════════════════════════════════════════════════════════════════
# 4 · the state stack and the cascade
# ═══════════════════════════════════════════════════════════════════════

# What flows down the tree (the spec's inheritable subset that we consume).
const _INHERITED = ("fill", "stroke", "stroke-width", "fill-opacity",
                    "stroke-opacity", "fill-rule", "color", "visibility",
                    "font-family", "font-size", "text-anchor",
                    "stroke-linejoin")   # inherited per the SVG spec
# What we read per element, wherever it appears (attribute, CSS or style=).
const _PRESENTATION = (_INHERITED..., "opacity", "stop-color", "stop-opacity",
                       "clip-path", "display")
# Rendering-relevant things we do NOT implement: collected into the single
# warning. (fill-rule only warns when it actually asks for evenodd.)
# stroke-linejoin is not in this list: miter and bevel are honoured, and
# `round` warns by VALUE (`stroke-linejoin:round`) rather than by attribute,
# because the attribute itself is supported.
const _KNOWN_UNSUPPORTED_ATTRS = ("stroke-dasharray", "stroke-dashoffset",
    "stroke-linecap", "stroke-miterlimit", "filter", "mask",
    "marker-start", "marker-mid", "marker-end", "paint-order", "vector-effect",
    "clip-rule", "baseline-shift", "letter-spacing", "word-spacing")

struct _Ctx
    mat::SMatrix{3,3,Float64,9}
    style::Dict{String,String}         # inherited, already computed
    opacity::Float64                   # accumulated group opacity
    # a clip-path seen on an ANCESTOR group: (id, matrix at that group) —
    # userSpaceOnUse resolves in the REFERENCING element's space, so the
    # matrix must be frozen where the attribute appeared
    clip::Union{Nothing,Tuple{String,SMatrix{3,3,Float64,9}}}
end
_Ctx(mat, style, opacity) = _Ctx(mat, style, opacity, nothing)

mutable struct _SVGBuild
    byid::Dict{String,_XMLNode}
    css::Vector{_CSSRule}
    vb::NTuple{4,Float64}              # viewBox (minx, miny, w, h) — % base
    sink::Vector{VMobject}             # where finished children land
    unknowns::Vector{String}           # what the single warning will report
    use_stack::Vector{String}          # cycle guard for <use>
    source_name::String
end

_note!(b::_SVGBuild, what::String) = what in b.unknowns || push!(b.unknowns, what)

"Pass 1: index ids and compile CSS (document order preserved)."
function _index!(b::_SVGBuild, node::_XMLNode)
    id = _attr(node, "id")
    id !== nothing && !haskey(b.byid, id) && (b.byid[id] = node)
    if _local_name(node.name) == "style"
        for c in node.children
            c isa String && _parse_css!(b, c)
        end
    end
    for c in node.children
        c isa _XMLNode && _index!(b, c)
    end
end

"The element's OWN declarations, cascaded in spec order."
function _own_style(b::_SVGBuild, node::_XMLNode)
    d = Dict{String,String}()
    for (k, v) in node.attrs
        lk = _local_name(k)
        if lk in _PRESENTATION
            d[lk] = strip(v)
        elseif lk in _KNOWN_UNSUPPORTED_ATTRS
            (lk == "clip-rule" && strip(v) == "nonzero") || _note!(b, "attr:$lk")
        end
    end
    for rule in b.css                       # pre-sorted ascending: later wins
        if _css_matches(rule, node)
            for (k, v) in rule.decls
                if k in _PRESENTATION
                    d[k] = v
                elseif k in _KNOWN_UNSUPPORTED_ATTRS
                    _note!(b, "attr:$k")
                end
            end
        end
    end
    st = _attr(node, "style")
    if st !== nothing
        for (k, v) in _parse_declarations(st)
            if k in _PRESENTATION
                d[k] = v
            elseif k in _KNOWN_UNSUPPORTED_ATTRS
                _note!(b, "attr:$k")
            end
        end
    end
    return d
end

"inherited ∘ own → computed. `inherit` keeps the inherited value (its meaning)."
function _computed_style(inherited::Dict{String,String}, own::Dict{String,String})
    d = copy(inherited)
    for (k, v) in own
        v == "inherit" || (d[k] = v)
    end
    return d
end

_inheritable(computed::Dict{String,String}) =
    Dict{String,String}(k => v for (k, v) in computed if k in _INHERITED)

_opacity_of(own::Dict{String,String}) =
    clamp(something(_flt(get(own, "opacity", "1")), 1.0), 0.0, 1.0)

# ═══════════════════════════════════════════════════════════════════════
# 5 · path data — the full grammar, with elliptical arcs
# ═══════════════════════════════════════════════════════════════════════

# The scanner is stateful ON PURPOSE (a global regex tokenizer cannot parse
# arc flags: in `a25,25 -30 0,1 50,-25` the `0,1` are single-character flags,
# and `011` after a flag context is THREE tokens, not the number eleven).
mutable struct _PathScan
    s::String
    i::Int
end

_ps_ws(c::Char) = c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == ','

function _ps_skip!(p::_PathScan)
    n = lastindex(p.s)
    while p.i <= n && _ps_ws(p.s[p.i])
        p.i += 1
    end
    return p
end

_ps_done(p::_PathScan) = (_ps_skip!(p); p.i > lastindex(p.s))

"Is the next token a number (i.e. the previous command repeats implicitly)?"
function _ps_more_args(p::_PathScan)
    _ps_skip!(p)
    p.i > lastindex(p.s) && return false
    c = p.s[p.i]
    return isdigit(c) || c == '-' || c == '+' || c == '.'
end

"One number under the SVG path grammar (`1.5.3` is 1.5 then .3; `1-2` two)."
function _ps_num!(p::_PathScan)
    _ps_skip!(p)
    s = p.s
    n = lastindex(s)
    j = p.i
    j <= n && (s[j] == '-' || s[j] == '+') && (j += 1)
    d0 = j
    while j <= n && isdigit(s[j]); j += 1; end
    if j <= n && s[j] == '.'
        j += 1
        while j <= n && isdigit(s[j]); j += 1; end
    end
    j > d0 || throw(ArgumentError(
        "malformed number in the SVG path at byte $(p.i): «$(s[p.i:min(n, p.i+12)])…»"))
    if j <= n && (s[j] == 'e' || s[j] == 'E')
        k = j + 1
        k <= n && (s[k] == '-' || s[k] == '+') && (k += 1)
        if k <= n && isdigit(s[k])
            j = k
            while j <= n && isdigit(s[j]); j += 1; end
        end
    end
    x = parse(Float64, s[p.i:j-1])
    p.i = j
    return x
end

"An arc flag: EXACTLY one character, 0 or 1 (the spec quirk)."
function _ps_flag!(p::_PathScan)
    _ps_skip!(p)
    p.i > lastindex(p.s) && throw(ArgumentError("truncated arc command"))
    c = p.s[p.i]
    c == '0' || c == '1' || throw(ArgumentError(
        "arc flag must be 0 or 1, got '$c' at byte $(p.i)"))
    p.i += 1
    return c == '1'
end

"""
Append an elliptical arc as quadratics: center (ccx,ccy), radii (rx,ry),
x-axis rotation φ, from angle θ1 sweeping Δθ. Same construction as
`quadratic_bezier_points_for_arc` (anchors on the ellipse, handles nudged by
1/cos(Δθ/nc/2)) — quadratics are affine-invariant, so the circle recipe maps
exactly onto the ellipse. Density matches Circle: a full turn = 16 components.
The first mapped point is snapped onto the current point (add_arc_to!'s trick)
so subpaths never open by a rounding hair.
"""
function _ellipse_arc_append!(m::VMobject, trans::F, ccx, ccy, rx, ry, φ, θ1, Δθ) where {F}
    # parenthesise like _init_arc!: (15·TAU)/TAU floats to
    # 14.999…8 and floor loses a component — 15·(TAU/TAU) is exact
    nc = Int(floor(15 * (abs(Δθ) / TAU))) + 1
    nudge = 1 / cos(Δθ / nc / 2)
    cosφ, sinφ = cos(φ), sin(φ)
    npts = 2nc + 1
    mapped = Vector{Point3f}(undef, npts)
    for (k, a) in enumerate(range(θ1, θ1 + Δθ; length = npts))
        ux = cos(a); uy = sin(a)
        if iseven(k)
            ux *= nudge; uy *= nudge
        end
        qx = rx * ux; qy = ry * uy
        mapped[k] = trans(cosφ * qx - sinφ * qy + ccx, sinφ * qx + cosφ * qy + ccy)
    end
    delta = m.points[end] - mapped[1]
    append_points!(m, [p + delta for p in @view mapped[2:end]])
    return m
end

"A command's arc arguments → center parametrization (spec appendix B.2.4)."
function _arc_to!(m::VMobject, trans::F, cx, cy, rx, ry, φdeg, large::Bool,
                  sweep::Bool, x, y) where {F}
    (x == cx && y == cy) && return m                 # zero-length: spec skips it
    if rx == 0 || ry == 0                            # degenerate: a line
        add_line_to!(m, trans(x, y))
        return m
    end
    rx, ry = abs(rx), abs(ry)
    φ = deg2rad(φdeg)
    cosφ, sinφ = cos(φ), sin(φ)
    dx2, dy2 = (cx - x) / 2, (cy - y) / 2
    x1p = cosφ * dx2 + sinφ * dy2
    y1p = -sinφ * dx2 + cosφ * dy2
    Λ = x1p^2 / rx^2 + y1p^2 / ry^2
    if Λ > 1                                          # radii too small: scale up
        rx *= sqrt(Λ); ry *= sqrt(Λ)
    end
    num = rx^2 * ry^2 - rx^2 * y1p^2 - ry^2 * x1p^2
    den = rx^2 * y1p^2 + ry^2 * x1p^2
    coef = (large != sweep ? 1 : -1) * sqrt(max(num, 0.0) / den)
    cxp = coef * rx * y1p / ry
    cyp = -coef * ry * x1p / rx
    ccx = cosφ * cxp - sinφ * cyp + (cx + x) / 2
    ccy = sinφ * cxp + cosφ * cyp + (cy + y) / 2
    θ1 = atan((y1p - cyp) / ry, (x1p - cxp) / rx)
    θ2 = atan((-y1p - cyp) / ry, (-x1p - cxp) / rx)
    Δθ = θ2 - θ1
    sweep && Δθ < 0 && (Δθ += TAU)
    !sweep && Δθ > 0 && (Δθ -= TAU)
    return _ellipse_arc_append!(m, trans, ccx, ccy, rx, ry, φ, θ1, Δθ)
end

"""
The FULL d= grammar: M L H V C S Q T A Z, absolute and relative, implicit
repetition, `M` repeating as lines, S/T control reflection. Cubics go through
`_cubic_to_two_quadratics` (the engine is natively quadratic).
"""
function _path_data!(m::VMobject, d::AbstractString, trans::F) where {F}
    p = _PathScan(String(d), 1)
    cx = cy = sx = sy = 0.0
    pcx = pcy = 0.0
    cmd = ' '
    last_cmd = ' '
    while !_ps_done(p)
        c = p.s[p.i]
        i0 = p.i
        if isletter(c)
            cmd = c
            p.i += 1
        elseif cmd == ' ' || uppercase(cmd) == 'Z'
            # A number where nothing can repeat. After `Z` the branch below
            # consumes no input, so `Z 5 5` would spin forever; an importer
            # that "never throws" must not hang either.
            throw(ArgumentError("unknown or misplaced SVG path command '$cmd' at byte $(p.i) of the path data"))
        end                                           # else: implicit repetition
        rel = islowercase(cmd)
        C = uppercase(cmd)
        if C == 'M'
            x = _ps_num!(p); y = _ps_num!(p)
            rel && (x += cx; y += cy)
            cx, cy = x, y; sx, sy = x, y
            start_new_path!(m, trans(x, y))
            cmd = rel ? 'l' : 'L'                     # repeated M means lines
        elseif C == 'L'
            x = _ps_num!(p); y = _ps_num!(p)
            rel && (x += cx; y += cy)
            cx, cy = x, y
            add_line_to!(m, trans(x, y))
        elseif C == 'H'
            x = _ps_num!(p); rel && (x += cx)
            cx = x
            add_line_to!(m, trans(cx, cy))
        elseif C == 'V'
            y = _ps_num!(p); rel && (y += cy)
            cy = y
            add_line_to!(m, trans(cx, cy))
        elseif C == 'C' || C == 'S'
            local x1, y1
            if C == 'C'
                x1 = _ps_num!(p); y1 = _ps_num!(p)
                rel && (x1 += cx; y1 += cy)
            else                                      # reflected first control
                x1 = last_cmd in ('C', 'S') ? 2cx - pcx : cx
                y1 = last_cmd in ('C', 'S') ? 2cy - pcy : cy
            end
            x2 = _ps_num!(p); y2 = _ps_num!(p)
            x = _ps_num!(p); y = _ps_num!(p)
            rel && (x2 += cx; y2 += cy; x += cx; y += cy)
            h1, mid, h2 = _cubic_to_two_quadratics(trans(cx, cy), trans(x1, y1),
                                                   trans(x2, y2), trans(x, y))
            add_quadratic_bezier_to!(m, h1, mid)
            add_quadratic_bezier_to!(m, h2, trans(x, y))
            pcx, pcy = x2, y2
            cx, cy = x, y
        elseif C == 'Q' || C == 'T'
            local x1, y1
            if C == 'Q'
                x1 = _ps_num!(p); y1 = _ps_num!(p)
                rel && (x1 += cx; y1 += cy)
            else
                x1 = last_cmd in ('Q', 'T') ? 2cx - pcx : cx
                y1 = last_cmd in ('Q', 'T') ? 2cy - pcy : cy
            end
            x = _ps_num!(p); y = _ps_num!(p)
            rel && (x += cx; y += cy)
            add_quadratic_bezier_to!(m, trans(x1, y1), trans(x, y))
            pcx, pcy = x1, y1
            cx, cy = x, y
        elseif C == 'A'
            rx = _ps_num!(p); ry = _ps_num!(p)
            φ = _ps_num!(p)
            large = _ps_flag!(p); sweep = _ps_flag!(p)
            x = _ps_num!(p); y = _ps_num!(p)
            rel && (x += cx; y += cy)
            _arc_to!(m, trans, cx, cy, rx, ry, φ, large, sweep, x, y)
            cx, cy = x, y
        elseif C == 'Z'
            (cx != sx || cy != sy) && add_line_to!(m, trans(sx, sy))
            cx, cy = sx, sy
        else
            throw(ArgumentError("unknown or misplaced SVG path command '$cmd'"))
        end
        last_cmd = C
        # the belt to the braces above: an iteration that consumed nothing would
        # loop forever, whatever branch it took
        p.i > i0 || throw(ArgumentError("the SVG path scanner did not advance at byte $(p.i) ('$cmd')"))
    end
    return m
end

# ═══════════════════════════════════════════════════════════════════════
# 6 · the graphic elements
# ═══════════════════════════════════════════════════════════════════════

_make_trans(M::SMatrix{3,3,Float64,9}) =
    (x, y) -> begin
        px = M[1, 1] * x + M[1, 2] * y + M[1, 3]
        py = M[2, 1] * x + M[2, 2] * y + M[2, 3]
        Point3f(px, py, 0)
    end

"Drop subpaths that collapsed to a single point (the ghost trap of the subpath list)."
function _drop_point_subpaths!(m::VMobject)
    has_points(m) || return m
    keep = Point3f[]
    for sp in get_subpaths(m)
        collapsed = all(p -> p == sp[1], sp)
        collapsed && continue
        if isempty(keep)
            append!(keep, sp)
        else
            push!(keep, keep[end], sp[1])            # the pinned-handle cut
            append!(keep, @view sp[2:end])
        end
    end
    length(keep) == length(m.points) && return m
    set_points!(m, keep)
    return m
end

function _rect_geometry!(m::VMobject, trans::F, x, y, w, h, rx, ry) where {F}
    if rx <= 0 && ry <= 0
        start_new_path!(m, trans(x, y))
        add_line_to!(m, trans(x + w, y))
        add_line_to!(m, trans(x + w, y + h))
        add_line_to!(m, trans(x, y + h))
        add_line_to!(m, trans(x, y))
        return m
    end
    rx <= 0 && (rx = ry)                              # the spec's auto rules
    ry <= 0 && (ry = rx)
    rx = min(rx, w / 2); ry = min(ry, h / 2)
    q = TAU / 4
    start_new_path!(m, trans(x + rx, y))
    add_line_to!(m, trans(x + w - rx, y))
    _ellipse_arc_append!(m, trans, x + w - rx, y + ry, rx, ry, 0.0, -q, q)
    add_line_to!(m, trans(x + w, y + h - ry))
    _ellipse_arc_append!(m, trans, x + w - rx, y + h - ry, rx, ry, 0.0, 0.0, q)
    add_line_to!(m, trans(x + rx, y + h))
    _ellipse_arc_append!(m, trans, x + rx, y + h - ry, rx, ry, 0.0, q, q)
    add_line_to!(m, trans(x, y + ry))
    _ellipse_arc_append!(m, trans, x + rx, y + ry, rx, ry, 0.0, 2q, q)
    return m
end

"cx,cy,rx,ry → the full ellipse, closed EXACTLY (16 components, like Circle)."
function _ellipse_geometry!(m::VMobject, trans::F, cx, cy, rx, ry) where {F}
    start = trans(cx + rx, cy)
    start_new_path!(m, start)
    _ellipse_arc_append!(m, trans, cx, cy, rx, ry, 0.0, 0.0, TAU)
    m.points[end] = start                             # bit-exact closure
    _note_data_changed!(m)
    return m
end

function _poly_geometry!(m::VMobject, trans::F, v::AbstractString, close::Bool) where {F}
    nums = _floats(v)
    length(nums) < 4 && return m
    isodd(length(nums)) && pop!(nums)                 # spec: render up to last pair
    start_new_path!(m, trans(nums[1], nums[2]))
    for k in 3:2:length(nums)-1
        add_line_to!(m, trans(nums[k], nums[k+1]))
    end
    close && add_line_to!(m, trans(nums[1], nums[2]))
    return m
end

const _X_ATTRS = ("x", "x1", "x2", "cx", "width", "rx")   # % resolves vs viewBox w

function _geometry!(b::_SVGBuild, ln::String, node::_XMLNode, child::VMobject,
                    trans::F) where {F}
    fa(name, default = 0.0) = begin
        v = _attr(node, name)
        x = _flt(v)
        x === nothing && return default
        if v !== nothing && endswith(strip(v), "%")       # spec: vs the viewport
            x /= 100
            x *= name in _X_ATTRS ? b.vb[3] :
                 name == "r" ? hypot(b.vb[3], b.vb[4]) / sqrt(2) : b.vb[4]
        end
        x
    end
    if ln == "path"
        d = _attr(node, "d")
        d === nothing || _path_data!(child, d, trans)
    elseif ln == "rect"
        w = fa("width"); h = fa("height")
        (w > 0 && h > 0) &&
            _rect_geometry!(child, trans, fa("x"), fa("y"), w, h, fa("rx"), fa("ry"))
    elseif ln == "circle"
        r = fa("r")
        r > 0 && _ellipse_geometry!(child, trans, fa("cx"), fa("cy"), r, r)
    elseif ln == "ellipse"
        rx = fa("rx"); ry = fa("ry")
        (rx > 0 && ry > 0) &&
            _ellipse_geometry!(child, trans, fa("cx"), fa("cy"), rx, ry)
    elseif ln == "line"
        start_new_path!(child, trans(fa("x1"), fa("y1")))
        add_line_to!(child, trans(fa("x2"), fa("y2")))
    elseif ln == "polyline"
        _poly_geometry!(child, trans, something(_attr(node, "points"), ""), false)
    elseif ln == "polygon"
        _poly_geometry!(child, trans, something(_attr(node, "points"), ""), true)
    end
    return child
end

# ═══════════════════════════════════════════════════════════════════════
# 7 · gradients: evaluated onto the SoA style rows
# ═══════════════════════════════════════════════════════════════════════

"stops (offset ∈ [0,1] ascending, RGBA) — following href chains (Inkscape
defines the stops once and references them from every gradient)."
function _gradient_stops(b::_SVGBuild, node::_XMLNode, depth::Int = 0)
    stops = Tuple{Float64,Vec4f}[]
    for c in node.children
        c isa _XMLNode || continue
        _local_name(c.name) == "stop" || continue
        own = _own_style(b, c)
        off = strip(something(_attr(c, "offset"), "0"))
        t = endswith(off, "%") ? something(tryparse(Float64, off[1:end-1]), 0.0) / 100 :
            something(tryparse(Float64, off), 0.0)
        paint = _svg_paint(b, get(own, "stop-color", "black"), Dict{String,String}())
        rgb, ca = paint isa Tuple && paint[1] == :rgb ? (paint[2], paint[3]) :
                  ((0f0, 0f0, 0f0), 1f0)
        so = Float32(clamp(something(_flt(get(own, "stop-opacity", "1")), 1.0), 0, 1))
        t_clamped = clamp(t, 0.0, 1.0)
        isempty(stops) || (t_clamped = max(t_clamped, stops[end][1]))  # ascending
        push!(stops, (t_clamped, Vec4f(rgb[1], rgb[2], rgb[3], so * ca)))
    end
    if isempty(stops) && depth < 8
        href = _attr(node, "href")
        if href !== nothing && startswith(href, "#") && haskey(b.byid, href[2:end])
            return _gradient_stops(b, b.byid[href[2:end]], depth + 1)
        end
    end
    return stops
end

function _stop_color(stops::Vector{Tuple{Float64,Vec4f}}, t::Float64)
    t <= stops[1][1] && return stops[1][2]
    for k in 2:length(stops)
        t1, c1 = stops[k-1]
        t2, c2 = stops[k]
        if t <= t2
            α = t2 ≈ t1 ? 1.0 : (t - t1) / (t2 - t1)
            return Vec4f(c1 + Float32(α) * (c2 - c1))
        end
    end
    return stops[end][2]
end

"spreadMethod applied to an unclamped t: 0 = pad · 1 = reflect · 2 = repeat."
function _spread_t(t::Float64, spread::Int32)
    spread == Int32(1) && return 1.0 - abs(mod(t, 2.0) - 1.0)
    spread == Int32(2) && return mod(t, 1.0)
    return clamp(t, 0.0, 1.0)
end

"""
SVG focal radial parameter at `p` (uv space: centre 0, radius 1, focus `f`
strictly inside): the t for which p lies on the circle centred f + t·(0 − f)
with radius t. One positive root because |f| < 1. The SAME closed form runs
per pixel in the FILL_GRAD fragment shader — rows and pixels agree at anchors.
"""
function _radial_t(p::SVector{2,Float64}, f::SVector{2,Float64})
    ff = f[1]^2 + f[2]^2
    ff < 1e-12 && return hypot(p[1], p[2])
    d = p - f
    A = ff - 1.0
    B = d[1] * f[1] + d[2] * f[2]
    C = d[1]^2 + d[2]^2
    return (-B - sqrt(max(B^2 - A * C, 0.0))) / A
end

"""
Bake the per-fragment sidecar (core/mobject.jl's FillGradient) once the rows
are written: the ramp texels come from the SAME `_stop_color` the rows used,
and `baked_rgba` snapshots the rows so the renderer can tell "as imported"
from "user-repainted" (see `active_fill_gradient`).
"""
function _attach_fill_gradient!(child::VMobject, kind::Symbol, uv::Vector{Vec2f},
                                focus::NTuple{2,Float32}, spread::Int32,
                                stops::Vector{Tuple{Float64,Vec4f}},
                                opacity_mult::Float64)
    ramp = Vector{Float32}(undef, 4 * RAMP_RESOLUTION)
    for k in 1:RAMP_RESOLUTION
        c = _stop_color(stops, (k - 0.5) / RAMP_RESOLUTION)
        ramp[4k-3] = c[1]
        ramp[4k-2] = c[2]
        ramp[4k-1] = c[3]
        ramp[4k] = c[4] * Float32(opacity_mult)
    end
    child.fill_gradient = FillGradient(kind, uv, focus, spread, ramp,
                                       copy(child.fill_rgba))
    return child
end

"An inherited-with-href gradient attribute (x1, cx… live on the ancestor)."
function _grad_attr(b::_SVGBuild, node::_XMLNode, name::String, default::String,
                    depth::Int = 0)
    v = _attr(node, name)
    v !== nothing && return v
    href = _attr(node, "href")
    if depth < 8 && href !== nothing && startswith(href, "#") &&
       haskey(b.byid, href[2:end])
        return _grad_attr(b, b.byid[href[2:end]], name, default, depth + 1)
    end
    return default
end

"""
Evaluate the gradient at every style row of `child`. All evaluation happens in
the element's LOCAL user space (points are mapped back through inv(M)): that
keeps objectBoundingBox boxes axis-aligned and radial circles circular even
when the element's transform rotates or shears. Linear gradients are affine-
covariant, so this is exact; per-ROW sampling is the stated approximation.
"""
function _apply_gradient!(b::_SVGBuild, child::VMobject, gnode::_XMLNode,
                          M::SMatrix{3,3,Float64,9}, which::Symbol,
                          opacity_mult::Float64)
    kind = _local_name(gnode.name)
    kind in ("linearGradient", "radialGradient") || (_note!(b, "paint-ref:$kind"); return)
    stops = _gradient_stops(b, gnode)
    isempty(stops) && (_note!(b, "gradient-without-stops"); return)

    # ASK whether the matrices invert. `inv` of a singular SMatrix never
    # throws (StaticArrays divides by zero and hands back Inf/NaN), so a
    # `try inv() catch` would attach a gradient with uv = NaN — every row
    # painted the last stop, no warning. Instead the element's fill is left at
    # the factory default and a note is recorded.
    dM = det(M)
    (dM == 0 || !isfinite(dM)) && (_note!(b, "gradient-singular-transform"); return)
    Minv = inv(M)
    GT = _parse_transform(b, _attr(gnode, "gradientTransform"))
    dG = det(GT)
    (dG == 0 || !isfinite(dG)) && (_note!(b, "gradient-singular-transform"); return)
    GTinv = inv(GT)
    obb = _grad_attr(b, gnode, "gradientUnits", "objectBoundingBox") == "objectBoundingBox"

    # local coordinates of every row (and the local bbox, if oBB needs it)
    n = get_num_points(child)
    loc = Vector{SVector{2,Float64}}(undef, n)
    for i in 1:n
        p = child.points[i]
        loc[i] = SVector(Minv[1, 1] * p[1] + Minv[1, 2] * p[2] + Minv[1, 3],
                         Minv[2, 1] * p[1] + Minv[2, 2] * p[2] + Minv[2, 3])
    end
    bbmin = SVector(minimum(q[1] for q in loc), minimum(q[2] for q in loc))
    bbsize = SVector(max(maximum(q[1] for q in loc) - bbmin[1], 1e-12),
                     max(maximum(q[2] for q in loc) - bbmin[2], 1e-12))

    frac(v, axis) = begin                             # a gradient coordinate
        s = strip(v)
        x = something(_flt(s), 0.0)
        endswith(s, "%") && (x /= 100)
        obb ? x : x                                   # oBB: fraction; user: units
    end
    spread_s = _grad_attr(b, gnode, "spreadMethod", "pad")
    spread = spread_s == "reflect" ? Int32(1) : spread_s == "repeat" ? Int32(2) :
             Int32(0)

    rows = which === :fill ? child.fill_rgba : child.stroke_rgba
    uv = Vector{Vec2f}(undef, n)
    focus = (0f0, 0f0)
    if kind == "linearGradient"
        p1 = SVector(frac(_grad_attr(b, gnode, "x1", "0"), 1),
                     frac(_grad_attr(b, gnode, "y1", "0"), 2))
        p2 = SVector(frac(_grad_attr(b, gnode, "x2", obb ? "1" : "0"), 1),
                     frac(_grad_attr(b, gnode, "y2", "0"), 2))
        # unitless numbers in oBB are already fractions; percentages handled ↑
        D = p2 - p1
        dd = max(sum(abs2, D), 1e-24)
        for i in 1:n
            q = loc[i]
            u = obb ? (q - bbmin) ./ bbsize : q
            g = SVector(GTinv[1, 1] * u[1] + GTinv[1, 2] * u[2] + GTinv[1, 3],
                        GTinv[2, 1] * u[1] + GTinv[2, 2] * u[2] + GTinv[2, 3])
            traw = sum((g - p1) .* D) / dd
            uv[i] = Vec2f(traw, 0)
            c = _stop_color(stops, _spread_t(traw, spread))
            rows[i] = Vec4f(c[1], c[2], c[3], c[4] * Float32(opacity_mult))
        end
        which === :fill &&
            _attach_fill_gradient!(child, :linear, uv, focus, spread, stops,
                                   opacity_mult)
    else                                              # radialGradient
        cx = frac(_grad_attr(b, gnode, "cx", obb ? "0.5" : "0"), 1)
        cy = frac(_grad_attr(b, gnode, "cy", obb ? "0.5" : "0"), 2)
        r = frac(_grad_attr(b, gnode, "r", obb ? "0.5" : "1"), 1)
        r = max(r, 1e-12)
        # the focal point (fx, fy) defaults to the centre; browsers clamp a
        # focus outside the end circle ONTO it — same here, so the per-pixel
        # quadratic always has exactly one positive root
        fxs = _grad_attr(b, gnode, "fx", "")
        fys = _grad_attr(b, gnode, "fy", "")
        fx = isempty(fxs) ? cx : frac(fxs, 1)
        fy = isempty(fys) ? cy : frac(fys, 2)
        fu = SVector((fx - cx) / r, (fy - cy) / r)
        nf = hypot(fu[1], fu[2])
        nf > 0.999 && (fu = fu .* (0.999 / nf))
        focus = (Float32(fu[1]), Float32(fu[2]))
        for i in 1:n
            q = loc[i]
            u = obb ? (q - bbmin) ./ bbsize : q
            g = SVector(GTinv[1, 1] * u[1] + GTinv[1, 2] * u[2] + GTinv[1, 3],
                        GTinv[2, 1] * u[1] + GTinv[2, 2] * u[2] + GTinv[2, 3])
            p = SVector((g[1] - cx) / r, (g[2] - cy) / r)
            uv[i] = Vec2f(p[1], p[2])
            c = _stop_color(stops, _spread_t(_radial_t(p, fu), spread))
            rows[i] = Vec4f(c[1], c[2], c[3], c[4] * Float32(opacity_mult))
        end
        which === :fill &&
            _attach_fill_gradient!(child, :radial, uv, focus, spread, stops,
                                   opacity_mult)
    end
    # the factory default follows the mid colour (new points are never added
    # to an imported child, this is just coherence for match_style!)
    mid = _stop_color(stops, 0.5)
    which === :fill ? (child.default_fill_rgba = mid) : (child.default_stroke_rgba = mid)
    return
end

# ═══════════════════════════════════════════════════════════════════════
# 7¾ · fill-rule="evenodd" — normalised to winding at import time
# ═══════════════════════════════════════════════════════════════════════
#
# The fill computes NONZERO winding coverage. For subpaths that do not
# self-intersect (icon sets, fonts, Inkscape output — the real-world class),
# evenodd is EQUIVALENT to nonzero once every subpath's orientation alternates
# with its nesting depth: a hole turns clockwise inside its counter-clockwise
# container. So the importer measures the nesting by parity ray casting and
# REVERSES the subpaths whose orientation disagrees — zero renderer changes,
# and the mobject that leaves the importer is a plain winding fill every
# animation already understands. The one case parity cannot express is a
# subpath that crosses ITSELF (a one-stroke star); that residue is left as it is.

"Signed area (shoelace) of a closed 2D polyline."
function _poly_signed_area(poly::Vector{SVector{2,Float64}})
    a = 0.0
    n = length(poly)
    for i in 1:n
        p = poly[i]
        q = poly[mod1(i + 1, n)]
        a += p[1] * q[2] - q[1] * p[2]
    end
    return a / 2
end

"Even-odd ray casting (+x ray): is `pt` inside the closed polyline?"
function _point_in_poly(poly::Vector{SVector{2,Float64}}, pt::SVector{2,Float64})
    inside = false
    n = length(poly)
    for i in 1:n
        p = poly[i]
        q = poly[mod1(i + 1, n)]
        ((p[2] > pt[2]) != (q[2] > pt[2])) || continue
        x = p[1] + (pt[2] - p[2]) / (q[2] - p[2]) * (q[1] - p[1])
        x > pt[1] && (inside = !inside)
    end
    return inside
end

"""
Reverse the subpaths of `m` so orientation alternates with nesting depth —
the winding equivalent of evenodd for non-self-intersecting subpaths. Works
IN PLACE on points and style rows (the pairing survives, so it is safe both
before and after gradients touch the rows), re-pins the jump handle after
each reversed subpath, and verifies the subpath structure came out intact —
on any surprise it restores everything and returns false (caller notes).
"""
function _normalize_evenodd!(m::VMobject)
    has_points(m) || return true
    ends = get_subpath_end_indices(m)
    k = length(ends)
    k < 2 && return true       # one subpath: nonzero == evenodd without self-crossing
    starts = [1; ends[1:end-1] .+ 2]

    # dense polyline per subpath (t = 0, ¼, ½, ¾ of every curve) for the
    # parity tests AND the orientation measure — both on the same geometry
    polys = Vector{Vector{SVector{2,Float64}}}(undef, k)
    for (idx, (s, e)) in enumerate(zip(starts, ends))
        poly = SVector{2,Float64}[]
        for i in s:2:e-2
            a0, h, a1 = m.points[i], m.points[i+1], m.points[i+2]
            for t in (0.0, 0.25, 0.5, 0.75)
                w0 = (1 - t)^2
                w1 = 2t * (1 - t)
                w2 = t^2
                push!(poly, SVector(w0 * a0[1] + w1 * h[1] + w2 * a1[1],
                                    w0 * a0[2] + w1 * h[2] + w2 * a1[2]))
            end
        end
        polys[idx] = poly
    end
    areas = [_poly_signed_area(p) for p in polys]

    # nesting depth: i is inside j when a majority of three probe points of i
    # pass j's parity test (three, because a probe can graze j's boundary)
    depths = zeros(Int, k)
    for i in 1:k
        np = length(polys[i])
        np == 0 && continue
        probes = unique([1, max(1, np ÷ 3), max(1, (2np) ÷ 3)])
        for j in 1:k
            (i == j || length(polys[j]) < 3) && continue
            votes = count(idx -> _point_in_poly(polys[j], polys[i][idx]), probes)
            2votes > length(probes) && (depths[i] += 1)
        end
    end

    # reference sign: the largest subpath at depth 0 keeps its orientation
    outer = findall(iszero, depths)
    isempty(outer) && (outer = collect(1:k))
    σ0 = sign(areas[outer[argmax([abs(areas[o]) for o in outer])]])
    σ0 == 0 && return true                       # everything degenerate: nothing to do

    saved = nothing
    for i in 1:k
        areas[i] == 0 && continue
        want = iseven(depths[i]) ? σ0 : -σ0
        sign(areas[i]) == want && continue
        if saved === nothing
            saved = (copy(m.points), copy(m.fill_rgba), copy(m.stroke_rgba),
                     copy(m.stroke_width))
        end
        s, e = starts[i], ends[i]
        reverse!(m.points, s, e)
        reverse!(m.fill_rgba, s, e)
        reverse!(m.stroke_rgba, s, e)
        reverse!(m.stroke_width, s, e)
        e < length(m.points) && (m.points[e+1] = m.points[e])   # re-pin the jump
    end
    saved === nothing && return true
    m.subpath_end_indices = nothing
    if get_subpath_end_indices(m) == ends
        return true
    end
    # a reversal created or destroyed a pinned-handle cut (a handle sitting
    # bit-exactly on its FOLLOWING anchor becomes a cut when flipped) —
    # restore, report, render as before
    m.points .= saved[1]
    m.fill_rgba .= saved[2]
    m.stroke_rgba .= saved[3]
    m.stroke_width .= saved[4]
    m.subpath_end_indices = nothing
    return false
end

# ═══════════════════════════════════════════════════════════════════════
# 8 · style application per graphic element
# ═══════════════════════════════════════════════════════════════════════

function _apply_style!(b::_SVGBuild, child::VMobject, node::_XMLNode,
                       computed::Dict{String,String}, M::SMatrix{3,3,Float64,9},
                       total_opacity::Float64)
    fill_op = clamp(something(_flt(get(computed, "fill-opacity", "1")), 1.0), 0, 1)
    stroke_op = clamp(something(_flt(get(computed, "stroke-opacity", "1")), 1.0), 0, 1)
    sw = something(_flt(get(computed, "stroke-width", "1")), 1.0)

    fill = _svg_paint(b, get(computed, "fill", "black"), computed)
    # evenodd → winding BEFORE any gradient bakes its uv onto the points
    if fill !== :none && get(computed, "fill-rule", "nonzero") == "evenodd"
        _normalize_evenodd!(child) || _note!(b, "fill-rule:evenodd")
    end
    if fill === :none
        set_fill!(child; opacity = 0)
    elseif fill[1] == :rgb
        set_fill!(child; color = Vec4f(fill[2][1], fill[2][2], fill[2][3], 1),
                  opacity = fill_op * total_opacity * fill[3])
    elseif fill[1] == :url && haskey(b.byid, fill[2])
        _apply_gradient!(b, child, b.byid[fill[2]], M, :fill, fill_op * total_opacity)
    else
        _note!(b, "paint-ref:#$(fill[2])")
        set_fill!(child; color = Vec4f(0, 0, 0, 1), opacity = fill_op * total_opacity)
    end

    # stroke-linejoin: three of SVG's four map straight onto
    # the shader's codes; `round` has NO destination — the join is computed in
    # a stroke shader ported from manimlib, which has no round join — so it
    # keeps warning instead of quietly becoming something else.
    # Only when the document SAYS so. SVG's initial value is `miter`, but
    # honouring that default would retag every path ever imported from :auto
    # to :miter and change how scenes that asked for nothing render. An absent
    # attribute is not a request, so the engine's own default stands.
    lj = get(computed, "stroke-linejoin", "")
    if lj in ("miter", "bevel")
        set_joint_type!(child, Symbol(lj); recurse = false)
    elseif !isempty(lj)          # round, arcs, miter-clip: no destination here
        _note!(b, "stroke-linejoin:$lj")
    end

    stroke = _svg_paint(b, get(computed, "stroke", "none"), computed)
    if stroke === :none || sw <= 0
        set_stroke!(child; opacity = 0, width = 0)
    elseif stroke[1] == :rgb
        set_stroke!(child; color = Vec4f(stroke[2][1], stroke[2][2], stroke[2][3], 1),
                    opacity = stroke_op * total_opacity * stroke[3], width = sw)
    elseif stroke[1] == :url && haskey(b.byid, stroke[2])
        set_stroke!(child; width = sw)
        _apply_gradient!(b, child, b.byid[stroke[2]], M, :stroke,
                         stroke_op * total_opacity)
    else
        _note!(b, "paint-ref:#$(stroke[2])")
        set_stroke!(child; opacity = 0, width = 0)
    end
    return child
end

# ═══════════════════════════════════════════════════════════════════════
# 9 · clipPath — parsed into invisible "_clip" children (clip_layers consumes them)
# ═══════════════════════════════════════════════════════════════════════

"clip-path value → its id, or nothing (collecting the unparseable)."
function _clip_id(b::_SVGBuild, own::Dict{String,String})
    cp = get(own, "clip-path", "")
    isempty(cp) && return nothing
    m = match(r"url\(\s*['\"]?#([^'\")\s]+)", cp)
    m === nothing && (_note!(b, "clip-path:$cp"); return nothing)
    return String(m[1])
end

function _attach_clip!(b::_SVGBuild, child::VMobject, id::String,
                       M::SMatrix{3,3,Float64,9})
    haskey(b.byid, id) || (_note!(b, "clip-path:#$id"); return child)
    cnode = b.byid[id]
    _attr(cnode, "clipPathUnits", "userSpaceOnUse") == "userSpaceOnUse" ||
        _note!(b, "clipPathUnits:objectBoundingBox")

    # the clip's shapes are built in the SAME user space as the element, then
    # made invisible: they ride along with every transform, cost nothing to
    # draw flat, and clip_layers() finds them by key.
    shapes = VMobject[]
    old_sink = b.sink
    b.sink = shapes
    ctx = _Ctx(M, Dict{String,String}("fill" => "white"), 1.0)
    for c in cnode.children
        c isa _XMLNode && _walk!(b, c, ctx)
    end
    b.sink = old_sink
    for s in shapes
        set_fill!(s; opacity = 0)
        set_stroke!(s; opacity = 0, width = 0)
        set_key!(s, "_clip")
        add_key!(s, "_clipref:$id")
        add!(child, s)
    end
    isempty(shapes) || add_key!(child, "_clipped:$id")
    return child
end

"""
    clip_layers(svg) → Vector{Layer}

The SVG as compositor layers with its `clipPath`s as REAL per-pixel masks
— what Manim rasterizes away, here it is exact. Children without a clip
share painter's-order layers; every clipped child gets its own layer, because
two elements can reference the same clipPath from different transforms. The
mask shapes are COPIES frozen at call time (a static clip); re-call after
moving things if the clip must follow.

    comp = Composition(clip_layers(svg)...; background=(0,0,0,1))
    use_composition!(scene, comp)
"""
function clip_layers(svg::VMobject)
    layers = Layer[]
    run = Mobject[]
    for child in svg.submobjects
        clips = [s for s in (child isa VMobject ? child.submobjects : Mobject[])
                 if s isa VMobject && has_key(s, "_clip")]
        if isempty(clips)
            push!(run, child)
            continue
        end
        isempty(run) || (push!(layers, Layer(run...)); run = Mobject[])
        mask_shapes = VMobject[]
        for s in clips
            c = copy(s)
            set_fill!(c; color = Vec4f(1, 1, 1, 1), opacity = 1.0)
            set_stroke!(c; opacity = 0, width = 0)
            push!(mask_shapes, c)
        end
        push!(layers, Layer(child; mask = Mask(mask_shapes...)))
    end
    isempty(run) || push!(layers, Layer(run...))
    return layers
end

# ═══════════════════════════════════════════════════════════════════════
# 10 · <text> — through OUR font pipeline, not "text ignored"
# ═══════════════════════════════════════════════════════════════════════

function _collect_text(b::_SVGBuild, node::_XMLNode)
    io = IOBuffer()
    for c in node.children
        if c isa String
            print(io, c)
        elseif c isa _XMLNode && _local_name(c.name) == "tspan"
            (_attr(c, "x") === nothing && _attr(c, "y") === nothing &&
             _attr(c, "dx") === nothing && _attr(c, "dy") === nothing) ||
                _note!(b, "tspan-positioning")
            print(io, _collect_text(b, c))
        end
    end
    return String(take!(io))
end

function _text_element!(b::_SVGBuild, node::_XMLNode,
                        computed::Dict{String,String}, M::SMatrix{3,3,Float64,9},
                        total_opacity::Float64)
    str = String(strip(replace(_collect_text(b, node), r"\s+" => " ")))
    isempty(str) && return
    fsize = something(_flt(get(computed, "font-size", "16")), 16.0)
    fam = String(strip(first(split(get(computed, "font-family", "DejaVu Sans"), ',')),
                       ['\'', '"', ' ']))
    tm = try
        TextMobject(str; font = fam, size = fsize, center = false)
    catch err
        # only the font-not-found ArgumentError falls back — anything else is
        # a real bug and must SURFACE, not vanish into an empty drawing
        (err isa ArgumentError && fam != "DejaVu Sans") || rethrow()
        _note!(b, "font:$fam")
        TextMobject(str; font = "DejaVu Sans", size = fsize, center = false)
    end
    # start is EXACT (the pen begins at local x=0); middle/end anchor the
    # outline bbox — the spec anchors the ADVANCE, so they differ by the side
    # bearings (~5% of an em). Manim ignores <text> altogether.
    anchor = get(computed, "text-anchor", "start")
    xl, xr = Float64(get_left(tm)[1]), Float64(get_right(tm)[1])
    dx = anchor == "middle" ? -(xl + xr) / 2 : anchor == "end" ? -xr : 0.0
    x = something(_flt(_attr(node, "x")), 0.0)
    y = something(_flt(_attr(node, "y")), 0.0)
    # our glyphs live y-UP; the document runs y-down; the root context already
    # flips once. Composing a LOCAL diag(1,−1) under the baseline translation
    # hands the glyphs to the document exactly once flipped — upright on screen.
    T = M * _affine(1, 0, 0, -1, x, y) * _translation(dx, 0.0)
    f = p -> Point3f(T[1, 1] * p[1] + T[1, 2] * p[2] + T[1, 3],
                     T[2, 1] * p[1] + T[2, 2] * p[2] + T[2, 3], 0)
    for g in get_family(tm)
        g isa VMobject && has_points(g) || continue
        apply_points_function!(f, g; about_point = nothing, about_edge = nothing)
    end
    fill = _svg_paint(b, get(computed, "fill", "black"), computed)
    fill_op = clamp(something(_flt(get(computed, "fill-opacity", "1")), 1.0), 0, 1)
    if fill === :none
        set_fill!(tm; opacity = 0)
    elseif fill[1] == :rgb
        set_fill!(tm; color = Vec4f(fill[2][1], fill[2][2], fill[2][3], 1),
                  opacity = fill_op * total_opacity * fill[3])
    end                                               # gradient text: not yet
    id = _attr(node, "id")
    id === nothing || set_key!(tm, id)
    push!(b.sink, tm)
    return
end

# ═══════════════════════════════════════════════════════════════════════
# 11 · the walker
# ═══════════════════════════════════════════════════════════════════════

# Editor/metadata namespaces: ignored in silence — the single warning is for
# things that would CHANGE the picture.
const _SILENT_PREFIXES = ("sodipodi", "inkscape", "rdf", "cc", "dc", "xmlns", "xml")
const _SKIP_ELEMENTS = ("title", "desc", "metadata", "defs", "style", "namedview",
                        "linearGradient", "radialGradient", "clipPath", "symbol",
                        "marker", "foreignObject")
const _WARN_SKIP_ELEMENTS = ("pattern", "filter", "mask", "script", "image")
const _GRAPHIC_ELEMENTS = ("path", "rect", "circle", "ellipse", "line",
                           "polyline", "polygon")
const _SVG_TAGS = Dict("path" => :SVGPath, "rect" => :SVGRect,
                       "circle" => :SVGCircle, "ellipse" => :SVGEllipse,
                       "line" => :SVGLine, "polyline" => :SVGPolyline,
                       "polygon" => :SVGPolygon)

function _walk!(b::_SVGBuild, node::_XMLNode, ctx::_Ctx)
    pfx = _prefix(node.name)
    (pfx != "" && pfx != "svg") && return             # editor namespaces
    ln = _local_name(node.name)
    ln in _SKIP_ELEMENTS && return
    ln in _WARN_SKIP_ELEMENTS && (_note!(b, "element:$ln"); return)

    own = _own_style(b, node)
    get(own, "display", "") == "none" && return
    computed = _computed_style(ctx.style, own)
    get(computed, "visibility", "visible") in ("hidden", "collapse") &&
        ln in (_GRAPHIC_ELEMENTS..., "text") && return
    M = ctx.mat * _parse_transform(b, _attr(node, "transform"))
    opacity = ctx.opacity * _opacity_of(own)

    # a clip-path on a container freezes (id, matrix) HERE and flows down;
    # spec-nested clips would intersect — one Mask draws a union, so the
    # inner one wins and the nesting is reported
    cid = _clip_id(b, own)
    clip_down = cid !== nothing ? (ctx.clip !== nothing && _note!(b, "nested-clip");
                                   (cid, M)) : ctx.clip

    if ln == "g" || ln == "a" || ln == "svg"
        if ln == "svg"                                # nested viewport: translate
            M = M * _translation(something(_flt(_attr(node, "x")), 0.0),
                                 something(_flt(_attr(node, "y")), 0.0))
        end
        ctx2 = _Ctx(M, _inheritable(computed), opacity, clip_down)
        for c in node.children
            c isa _XMLNode && _walk!(b, c, ctx2)
        end
    elseif ln == "switch"
        _note!(b, "element:switch")
        ctx2 = _Ctx(M, _inheritable(computed), opacity, clip_down)
        for c in node.children                        # first candidate only
            if c isa _XMLNode
                _walk!(b, c, ctx2)
                break
            end
        end
    elseif ln == "use"
        href = something(_attr(node, "href"), "")
        startswith(href, "#") || (_note!(b, "use:$href"); return)
        id = href[2:end]
        haskey(b.byid, id) || (_note!(b, "use:#$id"); return)
        id in b.use_stack && (_note!(b, "use-cycle:#$id"); return)
        length(b.use_stack) >= 20 && (_note!(b, "use-depth"); return)
        M2 = M * _translation(something(_flt(_attr(node, "x")), 0.0),
                              something(_flt(_attr(node, "y")), 0.0))
        push!(b.use_stack, id)
        target = b.byid[id]
        # the shadow tree: the use's computed style becomes the target's
        # inherited style; a <symbol> instantiates like a <g> (spec)
        ctx2 = _Ctx(M2, _inheritable(computed), opacity, clip_down)
        if _local_name(target.name) == "symbol"
            for c in target.children
                c isa _XMLNode && _walk!(b, c, ctx2)
            end
        else
            _walk!(b, target, ctx2)
        end
        pop!(b.use_stack)
    elseif ln in _GRAPHIC_ELEMENTS
        child = vmob(_SVG_TAGS[ln])
        _geometry!(b, ln, node, child, _make_trans(M))
        _drop_point_subpaths!(child)
        has_points(child) || return
        _apply_style!(b, child, node, computed, M, opacity)   # AFTER the points
        ln == "line" && set_fill!(child; opacity = 0)          # lines have no area
        id = _attr(node, "id")
        id === nothing || set_key!(child, id)
        clip_down === nothing || _attach_clip!(b, child, clip_down...)
        push!(b.sink, child)
    elseif ln == "text"
        _text_element!(b, node, computed, M, opacity)
    else
        _note!(b, "element:$ln")
    end
    return
end

# ═══════════════════════════════════════════════════════════════════════
# 12 · SVGMobject
# ═══════════════════════════════════════════════════════════════════════

"""
    SVGMobject(path_or_string; height=2.0, width=nothing, color=nothing,
               fill_color, fill_opacity, stroke_color, stroke_opacity,
               stroke_width, z_index, key)

A whole SVG document as a VMobject: one FLAT child per graphic element (like
manimlib), each carrying the file's `id` as its key — `svg["wheel"]` addresses
by id, `svg[3]` by position, and Transform aligns child-with-child. `height`
fits the result (aspect preserved); pass `width` to fit by width instead.
`color=` repaints every child, keeping the file's opacities. The style
keywords every constructor shares are applied to the whole family after the
import, as ManimGL's `set_style` is (`svg_mobject.py:55-110`): `stroke_width
= 7` draws a 7 where the file drew nothing, `fill_opacity = 0.25` fades every
shape, and a keyword the constructor does not know is an error.

Covers: the full path grammar (M L H V C S Q T A Z + implicit repetition),
rect/circle/ellipse/line/polyline/polygon (rounded rects included), nested
groups with the spec's transform and style cascade (presentation attrs <
`<style>` CSS < inline style), defs/use/symbol shadow trees, viewBox,
linear and radial gradients evaluated per style row, `<text>` through the
font pipeline, and `clipPath` via [`clip_layers`](@ref). Anything it does not
understand is reported in ONE warning — never a throw (the Inkscape test).
"""
const SVGMobject = VMobject{:SVGMobject}

function (::Type{SVGMobject})(source::AbstractString; height = 2.0,
                              width = nothing, color = nothing,
                              fill_color = nothing, fill_opacity = nothing,
                              stroke_color = nothing, stroke_opacity = nothing,
                              stroke_width = nothing, z_index = nothing,
                              key = nothing, kw...)
    isempty(kw) || _unknown_keyword(:SVGMobject, kw)
    src, name = if occursin('<', source)              # a filename cannot hold '<'
        String(source), "«inline SVG»"
    else
        isfile(source) || throw(ArgumentError(
            "SVGMobject: «$source» is neither an .svg file nor an SVG string"))
        read(source, String), basename(source)
    end
    root = _xml_parse(src)
    svg_i = findfirst(c -> c isa _XMLNode && _local_name(c.name) == "svg", root.children)
    svgnode = svg_i === nothing ? root : root.children[svg_i]::_XMLNode
    svg_i === nothing && !isempty(root.children) && @warn(
        "SVGMobject: no <svg> root in $name — parsing the fragment as-is")

    vb = let v = _attr(svgnode, "viewBox")
        nums = v === nothing ? Float64[] : _floats(v)
        if length(nums) == 4
            (nums[1], nums[2], max(nums[3], 1e-12), max(nums[4], 1e-12))
        else
            w = something(_flt(_attr(svgnode, "width")), 100.0)
            h = something(_flt(_attr(svgnode, "height")), 100.0)
            (0.0, 0.0, w, h)
        end
    end
    b = _SVGBuild(Dict{String,_XMLNode}(), _CSSRule[], vb, VMobject[],
                  String[], String[], name)
    _index!(b, svgnode)
    sort!(b.css; by = r -> (r.specificity, r.order))

    # THE flip — the only one in the whole importer.
    # The root's own presentation attributes inherit into the tree (spec:
    # `<svg fill="none">` is real and common in icon sets).
    root_style = _inheritable(_computed_style(Dict{String,String}(),
                                              _own_style(b, svgnode)))
    ctx0 = _Ctx(_affine(1, 0, 0, -1, 0, 0) *
                _parse_transform(b, _attr(svgnode, "transform")),
                root_style, 1.0)
    for c in svgnode.children
        c isa _XMLNode && _walk!(b, c, ctx0)
    end
    isempty(b.sink) && throw(ArgumentError(
        "SVGMobject: $name produced no geometry — is the drawing empty?"))

    m = vmob(:SVGMobject)
    add!(m, b.sink...)

    # fit: content bbox → requested size; stroke widths scale WITH the
    # geometry (the ribbon stays proportional to the drawing, then behaves
    # like any Manim stroke: later scale! does not touch it)
    w0, h0 = get_width(m), get_height(m)
    s = if width !== nothing && w0 > 1e-9
        Float64(width) / w0
    elseif h0 > 1e-9
        Float64(height) / h0
    elseif w0 > 1e-9                                  # flat drawing: fit width
        Float64(something(width, height)) / w0
    else
        1.0
    end
    scale!(m, s)
    move_to!(m, ORIGIN)
    for child in get_family(m)
        child isa VMobject || continue
        child.stroke_width .*= 100s                    # user units → stroke units
        child.default_stroke_width *= 100s
    end
    color === nothing || set_color!(m; color)
    # The shared style keywords, over the family and AFTER the
    # ×100 of the widths and after `color` — a width given here is in stroke
    # units like any other mobject's, and a fill colour wins over `color`
    (fill_color !== nothing || fill_opacity !== nothing || stroke_color !== nothing ||
     stroke_opacity !== nothing || stroke_width !== nothing) &&
        set_style!(m; fill_color, fill_opacity, stroke_color, stroke_opacity, stroke_width)
    z_index === nothing || set_z_index!(m, z_index)
    key === nothing || set_key!(m, key)

    isempty(b.unknowns) || @warn(
        "SVGMobject: $name uses features outside the importer — ignored: " *
        join(sort(b.unknowns), ", "))
    return m
end
