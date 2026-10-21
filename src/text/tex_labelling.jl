# text/tex_labelling.jl — ManimGL's string labelling, ported.
#
# The problem it solves: a formula compiled by LaTeX arrives as an SVG whose
# glyphs carry FONT IDS, not characters, so `tex["x"]`, `isolate`, `t2c` and
# `TransformMatchingTex` — everything that addresses a formula by what it
# SAYS — would have nothing to match on.
#
# ManimGL solves it by making LaTeX itself do the attribution
# (`manimlib/mobject/svg/string_mobject.py` + `svg/tex_mobject.py`): it cuts
# the string into SPANS (each `isolate` pattern, each `t2c` key, each
# user-written `{{…}}` pair, each of several string arguments), compiles the
# formula ONCE with `{{\color[RGB]{0,0,n} …}}` wrapped around span number n,
# and then reads each glyph's fill colour back as its span number. Span 0 is
# the whole string and is NOT wrapped: a glyph that belongs to no span comes
# out black and reads back as 0.
#
# This file is the parser half — the part that turns (string, isolate, t2c)
# into that labelled body and the list of spans. It is deliberately a LITERAL
# port, down to the five-component sort key of `parse()` and the way
# `get_command_matches` groups ADJACENT braces, because the whole point is
# that a formula labels the same here as in ManimGL: the body is meant to
# match what ManimGL itself produces, byte for byte.
#
# Two deliberate divergences from ManimGL:
#
#   · GL WARNS and drops a span that crosses a brace level or partly overlaps
#     another; here both are an ArgumentError naming the span. A silently
#     dropped span is a `tex[…]` that quietly addresses the wrong glyphs.
#   · GL's fallback for a substring that was NOT isolated
#     (`select_unisolated_substring`) slices the glyph list by a symbol count
#     (`utils/tex.py`), assuming the DVI ships boxes in string order. It does
#     not: on `\frac{a}{b}` it answers the fraction BAR for "a" (twice), and
#     on `\sum_{i=1}^n i^2` the ∑ for "i". That half is not ported — asking
#     for an un-isolated substring is an error that names `isolate`.
#
# Everything here works over CODE POINTS, like Python's `re`. Spans are kept
# as GL keeps them — 0-based, half-open — until the very end, where they
# become 1-based inclusive `UnitRange`s for Julia.

"One match of GL's `get_command_matches`: a `\\command` or a run of braces."
struct _TexCommand
    span::Tuple{Int,Int}    # 0-based, half-open, over code points
    flag::Int               # 1 = a run of `{`, -1 = a run of `}`, 0 = a \command
    len::Int                # how many braces in the run (the `{{` rule reads it)
end

_tex_letter(c::Char) = isascii(c) && isletter(c)

"The code points of a 0-based half-open span, as a String."
_tex_sub(chars::Vector{Char}, sp::Tuple{Int,Int}) = String(@view chars[(sp[1]+1):sp[2]])

"""
GL's `Tex.get_command_matches` (`tex_mobject.py:92-128`), literally.

The subtlety worth the port: braces are matched in RUNS, and a closing run
pairs with the innermost opening run by taking `min` of the two lengths, so
`{{` is ONE match of length two (which is what makes `{{…}}` a span) while
the `}}` of `\\frac{\\sqrt{x}}{y}` splits into two runs of one (which is what
keeps it from being a span). A leftover brace on either side is an error, the
same one TeX would give.
"""
function _tex_command_matches(chars::Vector{Char})
    result = _TexCommand[]
    open_stack = Tuple{Tuple{Int,Int},Int}[]
    n = length(chars)
    i = 1
    while i <= n
        c = chars[i]
        if c == '\\'
            j = i + 1
            if j > n
                i += 1                       # a trailing `\` matches nothing
                continue
            end
            if _tex_letter(chars[j])
                while j <= n && _tex_letter(chars[j])
                    j += 1
                end
            else
                j += 1                       # `\\`, `\,`, `\{` … one character
            end
            push!(result, _TexCommand((i - 1, j - 1), 0, 0))
            i = j
        elseif c == '{'
            j = i
            while j <= n && chars[j] == '{'
                j += 1
            end
            push!(open_stack, ((i - 1, j - 1), length(result)))
            i = j
        elseif c == '}'
            j = i
            while j <= n && chars[j] == '}'
                j += 1
            end
            close_start, close_end = i - 1, j - 1
            while true
                isempty(open_stack) && throw(ArgumentError(
                    "Missing '{' inserted: this formula closes a brace it never opened"))
                (open_start, open_end), index = pop!(open_stack)
                k = min(open_end - open_start, close_end - close_start)
                insert!(result, index + 1, _TexCommand((open_end - k, open_end), 1, k))
                push!(result, _TexCommand((close_start, close_start + k), -1, k))
                close_start += k
                close_start < close_end && continue
                open_end -= k
                open_start < open_end && push!(open_stack, ((open_start, open_end), index))
                break
            end
            i = j
        else
            i += 1
        end
    end
    isempty(open_stack) && return result
    throw(ArgumentError("Missing '}' inserted: this formula opens a brace it never closes"))
end

"""
Every non-overlapping occurrence of `sel` in `chars`, left to right — GL's
`find_spans_by_selector` for a plain string (`re.finditer(re.escape(sel), …)`).
Only the string form is ported: GL also takes a compiled regex and an index
pair, and neither has a Janim caller.
"""
function _tex_spans_of(chars::Vector{Char}, sel::AbstractString)
    pat = collect(String(sel))
    out = Tuple{Int,Int}[]
    # GL's `re.finditer("")` matches at every position, which would label the
    # whole formula one empty span at a time. It is a user error either way,
    # and saying so beats a hundred empty labels.
    isempty(pat) && throw(ArgumentError(
        "isolate/t2c: an empty pattern selects nothing — name the substring you mean"))
    n, m = length(chars), length(pat)
    i = 1
    while i <= n - m + 1
        if @views chars[i:(i+m-1)] == pat
            push!(out, (i - 1, i + m - 1))
            i += m                          # finditer does not overlap
        else
            i += 1
        end
    end
    return out
end

"""
    _tex_labelling(s; isolate, t2c) → (body = String, spans = Vector{UnitRange{Int}})

ManimGL's `StringMobject.parse` + `get_content(is_labelled = true)`
(`string_mobject.py:210-386`), ported literally.

`body` is `s` with `{{\\color[RGB]{r, g, b}` … `}}` wrapped around each span,
ready to be dropped into the document's maths or text environment; `spans` are
those spans over `s` itself, 1-based and inclusive, with `spans[1]` the whole
string (GL's span 0, which is never wrapped). A glyph that reads back label
`n` belongs to `spans[n + 1]`.

`t2c` takes the KEYS only: the colouring happens afterwards, on the parts the
labels produced, so one mechanism addresses and another paints.
"""
function _tex_labelling(s::AbstractString; isolate = String[], t2c = String[])
    chars = collect(String(s))
    n = length(chars)
    # the four categories of GL's parse(), in its order: t2c keys, isolate
    # patterns, `protect` (which Tex never sets — kept so the port reads like
    # the original) and the commands
    configured = Tuple{Int,Int}[]
    for sel in _tex_selectors(t2c), sp in _tex_spans_of(chars, sel)
        push!(configured, sp)
    end
    isolated = Tuple{Int,Int}[]
    for sel in _tex_selectors(isolate), sp in _tex_spans_of(chars, sel)
        push!(isolated, sp)
    end
    protected = Tuple{Int,Int}[]
    commands = _tex_command_matches(chars)

    span_of(cat, i) = cat == 0 ? configured[i] : cat == 1 ? isolated[i] :
                      cat == 2 ? protected[i] : commands[i].span
    # GL's five-component key (`string_mobject.py:219-236`). At one position it
    # closes non-empty spans, then opens empty ones, then closes empty ones,
    # then opens non-empty ones; `-paired_index` makes the LONGEST span open
    # first and the most recent one close first. Reproduced, not re-derived:
    # it is what decides the nesting when two spans share an edge.
    function key(cat, i, flag)
        sp = span_of(cat, i)
        index, paired = flag == 1 ? (sp[1], sp[2]) : (sp[2], sp[1])
        return (index, flag * (index != paired ? 2 : -1), -paired, flag * cat, flag * i)
    end
    counts = (length(configured), length(isolated), length(protected), length(commands))
    items = [(cat, i, flag) for cat in 0:3 for i in 1:counts[cat+1] for flag in (1, -1)]
    sort!(items; by = t -> key(t...))

    inserted = Tuple{Int,Int}[]      # (command index, 0) or (label, ±1)
    labelled = Tuple{Int,Int}[]      # span per label, 0-based half-open
    overlapping = Tuple{Int,Int}[]
    mismatched = Tuple{Int,Int}[]
    label = 1
    protect_level = 0
    bracket_stack = Int[0]
    bracket_count = 0
    open_command_stack = Tuple{Int,Int}[]
    open_stack = Tuple{Int,Int,Int,Int,Vector{Int}}[]
    for (cat, i, flag) in items
        if cat >= 2
            protect_level += flag
            (flag == 1 || cat == 2) && continue
            push!(inserted, (i, 0))
            cflag = commands[i].flag
            if cflag == 1
                bracket_count += 1
                push!(bracket_stack, bracket_count)
                push!(open_command_stack, (length(inserted), i))
                continue
            end
            cflag == 0 && continue
            pos, i_ = pop!(open_command_stack)
            pop!(bracket_stack)
            # `get_attr_dict_from_command_pair`: only a run of TWO braces or
            # more makes a span — that is the `{{…}}` the user writes
            commands[i_].len >= 2 || continue
            push!(labelled, (commands[i_].span[2], commands[i].span[1]))
            insert!(inserted, pos + 1, (label, 1))
            insert!(inserted, length(inserted), (label, -1))
            label += 1
            continue
        end
        if flag == 1
            push!(open_stack, (length(inserted), cat, i, protect_level, copy(bracket_stack)))
            continue
        end
        sp = span_of(cat, i)
        pos, cat_, i_, plevel_, bstack_ = pop!(open_stack)
        if cat_ != cat || i_ != i
            push!(overlapping, sp)
            continue
        end
        # a span that falls INSIDE a command (the `a` of `\frac`) is dropped in
        # silence, here as in GL: it is not the user's `a`, it is TeX's
        (plevel_ != 0 || protect_level != 0) && continue
        if bstack_ != bracket_stack
            push!(mismatched, sp)
            continue
        end
        push!(labelled, sp)
        insert!(inserted, pos + 1, (label, 1))
        push!(inserted, (label, -1))
        label += 1
    end
    isempty(overlapping) || throw(ArgumentError(
        "isolate/t2c: partly overlapping substrings " *
        join(("«" * _tex_sub(chars, sp) * "»" for sp in overlapping), ", ") *
        " — two patterns may nest, but they may not cross (ManimGL warns and " *
        "drops them; here it is an error, so nothing addresses the wrong glyphs)"))
    isempty(mismatched) || throw(ArgumentError(
        "isolate/t2c: cannot label " *
        join(("«" * _tex_sub(chars, sp) * "»" for sp in mismatched), ", ") *
        " — it crosses a brace level, so LaTeX has no group to colour. Isolate " *
        "a substring that sits inside one pair of braces"))
    pushfirst!(labelled, (0, n))
    pushfirst!(inserted, (0, 1))
    push!(inserted, (0, -1))

    # `reconstruct_string` (`string_mobject.py:333-368`): walk the inserted
    # items, keep the text between them, and drop the FIRST and LAST insertions
    # — those two are span 0, which bounds the walk and is never wrapped.
    pieces = Tuple{Tuple{Int,Int},String}[]
    for (i, flag) in inserted
        if flag == 0
            push!(pieces, (commands[i].span, _tex_sub(chars, commands[i].span)))
        else
            sp = labelled[i+1]
            idx = flag < 0 ? sp[2] : sp[1]
            push!(pieces, ((idx, idx), _tex_color_command(i, flag)))
        end
    end
    out = IOBuffer()
    m = length(pieces)
    for k in 1:(m-1)
        print(out, _tex_sub(chars, (pieces[k][1][2], pieces[k+1][1][1])))
        k <= m - 2 && print(out, pieces[k+1][2])
    end
    return (body = String(take!(out)),
            spans = [(sp[1]+1):sp[2] for sp in labelled])
end

"One selector or a collection of them, as a vector of strings."
_tex_selectors(x::AbstractString) = [String(x)]
_tex_selectors(x) = String[String(s) for s in x]

"""
The label as LaTeX writes it: `\\color[RGB]{r, g, b}` with the label read as a
24-bit integer, so label 1 is `{0, 0, 1}`. `xcolor`'s `RGB` model is 0-255 per
channel and Float32 keeps eight bits per channel exactly, so the integer
survives the round trip through the SVG and the colour rows.
"""
function _tex_color_command(label::Int, flag::Int)
    flag < 0 && return "}}"
    rg, b = divrem(label, 256)
    r, g = divrem(rg, 256)
    return "{{\\color[RGB]{$r, $g, $b}"
end

"The label a glyph's fill colour carries: GL's `hex_to_int(color_to_hex(…))`."
_tex_label_of(rgba::Vec4f) = (round(Int, rgba[1] * 255) << 16) |
                             (round(Int, rgba[2] * 255) << 8) |
                              round(Int, rgba[3] * 255)

"""
    _tex_keys_by_span(s, spans, labels) → Vector{Vector{String}}

What each glyph is called. A glyph labelled `n` belongs to `spans[n + 1]` and
to every span that CONTAINS it, so `Tex(raw"x^2 + y^2"; isolate = ["x^2", "^2"])`
gives the `2` of `x^2` both keys and `tex["x^2"]`, `tex["^2"]` each answer what
ManimGL answers. Span 1 (the whole string) is never a key: it would name every
glyph.

Keys are a LIST on every mobject and `_isolate!` (the `:math` route) only adds
to it, so both routes address through the same mechanism and
`TransformMatchingTex` needs no route of its own.
"""
function _tex_keys_by_span(s::AbstractString, spans::Vector{UnitRange{Int}},
                           labels::Vector{Int})
    chars = collect(String(s))
    texts = [String(@view chars[sp]) for sp in spans]
    out = Vector{String}[]
    for L in labels
        keys = String[]
        if 1 <= L <= length(spans) - 1
            own = spans[L+1]
            for j in 2:length(spans)
                sp = spans[j]
                first(sp) <= first(own) && last(sp) >= last(own) && push!(keys, texts[j])
            end
        end
        push!(out, keys)
    end
    return out
end
