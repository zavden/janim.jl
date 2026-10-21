# text/text.jl — text and math as VMobjects.
#
# The thesis: math WITHOUT LaTeX. `Tex("x^2")` uses MathTeXEngine (0.2 ms
# per formula when warm) → glyph positions → FreeType outlines →
# QUADRATIC béziers in our 2n+1 layout. Every glyph is a set of subpaths of
# the SAME VMobject: the holes of an 'e' or an '8' come free from winding
# and a Transform between formulas works with align_points as is.
#
# The three routes:
#   via=:math   (default) — MathTeXEngine, math subset, milliseconds
#   via=:latex  — real latex + dvisvgm → SVG → VMobject (needs a system latex;
#                 covers environments, \newcommand, EVERYTHING)
#   via=:typst  — Typst_jll → SVG → VMobject (TYPST syntax, not LaTeX)
#
# Fonts: OTF/CFF brings CUBIC outlines → approximated with 2 quadratics per
# cubic (the same technique ManimGL uses for SVG); TrueType is already
# natively quadratic and goes straight in.

using MathTeXEngine: MathTeXEngine, generate_tex_elements, TeXChar
using FreeTypeAbstraction: FTFont, findfont
using FreeType
using SHA: sha256
import Typst_jll

# (`_cubic_to_two_quadratics` lives in core/paths.jl: the SVG importer
# shares it, and core files are included before this one.)

# ── FreeType outline → subpaths ────────────────────────────────────────

"""
Walk the glyph outline (TrueType/CFF conventions: tag&1 = on-curve; off-curve
with tag&2 = cubic control, without it = conic control with implicit anchors
at the midpoints) and add it to `m` through `trans(x_em, y_em)`.
"""
function _add_glyph!(m::VMobject, font::FTFont, glyph_id::Integer, trans::F) where {F}
    face = font.ft_ptr
    err = FT_Load_Glyph(face, UInt32(glyph_id), FT_LOAD_NO_SCALE)
    err == 0 || throw(ArgumentError("FreeType cannot load glyph $glyph_id (err $err)"))
    rec = unsafe_load(face)
    g = unsafe_load(rec.glyph)
    o = g.outline
    o.n_contours == 0 && return m                     # a space
    upem = Float64(rec.units_per_EM)
    pts = unsafe_wrap(Array, o.points, o.n_points)
    tags = unsafe_wrap(Array, o.tags, o.n_points)
    ends = unsafe_wrap(Array, o.contours, o.n_contours)

    first_i = 1
    for c in 1:o.n_contours
        last_i = Int(ends[c]) + 1
        n = last_i - first_i + 1
        pnt(k) = trans(pts[first_i-1+mod1(k, n)].x / upem,
                       pts[first_i-1+mod1(k, n)].y / upem)
        tg(k) = Int(tags[first_i-1+mod1(k, n)]) & 3

        k0 = findfirst(k -> tg(k) & 1 == 1, 1:n)
        start = k0 === nothing ? (pnt(1) + pnt(2)) / 2 : pnt(k0)
        k0 = something(k0, 0)                          # all-conic: virtual start
        start_new_path!(m, start)

        k = k0 + 1
        done = 0
        while done < n
            t = tg(k)
            if t & 1 == 1                              # anchor → line
                add_line_to!(m, pnt(k))
                k += 1; done += 1
            elseif t == 0                              # conic control (native quadratic!)
                ctrl = pnt(k)
                if tg(k + 1) & 1 == 1
                    add_quadratic_bezier_to!(m, ctrl, pnt(k + 1))
                    k += 2; done += 2
                else                                   # implicit anchor at the midpoint
                    add_quadratic_bezier_to!(m, ctrl, (ctrl + pnt(k + 1)) / 2)
                    k += 1; done += 1
                end
            else                                       # t == 2: a pair of cubic controls
                a0 = m.points[end]
                h1, mid, h2 = _cubic_to_two_quadratics(a0, pnt(k), pnt(k + 1), pnt(k + 2))
                add_quadratic_bezier_to!(m, h1, mid)
                add_quadratic_bezier_to!(m, h2, pnt(k + 2))
                k += 3; done += 3
            end
        end
        m.points[end] == start || add_line_to!(m, start)   # close the contour
        first_i = last_i + 1
    end
    return m
end

"A rectangle (the rules of \\frac and friends) as a closed subpath."
function _add_rect!(m::VMobject, x0, y0, x1, y1, trans::F) where {F}
    start_new_path!(m, trans(x0, y0))
    add_line_to!(m, trans(x1, y0))
    add_line_to!(m, trans(x1, y1))
    add_line_to!(m, trans(x0, y1))
    add_line_to!(m, trans(x0, y0))
    return m
end

# ── Tex: the three routes ──────────────────────────────────────────────

# ── session default, disk cache, calibration ───────────────────────────

const TEX_VIA = Ref{Symbol}(:math)

"""
    config_tex!(; via)

Set the default route [`Tex`](@ref) takes for the rest of the session:
`:math`, `:latex`, `:typst` or `:auto`.

```julia
config_tex!(via = :latex)          # this session compiles with real LaTeX
Tex(raw"x^2"; via = :math)         # …except here
```

A per-call `via` always wins. This is a module `Ref` and NOT a persistent
config file: it is explicit, it is visible, it dies with the session, and there
is nothing to un-set on a machine where someone once changed it. Anything that
must survive belongs in the scene's own source.

`:auto` tries `:math` and falls back where MathTeXEngine will not follow,
warning once per session on purpose.
"""
function config_tex!(; via::Symbol)
    via in (:math, :latex, :typst, :auto) || throw(ArgumentError(
        "config_tex!(via = :$via): use :math, :latex, :typst or :auto"))
    TEX_VIA[] = via
    return via
end

# The disk cache stores the SVG TEXT, never the VMobject: parsing is cheap
# and text survives every engine refactor. Key = via + engine
# version + the FULL compiled source, so template edits invalidate honestly.
# A RAM memo on top makes the second call in a session allocation-cheap.
const _TEX_SVG_MEMO = Dict{String,String}()
const _LATEX_VERSION = Ref{String}("")

_tex_cache_dir() = get(ENV, "JANIM_TEX_CACHE",
                       joinpath(get(ENV, "XDG_CACHE_HOME",
                                    joinpath(homedir(), ".cache")), "janim", "tex"))

function _latex_version()
    isempty(_LATEX_VERSION[]) || return _LATEX_VERSION[]
    v(cmd) = try
        String(first(split(read(cmd, String), '\n')))
    catch
        "?"
    end
    _LATEX_VERSION[] = v(`latex --version`) * " + " * v(`dvisvgm --version`)
end
_typst_version() = string(pkgversion(Typst_jll))

"memo → disk → compile; the write is atomic (tmp + rename). do-block form."
function _cached_svg(compile::F, via::Symbol, version::String, source::String) where {F}
    key = bytes2hex(sha256(codeunits(string(via, '\0', version, '\0', source))))
    svg = get(_TEX_SVG_MEMO, key, nothing)
    svg === nothing || return svg
    path = joinpath(_tex_cache_dir(), key[1:40] * ".svg")
    svg = isfile(path) ? _read_cache_file(path, via) : nothing
    # A file cut short (a full disk, an interrupted copy of the cache) would
    # parse without a word into FEWER glyphs: `\int_0^1 x\,dx` coming back
    # with 3 children of 6, 0.616 wide instead of 1.616. Every document
    # dvisvgm and typst write whole ends with the root's closing tag, so
    # anything else is compiled again and overwritten.
    if svg === nothing || !endswith(rstrip(svg), "</svg>")
        svg = compile(source)
        _write_cache_file(path, svg, via)
    end
    return _TEX_SVG_MEMO[key] = svg
end

# An I/O error on the cache names the FILE: a bare SystemError from deep
# inside `Tex` would not say which file of the cache it was about.
_cache_owner(via::Symbol) = via === :typst ? "Typst" : "LaTeX"

function _read_cache_file(path::String, via::Symbol)
    try
        return read(path, String)
    catch err
        err isa InterruptException && rethrow()
        throw(ArgumentError(
            "the $(_cache_owner(via)) cache file $path could not be read: " *
            sprint(showerror, err)))
    end
end

function _write_cache_file(path::String, svg::String, via::Symbol)
    tmp = path * ".tmp-$(getpid())"
    try
        mkpath(dirname(path))
        write(tmp, svg)
        mv(tmp, path; force = true)
    catch err
        err isa InterruptException && rethrow()
        try
            rm(tmp; force = true)
        catch
        end
        throw(ArgumentError(
            "the $(_cache_owner(via)) cache file $path could not be written: " *
            sprint(showerror, err)))
    end
    return path
end

# Calibration: the parity contract is "same formula → same
# x-height and same baseline in every route". :math is the metric REFERENCE
# (default route, real font metrics); :latex/:typst measure a probe "x" once
# per engine (the compile rides the cache) and derive the factor that lands
# their x-height ON :math's.
const _TEX_CAL = Dict{Symbol,Float64}()
const _XH_MATH = Ref(0.0)

function _xheight_math()
    _XH_MATH[] > 0 && return _XH_MATH[]
    probe = vmob(:Tex)
    g() = vmob(:Glyph; fill_opacity = 1.0)
    _tex_math!(probe, g, "x", 1.0)
    return _XH_MATH[] = Float64(get_height(probe))
end

function _tex_cal(via::Symbol)
    get!(_TEX_CAL, via) do
        probe = vmob(:Tex)
        g() = vmob(:Glyph; fill_opacity = 1.0)
        _tex_svg!(probe, g, via === :latex ? _svg_latex("x") : _svg_typst("x"), 1.0)
        via === :typst && _strip_typst_sentinel!(probe, 1.0)
        _xheight_math() / Float64(get_height(probe))
    end
end

# ═══════════════════════════════════════════════════════════════════════
# Text is born at ManimGL's size
# ═══════════════════════════════════════════════════════════════════════
#
# At `size = 1` every route of Janim draws text about 2.07–2.20 times the size
# ManimGL gives it at its default `font_size = 48`. These are the ratios,
# MEASURED against ManimGL on strings whose glyphs the two engines agree
# about:
#
#   :latex / LMathTex  2.0700   F=ma 3.45328 / 1.66825, exact to five digits
#   :math              2.0731   a lone glyph; SPACING is another story, below
#   :typst             2.0777   idem
#   LTex (text mode)   2.1839   Hola 2.09674 / 0.96010
#   TextMobject        2.2017   a PURE scale: H, Hola and x agree to four
#                               decimals with DejaVu Sans on both sides
#
# What the number does NOT fix is `:math`'s spacing: MathTeXEngine sets
# relations tighter than LaTeX, so a formula with operators lands anywhere
# from 1.86 to 3.08 of GL's width whatever constant is in front of it. A
# formula that has to line up with a ManimGL render should take `via = :latex`;
# the difference is documented rather than papered over.
const _GL_SIZE = (math = 2.0731, latex = 2.0700, typst = 2.0777,
                  ltex = 2.1839, text = 2.2017)

"""
    _text_size(size, font_size, k, what) → Float64

The one place `size` and `font_size` meet. `size` is Janim's own unit;
`font_size` is ManimGL's, and divides by the route's
calibration `k`. Both together is an error, because silently preferring one
is how a scene ends up half the size its author read in the source.
"""
function _text_size(size, font_size, k::Real, what)
    if size !== nothing && font_size !== nothing
        throw(ArgumentError(
            "$what takes `size` OR `font_size`, not both — they are two ways " *
            "of saying the same thing. `font_size = 48` is ManimGL's default " *
            "and the default here; `size = 1` is Janim's own unit."))
    end
    # `size` gets the same check as `font_size`: 0 would draw a text of
    # height 0.0, −1 upside down, and NaN would poison every point, all in
    # silence
    size === nothing || (isfinite(size) && size > 0) || throw(ArgumentError(
        "$what: size must be finite and positive, got $size"))
    size === nothing || return Float64(size)
    fs = font_size === nothing ? DEFAULT_FONT_SIZE : Float64(font_size)
    isfinite(fs) && fs > 0 || throw(ArgumentError(
        "$what: font_size must be finite and positive, got $fs"))
    return fs / (DEFAULT_FONT_SIZE * k)
end

# The stroke a glyph is BORN with. ManimGL's StringMobject sets
# the stroke on the whole family right after constructing
# (`string_mobject.py:71`, `stroke_width: float = 0` and
# `stroke_color = DEFAULT_MOBJECT_COLOR`), so its glyphs carry width 0 and
# opacity 1: nothing is drawn until someone asks for a width, and then it IS
# drawn. A glyph born at opacity 0 would make `set_stroke!(tex; width = 2)`
# paint nothing and `Tex(s; stroke_width = 2)` reach only the parent — the
# argument accepted and thrown away. The constructor's three stroke keywords
# reach the glyphs; the parent still gets them too, through `kw...`.
_glyph_stroke(kw, color) = (color = get(kw, :stroke_color, color),
                            opacity = get(kw, :stroke_opacity, 1.0),
                            width = get(kw, :stroke_width, 0.0))
# The same for the FILL, and for the two keywords that are per-glyph
# attributes: GL applies the whole style to the family
# (svg_mobject.py:104-110), so `fill_color`/`fill_opacity` must reach the
# glyphs and not only the point-less parent (or `TextMobject("ab";
# fill_opacity = 0.3)` would draw at 1.0).
# `key` stays the parent's: on every glyph it would pair whole formulas in
# TransformMatchingTex.
_glyph_fill(kw, color) = (color = get(kw, :fill_color, color),
                          opacity = get(kw, :fill_opacity, 1.0))
_glyph_extra(kw) = (; (k => v for (k, v) in pairs(kw) if k === :z_index || k === :joint_type)...)

# An empty (or all-blank) formula is refused at the ENTRY, with one message
# for every route (otherwise `:math` would die inside MathTeXEngine
# (`unravel(::Space)`), and `:latex` and `:typst` would say «produced no
# geometry» after a compile).
function _assert_formula(formula::AbstractString, what::AbstractString)
    isempty(strip(formula)) && throw(ArgumentError(
        "$what: an empty formula — GL's Tex(\"\") is an empty mobject; here a " *
        "mobject with no glyphs cannot be placed or animated, so it is an error"))
    return formula
end

"""
    Tex(formula...; via=config_tex!'s default, font_size=48, color=WHITE,
        isolate=String[], t2c=nothing, center=true, kw...)

A formula as a VMobject (pure fill, no stroke — like Manim). `via=:math`
(MathTeXEngine, milliseconds) covers the math subset; beyond that subset
(environments, \\newcommand) use `via=:latex` (system latex+dvisvgm) or
`via=:typst` (Typst_jll — Typst syntax, not LaTeX). `via=:auto` tries
`:math` and falls back with one warning per session (the route that made
the bytes is never silent).

The three routes share x-height and baseline (calibrated
against `:math`; `center=false` leaves the baseline at y=0 instead of
centering). `isolate=["x^2"]` labels the glyphs of each occurrence with the
pattern as a key — `tex["x^2"]` addresses them, TransformMatchingTex pairs
them, and `t2c=Dict("x"=>RED)` paints them. Several arguments join with a
space and each becomes an isolate of its own, as in ManimGL:
`Tex("f(", "x", ")", "+h")` answers `tex["x"]`.

The routes label by different means and answer the same. Every `:math`
glyph carries its own character, so `tex["x"]` works with nothing
asked for. A LaTeX SVG carries font ids, so `:latex` uses ManimGL's mechanism
— one compile with each part wrapped in a colour, then attribution by that
colour — which means through LaTeX a glyph answers ONLY to the `isolate`
patterns and `t2c` keys given here, and asking for anything else is an error
that says so. `:typst` has neither.

They are different typesetters and count glyphs differently: `\\cdots` is ONE
glyph through `:math` and THREE through `:latex`, which is ManimGL's count.
Address by key, not by index, if you may change route.

A bare `Tex(s)` comes out the size ManimGL gives it, `font_size`
means what it means there, and `size` is Janim's own unit. Through
`:latex` that is not an approximation — one constant makes this function
ManimGL's `Tex` to five digits. Through `:math` the SIZE matches and the
SPACING does not, because MathTeXEngine sets relations tighter than LaTeX;
for a formula that has to line up with a GL render, `via = :latex`.
"""
const Tex = VMobject{:Tex}

function (::Type{Tex})(formulas::AbstractString...; via::Symbol = TEX_VIA[],
                       size = nothing, font_size = nothing, color = WHITE,
                       isolate = String[], t2c = nothing, center::Bool = true, kw...)
    isempty(formulas) && throw(ArgumentError(
        "Tex needs at least one string — Tex(raw\"x^2\")"))
    formula, patterns = _tex_join(formulas, isolate)
    _assert_formula(formula, "Tex")                     # before any route
    t2c_keys = String[String(k) for k in _t2c_keys(t2c)]
    labelled = !isempty(patterns) || !isempty(t2c_keys)
    # the calibration belongs to the ROUTE, so `:auto` resolves against
    # `:math`'s — the route it tries first. The fallback to `:latex` then
    # carries math's constant, 0.15 % away from its own: a thousandth of a
    # glyph, and the alternative is compiling the formula twice to find out.
    k = via === :latex ? _GL_SIZE.latex : via === :typst ? _GL_SIZE.typst : _GL_SIZE.math
    size = _text_size(size, font_size, k, "Tex")
    # STRUCTURE like Manim's Tex: a PARENT without points + one CHILD per
    # glyph. Each glyph fills its winding IN ISOLATION (its holes are its own
    # subpaths) — with every glyph in a single VMobject, an intermediate blob
    # of a Transform flies over its neighbours and CANCELS their winding (a
    # visible flicker). Transform also pairs glyph with glyph in reading
    # order instead of subpaths sorted by length.
    m = vmob(:Tex; kw...)
    st = _glyph_stroke(kw, color)
    fl = _glyph_fill(kw, color)
    ex = _glyph_extra(kw)
    glyph() = vmob(:Glyph; fill_color = fl.color, fill_opacity = fl.opacity,
                   stroke_color = st.color, stroke_opacity = st.opacity,
                   stroke_width = st.width, ex...)
    built = false
    if via === :auto
        # `:auto` normally decides BY BUILDING, which costs one compile. With
        # isolate or t2c the route has to be known first — only `:latex`
        # labels — so it is decided by a probe instead, and the extra 0.3 ms
        # is paid only by the formulas that ask for labels.
        if labelled
            via = _auto_probe(formula)
            via === :math || add_key!(m, "_via:$via")
        else
            via = _auto_route(m, glyph, formula, Float64(size))
            built = true
        end
    end
    if !built
        if via === :math
            _tex_math!(m, glyph, formula, Float64(size))
        elseif via === :latex
            _tex_latex_labelled!(m, glyph, formula, Float64(size) * _tex_cal(:latex),
                                 patterns, t2c_keys,
                                 (body, color) -> _latex_source(body; color))
        elseif via === :typst
            labelled && throw(ArgumentError(
                "isolate/t2c through :typst: the labels are LaTeX's — a formula " *
                "is compiled once with each part in a colour and the glyphs are " *
                "attributed by it (ManimGL's mechanism, and ManimGL has no Typst). " *
                "Use via=:latex or via=:math."))
            sz = Float64(size) * _tex_cal(:typst)
            _tex_svg!(m, glyph, _svg_typst(formula), sz)
            _strip_typst_sentinel!(m, sz)
        else
            throw(ArgumentError(
                "unknown via=:$via — use :math, :latex, :typst or :auto"))
        end
    end
    isempty(m.submobjects) && throw(ArgumentError("«$formula» produced no geometry"))
    # `:math` knows every glyph by its character, so it labels by matching runs
    # of them; `:latex` was labelled by the compile above. Same keys, so
    # `tex[…]` and TransformMatchingTex never learn which route made them.
    if via === :math
        for p in patterns
            _isolate!(m, p)
        end
        for p in t2c_keys
            p in patterns || _isolate!(m, p)
        end
        _record_char_runs!(m)          # AFTER isolate, which wins
    end
    _apply_t2c!(m, t2c)
    center && move_to!(m, ORIGIN)
    return m
end

"""
ManimGL's several-strings rule (`tex_mobject.py:52-57`): the arguments join
with a space and each one becomes an isolate of its own, so
`Tex("f(", "x", ")", "+h")` answers `tex["x"]` with no isolate list.

One argument is passed through UNTOUCHED — GL strips it, and stripping a lone
formula would change what `:math` lays out for a string nobody meant to change.
"""
function _tex_join(strings, isolate)
    patterns = _tex_selectors(isolate)
    length(strings) == 1 && return String(strings[1]), patterns
    append!(patterns, String[String(x) for x in strings])
    return String(strip(join(strings, " "))), patterns
end

"""
The (pattern → colour) pairs of a `t2c`/`t2w` block, IN ORDER.

ManimGL paints them in insertion order, so with keys that overlap
the LAST one wins: `{"x": GREEN, "x^2": RED}` leaves the x RED in ManimGL, and
the reverse leaves it GREEN (measured in both engines). A Julia `Dict` has no
order to preserve, so a `Vector` (or tuple) of pairs is the ordered form —
`t2c = ["x" => GREEN, "x^2" => RED]` — and the `Dict` form keeps working for
the ordinary case where no two keys touch the same glyph.
"""
_t2c_pairs(::Nothing) = Pair[]
_t2c_pairs(d::AbstractDict) = [k => v for (k, v) in d]
function _t2c_pairs(v::Union{AbstractVector,Tuple})
    all(p -> p isa Pair, v) || throw(ArgumentError(
        "t2c/t2w as a list must be a list of PAIRS, like [\"x\" => RED, \"y\" => BLUE] " *
        "— got $(typeof(v))"))
    return collect(v)
end
_t2c_pairs(x) = throw(ArgumentError(
    "t2c/t2w takes a Dict or an ordered list of pairs, not a $(typeof(x))"))

"The keys of a t2c block, in order — what `isolate` has to know about."
_t2c_keys(t2c) = [first(p) for p in _t2c_pairs(t2c)]

"Paint each `t2c` key over the parts the labels named — the same call on every route."
function _apply_t2c!(m::VMobject, t2c)
    t2c === nothing && return m
    for (pattern, colour) in _t2c_pairs(t2c)
        set_color!(m[String(pattern)]; color = colour)
    end
    return m
end

# :auto — never silent: one warning per session names the route that
# actually made the bytes, and the parent carries it as a "_via:…" key.
# The formulas :math rejects are LaTeX constructs (environments,
# \\newcommand), and Typst does not speak LaTeX — falling to :typst would
# feed LaTeX source to a Typst compiler. So :auto prefers :latex when texlive
# exists and only then :typst (always installed, best effort on the shared
# syntax subset).
const _AUTO_WARNED = Ref(false)

"The route `:auto` falls to when `:math` refuses, and the one warning it owes."
function _auto_fallback(formula::String)
    fallback = Sys.which("latex") !== nothing && Sys.which("dvisvgm") !== nothing ?
               :latex : :typst
    if !_AUTO_WARNED[]
        @warn "Tex via=:auto: :math cannot cover «$formula» — falling back to " *
              ":$fallback (the bytes come from :$fallback; this prints once " *
              "per session)"
        _AUTO_WARNED[] = true
    end
    return fallback
end

function _auto_route(m::VMobject, glyph::Function, formula::String, size::Float64)
    try
        _tex_math!(m, glyph, formula, size)
        return :math
    catch err
        err isa ArgumentError || rethrow()
    end
    fallback = _auto_fallback(formula)
    if fallback === :latex
        _tex_svg!(m, glyph, _svg_latex(formula), size * _tex_cal(:latex))
    else
        s = size * _tex_cal(:typst)
        _tex_svg!(m, glyph, _svg_typst(formula), s)
        _strip_typst_sentinel!(m, s)
    end
    add_key!(m, "_via:$fallback")
    return fallback
end

"""
Which route `:auto` would take, decided WITHOUT building it.

`isolate` and `t2c` have to know the route before the compile — only `:latex`
carries labels — and `_auto_route` only knows by having built. The probe is
the same parse `:math` would do, 0.2–0.4 ms, and it warns through the same
gate, so the session still hears once which route made the bytes.
"""
function _auto_probe(formula::String)
    try
        generate_tex_elements(_mathize(formula))
        return :math
    catch
        # any parse failure is beyond the :math route, the same limit _tex_math! names
    end
    return _auto_fallback(formula)
end

"""
Variables set in math ITALIC, the way every TeX engine sets them.

MathTeXEngine flattens its stream to one font and the UPRIGHT glyph for
every letter (measured: the x of `x`, of `\\sin(x)` and of `\\mathrm{x}`
all arrive as glyph 89), so no downstream layer can tell a variable from a
function name. The discrimination lives in the SOURCE, so the fix does too:
bare Latin letters are rewritten to their Mathematical Italic codepoints
(U+1D44E…, U+1D434…) BEFORE parsing — the engine then finds the italic
glyph (x → 2714) and lays it out with its own metrics. Untouched: macro
names (`\\sin` stays a macro), the argument of the upright-by-meaning
macros (`\\mathrm`, `\\text`, …), digits and operators. The pitfall the
Unicode chart hides: math-italic `h` (U+1D455) is UNASSIGNED — Planck's
ℎ (U+210E) is the italic h.
"""
const _UPRIGHT_ARG_MACROS = ("mathrm", "text", "textrm", "textbf", "textit",
                             "mathbf", "mathsf", "mathtt", "operatorname",
                             "mbox")

function _mathize(formula::AbstractString)
    out = IOBuffer()
    cs = collect(formula)
    i = 1
    italic(c) = c == 'h' ? 'ℎ' :
                'a' <= c <= 'z' ? Char(0x1D44E + (c - 'a')) :
                'A' <= c <= 'Z' ? Char(0x1D434 + (c - 'A')) : c
    while i <= length(cs)
        c = cs[i]
        if c == '\\' && i < length(cs) && isletter(cs[i+1])
            j = i + 1
            while j <= length(cs) && isletter(cs[j]); j += 1; end
            name = String(cs[i+1:j-1])
            print(out, '\\', name)
            i = j
            if name in _UPRIGHT_ARG_MACROS
                while i <= length(cs) && cs[i] == ' '; print(out, cs[i]); i += 1; end
                if i <= length(cs) && cs[i] == '{'
                    depth = 0
                    while i <= length(cs)
                        cs[i] == '{' && (depth += 1)
                        cs[i] == '}' && (depth -= 1)
                        print(out, cs[i])
                        i += 1
                        depth == 0 && break
                    end
                end
            end
        elseif isascii(c) && isletter(c)
            print(out, italic(c))
            i += 1
        else
            print(out, c)
            i += 1
        end
    end
    return String(take!(out))
end

"The user addresses glyphs in ASCII: the key of an italicized letter is the
letter the user typed, so `tex[\"x\"]`, isolate and TransformMatchingTex
keep speaking ASCII while the pixels speak italic."
_unmathize(c::Char) =
    c == 'ℎ' ? 'h' :
    Char(0x1D44E) <= c <= Char(0x1D467) ? Char('a' + (c - Char(0x1D44E))) :
    Char(0x1D434) <= c <= Char(0x1D44D) ? Char('A' + (c - Char(0x1D434))) : c

function _tex_math!(m::VMobject, glyph::Function, formula::String, size::Float64)
    els = try
        generate_tex_elements(_mathize(formula))
    catch err
        detail = first(sprint(showerror, err), 80)
        throw(ArgumentError(
            "MathTeXEngine does not cover «$formula» ($detail) — this is a " *
            "limit of the :math route (environments and \\newcommand): use Tex(f; via=:latex) " *
            "or via=:typst"))
    end
    for (el, pos, scale) in els
        trans = (x, y) -> Point3f((pos[1] + x * scale) * size,
                                  (pos[2] + y * scale) * size, 0)
        g = glyph()
        if el isa TeXChar
            # Each glyph is labelled with the character it represents,
            # so `tex["x"]` addresses out of the box and isolate matches
            # descriptor sequences over these keys (:math is the only route
            # that knows which glyph is which — SVG routes see font ids).
            set_key!(g, string(_unmathize(el.represented_char)))
            _add_glyph!(g, el.font, el.glyph_id, trans)
        elseif el isa MathTeXEngine.HLine
            # rules carry a kind key too: isolate can match a \frac pattern
            # (its bar included) and TransformMatchingTex pairs bar with bar
            set_key!(g, "_hline")
            _add_rect!(g, 0.0, -el.thickness / 2, el.width, el.thickness / 2, trans)
        elseif el isa MathTeXEngine.VLine
            set_key!(g, "_vline")
            _add_rect!(g, -el.thickness / 2, 0.0, el.thickness / 2, el.height, trans)
        end
        has_points(g) && add!(m, g)
    end
    return m
end

# ── isolate: pattern → keys on the matching glyph runs ─────────────────

"""
The pattern compiled alone gives its DESCRIPTOR sequence (characters and
rule kinds); the formula's children carry the same descriptors as their
first key. Every non-overlapping occurrence of the pattern's sequence as a
CONTIGUOUS run of children gets the pattern added as a key — no
restructuring, so no orphaned references (the become! trap) and
`tex[pattern]` addresses the union of occurrences, which is exactly what
TransformMatchingTex consumes. Matching is by glyph sequence, so a pattern
like "b" also claims the b of "b^2" when it comes first — same fragility
Manim's substring matching has; isolate the longer pattern too if it bites.
"""
function _isolate!(m::VMobject, pattern::String)
    want = _pattern_descriptors(pattern)
    have = [isempty(get_keys(c)) ? "" : get_keys(c)[1] for c in m.submobjects]
    runs = Vector{Int}[]               # one entry per OCCURRENCE
    hits = 0
    i = 1
    while i <= length(have) - length(want) + 1
        if @views have[i:i+length(want)-1] == want
            for j in i:i+length(want)-1
                add_key!(m.submobjects[j]::VMobject, pattern)
            end
            push!(runs, collect(i:i+length(want)-1))
            hits += 1
            i += length(want)          # non-overlapping, left to right
        else
            i += 1
        end
    end
    hits == 0 && throw(ArgumentError(
        "isolate: «$pattern» does not occur in this formula as a glyph run — " *
        "its glyphs $(want) were not found in $(have). Check the pattern " *
        "(it must appear literally, like Manim's substring matching)."))
    _record_key_runs!(m, pattern, runs)
    return m
end

"""
One recorded occurrence PER GLYPH for every one-character key
(the character each `:math` and `TextMobject` glyph carries). GL's
`select_parts("x")` walks the string's occurrences
(`select_unisolated_substring`), so `get_parts_by_tex(Tex("x+x"), "x")` is two
parts of one glyph — not one part of two, which is what recording only
`isolate`'s occurrences would give. A key somebody already recorded (`isolate`, a `t2c` key) is left
alone: those runs came first and they win. `m[key]`, the union, and the pixels
do not change.
"""
function _record_char_runs!(m::VMobject)
    runs = Pair{String,Vector{Vector{Int}}}[]
    for (i, c) in enumerate(m.submobjects)
        c isa VMobject || continue
        for k in get_keys(c)
            length(k) == 1 || continue
            j = findfirst(p -> first(p) == k, runs)
            j === nothing ? push!(runs, k => [[i]]) : push!(last(runs[j]), [i])
        end
    end
    for (k, rs) in runs
        _key_runs(m, k) === nothing && _record_key_runs!(m, k, rs)
    end
    return m
end

function _pattern_descriptors(pattern::String)
    els = try
        generate_tex_elements(_mathize(pattern))   # same route, same map
    catch err
        detail = first(sprint(showerror, err), 60)
        throw(ArgumentError(
            "isolate: «$pattern» is not compilable on its own ($detail) — " *
            "isolate patterns must stand alone, like Manim's double-brace splits"))
    end
    out = String[]
    for (el, _, _) in els
        push!(out, el isa TeXChar ? string(_unmathize(el.represented_char)) :
                   el isa MathTeXEngine.HLine ? "_hline" : "_vline")
    end
    isempty(out) && throw(ArgumentError("isolate: «$pattern» produces no glyphs"))
    return out
end

# ── the SVG routes (dvisvgm and typst converge here) ───────────────────

"""
dvisvgm/typst SVG → one child per graphic element, through the GENERAL SVG
importer. It handles every element they emit, including dvisvgm `<rect>`s
whatever the order of their attributes and typst's stroked bar paths. Both
are the fraction bar, so `\\frac` via :latex/:typst renders WITH it.

It hands back the LABEL of every glyph it added: the 24-bit integer
the SVG carries in that element's colour, which a labelled compile puts there
and `_apply_tex_keys!` reads. An unlabelled document paints everything black,
so the answer is all zeros and nobody looks at it.
"""
function _tex_svg!(m::VMobject, glyph::Function, svg::String, scale_factor::Float64)
    root = _xml_parse(svg)
    i = findfirst(c -> c isa _XMLNode && _local_name(c.name) == "svg", root.children)
    node = i === nothing ? root : root.children[i]::_XMLNode
    b = _SVGBuild(Dict{String,_XMLNode}(), _CSSRule[], (0.0, 0.0, 100.0, 100.0),
                  VMobject[], String[], String[], "tex-svg")
    _index!(b, node)
    sort!(b.css; by = r -> (r.specificity, r.order))
    # the tex routes scale METRICALLY (constructor's factor), never fit — and
    # the y flip lives in this root matrix, same single place as SVGMobject
    ctx0 = _Ctx(_affine(scale_factor, 0, 0, -scale_factor, 0, 0),
                Dict{String,String}(), 1.0)
    for c in node.children
        c isa _XMLNode && _walk!(b, c, ctx0)
    end
    labels = Int[]
    for child in b.sink
        # the label lives in the SVG's own colour, so it is read BEFORE
        # `glyph()` repaints the element in the Tex colour. A rule
        # drawn as a stroke carries it in the stroke instead.
        filled = any(c -> c[4] > 0, child.fill_rgba)
        rows = filled ? child.fill_rgba : child.stroke_rgba
        label = isempty(rows) ? 0 : _tex_label_of(rows[1])
        g2 = glyph()                              # the Tex colour, uniformly
        set_points!(g2, child.points)
        stroked = any(>(0), child.stroke_width) && any(c -> c[4] > 0, child.stroke_rgba)
        if stroked && !filled
            # a rule drawn as a stroke (typst's bars): keep it a stroke, in
            # the glyph colour, width converted like SVGMobject does
            set_fill!(g2; opacity = 0)
            set_stroke!(g2; opacity = 1.0,
                        width = child.stroke_width[1] * 100 * scale_factor)
        end
        if has_points(g2)
            add!(m, g2)
            push!(labels, label)
        end
    end
    return labels
end

"""
    _apply_tex_keys!(m, string, spans, labels) → m

The second half of ManimGL's mechanism: every glyph gets, as keys,
the substrings of the spans that contain it, so `tex["x^2"]` and
`TransformMatchingTex` work through `:latex` exactly as through `:math`.

A label outside the span list means the formula painted a colour of its own
(a `\\color` the user wrote): that glyph falls back to span 0, with one
warning, which is what ManimGL does (`string_mobject.py:103-111`).
"""
function _apply_tex_keys!(m::VMobject, s::AbstractString,
                          spans::Vector{UnitRange{Int}}, labels::Vector{Int})
    length(spans) <= 1 && return m
    top = length(spans) - 1
    stray = unique(L for L in labels if L > top)
    isempty(stray) || @warn("Tex: unrecognizable colour labels $(stray) — this " *
                            "formula paints a colour of its own, so those glyphs " *
                            "answer to no isolate/t2c key")
    clean = [L > top ? 0 : L for L in labels]
    for (g, ks) in zip(m.submobjects, _tex_keys_by_span(s, spans, clean)), k in ks
        add_key!(g::VMobject, k)
    end
    # Each SPAN is one occurrence, in source order — which is the
    # order ManimGL's `find_spans_by_selector` returns them in. A glyph belongs
    # to span j when its own span sits inside it, the same containment
    # `_tex_keys_by_span` uses for the keys.
    chars = collect(String(s))
    for j in 2:length(spans)
        idx = [g for g in eachindex(clean)
               if 1 <= clean[g] <= top && first(spans[clean[g]+1]) >= first(spans[j]) &&
                  last(spans[clean[g]+1]) <= last(spans[j])]
        isempty(idx) && continue
        text = String(@view chars[spans[j]])
        prev = _key_runs(m, text)
        runs = prev === nothing ? Vector{Int}[] : prev
        # A span labelled twice (`isolate` + `t2c`, `{{…}}` + `t2c`, a pattern
        # repeated) is ONE occurrence: GL's `select_parts` walks the string's
        # occurrences (string_mobject.py:514-547), the labels are how it finds
        # the glyphs, and two labels over one range are one part (not
        # `[[1], [1]]`). The LaTeX body keeps both labels (GL's does too): the
        # document, the SVG and the cache do not change.
        idx in runs || push!(runs, idx)   # the stored vector itself: re-recording is a no-op
        _record_key_runs!(m, text, runs)
    end
    return m
end

"""
    _tex_latex_labelled!(m, glyph, string, scale, isolate, t2c, source) → m

One compile with the labels in it, then the keys — the shape shared by
`Tex(via = :latex)`, `LTex` and `LMathTex`. `source(body, color)` builds the
document each of them wants (they differ only in that). With no spans it
compiles the ORIGINAL string through the ORIGINAL document, so a formula
without `isolate` or `t2c` compiles the plain document.
"""
function _tex_latex_labelled!(m::VMobject, glyph::Function, s::String,
                              scale::Float64, isolate, t2c, source::Function)
    lab = _tex_labelling(s; isolate, t2c)
    plain = length(lab.spans) == 1
    labels = _tex_svg!(m, glyph, _svg_latex_source(source(plain ? s : lab.body, !plain)),
                       scale)
    isempty(m.submobjects) && throw(ArgumentError(
        "«$s» produced no geometry — LaTeX compiled it to nothing"))
    return _apply_tex_keys!(m, s, lab.spans, labels)
end

# An environment (\begin{align*}…) is a COMPLETE math construct: wrapping it
# in $…$ would break the compile, so the template only adds dollars to bare
# formulas. Multi-line content has one baseline per line; y=0 is TeX's box
# reference then — stated, not hidden.
function _latex_source(formula::String; color::Bool = false)
    # \displaystyle: bare $…$ is TEXTSTYLE and shrinks \frac/\sum, while
    # :math (and manim, whose default template is an align* environment)
    # typeset in display — measured: the same \frac was 1.29 tall vs 2.31
    body = startswith(lstrip(formula), "\\begin{") ? formula :
           "\$\\displaystyle $formula\$"
    # `xcolor` ONLY when the body carries labels. An unlabelled document stays
    # the plain one, which keeps the disk cache (keyed on the document) and
    # `_TPL_CAL` untouched.
    pre = color ? TEX_BASE_PREAMBLE * "\n" * TEX_COLOR_PREAMBLE : TEX_BASE_PREAMBLE
    return "$TEX_DOCUMENTCLASS\n$pre\n\\begin{document}\n$body\n\\end{document}\n"
end

_svg_latex(formula::String) = _svg_latex_source(_latex_source(formula))

# The same compile, entered with a COMPLETE document instead of a bare
# formula, so a TexTemplate can hand over its own preamble. The disk cache
# already keys on the whole source (`_cached_svg`), so two templates cache
# apart and a changed preamble invalidates only its own entries.
function _svg_latex_source(source_doc::String)
    _cached_svg(:latex, _latex_version(), source_doc) do source
        latex = Sys.which("latex")
        dvisvgm = Sys.which("dvisvgm")
        (latex === nothing || dvisvgm === nothing) && throw(ArgumentError(
            "via=:latex needs `latex` and `dvisvgm` on the system — " *
            "install texlive or use via=:math / via=:typst"))
        mktempdir() do dir
            write(joinpath(dir, "f.tex"), source)
            ok = _run_with_timeout(
                pipeline(
                    Cmd(`$latex -interaction=batchmode -halt-on-error f.tex`; dir);
                    stdout = devnull,
                    stderr = devnull,
                ),
                _TEX_TIMEOUT[],
                "latex",
            )
            # `batchmode` prints nothing, so a bare ProcessFailedException
            # would be all the user gets. The log HAS the reason on the line
            # starting with "!", and with LTex/LMathTex the common miss is
            # mode confusion (x^2 in text mode, a stray $ in math mode), which
            # is worth naming instead of making them read a stack trace.
            ok || throw(ArgumentError(
                "LaTeX could not compile this:\n" *
                _latex_error(joinpath(dir, "f.log")) *
                "\nthe document it was given:\n" *
                join("  │ " .* split(rstrip(source), '\n'), "\n")))
            _dvisvgm_svg(dvisvgm, dir)
        end
    end
end

# The deadline both LaTeX tools run under, in seconds.
# `\def\a{\a}\a` sends latex into an endless expansion that batchmode never
# reports, and a bare `run` would wait for it forever.
const _TEX_TIMEOUT = Ref(120.0)

"""
    _run_with_timeout(cmd, seconds, tool) → Bool

Run `cmd` — a `Cmd` or a `pipeline`, which is why the signature
says `AbstractCmd` — and kill it at `seconds`: SIGTERM, then SIGKILL a second
later if it is still there. `true` when it succeeded, `false` when it failed
on its own (the caller has the better message for that), and an ArgumentError
naming `tool` and the seconds when the deadline had to kill it.
"""
function _run_with_timeout(cmd::Base.AbstractCmd, seconds::Real, tool::AbstractString)
    p = run(cmd; wait = false)
    if !isfinite(seconds)                  # `_TEX_TIMEOUT[] = Inf`: no deadline at all
        wait(p)
        return success(p)
    end
    fired = Ref(false)
    t = Timer(seconds) do _
        process_running(p) || return
        fired[] = true
        kill(p)                                        # SIGTERM: let it go cleanly
        sleep(1.0)
        process_running(p) && kill(p, Base.SIGKILL)    # …and then not ask again
    end
    try
        wait(p)
    finally
        close(t)
    end
    ok = success(p)            # one that finished as the deadline struck is fine
    fired[] && !ok && throw(ArgumentError(
        "$tool did not finish in $(seconds) s — the document is probably looping " *
        "(a recursive macro?); if it is only slow, raise Janim._TEX_TIMEOUT[] " *
        "(seconds)"))
    return ok
end

"""
    _dvisvgm_svg(dvisvgm, dir) → String

`f.dvi` in `dir` → the SVG text, under the same deadline as latex. dvisvgm
writes its reason on stderr and nowhere else, so stderr is captured and the
reason is the message, instead of a bare ProcessFailedException.
"""
function _dvisvgm_svg(dvisvgm::AbstractString, dir::AbstractString)
    errbuf = IOBuffer()
    ok = _run_with_timeout(
        pipeline(
            Cmd(`$dvisvgm --no-fonts -o f.svg f.dvi`; dir = String(dir));
            stdout = devnull,
            stderr = errbuf,
        ),
        _TEX_TIMEOUT[],
        "dvisvgm",
    )
    ok || throw(ArgumentError(
        "dvisvgm could not convert the DVI:\n" * rstrip(String(take!(errbuf)))))
    return read(joinpath(dir, "f.svg"), String)
end

"The reason out of a LaTeX log: its `!` line, plus the hint that fits it."
function _latex_error(log::String)
    lines = isfile(log) ? readlines(log) : String[]
    i = findfirst(l -> startswith(l, "!"), lines)
    msg = i === nothing ? "  (no `!` line in the log)" :
          join("  " .* lines[i:min(i + 2, length(lines))], "\n")
    hint = i === nothing ? "" :
           occursin("Missing \$ inserted", lines[i]) || occursin("forgotten \$", lines[i]) ?
               "\n  → a MODE mismatch: `^` and `_` need LMathTex, and inside LMathTex " *
               "the body already sits in \$…\$, so a bare \$ closes it — prose goes in LTex." :
           occursin("Undefined control sequence", lines[i]) ?
               "\n  → that macro's package is missing: add_to_preamble!(tpl, raw\"\\usepackage{…}\")." : ""
    return msg * hint
end

# The typst page crops to the ink bbox, so unlike dvisvgm (whose y=0 IS the
# baseline — measured with a depth-0 \vrule) the baseline drifts with the
# content's ascent. The SENTINEL pins it: a 0.05×10 pt ink box whose bottom
# sits ON the baseline, compiled with every formula, measured and deleted at
# import. Its 0.05 pt of advance is the price — invisible next to a glyph.
const _TYPST_SENTINEL_W = 0.05   # pt
const _TYPST_SENTINEL_H = 10.0   # pt

_typst_source(formula::String) = """
    #set page(width: auto, height: auto, margin: 1pt, fill: none)
    \$#box(width: $(_TYPST_SENTINEL_W)pt, height: $(_TYPST_SENTINEL_H)pt, fill: black) $formula \$
    """

function _svg_typst(formula::String)
    _cached_svg(:typst, _typst_version(), _typst_source(formula)) do source
        mktempdir() do dir
            write(joinpath(dir, "f.typ"), source)
            run(pipeline(`$(Typst_jll.typst()) compile $(joinpath(dir, "f.typ")) $(joinpath(dir, "f.svg"))`;
                         stdout = devnull, stderr = devnull))
            read(joinpath(dir, "f.svg"), String)
        end
    end
end

"""
Find the sentinel among the children (unique: ≈0.05 pt wide, ≈10 pt tall at
scale `s`), shift the whole mobject so its bottom — the BASELINE — lands on
y=0, and delete it. If typst ever renders it differently the import still
works: one warning, no normalisation, never a throw (the acid-test rule).
"""
function _strip_typst_sentinel!(m::VMobject, s::Float64)
    # the sentinel is the FIRST element of the source, so it must be the
    # first child (walker = document order) — checking only that one keeps a
    # real thin bar later in the formula from ever being mistaken for it
    sent = isempty(m.submobjects) ? nothing : m.submobjects[1]
    if !(sent isa VMobject && has_points(sent) &&
         get_width(sent) < 0.5 * s &&
         abs(get_height(sent) - _TYPST_SENTINEL_H * s) < 0.1 * _TYPST_SENTINEL_H * s)
        @warn "typst sentinel not where expected — baseline left as imported" maxlog = 1
        return m
    end
    baseline = Float64(get_bottom(sent)[2])
    remove!(m, sent)
    shift!(m, Point3f(0, -baseline, 0))
    return m
end

# ── TexTemplate, LTex, LMathTex — LaTeX with your own packages ─────────
#
# `Tex(via = :latex)` compiles with a preamble wired into the source and always
# in math mode. That covers a formula and nothing else: MEASURED,
# `Tex("hola mundo"; via=:latex)` loses the space (math mode has none) and
# `Tex(raw"let $z=i$"; via=:latex)` fails outright, because the inner `$`
# closes the outer one. Manim splits the two — `Tex` is text mode, `MathTex` is
# math mode — and lets you edit the preamble. These are that pair, plus the
# template they share.
#
# THE BASE IS NOT A FIELD. `TEX_BASE_PREAMBLE` is a constant and a template
# only stores what you ADD, so "the file everything inherits from is never
# touched" is not a warning in a docstring — there is nothing to touch. You
# grow it with `add_to_preamble!`, which is the whole point: packages are what
# unlock glyphs (`physics`, `braket`, `siunitx`), and the size never belongs
# there — that is `size`/`scale!`'s job on this side.

"""
The minimum preamble every template inherits, and the one thing a template
CANNOT change. `amsmath` + `amssymb` is what the math routes already assumed,
so a default `TexTemplate` compiles the same document `via = :latex` does —
identical, not merely similar.
"""
const TEX_BASE_PREAMBLE = "\\usepackage{amsmath,amssymb}"

"The one package the LABELLED compile adds: `\\color[RGB]{r, g, b}`."
const TEX_COLOR_PREAMBLE = "\\usepackage{xcolor}"

const TEX_DOCUMENTCLASS = "\\documentclass[preview]{standalone}"

"""
    TexTemplate()
    TexTemplate(preamble::AbstractString)

The preamble [`LTex`](@ref) and [`LMathTex`](@ref) compile with, as a VALUE you
pass — not a config file that applies behind your back (the engine has none).

```julia
tpl = TexTemplate()
add_to_preamble!(tpl, raw"\\usepackage{physics}")
LMathTex(raw"\\dv{f}{x}"; template = tpl)
```

It holds only your ADDITIONS: [`TEX_BASE_PREAMBLE`](@ref) and the
documentclass are constants, so the base cannot be edited and the size knobs
(`12pt`…) cannot be reached — size is `size =` and `scale!` on this side, as
in Manim. What a template is for is PACKAGES, which is what unlocks glyphs.

`print(tpl)` shows the document it will compile, base included, with the
frozen part marked. [`tex_source`](@ref) returns it as a String.

Read one from a file with `TexTemplate(read("mine.tex", String))` — the file
supplies additions, and it is still a value you hand over explicitly.
"""
mutable struct TexTemplate
    preamble::Vector{String}
    document::Vector{String}
end

TexTemplate() = TexTemplate(String[], String[])
TexTemplate(preamble::AbstractString) = add_to_preamble!(TexTemplate(), preamble)

Base.copy(t::TexTemplate) = TexTemplate(copy(t.preamble), copy(t.document))

"""
    add_to_preamble!(t, lines...) → t

Add `\\usepackage{…}`, `\\newcommand{…}` and friends to `t`'s preamble. This is
the only way a template changes: the base is a constant.

A macro needs its package present — `\\newcommand{\\RR}{\\mathbb{R}}` wants
`amssymb`, which the base already carries.
"""
function add_to_preamble!(t::TexTemplate, lines::AbstractString...)
    for l in lines
        push!(t.preamble, String(l))
    end
    return t
end

"""
    add_to_document!(t, lines...) → t

Add commands that run AFTER `\\begin{document}` (colour definitions, a
`\\pagecolor`, a `\\tikzset`). Manim calls these `post_doc_commands`.
"""
function add_to_document!(t::TexTemplate, lines::AbstractString...)
    for l in lines
        push!(t.document, String(l))
    end
    return t
end

"""
    tex_source(t, body = "…"; math = true, color = false) → String

The complete `.tex` document `t` compiles — what you read when LaTeX fails and
you want to know what it was actually handed. `math = true` wraps `body` the
way [`LMathTex`](@ref) does; `false` leaves it in text mode, like [`LTex`](@ref).
`color = true` adds `xcolor`, which only the labelled compile behind `isolate`
and `t2c` needs — every other document is the plain one.
"""
function tex_source(t::TexTemplate, body::AbstractString = "…"; math::Bool = true,
                    color::Bool = false, alignment::AbstractString = "")
    # An environment (\begin{align*}…) is already a complete math construct;
    # wrapping it in $…$ breaks the compile. Same rule as `_latex_source`.
    b = String(body)
    inner = !math || startswith(lstrip(b), "\\begin{") ? b : "\$\\displaystyle $b\$"
    # `color = true` adds xcolor, and ONLY then: see `_latex_source`
    pre = join([TEX_BASE_PREAMBLE; (color ? [TEX_COLOR_PREAMBLE] : String[]); t.preamble], "\n")
    post = isempty(t.document) ? "" : join(t.document, "\n") * "\n"
    # ManimGL writes `\centering` into EVERY Tex document
    # (`tex_mobject.py:42,189`). Here it is emitted only when asked for, so a
    # document written without it is the plain one — which keeps the disk
    # cache valid.
    # …and it comes with the blank line GL's `"\n\n".join` leaves after the
    # body: that `\par` is what CLOSES the aligned paragraph. Without it the
    # box grows to the full text width — measured, 202 pt against 59.5 pt for
    # the same two lines, which is a difference you see across a room.
    align = isempty(alignment) ? "" : String(alignment) * "\n"
    par = isempty(alignment) ? "" : "\n"
    return "$TEX_DOCUMENTCLASS\n$pre\n\\begin{document}\n$post$align$inner$par\n\\end{document}\n"
end

function Base.show(io::IO, ::MIME"text/plain", t::TexTemplate)
    println(io, "TexTemplate · ", length(t.preamble), " preamble line(s), ",
            length(t.document), " document line(s)")
    println(io, "  ── frozen (TEX_BASE_PREAMBLE + documentclass) ──")
    for l in split(TEX_DOCUMENTCLASS * "\n" * TEX_BASE_PREAMBLE, '\n')
        println(io, "  │ ", l)
    end
    println(io, "  ── yours (add_to_preamble! / add_to_document!) ──")
    isempty(t.preamble) && isempty(t.document) && println(io, "  │ (nothing yet)")
    for l in t.preamble
        println(io, "  │ ", l)
    end
    for l in t.document
        println(io, "  │ [doc] ", l)
    end
    print(io, "  ── it compiles ──\n", join("  │ " .* split(rstrip(tex_source(t)), '\n'), "\n"))
end

Base.show(io::IO, t::TexTemplate) = show(io, MIME"text/plain"(), t)

"The template `LTex`/`LMathTex` use when none is passed. A session default, like `config_tex!`; never persisted."
const TEX_TEMPLATE = Ref(TexTemplate())

# The x-height calibration belongs to the TEMPLATE and the MODE, not to the
# route. MEASURED with the documentclass frozen: packages that only add glyphs
# leave it alone (physics/xcolor/mathtools/siunitx, Δ 0.00 %), but a font
# package moves it (newtxmath 0.42 %, mathpazo 8.27 %) and text mode sits
# 5.20 % below math mode. Inheriting one number would size those wrong with no
# symptom. One extra compile per (template, mode), then the disk cache.
const _TPL_CAL = Dict{String,Float64}()

function _tpl_cal(t::TexTemplate, math::Bool)
    # A template that paints needs xcolor in the probe as well: the labelled
    # compile loads it, and without it `\color{blue}` in `add_to_document!`
    # would die HERE on «Undefined control sequence». A template that does not
    # paint compiles the plain probe — the default template's constant and the
    # disk cache under it do not move.
    color = any(
        l -> occursin("\\color", l) || occursin("\\textcolor", l),
        [t.preamble; t.document],
    )
    src = tex_source(t, "x"; math, color)
    get!(_TPL_CAL, src) do
        probe = vmob(:Tex)
        g() = vmob(:Glyph; fill_opacity = 1.0)
        _tex_svg!(probe, g, _svg_latex_source(src), 1.0)
        _xheight_math() / Float64(get_height(probe))
    end
end

function _latex_mobject(tagsym::Symbol, body::AbstractString, math::Bool,
                        template::TexTemplate, size::Real, color, center::Bool,
                        isolate, t2c, kw; alignment::AbstractString = "")
    m = vmob(tagsym; kw...)
    st = _glyph_stroke(kw, color)
    fl = _glyph_fill(kw, color)
    ex = _glyph_extra(kw)
    glyph() = vmob(:Glyph; fill_color = fl.color, fill_opacity = fl.opacity,
                   stroke_color = st.color, stroke_opacity = st.opacity,
                   stroke_width = st.width, ex...)
    t2c_keys = String[String(k) for k in _t2c_keys(t2c)]
    _tex_latex_labelled!(m, glyph, String(body),
                         Float64(size) * _tpl_cal(template, math), isolate, t2c_keys,
                         (b, c) -> tex_source(template, b; math, color = c, alignment))
    _apply_t2c!(m, t2c)
    center && move_to!(m, ORIGIN)
    return m
end

"""
    LTex(text; template=TexTemplate(), size=1.0, color=WHITE, center=true, kw...)

Text through real LaTeX, in TEXT mode — Manim CE's `Tex`. Prose keeps its
spaces, `\\textbf`/`\\emph` work, and `\$…\$` switches to math INSIDE it:

```julia
LTex(raw"let \$z_3 = i \\cdot z_1\$")
```

That line is an error on `Tex(via = :latex)`, which is always math mode — the
inner `\$` closes the outer one. Superscripts are the mirror image: `x^2` bare
belongs in [`LMathTex`](@ref) and fails here, exactly as in Manim.

Pass a [`TexTemplate`](@ref) to add packages. Needs `latex` and `dvisvgm`; for
math without a LaTeX install, [`Tex`](@ref) (`via = :math`) runs in 0.2 ms.

`isolate`, `t2c` and several string arguments work here too, by the same
colour mechanism `Tex(via = :latex)` uses — so a glyph answers only to the
patterns given, and `\\cdots` is three glyphs, ManimGL's count.
"""
const LTex = VMobject{:LTex}

function (::Type{LTex})(texts::AbstractString...; template::TexTemplate = TEX_TEMPLATE[],
                        size = nothing, font_size = nothing, color = WHITE,
                        center::Bool = true, isolate = String[], t2c = nothing,
                        alignment::AbstractString = "", kw...)
    isempty(texts) && throw(ArgumentError("LTex needs at least one string"))
    text, patterns = _tex_join(texts, isolate)
    _assert_formula(text, "LTex")
    size = _text_size(size, font_size, _GL_SIZE.ltex, "LTex")   # TEXT mode
    _latex_mobject(:LTex, text, false, template, size, color, center, patterns, t2c, kw; alignment)
end

"""
    LMathTex(formula; template=TexTemplate(), size=1.0, color=WHITE, center=true, kw...)

A formula through real LaTeX, in display math — Manim CE's `MathTex`. With the
default template it compiles the same document as `Tex(f; via = :latex)`, so it
is that route with a preamble you can grow:

```julia
tpl = TexTemplate()
add_to_preamble!(tpl, raw"\\usepackage{physics}")
LMathTex(raw"\\dv{f}{x}"; template = tpl)
```

It also answers the one thing `via = :math` gets wrong: real LaTeX sets
variables in ITALIC, and MathTeXEngine asks for the ASCII glyph, which is
upright. An environment (`\\begin{align*}…`) is passed through untouched.
"""
const LMathTex = VMobject{:LMathTex}

function (::Type{LMathTex})(formulas::AbstractString...; template::TexTemplate = TEX_TEMPLATE[],
                            size = nothing, font_size = nothing, color = WHITE,
                            center::Bool = true, isolate = String[], t2c = nothing,
                            alignment::AbstractString = "", kw...)
    isempty(formulas) && throw(ArgumentError("LMathTex needs at least one string"))
    formula, patterns = _tex_join(formulas, isolate)
    _assert_formula(formula, "LMathTex")
    # math mode, so the same constant as `Tex(via = :latex)` — measured equal
    size = _text_size(size, font_size, _GL_SIZE.latex, "LMathTex")
    _latex_mobject(:LMathTex, formula, true, template, size, color, center, patterns, t2c, kw; alignment)
end

# ── plain text (Latin, no complex shaping) ─────────────────────────────

"""
    TextMobject(s; font="DejaVu Sans", size=1.0, color=WHITE, t2c=nothing,
                t2w=nothing, kw...)

Plain text through FreeType: outlines + advances + kerning. Simple Latin —
complex shaping (Arabic, ligatures…) stays out (that is HarfBuzz, and a
project of its own). Every glyph is a child carrying its
character as a key: `text["a"]` groups the a's.

Style BY RANGE, CE's `t2c`/`t2w`, keyed by substring or by
character range:

    TextMobject("stable orbit"; t2c = Dict("orbit" => YELLOW, 1:6 => BLUE))
    TextMobject("very important"; t2w = Dict("important" => :bold))

It is applied HERE, inside the constructor, and not afterwards, because this
is the only place that knows which glyph came from which character — spaces
produce no child, so glyph number and character number are not the same
thing. A `t2w` value is a weight (`:bold`) or a whole font name.
"""
const TextMobject = VMobject{:TextMobject}

"The character ranges a t2c/t2w key selects: a substring's occurrences, or a range."
function _text_ranges(pat::AbstractString, chars::Vector{Char})
    p = collect(pat)
    (isempty(p) || length(p) > length(chars)) && return UnitRange{Int}[]
    # The occurrences do not overlap — GL's `re.finditer` (and
    # CE's): "aaa" with "aa" is ONE range of two, not three of two
    out = UnitRange{Int}[]
    i = 1
    while i <= length(chars) - length(p) + 1
        if @views chars[i:i+length(p)-1] == p
            push!(out, i:i+length(p)-1)
            i += length(p)
        else
            i += 1
        end
    end
    return out
end
_text_ranges(r::AbstractUnitRange, chars::Vector{Char}) =
    [max(1, Int(first(r))):min(length(chars), Int(last(r)))]
_text_ranges(x, ::Vector{Char}) = throw(ArgumentError(
    "a t2c/t2w key is a substring (\"word\") or a character range (2:5), " *
    "not a $(typeof(x))"))

# `findfont` WALKS the system's font directories and scores every face, on
# every call — measured at 58 ms of the 66 ms a whole TextMobject costs, and
# paid by every `set_number!` on every frame (85 ms/frame in a live counter,
# where it WAS the frame). The query is
# pure for a running session (name → face), so one Dict kills it; `nothing`
# is cached too, so a missing font stays missing at the same speed.
const _FONT_CACHE = Dict{String,Union{Nothing,FTFont}}()

_findfont(name::AbstractString) =
    get!(() -> findfont(String(name)), _FONT_CACHE, String(name))

"""
The missing half of the check above: `findfont` never answers
`nothing` for a family that exists nowhere — it scores every installed face
and returns the CLOSEST one, so «DejaVu Serif» on a machine without it comes
back as DejaVu Sans with the same width (8.5034 for both: no number betrays
it, only the pixel). The WEIGHT refuses that silence; the FAMILY must too.
Tolerance: the resolved family must equal the request, or
the request must name the full face — «DejaVu Sans» accepts
DejaVu Sans / Book, «DejaVu Serif» refuses DejaVu Sans and says so.
"""
function _assert_family(requested::AbstractString, f, what::AbstractString)
    req = lowercase(strip(requested))
    req == lowercase(strip(f.family_name)) && return f
    req == lowercase(strip(string(f.family_name, " ", f.style_name))) && return f
    throw(ArgumentError(
        "$what: this system has no «$requested» — the closest face is " *
        "$(f.family_name) $(f.style_name), and findfont would have used it " *
        "SILENTLY. Install the family or name one you have."))
end

"""
The face a weight asks for: a symbol names a variant of the family
(`:bold` → "DejaVu Sans Bold").

`findfont` is FUZZY — it always answers with the closest face it has, never
with `nothing` — so asking is not enough: a symbol's request is checked
against the style the font actually reports, and a miss is an error instead
of a silent fallback to the regular weight.
"""
function _weighted_font(family::AbstractString, w)
    name = w isa Symbol ? string(family, " ", uppercasefirst(String(w))) : String(w)
    f = _findfont(name)
    f === nothing && throw(ArgumentError(
        "t2w: cannot find the font «$name» — pass the exact family name " *
        "(\"DejaVu Sans Bold\") or install the variant"))
    # The weight may sit in the FAMILY name: «Iwona Cond Light» is a family
    # whose face is «Regular», and asking only the style would refuse a face
    # that is installed. `_assert_family` below still demands the family.
    wl = lowercase(String(w))
    if w isa Symbol && !(occursin(wl, lowercase(f.style_name)) ||
                         occursin(wl, lowercase(f.family_name)))
        throw(ArgumentError(
            "t2w: this system has no «$name» — the closest face is " *
            "$(f.family_name) $(f.style_name), which is not $(String(w)). " *
            "Install the variant or name a font you have."))
    end
    return _assert_family(name, f, "t2w")   # the family must match too
end

# Kerning is a pair inside one FACE, and `===` asks for one OBJECT.
# `_findfont` caches by the name asked for, so «DejaVu Sans» and
# «DejaVu Sans Book» — one face under two names — are two objects, and
# `t2w = Dict("V" => "DejaVu Sans Book")` would lose the V–A pair (Δx 0.3107
# instead of 0.2817). Two names of one face agree on family, style and glyph count;
# the count guards the glyph indices, which are the previous face's.
_same_face(a, b) = a === b ||
    (a !== nothing && a.family_name == b.family_name &&
     a.style_name == b.style_name && a.num_glyphs == b.num_glyphs)

function (::Type{TextMobject})(s::AbstractString; font::String = "DejaVu Sans",
                         size = nothing, font_size = nothing, color = WHITE,
                         center::Bool = true, t2c = nothing, t2w = nothing, kw...)
    size = _text_size(size, font_size, _GL_SIZE.text, "TextMobject")
    family = font
    base = _findfont(family)
    base === nothing && throw(ArgumentError(
        "cannot find the font «$family» — try findfont(...) with another name"))
    _assert_family(family, base, "font")    # no silent family swap
    chars = collect(String(s))
    n = length(chars)
    fl = _glyph_fill(kw, color)                         # `fill_color` is the glyphs' colour too
    colours = Any[fl.color for _ in 1:n]
    faces = Any[base for _ in 1:n]
    if t2c !== nothing
        for (pat, col) in _t2c_pairs(t2c), r in _text_ranges(pat, chars)
            for i in r
                colours[i] = col
            end
        end
    end
    if t2w !== nothing
        for (pat, w) in _t2c_pairs(t2w)
            f = _weighted_font(family, w)
            for r in _text_ranges(pat, chars), i in r
                faces[i] = f
            end
        end
    end
    m = vmob(:TextMobject; kw...)
    st = _glyph_stroke(kw, nothing)
    ex = _glyph_extra(kw)
    glyph(c) = vmob(:Glyph; fill_color = c, fill_opacity = fl.opacity,
                    stroke_color = something(st.color, c),
                    stroke_opacity = st.opacity, stroke_width = st.width, ex...)
    advance = 0.0
    gi_prev = UInt32(0)
    face_prev = nothing
    for (i, ch) in enumerate(chars)
        fnt = faces[i]
        face = fnt.ft_ptr
        upem = Float64(unsafe_load(face).units_per_EM)
        gi = FT_Get_Char_Index(face, ch)
        # kerning is a pair INSIDE one face: across a font change there is none
        if gi_prev != 0 && gi != 0 && _same_face(face_prev, fnt)
            kv = Ref(FT_Vector(0, 0))
            FT_Get_Kerning(face, gi_prev, gi, FT_KERNING_UNSCALED, kv)
            advance += kv[].x / upem
        end
        if gi != 0
            x0 = advance
            child = glyph(colours[i])
            set_key!(child, string(ch))       # `text["a"]`, the basis for t2c
            _add_glyph!(child, fnt, gi,
                            (x, y) -> Point3f((x0 + x) * size, y * size, 0))
            has_points(child) && add!(m, child)
            FT_Load_Glyph(face, gi, FT_LOAD_NO_SCALE)
            g = unsafe_load(unsafe_load(face).glyph)
            advance += g.advance.x / upem
        else
            # the gap stays, but it is not silent: once per
            # (font, character) — `maxlog` counts per `_id`, in each logger
            @warn(
                "TextMobject: «$ch» has no glyph in $(fnt.family_name) — a 0.33 em gap is left",
                maxlog = 1,
                _id = Symbol("missing_glyph_", fnt.family_name, '_', ch)
            )
            advance += 0.33                            # a gap for unknown glyphs
        end
        gi_prev = gi
        face_prev = fnt
    end
    isempty(m.submobjects) && throw(ArgumentError("«$s» produced no geometry"))
    _record_char_runs!(m)                  # one part per occurrence
    # center=false keeps the natural metrics (baseline at y=0, pen from x=0) —
    # the SVG importer anchors by them; the default recenters
    center && move_to!(m, ORIGIN)
    return m
end
