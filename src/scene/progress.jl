# scene/progress.jl — ManimCE-style per-animation progress bars.
#
# One bar per numbered animation (waits included, like the numbering itself),
# overwritten in place while it runs and COMMITTED as a line when it ends, so
# a finished render leaves a readable history — that history is the point:
# reading it is how you analyse a scene.
#
# The same sink drives three fronts:
#   · a local terminal (direct script runs, the cold preview): \r overwrite
#     on stderr, ANSI colours, eighth-block fill.
#   · the daemon's socket (`janim render`, warm `janim preview`): each update
#     goes as a `PROG <text>` line (overwrite) or `PROGN <text>` line
#     (commit); the bash client draws them with \r — the daemon renders the
#     TEXT, the client only moves the cursor, so the aesthetics live here.
#   · the live playhead: the sink is persistent on the Live and keeps
#     a HIGH-WATER mark, so a backward jump's rebuild does not re-narrate
#     animations already shown; an edit resets it and narrates the new code.
#
# Byte-determinism is untouched: the bar writes to stderr or the socket,
# never into the render; `time()` here is display only (fps/eta).

using Printf

"Eighth-block bar: `▕██████▊     ▏` — `frac` of `cells` filled, left to right."
function _bar_cells(frac::Float64, cells::Int)
    f = clamp(frac, 0.0, 1.0) * cells
    full = floor(Int, f)
    rem8 = round(Int, 8 * (f - full))
    rem8 == 8 && (full += 1; rem8 = 0)
    partial = rem8 == 0 ? "" : string(("▏", "▎", "▍", "▌", "▋", "▊", "▉")[rem8])
    return "▕" * "█"^full * partial * " "^max(0, cells - full - (isempty(partial) ? 0 : 1)) * "▏"
end

"""
The bar's text for animation `idx` labelled `label`, at frame `j` of `n`,
`dt` seconds since the animation began. Pure.
"""
function _bar_text(idx::Int, label::String, j::Int, n::Int, dt::Float64)
    frac = n == 0 ? 1.0 : j / n
    fps = dt > 0 ? j / dt : 0.0
    eta = fps > 0 ? (n - j) / fps : 0.0
    head = rpad("Animation $idx · $label", 26)
    pct = lpad(string(round(Int, 100frac)), 3)
    tail = j >= n ? @sprintf("100%% · %d f · %.1f s", n, dt) :
                    @sprintf("%s%% · %d/%d · %.0f f/s · eta %.1f s", pct, j, n, fps, eta)
    return string("\e[2m", head, "\e[0m \e[36m", _bar_cells(frac, 16), "\e[0m ",
                  j >= n ? "\e[32m" : "\e[2m", tail, "\e[0m")
end

"""
    RenderProgress(io; socket=false)

The sink. `socket=true` speaks the daemon protocol's `PROG`/`PROGN` lines
instead of \\r overwrites. A write failure DISABLES the sink instead of
killing the render: a client that hung up loses its bar, not its mp4.
"""
mutable struct RenderProgress
    io::IO
    socket::Bool
    enabled::Bool
    seen::Int           # high-water mark: rebuilds do not re-narrate
    cur::Int            # animation being narrated (0 = none)
    t_anim::Float64     # when it began
    t_emit::Float64     # last update actually written (throttle)
end
RenderProgress(io::IO; socket::Bool = false) =
    RenderProgress(io, socket, true, 0, 0, 0.0, 0.0)

function _emit!(p::RenderProgress, text::String, commit::Bool)
    p.enabled || return nothing
    try
        if p.socket
            print(p.io, commit ? "PROGN " : "PROG ", text, "\n")
        else
            print(p.io, "\r\e[K", text, commit ? "\n" : "")
        end
        flush(p.io)
    catch
        p.enabled = false        # the render outlives its audience
    end
    return nothing
end

"""
Format one line and write it. Exists so the inference barrier can cover
BOTH — a render without a bar (every farm worker, the daemon) executes none
of this, but inference is static and would explore all of it. The runtime
price of the barrier lands only where the bar is on, and only once per
EMITTED line — throttled to ~7/s, unmeasurable against a render.
"""
_emit_line!(p::RenderProgress, idx::Int, label::String, j::Int, n::Int,
            dt::Float64, done::Bool) =
    _emit!(p, _bar_text(idx, label, j, n, dt), done)

"""
    _progress!(scene, label, j, n)

One frame of animation `scene.anim_index`. No-op without a sink. Throttled
to ~7 updates/s; the first and last frame always land, and the last COMMITS
the line (the history). Animations at or below the high-water mark are
silent — that is what keeps a playhead rebuild from re-narrating.
"""
function _progress!(scene, label::AbstractString, j::Int, n::Int)
    p = scene.progress
    p === nothing && return nothing
    idx = scene.anim_index
    idx <= p.seen && return nothing
    now = time()
    if p.cur != idx
        p.cur = idx
        p.t_anim = now
        p.t_emit = 0.0
    end
    done = j >= n
    (done || j == 1 || now - p.t_emit > 0.15) || return nothing
    p.t_emit = now
    # Inference barrier. It has to wrap the FORMATTING, not just the
    # write: `_bar_text` is where Printf's `@sprintf` lives, and its
    # `Format{...}`/`Spec{Val{'f'}}` machinery is one of the most expensive
    # things in the engine to INFER — ~20% of a cold first frame. Passing
    # `_bar_text(...)` as an argument to a barrier would infer it anyway,
    # which is why `_emit_line!` exists.
    Base.invokelatest(_emit_line!, p, idx, String(label), j, n,
                      now - p.t_anim, done)
    done && (p.seen = idx; p.cur = 0)
    return nothing
end

"`:auto` resolution: a bar on stderr when someone is watching it."
_auto_progress(want_bar::Bool) =
    want_bar && stderr isa Base.TTY ? RenderProgress(stderr) : nothing
