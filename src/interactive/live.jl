# The live window — our replacement for ManimGL's embed().
#
# This file is included AT RUNTIME, never at package load — it drives GLFW,
# and loading it lazily is what keeps `using Janim` display-free. The public
# names (`live`, `setup_live`, `live_step!`, `live_status`) are static
# delegators defined by the lazy loader; this file provides their `_*_gl`
# implementations. `Controls` and its pure handlers live in
# interactive/controls.jl (static).
#
# The loader of THIS file is `_ensure_live!`, not `_ensure_gl!`.
# Parsing and compiling it costs 0.37 s, and only a preview needs it — a
# render process that paid for it would be buying a playhead it would never
# move.
#
# Model: a PLAYHEAD going forward, DETERMINISTIC REPLAY going back.
#   · `construct` runs ONCE, as a coroutine: `Scene.frame_hook` parks it at
#     the end of every frame and the live loop feeds it frame by frame —
#     ManimGL's incremental loop (scene.py: progress_through_animations),
#     with a parking brake. Forward playback is O(1) per frame. (Re-simulating
#     the WHOLE construct per displayed frame would be O(total) per tick —
#     11.9 s/tick on an updater lesson — and previews would crawl.)
#   · Going BACK is exact replay: any jump behind the playhead rebuilds it
#     from t=0 (skip-draw, no GPU until the target). The frame is a function
#     of its NUMBER, never of how you got there.
#   · The navigation map (animation starts, checkpoints, total) GROWS
#     with the playhead instead of being known at tick 1: a forward hop to
#     a landmark that has not materialised yet PLAYS to it.
#   · The USER's camera (mouse, a port of ManimGL's window controls) lives
#     apart and is COMPOSED over the scene's camera: if the scene never
#     touches its camera, you are in charge; if it does, your deltas go on
#     top. `r` resets. Touching it rebuilds the playhead (the deltas are
#     composed at scene birth).
#   · Visited frames are CACHED (index → image, capped by bytes) —
#     scrubbing backwards is instantaneous. The cache is invalidated when
#     the file is edited (mtime) or when the camera moves.
#   · Revise: each scene file is tracked with includet INTO ITS OWN MODULE
#     (`_LIVE_MODS`) — two files both defining `construct` in Main would
#     fight over one method table, and the loser's preview would show the
#     winner's scene. Every tick calls revise() (6 µs when nothing changed)
#     and the edited scene shows up without restarting. Everything is invoked
#     through invokelatest (world age).

using StaticArrays: SVector

# Revise is loaded LAZILY (only when the live window is set up): loading it
# with `using` would cost ~2 s of TTFX to EVERY Janim user (measured:
# 0.95→3.05 s) and to every render_parallel subprocess. Base.require +
# invokelatest.
const _REVISE = Ref{Module}()
function _revise_mod()
    if !isassigned(_REVISE)
        _REVISE[] = Base.require(Base.PkgId(
            Base.UUID("295af30f-e4ad-537b-8983-00126c2a3abe"), "Revise"))
    end
    return _REVISE[]
end

# ── the live state ─────────────────────────────────────────────────────

# Each scene file gets its OWN module, created once per path and kept
# (Revise needs the module rooted). Sharing Main would leave ONE method slot:
# previewing A and then B, both defining `construct(scene)`, B's window would
# play A's scene.
const _LIVE_MODS = Dict{String,Module}()

"The playhead's way out of a running `construct`. Never reaches the user."
struct _LiveAbort <: Exception end

"""
`construct`, running ONCE as a coroutine. `Scene.frame_hook` parks
the task at the end of every simulated frame; the live loop orders frames one
at a time through `step` and hears back through `ready`. `@async` is the
point, not a convenience: it is STICKY to the spawning thread, so the task's
GPU calls and the loop's stay on one thread, serialized by the handshake — the
one-render-thread invariant holds by construction.
"""
mutable struct Playhead
    scene::Scene
    task::Any
    step::Channel{Int}                  # loop → construct: 1 = one more frame, -1 = die
    ready::Channel{Tuple{Bool,Int}}     # construct → loop: (ended?, frames so far)
    idx::Int                            # frames the simulation has completed
    parked::Bool                        # the task waits in `step` for an order
    finished::Bool
    total::Int                          # 0 until construct ends
    error::Any                          # the scene's own exception, surfaced later
    ucam::Any                           # the user camera composed at birth —
end                                     # a drag applies to ∘ ucam⁻¹ to the parked
                                        # camera instead of rebuilding O(idx)

mutable struct Live
    path::String
    name::Symbol                        # which function of `path` this
                                        # session previews (:construct default)
    fps::Int
    resolution::Tuple{Int,Int}
    window::Any
    rv::Any
    ctrl::Controls
    idx::Int                            # current frame (1-based)
    mtime::Float64
    world::UInt                         # construct's newest method world —
                                        # cache/playhead belong to a WORLD, not
                                        # an mtime (Revise applies a tick late)
    pool::Vector{Array{UInt8,3}}        # recycled frame slots. A cache
                                        # that GROWS big arrays every tick drove
                                        # Julia's FULL collections (~150 ms
                                        # pauses, the periodic preview lag);
                                        # stable recycled slots do not.
    cache::Dict{Int,Array{UInt8,3}}     # capped by _trim_cache!
    hits::Int                           # cache hits (verifiable)
    construct::Any
    # The map. It GROWS as the playhead advances.
    anim_starts::Vector{Int}
    marks::Vector{Tuple{String,Int}}    # (checkpoint label, frame)
    total::Int                          # frames the scene lasts (0 = not known yet)
    mod::Module                         # the scene's own namespace
    abort::Function                     # polled between frames (daemon hangup)
    ph::Union{Nothing,Playhead}         # the parked construct, if one is alive
    progress::Any                       # a RenderProgress shared by every
end                                     # playhead (its high-water mark is
                                        # what stops rebuilds re-narrating)

# The navigation-by-landmark helpers (`_hop_to`, `_anim_at`, `_mark_at`) live
# in interactive/controls.jl: they are arithmetic over a vector of frame
# numbers, and loading them with the preview would make a render process
# compile them for nothing — and anything wanting to exercise the navigation
# rules would have to open a window first.

"""
    live_status(v) → String

Where you are, in words — the window's title bar. Separate from `live` so it
can be checked without opening a window.
"""
function _live_status_gl(v::Live)
    n = length(v.anim_starts)
    k = _anim_at(v.anim_starts, v.idx)
    s = "Janim · frame $(v.idx)" * (v.total > 0 ? "/$(v.total)" : "")
    n > 0 && (s *= " · animation $k/$n")
    m = _mark_at(v.marks, v.idx)
    m === nothing || (s *= " · $m")
    return s * (v.ctrl.paused ? " ⏸" : " ▶")
end

"""
    setup_live(path; fps=30, resolution=(1280,720), visible=false, samples=0)
        → Live

Prepares the live window over `path` (which defines `construct(scene)` — or
over an address `file.jl:name` naming another scene function of the
file): tracks it with Revise and leaves the state ready for `live_step!`.
`live` is the loop with GLFW events on top of this. `samples=4` turns on MSAA
for the session — the rv is built with it and every Scene the loop makes
borrows that rv, so the preview shows the same softened hard geometry a
render with `--samples 4` would write.
"""
function _setup_live_gl(path::String; fps::Int = 30,
                     resolution::Tuple{Int,Int} = (1280, 720),
                     visible::Bool = false, samples::Int = 0)
    R = _revise_mod()
    # `path` may be an ADDRESS (`file.jl:scene_name`): split before any
    # filesystem call sees it — abspath of the whole address is a non-path.
    fpath, name = Janim._scene_address(path)
    p = abspath(fpath)
    # One module per PATH — deliberately not per (path, name): the module is
    # the FILE's namespace, every scene the file defines lives in it, and
    # Revise tracks the file into it once. Keying it by scene would duplicate
    # the namespace per scene and track the same file twice for nothing. The
    # caches that must see the name (this session's frames, the playhead) are
    # per-Live, and the Live carries the name.
    mod = get!(_LIVE_MODS, p) do
        m = Module(Symbol(:JanimLive_, length(_LIVE_MODS) + 1))
        # The ambience of Main: scripts previewed there can use Janim's names
        # without a `using` of their own.
        Base.eval(m, :(using Janim))
        m
    end
    Base.invokelatest(R.includet, mod, p)
    # The session's rv carries the MSAA; every Scene the loop builds
    # borrows it, and reads `rv.samples` back for its on-demand compositor.
    # A window without an API (with its surface when it is visible)
    # and the session's VM on the process's GPU
    window = create_window(resolution...; title = "Janim (live)", visible)
    rv = setup_render_vm(_shared_gpu(), resolution...; samples)
    fn = Janim._scene_fn(mod, name, p)     # fails naming file + symbol
    v = Live(p, Symbol(name), fps, resolution, window, rv, Controls(),
             0, mtime(p), _construct_world(fn), Array{UInt8,3}[],
             Dict{Int,Array{UInt8,3}}(), 0, fn,
             Int[], Tuple{String,Int}[], 0, mod, () -> false, nothing,
             nothing)
    # The WHOLE frame budget is allocated here, once, and recycled
    # forever. Growing it lazily would make the GC pacer fire a FULL collection
    # (~150 ms, measured) every few dozen ticks of a first preview while the
    # cache climbed to its cap; pre-growing puts that cost inside setup —
    # already hidden behind the first tick's JIT — and the deliberate GC.gc()
    # resets the pacer at the new heap level, so ticks only ever churn the
    # young generation (~5 ms, invisible at 30 fps).
    for _ in 1:_cache_cap(v)
        push!(v.pool, Array{UInt8}(undef, 3, resolution...))
    end
    GC.gc()
    return v
end

"A frame slot: recycled from the pool, or (rarely) a fresh allocation."
function _pool_take!(v::Live)
    isempty(v.pool) && return Array{UInt8}(undef, 3, v.resolution...)
    return pop!(v.pool)
end

"Recycle every cached frame into the pool and empty the cache."
function _recycle_cache!(v::Live)
    for a in values(v.cache)
        push!(v.pool, a)
    end
    empty!(v.cache)
    return nothing
end

"The newest world any of `construct`'s methods was defined in."
_construct_world(fn) = maximum(UInt(m.primary_world) for m in methods(fn))

"""
Simulates the scene up to frame `idx` from t=0 and returns ONLY that frame
(skip-draw capture + the user's deltas). Not the per-tick path — the playhead
is. This stays as the REFERENCE the playhead must agree with: the same frame,
byte for byte, as `render_frame`.
"""
function _simulate(v::Live, idx::Int)
    scene = Scene(; fps = v.fps, resolution = v.resolution,
                context = (v.window, v.rv), samples = v.rv.samples)
    compose_camera!(scene.camera, v.ctrl.camera)
    scene.capture_t = (idx - 0.5) / v.fps
    try
        Base.invokelatest(v.construct, scene)
        # The map, for free. This call ran the whole `construct` to draw
        # ONE frame, so by now the scene knows where every animation began and
        # where every checkpoint sits. Nothing extra is simulated for it.
        v.anim_starts = scene.anim_starts
        v.marks = scene.checkpoint_frames
        v.total = scene.frames
        if scene.capture_img === nothing          # idx beyond the end
            draw_scene!(scene.rv, scene.mobjects, scene.camera; flip_y = true)
            scene.capture_img = read_rgb_topdown(scene.rv)
        end
        return scene.capture_img
    finally
        close(scene)                              # borrowed context: not destroyed
    end
end

# ── the playhead machinery ─────────────────────────────────────────────

"Start `construct` as a parked coroutine over a fresh scene (no draws)."
function _playhead_start(v::Live)
    scene = Scene(; fps = v.fps, resolution = v.resolution,
                  context = (v.window, v.rv), progress = v.progress,
                  samples = v.rv.samples)
    compose_camera!(scene.camera, v.ctrl.camera)
    ph = Playhead(scene, nothing, Channel{Int}(1), Channel{Tuple{Bool,Int}}(2),
                  0, false, false, 0, nothing,
                  user_cam_snapshot(v.ctrl.camera))
    # The handshake. `ready` has room for 2 on purpose: one frame
    # announcement plus the final (true, …) from the task's `finally`, so
    # that put! can never deadlock against a loop that stopped listening.
    scene.frame_hook = function (sc)
        put!(ph.ready, (false, sc.frames))
        take!(ph.step) == -1 && throw(_LiveAbort())
        return nothing
    end
    fn = v.construct
    ph.task = @async begin
        try
            Base.invokelatest(fn, scene)
        catch e
            # _LiveAbort is ours; a closed channel means the loop tore the
            # playhead down mid-frame. Anything else is the SCENE's own bug,
            # kept to be rethrown to the caller.
            e isa _LiveAbort || e isa InvalidStateException || (ph.error = e)
        finally
            try
                put!(ph.ready, (true, scene.frames))
            catch
            end
        end
    end
    return ph
end

"""
Advance the playhead to frame `target` (or the scene's end). Control returns
to this loop after EVERY simulated frame — that is what keeps the keys and
the client hangup alive during a long seek.
"""
function _playhead_advance!(v::Live, ph::Playhead, target::Int)
    while !ph.finished && ph.idx < target
        if ph.parked
            put!(ph.step, 1)
            ph.parked = false
        end
        ended, f = take!(ph.ready)
        ph.idx = f
        if ended
            ph.finished = true
            ph.total = f
        else
            ph.parked = true
            # Events fire inside this poll, and the mouse handlers act
            # on the COMPOSED frame — refresh what the delta is composing
            # with first. During a seek the scene may be animating its own
            # camera, so this also keeps a mid-seek drag on the live base.
            _refresh_scene_base!(v.ctrl, ph.scene.camera, ph.ucam)
            v.window === nothing || GLFW.PollEvents()
            (v.abort() || v.ctrl.quit) && break
        end
    end
    return ph
end

"Tear the playhead down: order the task to die, drain, close, free the scene."
function _playhead_close(ph::Playhead)
    try
        while !ph.finished
            if ph.parked
                put!(ph.step, -1)
                ph.parked = false
            end
            ended, _ = take!(ph.ready)
            ended ? (ph.finished = true) : (ph.parked = true)
        end
    catch
    end
    try close(ph.step) catch end
    try close(ph.ready) catch end
    ph.task === nothing || (try wait(ph.task) catch end)
    ph.scene.frame_hook = nothing
    try close(ph.scene) catch end       # borrowed context: the window survives
    return nothing
end

function _invalidate_playhead!(v::Live)
    v.ph === nothing && return nothing
    _playhead_close(v.ph)
    v.ph = nothing
    return nothing
end

"""
The frame `target`, via the playhead. Behind it (or after an error): rebuild
from t=0 — the exact rewind, paid per JUMP rather than per tick. At or
ahead of it: advance and draw. The draw happens from the LOOP while the task
is parked: the mobjects hold exactly frame `idx`'s state, so this is the
same picture `_advance!` would have captured — `render_frame`'s, byte for
byte.
"""
function _frame_via_playhead!(v::Live, target::Int)
    ph = v.ph
    if ph === nothing || target < ph.idx || ph.error !== nothing
        _invalidate_playhead!(v)
        ph = v.ph = _playhead_start(v)
    end
    _playhead_advance!(v, ph, target)
    ph.error === nothing || throw(ph.error)
    _draw_frame!(ph.scene)
    return read_rgb_topdown!(ph.scene.rv, _pool_take!(v))
end

"""
The next landmark of `kind` (:anim | :mark) strictly beyond frame `beyond` —
PLAYING the scene forward until one materialises, because the map only knows
what the playhead has reached. Runs to the end without finding one: stays
put, which keeps the invariant that a forward hop never decreases the frame.
"""
function _seek_landmark!(v::Live, kind::Symbol, beyond::Int)
    ph = v.ph
    if ph === nothing || ph.error !== nothing
        _invalidate_playhead!(v)
        ph = v.ph = _playhead_start(v)
    end
    landmark() = begin
        ms = kind === :anim ? ph.scene.anim_starts :
             [f for (_, f) in ph.scene.checkpoint_frames]
        i = findfirst(m -> m > beyond, ms)
        i === nothing ? nothing : ms[i]
    end
    while true
        l = landmark()
        l === nothing || return l
        ph.finished && return beyond
        _playhead_advance!(v, ph, ph.idx + 1)
        (v.abort() || v.ctrl.quit) && return beyond
    end
end

"Forward hops, unit by unit: known landmarks first, the playhead for the rest."
function _hop_forward!(v::Live, kind::Symbol, n::Int)
    cur = v.idx
    for _ in 1:n
        known = kind === :anim ? v.anim_starts : [f for (_, f) in v.marks]
        i = findfirst(m -> m > cur, known)
        nxt = i === nothing ? _seek_landmark!(v, kind, cur) : known[i]
        nxt == cur && break             # nothing ahead at all: stay
        cur = nxt
        _refresh_map!(v)                # the seek may have grown the map
    end
    return cur
end

"""
The navigation map, read off the playhead's scene as it grows — MONOTONE.
A rebuilt playhead (any backward jump) starts with a shorter map than the one
already learned; landmarks are deterministic, so the map only ever advances.
Shrinking here would empty `marks` after a rewind and silently disarm
stop-at-checkpoints. Only an EDIT resets it (in `live_step!`): new
code may genuinely have different landmarks.
"""
function _refresh_map!(v::Live)
    ph = v.ph
    ph === nothing && return nothing
    s = ph.scene
    length(s.anim_starts) > length(v.anim_starts) && (v.anim_starts = s.anim_starts)
    length(s.checkpoint_frames) > length(v.marks) && (v.marks = s.checkpoint_frames)
    ph.finished && ph.total > 0 && (v.total = ph.total)
    return nothing
end

# The frame cache, bounded: ~500 MB of frames, evicting whatever sits farthest
# from the playhead — unbounded, a long 720p session would grow gigabytes.
#
# The floor is 8 frames (what the ,/. step-back needs), not 60: a floor of 60
# would OVERRIDE the budget above 1080p — a 4K preview would hold
# 60 × 24.9 MB = 1493 MB against the 500 promised, and the pool below
# pre-grows to the cap so the bill would be paid up front.
# With 8: 720p keeps 180 frames and 1080p keeps 80, 1440p drops to 45 and 4K
# to 20 — the budget HOLDS through 4K. A scrub past the cache is never wrong,
# only slower: backward jumps re-simulate.
_cache_cap(resolution::Tuple{Int,Int}) =
    max(8, 500_000_000 ÷ (3 * prod(resolution)))
_cache_cap(v::Live) = _cache_cap(v.resolution)

function _trim_cache!(v::Live)
    cap = _cache_cap(v)
    while length(v.cache) > cap
        far = argmax(k -> abs(k - v.idx), collect(keys(v.cache)))
        push!(v.pool, v.cache[far])     # recycle, never free (GC pauses)
        delete!(v.cache, far)
    end
    return nothing
end

"""
    live_step!(v) → image 3×W×H

One tick of the live loop: revise() (hot reload), advance/pause/scrub, and
the frame from the frame cache, from the playhead (forward), or by rebuilding
it (backward). The framebuffer is left ready for `present!`.

The returned array is a RECYCLED cache slot: treat it as valid
until the frame leaves the cache (an edit, a camera move, or eviction) and
`copy` it if you need it longer — allocating a fresh ~3 MB frame per tick
would feed Julia's full collections and their ~150 ms periodic pauses.
"""
function _live_step_gl(v::Live)
    Base.invokelatest(_revise_mod().revise)
    # The session's own scene name. If an edit DELETES the function this
    # throws UndefVarError, which `_live_tick!` catches — the session freezes
    # on the error banner and watches the file, same as any other broken edit.
    v.construct = Base.invokelatest(getfield, v.mod, v.name)

    v.mtime = mtime(v.path)                     # kept for the loop's frozen watch
    # Invalidate on the WORLD, not the mtime. Revise applies an edit a
    # tick late; gating on mtime would rebuild cache and playhead with the OLD
    # code under the NEW mtime — a poisoned state a paused session never leaves.
    # The world of `construct`'s newest method only moves when the new code
    # is really in, so the rebuild below always runs the edit.
    w = _construct_world(v.construct)
    if w != v.world                             # edited: the scene changed
        v.world = w
        _recycle_cache!(v)
        _invalidate_playhead!(v)                # rebuilt lazily, with new code
        v.anim_starts = Int[]                   # the NEW code's landmarks may
        v.marks = Tuple{String,Int}[]           # differ: relearn the map
        v.total = 0
        v.progress === nothing ||               # …and narrate them again
            (v.progress.seen = 0; v.progress.cur = 0)
    end
    if v.ctrl.touched                           # the user's camera changed
        v.ctrl.touched = false
        _recycle_cache!(v)                      # the frames belonged to the old view
        if v.ph === nothing || v.ph.error !== nothing
            _invalidate_playhead!(v)            # next build composes at birth
        else
            # A drag does not rebuild the playhead (that would be O(idx) per
            # drag tick). The deltas form a group, so re-expressing
            # them on the PARKED camera (to ∘ from⁻¹ on top) equals the
            # rebuild exactly for scenes that do not animate their own
            # camera; the normal draw below then shows the new view in O(1).
            # Any backward jump still recomposes from birth (the reference).
            apply_user_delta!(v.ph.scene.camera, v.ph.ucam, v.ctrl.camera)
            v.ph.ucam = user_cam_snapshot(v.ctrl.camera)
        end
    end

    # advance / pause / step / scrub / hop
    if :left in v.ctrl.keys_down
        v.ctrl.scrub -= v.fps                   # 1 s back
        delete!(v.ctrl.keys_down, :left)
    end
    if :right in v.ctrl.keys_down
        v.ctrl.scrub += v.fps
        delete!(v.ctrl.keys_down, :right)
    end
    advanced = false                            # only a PLAYING tick
    if v.ctrl.home
        v.idx = 1
        v.ctrl.home = false
    elseif v.ctrl.hop_anims != 0                # [ ] by animation
        # Forward hops may PLAY to a landmark not yet on the map.
        v.idx = v.ctrl.hop_anims > 0 ? _hop_forward!(v, :anim, v.ctrl.hop_anims) :
                _hop_to(v.anim_starts, v.idx, v.ctrl.hop_anims)
        v.ctrl.hop_anims = 0
    elseif v.ctrl.hop_marks != 0                # PgUp/PgDn by checkpoint
        v.idx = v.ctrl.hop_marks > 0 ? _hop_forward!(v, :mark, v.ctrl.hop_marks) :
                _hop_to([f for (_, f) in v.marks], v.idx, v.ctrl.hop_marks)
        v.ctrl.hop_marks = 0
    elseif v.ctrl.scrub != 0
        v.idx = max(1, v.idx + v.ctrl.scrub)
        v.ctrl.scrub = 0
    elseif v.ctrl.paused
        v.idx = max(1, v.idx + v.ctrl.steps)
        v.ctrl.steps = 0
    else
        # playing. Once the film is over, hold the LAST frame instead of
        # counting into the void.
        if v.total > 0 && v.idx >= v.total
            v.idx = v.total
        else
            v.idx += 1
        end
        advanced = true
    end

    # Stop at a checkpoint, and only when PLAYING into it. Gated on
    # `advanced` so that resuming with space does not re-trigger at the frame
    # we just stopped on, and so that jumping TO a checkpoint on purpose is
    # not treated as arriving at one.
    if advanced && v.ctrl.stop_at_marks && any(f == v.idx for (_, f) in v.marks)
        v.ctrl.paused = true
    end

    img = get(v.cache, v.idx, nothing)
    if img === nothing
        img = _frame_via_playhead!(v, v.idx)
        v.cache[v.idx] = img
        _trim_cache!(v)
    else
        v.hits += 1
        # present! blits the scene target, and a tick served from cache would
        # never redraw it — a backward scrub would show the last MISS until
        # the next one. Leave the HIT in the framebuffer too.
        _blit_image!(v.rv, img)
    end
    _refresh_map!(v)
    # The mouse handlers act on the COMPOSED frame (ManimGL's model): keep
    # the pair they compose with in step with the parked camera — at tick
    # END, so a playhead rebuilt above is already reflected when present!'s
    # poll fires the next events. With no playhead (frozen, or invalidated
    # this very tick) the last known base stays: a one-tick transient.
    v.ph === nothing || _refresh_scene_base!(v.ctrl, v.ph.scene.camera, v.ph.ucam)
    return img
end

# ── the preview that does not die ──────────────────────────────────────

"""
One guarded tick: `(img, nothing)` on success, `(nothing, err)` when the
scene (or a broken edit) threw. Interrupt still propagates — Ctrl-C is a
way out, not an error. The loop uses this to FREEZE instead of dying;
`live_step!` itself keeps throwing (tests and tools want the exception).
"""
function _live_tick!(v::Live)
    try
        return _live_step_gl(v), nothing
    catch e
        e isa InterruptException && rethrow()
        return nothing, e
    end
end

"""
The frozen frame — the last good picture under a dim veil, a banner
with the error, and what the session is waiting for. Drawn with the live
convention (flip_y) straight into the scene target, so `present!` shows it as-is.
"""
function _error_overlay!(v::Live, err, base)
    W, H = v.resolution
    cam = Camera(width = W, height = H)
    fw, fh = cam.frame_width, cam.frame_height
    mobs = Any[]
    if base !== nothing
        rgba = Array{UInt8}(undef, 4, size(base, 2), size(base, 3))
        rgba[1:3, :, :] .= base
        rgba[4, :, :] .= 0xff
        push!(mobs, ImageMobject(rgba; height = fh))
        veil = Rectangle(width = fw, height = fh)
        set_stroke!(veil; opacity = 0)
        set_fill!(veil; color = "#000000", opacity = 0.45)
        push!(mobs, veil)
    end
    banner = Rectangle(width = fw, height = 2.1)
    set_stroke!(banner; opacity = 0)
    set_fill!(banner; color = "#121216", opacity = 0.85)
    to_edge!(banner, UP; buff = 0.0)
    push!(mobs, banner)
    head = TextMobject("The scene threw — frozen at the last good frame";
                       size = 0.4, color = "#FF6B6B")
    to_edge!(head, UP; buff = 0.22)
    push!(mobs, head)
    msg = err === nothing ? "unknown error" : sprint(showerror, err)
    prev = head
    for line in first(split(msg, '\n'), 2)
        s = strip(line)
        isempty(s) && continue
        length(s) > 110 && (s = first(s, 107) * "…")
        t = TextMobject(String(s); size = 0.27, color = "#DDDDDD")
        next_to!(t, prev, DOWN; buff = 0.14)
        push!(mobs, t)
        prev = t
    end
    foot = TextMobject("watching $(basename(v.path)) — save a fix to resume · Esc/q quits";
                       size = 0.3, color = "#9AA5B1")
    next_to!(foot, prev, DOWN; buff = 0.18)
    push!(mobs, foot)
    draw_scene!(v.rv, mobs, cam; flip_y = true)
    return nothing
end

"""
Freeze the window on `err`. The overlay is built with the engine's own text
stack; if even that throws (an exotic environment), fall back to the plain
last-good frame — the window must survive anything the scene does.
"""
function _freeze_frame!(v::Live, err, base)
    try
        _error_overlay!(v, err, base)
    catch
        base === nothing || _blit_image!(v.rv, base)
    end
    return nothing
end

"""
The timeline — a bottom strip with the played fill, one tick per
animation start and one gold mark per checkpoint, drawn INTO the frame's
target AFTER the frame was cached: mp4 renders, `render_frame` and the frame
cache never contain it (live-only pixels). This computes the segments;
the backend paints them (`_paint_strip!`: one `writeTexture` into the
target) — no shader, no geometry, deterministic by construction.
"""
function _draw_timeline!(v::Live)
    W, H = v.resolution
    total = v.total > 0 ? v.total :
            (v.ph === nothing ? v.idx : max(v.ph.idx, v.idx))
    total <= 0 && return nothing
    bar = max(4, H ÷ 90)
    segs = Tuple{Int,Int,Float64,Float64,Float64}[]
    seg(x0, x1, r, g, b) = begin
        x0 = clamp(x0, 0, W); x1 = clamp(x1, 0, W)
        x1 > x0 && push!(segs, (x0, x1, r, g, b))
        return nothing
    end
    seg(0, W, 0.10, 0.10, 0.12)                                   # track
    seg(0, round(Int, W * clamp(v.idx / total, 0, 1)),
        0.345, 0.769, 0.867)                                      # played (#58C4DD)
    for f in v.anim_starts                                        # act starts
        x = round(Int, W * (f - 1) / total)
        seg(x, x + 2, 0.62, 0.62, 0.66)
    end
    for (_, f) in v.marks                                         # checkpoints
        x = round(Int, W * (f - 1) / total)
        seg(x, x + 3, 1.0, 0.823, 0.369)                          # #FFD25E
    end
    _paint_strip!(v.rv, W, H, bar, segs)
    return nothing
end

"""
    live(path; fps=30, resolution=(1280,720), stop_at_checkpoints=false,
         max_seconds=Inf, abort=() -> false, samples=0)

The complete interactive loop: a visible window, mouse (drag=pan, `d`+move=
rotate, `f`+move=pan, wheel=zoom about the cursor), `r`=reset, space=pause,
`.`/`,`=frame by frame, ←/→=scrub ±1 s with cache. Editing `path` in your
editor reloads the scene WITHOUT restarting (Revise).

Leaving is ManimGL's way: **Esc or `q`**, at any moment — the window's close
button and a Ctrl-C in the terminal work too. `abort` is polled once per tick;
the daemon passes a closure that flips when its CLI client hangs up, which is
what turns a Ctrl-C in the terminal into the daemon's window closing.

Navigation is by MEANING instead of by seconds: `[`/`]` jump to the
previous/next animation, `PgUp`/`PgDn` to the previous/next `checkpoint!`,
`Home` back to the first frame, and `c` toggles stopping automatically at
checkpoints (`stop_at_checkpoints=true` starts with it on). All of them
pause, because the point of landing on a frame is to look at it.

**Forward is incremental, backward is exact**: `construct` runs once
as a coroutine and playback feeds it frame by frame — ManimGL's loop, O(1)
per frame. Any jump BACKWARD rebuilds that coroutine from t=0, so rewinding
cannot desynchronise the state from the picture — not even with integrators.
It deliberately does NOT resume from checkpoint snapshots, which would be
faster: a snapshot restores geometry, but a script's closures are rebuilt
from scratch, so a stateful updater would resume with the wrong velocity.

**The window does not die**: when the scene throws — or an edit stops
compiling — the session FREEZES on the last good frame with the error on
top and keeps watching the file; save a fix and it resumes alone, with the
map and cache relearned. Dragging the camera redraws the parked state in
O(1) instead of rebuilding the playhead (exact for scenes that do not
animate their own camera; a backward jump always recomposes from birth).
A timeline strip at the bottom shows the played range, one tick per
animation and a gold mark per checkpoint — live-only pixels: mp4 renders,
`render_frame` and the frame cache never contain them.

`samples=4` turns on the same MSAA a render would use, so what you
preview is what `--samples 4` will write.
"""
function _live_gl(path::String; fps::Int = 30, resolution::Tuple{Int,Int} = (1280, 720),
               stop_at_checkpoints::Bool = false, max_seconds::Real = Inf,
               abort::Function = () -> false, progress = :auto,
               samples::Int = 0)
    v = _setup_live_gl(path; fps, resolution, visible = true, samples)
    v.ctrl.stop_at_marks = stop_at_checkpoints
    v.abort = abort                     # seen BETWEEN FRAMES, even mid-seek
    # The bar narrates the FIRST pass through each animation (cold preview:
    # the terminal under the window; warm preview: streamed to the client).
    v.progress = progress === :auto ? _auto_progress(true) : progress
    W, H = resolution
    ppu() = v.ctrl.camera.frame_width / W       # pixel → user units (scroll)
    # Mouse DELTAS travel in FIXED-frame units — ManimGL's `coords`, the
    # nominal frame over the window, blind to any zoom. The handlers put the
    # zoom (and the composed rotation) back only where ManimGL does: in the pan.
    ppu_fix = FRAME_HEIGHT_DEF / H

    # The delta tracker starts UNSEEDED and re-seeds on every
    # re-entry: leave the window and come back, and the first event would
    # otherwise carry the whole journey as one delta — with `d` held that
    # is several radians in one tick, φ slammed into its clamps (the
    # frontal-plane snap) and the view teleported. cursor_delta! owns the
    # hygiene (seed events return nothing, warps inside the window are
    # capped); this callback only converts and dispatches.
    last_cursor = Ref((0.0, 0.0))
    cursor_seed = Ref(true)
    GLFW.SetCursorEnterCallback(v.window, (win, entered) -> begin
        entered && (cursor_seed[] = true)
        return nothing
    end)
    GLFW.SetCursorPosCallback(v.window, (win, x, y) -> begin
        dp = cursor_delta!(last_cursor, cursor_seed, x, y)
        dp === nothing && return
        d = (dp[1] * ppu_fix, -dp[2] * ppu_fix, 0.0)
        v.ctrl.dragging ? mouse_drag!(v.ctrl, d) : mouse_move!(v.ctrl, d)
    end)
    GLFW.SetMouseButtonCallback(v.window, (win, button, action, mods) ->
        (v.ctrl.dragging = action == GLFW.PRESS))
    GLFW.SetScrollCallback(v.window, (win, dx, dy) -> begin
        x, y = last_cursor[]
        point = ((x - W / 2) * ppu(), (H / 2 - y) * ppu(), 0.0)
        scroll!(v.ctrl, point, -dy * 2, H)      # one notch ≈ 2 px (factor ~0.95)
    end)
    key_map = Dict(GLFW.KEY_D => :d, GLFW.KEY_F => :f, GLFW.KEY_R => :r,
                      GLFW.KEY_SPACE => :space, GLFW.KEY_PERIOD => :period,
                      GLFW.KEY_COMMA => :comma, GLFW.KEY_LEFT => :left,
                      GLFW.KEY_RIGHT => :right,
                      # navigation by landmark
                      GLFW.KEY_LEFT_BRACKET => :bracket_left,
                      GLFW.KEY_RIGHT_BRACKET => :bracket_right,
                      GLFW.KEY_PAGE_UP => :page_up,
                      GLFW.KEY_PAGE_DOWN => :page_down,
                      GLFW.KEY_HOME => :home, GLFW.KEY_C => :c,
                      GLFW.KEY_ESCAPE => :escape, GLFW.KEY_Q => :q)
    GLFW.SetKeyCallback(v.window, (win, key, scancode, action, mods) -> begin
        haskey(key_map, key) || return
        s = key_map[key]
        action == GLFW.PRESS && key_press!(v.ctrl, s)
        action == GLFW.RELEASE && release!(v.ctrl, s)
    end)

    t0 = time()
    title = ""
    last_good = nothing
    frozen = nothing                    # the exception that froze the session
    frozen_mtime = 0.0
    try
        while !GLFW.WindowShouldClose(v.window) && !v.ctrl.quit && !abort() &&
              time() - t0 < max_seconds
            t_mark = time()
            if frozen === nothing
                img, err = _live_tick!(v)
                if err === nothing
                    last_good = img
                    _draw_timeline!(v)          # after the cache: live-only pixels
                else
                    # The scene broke (or the edit does not compile): freeze
                    # on the last good frame with the error on top and WATCH
                    # the file instead of letting the window die.
                    frozen = err
                    frozen_mtime = mtime(v.path)
                    _invalidate_playhead!(v)    # no per-tick rebuild grind
                    _freeze_frame!(v, err, last_good)
                    @warn "the scene threw — frozen; watching $(basename(v.path))" exception = err
                end
            else
                GLFW.PollEvents()               # Esc/q and the close button stay alive
                # keep Revise chewing (a broken file makes it throw: still broken)
                try
                    Base.invokelatest(_revise_mod().revise)
                catch
                end
                w = try
                    _construct_world(Base.invokelatest(getfield, v.mod, v.name))
                catch
                    v.world
                end
                # retry on the TRUE signal (the world moved: the fix is in) or
                # on a save (mtime) as belt and braces
                (w != v.world || mtime(v.path) != frozen_mtime) && (frozen = nothing)
            end
            present!(v.rv, v.window)
            # Pace the collector: one young collection per tick costs
            # ~1.5 ms on the pre-grown heap and keeps the pacer from ever
            # escalating to a full collection mid-session (a full is ~150 ms
            # — a periodic first-preview hitch).
            GC.gc(false)
            # Say where you are. Only when it CHANGES: setting the title
            # is a round trip to the display server (X11 or Wayland) and the
            # answer is the same for most ticks.
            s = frozen === nothing ? _live_status_gl(v) :
                "Janim · ERROR — watching $(basename(v.path)) (save to resume)"
            s == title || (GLFW.SetWindowTitle(v.window, s); title = s)
            spare = 1 / v.fps - (time() - t_mark)
            spare > 0 && sleep(spare)
        end
    catch e
        e isa InterruptException || rethrow()   # Ctrl-C is a way out, not an error
    finally
        # Even when the scene throws mid-session: a dead loop must not leak a
        # window — least of all inside the daemon, where nobody could close
        # it — nor a parked construct task grinding in the background.
        _invalidate_playhead!(v)
        _close_render_vm!(v.rv)         # the session's VM goes with the session
        close_context(v.window)
    end
    return v
end
