# backend/glfw.jl — the window system: GLFW's library through raw ccalls,
# the lazy load that keeps `using Janim` display-free, and the platform
# choice (Null / Wayland / X11).
#
# The preview's window is a GLFW window opened WITHOUT an API;
# `backend/wgpu/window.jl` presents on it through a WebGPU surface built from
# the window's native handles. Two facts shape the file:
#
#   · GLFW.jl initialises the window system in its module `__init__` (on
#     Linux it FORCES X11 and THROWS without one), so merely importing it
#     kills a headless machine before any of our code runs. Therefore this
#     file is static and GLFW.jl-free — raw ccalls into the GLFW *library*
#     (via GLFW_jll, whose load is display-free) and the lazy loaders — while
#     `backend/window.jl` (the `using GLFW` and the window factory) and
#     `interactive/live.jl` are included AT RUNTIME by `_ensure_gl!()` /
#     `_ensure_live!()`: only then does GLFW.jl load.
#   · On a machine with no display (or with JANIM_HEADLESS=1) the loader first
#     initialises GLFW's Null platform (GLFW 3.4, always compiled in) via
#     raw ccalls; GLFW.jl's own `Init()` then finds the library already
#     initialised and does not touch X11. On a Wayland session the same
#     trick picks GLFW's Wayland platform, so the preview is native and
#     Xwayland leaves the path; GLFW.jl's own `JULIA_GLFW_PLATFORM` still
#     overrides it. The bytes a frame renders do not depend on the platform:
#     a render to a file opens no window at all, and the pixels come from
#     the adapter, not from the window system.
#
# The names (`_ensure_gl!`, `gl_platform`, `_GL_READY`) keep their historical
# spelling; the «gl» in them reads as «GLFW».

import GLFW_jll

# ── raw GLFW ccalls (display-free, world-age-free) ──────────────────────
#
# These cover the GLFW touches that live INSIDE static render code — the
# preview's event pump, the framebuffer size, window destruction. They go
# through the C library directly so the static code neither loads GLFW.jl
# nor crosses a world-age boundary per frame.

_glfw_handle(window) = getfield(window, :handle)::Ptr{Cvoid}

"""
glfwGetFramebufferSize, via the C library. Physical pixels — on HiDPI
displays (Retina) they differ from the window's screen coordinates, and the
present pass must target these.
"""
_framebuffer_size(window) = _framebuffer_size(_glfw_handle(window))
function _framebuffer_size(handle::Ptr{Cvoid})
    w = Ref{Cint}(0); h = Ref{Cint}(0)
    ccall((:glfwGetFramebufferSize, GLFW_jll.libglfw), Cvoid,
          (Ptr{Cvoid}, Ptr{Cint}, Ptr{Cint}), handle, w, h)
    return (Int(w[]), Int(h[]))
end

const _EVENT_POLLS = Ref(0)          # glfwPollEvents calls (counted by tests)

"glfwPollEvents, via the C library (`present!` has no buffers to swap)."
function _poll_events!()
    _EVENT_POLLS[] += 1
    ccall((:glfwPollEvents, GLFW_jll.libglfw), Cvoid, ())
    return nothing
end

# ── the focus drain (GLFW 3.4 on Wayland) ───────────────────────────────
#
# GLFW implements key repeat on Wayland itself, with a timerfd: a key PRESS
# arms it (the compositor's delay and rate) and the RELEASE, or the
# keyboard's leave, disarms it — but both handlers return early when the
# library has no focused window. `glfwDestroyWindow` nulls that pointer
# without touching the timer, so a window destroyed while a key is held
# (the preview closes on Esc's PRESS, and a finger takes 50–150 ms to lift)
# leaves the timer armed for good: the next poll reads it and calls
# `_glfwInputKey(NULL, …)` — the daemon's SIGSEGV on the second preview —
# or, when the new window already had the focus, feeds it the phantom Esc
# that closed it by itself (it shows only with a HELD key, e.g.
# `wtype -P Escape -s 400 -p Escape`; a press-and-release in one instant
# never does). GLFW's master fixed both halves after 3.4 (the destroy
# disarms the timer, the repeat checks the focus); GLFW_jll 3.4.1 has
# neither. From outside the library the way out is to make the LEAVE
# happen while GLFW still knows the window: hide it (Wayland unmaps, the
# compositor sends keyboard.leave), pump until the focus is gone, then
# destroy. `_FOCUS_DRAINS` counts the drains.

const _GLFW_FOCUSED = Cint(0x00020001)
const _FOCUS_DRAINS = Ref(0)          # close_context: focused windows drained before the destroy
const _FOCUS_DRAIN_TIMEOUTS = Ref(0)  # …of which the leave never came before the ceiling
const _FOCUS_DRAIN_CEILING = 0.25     # seconds — the ceiling, never the cost (~1 ms on sway)

_window_focused(handle::Ptr{Cvoid}) =
    ccall((:glfwGetWindowAttrib, GLFW_jll.libglfw), Cint, (Ptr{Cvoid}, Cint),
          handle, _GLFW_FOCUSED) != 0

"""
    _drain_focus!(handle) → Bool

Hide a FOCUSED window and pump events until GLFW has seen its focus leave;
`false` when the window had none (nothing armed the repeat timer, nothing
to drain). Bounded by `_FOCUS_DRAIN_CEILING`; a drain that hits it is
counted in `_FOCUS_DRAIN_TIMEOUTS`. Why: the comment above.
"""
function _drain_focus!(handle::Ptr{Cvoid})
    _window_focused(handle) || return false
    _FOCUS_DRAINS[] += 1
    ccall((:glfwHideWindow, GLFW_jll.libglfw), Cvoid, (Ptr{Cvoid},), handle)
    t0 = time()
    while _window_focused(handle)
        if time() - t0 >= _FOCUS_DRAIN_CEILING
            _FOCUS_DRAIN_TIMEOUTS[] += 1
            break
        end
        ccall((:glfwWaitEventsTimeout, GLFW_jll.libglfw), Cvoid, (Cdouble,), 0.01)
    end
    return true
end

"""
GLFW.jl's `_window_callbacks`, once window.jl has loaded — `nothing` before
that, and this file must never name GLFW.jl (the reason is at the top:
static render code neither loads it nor crosses a world age per frame).

GLFW.jl keeps that `Dict{Window, Ref{Vector{Callback}}}` so the C
library cannot call a closure Julia has already collected, and
`GLFW.DestroyWindow` is the ONLY place that prunes it. `close_context`
destroys through the C library instead, so without this hand-over the entry
outlives the window it was protecting — and on the preview path four of the
five callbacks close over the `Live`, so the whole session stays reachable:
**+475.7 MiB per `janim preview`, for ever**.
"""
const _GLFW_WINDOWS = Ref{Any}(nothing)

"""
    close_context(window)

Destroy a window and forget it. What it releases first is the presenter —
the WebGPU surface on this window — because a surface that outlives its
wl_surface / X window is a use-after-free inside the driver's WSI. No
presenter: a no-op. Then, if the window has the keyboard focus, it is
hidden and the events pumped until GLFW has seen the focus go
(`_drain_focus!`: GLFW 3.4's Wayland key-repeat timer outlives a destroyed
window otherwise), and only then destroyed. `close_context(nothing)` is a
no-op too (a Scene that rendered to a file has no window).

The `delete!` takes the Dict itself and not a closure on purpose: `delete!`
is a Base method older than any world this can be called from, so it needs
no `invokelatest` — a closure installed by window.jl would.
"""
function close_context(window)
    handle = _glfw_handle(window)
    _release_presenter!(handle)
    _drain_focus!(handle)       # a held key must not outlive the window (GLFW 3.4 + Wayland)
    ccall((:glfwDestroyWindow, GLFW_jll.libglfw), Cvoid, (Ptr{Cvoid},), handle)
    # On Wayland glfwDestroyWindow only QUEUES the requests to the compositor
    # (libwayland buffers them; X11's destroy flushed). A process that exits
    # right after never notices; the daemon does — its window stayed on
    # screen with the title frozen after Esc. One poll flushes the queue on
    # every platform.
    _poll_events!()
    reg = _GLFW_WINDOWS[]
    reg === nothing || delete!(reg, window)
    return nothing
end
close_context(::Nothing) = nothing

# ── lazy loading ────────────────────────────────────────────────────────

const _GL_READY = Ref(false)
const _LIVE_READY = Ref(false)      # the preview's sources, loaded apart
const _GL_LOCK = ReentrantLock()
const _NULL_PLATFORM = Ref(false)   # no surface on a Null window

# GLFW 3.4 constants that GLFW.jl does not expose (init hints + platforms).
const _GLFW_PLATFORM         = Cint(0x00050003)
const _GLFW_PLATFORM_NULL    = Cint(0x00060005)
const _GLFW_PLATFORM_WAYLAND = Cint(0x00060003)
const _GLFW_PLATFORM_X11     = Cint(0x00060004)
const _GLFW_PLATFORM_WIN32   = Cint(0x00060001)
const _GLFW_PLATFORM_COCOA   = Cint(0x00060002)

"""
Headless when asked (JANIM_HEADLESS=1) or when there is nothing to talk to.
The same variable picks the CPU adapter (`backend/wgpu/context.jl`): one
knob, two halves — the adapter that draws
and the window system that would show it.
"""
_headless_env() =
    get(ENV, "JANIM_HEADLESS", "") in ("1", "true") ||
    (Sys.islinux() && !haskey(ENV, "DISPLAY") && !haskey(ENV, "WAYLAND_DISPLAY"))

"""
Initialise the GLFW *library* on `platform` BEFORE GLFW.jl loads. glfwInit
is idempotent: when GLFW.jl's `__init__` later calls it (forcing X11 on
Linux), the library is already up and the X11 hint is ignored — that is the
entire trick that lets GLFW.jl load on a machine without a display (Null)
and on a Wayland session without Xwayland.
"""
function _init_platform!(platform::Cint)
    ccall((:glfwInitHint, GLFW_jll.libglfw), Cvoid, (Cint, Cint),
          _GLFW_PLATFORM, platform)
    ok = ccall((:glfwInit, GLFW_jll.libglfw), Cint, ())
    ok == 1 || error("glfwInit(platform 0x", string(platform; base = 16),
                     ") failed — GLFW $(GLFW_jll.libglfw)")
    _NULL_PLATFORM[] = platform == _GLFW_PLATFORM_NULL
    return nothing
end
_init_null_platform!() = _init_platform!(_GLFW_PLATFORM_NULL)

"""
Wayland when the session offers it (`WAYLAND_DISPLAY`), this GLFW was built
with it, and the user did not choose a platform through GLFW.jl's own
`JULIA_GLFW_PLATFORM` — which keeps working exactly as before: GLFW.jl reads
it in `Init()`, and this code steps aside whenever it is set.
"""
_wayland_env() =
    Sys.islinux() && haskey(ENV, "WAYLAND_DISPLAY") &&
    !haskey(ENV, "JULIA_GLFW_PLATFORM") &&
    ccall((:glfwPlatformSupported, GLFW_jll.libglfw), Cint, (Cint,),
          _GLFW_PLATFORM_WAYLAND) == 1

"""
GLFW's Wayland backend asks xkbcommon for the locale's Compose table
at init, and xkbcommon 1.13 on Fedora 44 looks for the X Compose files
somewhere other than `/usr/share/X11/locale` unless `XLOCALEDIR` says so:
two `ERROR` lines on stderr per process («No Compose file for locale …»),
in every render, on a machine where the files exist. Of five variants (plain, `LANG=en_US.UTF-8`, `LC_CTYPE=C`, `XKB_LOG_LEVEL=critical`,
`XLOCALEDIR=/usr/share/X11/locale`) only the last two silence it, and only
the last one is a fix rather than a gag — it is the directory libX11 itself
reads. `get!` keeps a value the user exported; a machine without the
directory is left alone.
"""
function _point_xkb_at_x_locale!()
    dir = "/usr/share/X11/locale"
    isfile(joinpath(dir, "compose.dir")) && get!(ENV, "XLOCALEDIR", dir)
    return nothing
end

"""
    gl_platform() → :wayland | :x11 | :null | :win32 | :cocoa | :none

The window system GLFW is running on (`:none` before the first window).
The answer is a property of the process: GLFW picks its platform once, at
`glfwInit`, and every window after that — the preview's, a hidden one —
lives on it. The WebGPU surface is built from the platform's native handles
(`backend/wgpu/window.jl`), which is why it asks.
"""
function gl_platform()
    p = ccall((:glfwGetPlatform, GLFW_jll.libglfw), Cint, ())
    p == _GLFW_PLATFORM_WAYLAND && return :wayland
    p == _GLFW_PLATFORM_X11 && return :x11
    p == _GLFW_PLATFORM_NULL && return :null
    p == _GLFW_PLATFORM_WIN32 && return :win32
    p == _GLFW_PLATFORM_COCOA && return :cocoa
    return :none
end

# TWO lazy loads, not one: the split is worth 0.37 s in EVERY process that
# renders. `using GLFW` costs 0.005 s and window.jl 0.004 s, but live.jl
# costs 0.369 s to parse and compile. live.jl is the PREVIEW: the playhead,
# the frame pool, the timeline strip, the error overlay. A render — the
# farm's four workers, `janim render` — never touches any of it. A render to
# a file does not even reach the first load: only a preview opens a window.
const _GL_WINDOW_SOURCE = joinpath(@__DIR__, "window.jl")
const _GL_LIVE_SOURCE   = joinpath(@__DIR__, "..", "interactive", "live.jl")

"""
    _ensure_gl!()

On first need, load the GLFW-facing window source (and, on a
headless machine, initialise the Null platform first; on a Wayland session,
the Wayland one). Idempotent, locked, and cheap after the first call. Every
public entry that can end in a window passes through here via its delegator
below.

No driver knob is injected here: `STRICT_GL_ENV` is empty
(`backend/determinism.jl`), because the Vulkan drivers have no shader-variant
race to pin.
"""
function _ensure_gl!()
    _GL_READY[] && return nothing
    lock(_GL_LOCK) do
        _GL_READY[] && return nothing
        if _headless_env()
            _init_null_platform!()
        elseif _wayland_env()
            _point_xkb_at_x_locale!()
            _init_platform!(_GLFW_PLATFORM_WAYLAND)
        end
        Base.include(@__MODULE__, _GL_WINDOW_SOURCE)
        _GL_READY[] = true
        return nothing
    end
    return nothing
end

"""
    _ensure_live!()

The preview's own sources, loaded only when something actually
previews. Goes through `_ensure_gl!` first because live.jl is written
against the bindings window.jl brings in (`using GLFW` among them) — the
ORDER is what makes the headless trick work, so it is preserved here.
"""
function _ensure_live!()
    _LIVE_READY[] && return nothing
    _ensure_gl!()
    lock(_GL_LOCK) do
        _LIVE_READY[] && return nothing
        Base.include(@__MODULE__, _GL_LIVE_SOURCE)
        _LIVE_READY[] = true
        return nothing
    end
    return nothing
end

# ── public delegators (static names, runtime implementations) ───────────
#
# The `_*_gl` implementations appear when `_ensure_gl!` includes the runtime
# sources; `Base.invokelatest` jumps the world-age wall exactly once per
# call. These are entry-level calls (opening a window, a preview tick), not
# per-fragment work — the invokelatest cost is nanoseconds against them.

function _create_window_noapi end   # the preview window, in window.jl
function _live_gl end
function _setup_live_gl end
function _live_step_gl end
function _live_status_gl end

"""
    live(path; fps = 30, resolution = (1280, 720), stop_at_checkpoints = false,
               max_seconds = Inf, progress = :auto)

Open the interactive window on the scene file at `path` and run it until you
close it.

```julia
live("scene.jl")
```

The file must define `construct(scene)` — or pass `live("scene.jl:name")` to
preview another scene function the file defines (the daemon, the CLI and
the farm read the same address). It is tracked with Revise, so saving
an edit rebuilds the scene in about 80 ms without restarting anything. An
edit that only touches ANOTHER function of the file does not invalidate this
session's cache: Revise invalidates per function, not per file.
Playback is real time — `construct` runs ONCE as a coroutine and each frame
costs O(1).

| key | |
|---|---|
| `Esc` / `q` | quit |
| `space` | pause |
| `,` `.` | step one frame back / forward |
| `←` `→` | jump ∓1 second |
| `[` `]` | previous / next animation |
| `PgUp` `PgDn` | previous / next checkpoint |
| `Home` | back to the start |
| `c` | stop at checkpoints |

Dragging pans and the wheel zooms. Jumping BACKWARDS re-simulates exactly
rather than replaying a cache of pixels, so what you scrub through is the film
and not an approximation of it.

Errors do not end the session: break `construct` and the window freezes on the
last good frame and watches the file until your fix lands.

From the shell, `janim preview scene.jl` opens the same window inside the warm
daemon, which skips the start-up cost. To drive the loop yourself, see
[`setup_live`](@ref) and [`live_step!`](@ref).
"""
live(path::String; kw...) =
    (_ensure_live!(); Base.invokelatest(_live_gl, path; kw...))

"""
    setup_live(path; fps = 30, resolution = (1280, 720), visible = false) → Live

Build the live session WITHOUT entering the event loop: track `path` with
Revise, open the window, and return the state that [`live_step!`](@ref)
advances.

This is [`live`](@ref) split in two so that something else can own the loop —
a test that steps a fixed number of frames, an editor integration, a headless
session that only wants the pixels. `visible = false` keeps the window off the
screen.
"""
setup_live(path::String; kw...) =
    (_ensure_live!(); Base.invokelatest(_setup_live_gl, path; kw...))

"""
    live_step!(v)

Advance a live session by one frame: apply any pending Revise edit, rebuild
what the edit invalidated, simulate, and draw.

An edit is detected by the WORLD AGE of `construct`, not by the file's mtime —
Revise applies a change a tick after the file changes, so an mtime check would
rebuild the state with the old code and leave a session that never recovers.
"""
live_step!(v) = (_ensure_live!(); Base.invokelatest(_live_step_gl, v))

"""
    live_status(v) → String

One line describing where the session is: frame number and total, which
animation, the current checkpoint if there is one, and whether it is playing or
paused. This is what the preview's title bar and the CLI show.
"""
live_status(v) = (_ensure_live!(); Base.invokelatest(_live_status_gl, v))
