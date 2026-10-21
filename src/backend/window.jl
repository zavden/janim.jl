# backend/window.jl — the GLFW.jl half of the window.
#
# Included AT RUNTIME by `_ensure_gl!` (glfw.jl): the `using GLFW` below is
# the exact moment GLFW.jl loads and initialises — WITHOUT dragging live.jl
# along (that one has its own lazy load, `_ensure_live!`, because only a
# preview needs it). On a headless machine the Null platform has already been
# initialised, so that init is a no-op and nothing touches X11.
#
# A window is for the preview alone: the renderer draws into its own targets
# and presents on the window through a WebGPU surface
# (`backend/wgpu/window.jl`), so the window is opened with NO graphics API.

using GLFW

# Hand `close_context` the registry it is not allowed to name. `isdefined`
# rather than a bare reference so that a future GLFW.jl which renames this
# internal does not stop the engine from running (the callbacks registry would
# then simply not be pruned on close).
isdefined(GLFW, :_window_callbacks) &&
    (_GLFW_WINDOWS[] = getfield(GLFW, :_window_callbacks))

"""
The preview window: a GLFW window with NO graphics API
(`CLIENT_API = NO_API`, GLFW 3.4) — the events, the keys, the title and
the close button, and nothing to make current or to swap. The Null platform
gives a hidden one (no OSMesa needed: there is no context to make). WebGPU
presents on it through the surface `backend/wgpu/window.jl` builds from the
window's native handles. Window hints persist between windows in GLFW, so
the API hint is set on EVERY window rather than trusted from the last one.
"""
function _create_window_noapi(width::Int, height::Int; title = "Janim",
                              visible = true)
    GLFW.WindowHint(GLFW.CLIENT_API, GLFW.NO_API)
    GLFW.WindowHint(GLFW.VISIBLE, visible && !_NULL_PLATFORM[])
    GLFW.WindowHint(GLFW.RESIZABLE, false)
    return GLFW.CreateWindow(width, height, title)
end
