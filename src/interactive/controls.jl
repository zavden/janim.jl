# interactive/controls.jl — the live window's input state, GLFW-free.
#
# `Controls` and its handlers are pure state + camera math (a port of
# ManimGL's scene.py:738-817), so they load with the package and keep working
# headless. The window plumbing that FEEDS them (GLFW callbacks) lives in
# live.jl, which the lazy loader includes at runtime — see backend/glfw.jl.

# ── navigation by landmark ─────────────────────────────────────────────
#
# Arithmetic over a sorted vector of frame numbers: no window, no GPU, no
# Live. It lives here and not in live.jl because pure logic belongs with the
# package: otherwise every render process would compile it to never call it,
# and the navigation RULES could not be exercised without opening a preview
# first.

"""
    _hop_to(marks, idx, delta) → frame

The landmark `delta` steps away from `idx` along the sorted `marks`.

`-1` is "the largest landmark strictly before `idx`", which from the middle of
an animation lands on **its own** start — the ⏮ of every media player, and it
falls out of the definition instead of needing a rule.

Run out of landmarks and it STAYS PUT. Neither wrapping nor clamping to the
far end will do, and clamping is the one that looks reasonable and is not:
past the last checkpoint, "next checkpoint" would jump you BACKWARDS onto it.
The invariant is worth stating: **a forward hop never decreases the frame and
a backward hop never increases it**.
"""
function _hop_to(marks::Vector{Int}, idx::Int, delta::Int)
    isempty(marks) && return idx
    cur = idx
    for _ in 1:abs(delta)
        i = delta < 0 ? findlast(m -> m < cur, marks) : findfirst(m -> m > cur, marks)
        i === nothing && return cur          # no landmark that way: stay
        cur = marks[i]
    end
    return cur
end

"Which numbered animation frame `idx` falls inside (0 before the first)."
_anim_at(starts::Vector{Int}, idx::Int) = count(<=(idx), starts)

"The last checkpoint at or before `idx`, or `nothing`."
function _mark_at(marks::Vector{Tuple{String,Int}}, idx::Int)
    best = nothing
    for (label, f) in marks
        f <= idx && (best === nothing || f >= best[2]) && (best = (label, f))
    end
    return best === nothing ? nothing : best[1]
end

# ── the controls: a port of ManimGL's scene.py:738-817 ─────────────────

"""
    Controls(; camera, sens_pan3d, sens_scroll, …)

The live window's input state — which keys are down, whether it is paused,
what jump has been requested, and the user's camera DELTAS.

It is deliberately free of any window system: no GLFW, no callbacks, pure state
plus camera arithmetic. The window plumbing feeds it from outside
([`mouse_move!`](@ref), [`mouse_drag!`](@ref), [`scroll!`](@ref),
[`key_press!`](@ref), [`release!`](@ref)), which is what lets it load and work
on a headless machine and be tested without opening anything.

Its `camera` holds what the USER did on top of whatever the scene asked for;
[`compose_camera!`](@ref) applies one to the other, so panning the preview
never edits the scene's own camera. The field is `keys_down`, not `keys`, so it
cannot be confused with the child-key API ([`get_keys`](@ref)).

Key symbols are part of the interface: `:space`, `:comma`, `:period`, `:left`,
`:right`, `:home`.
"""
Base.@kwdef mutable struct Controls
    camera::Camera = Camera()          # the USER's camera (deltas)
    # The parked SCENE camera the deltas compose onto — orientation
    # and scale only. ManimGL's mouse handlers act on the COMPOSED frame (its
    # window and scene share one CameraFrame), so ours must know what the
    # delta is composing with: the rotate increments the composed euler and
    # the pan maps screen deltas through the composed rotation and scale.
    # Identity/1.0 — a scene that never touched its camera — makes every
    # formula collapse to the plain user delta. The live loop refreshes the
    # pair each tick (`_refresh_scene_base!`); it stays plain state, no window.
    scene_orientation::Quat = quat_identity()
    scene_scale::Float64 = 1.0
    keys_down::Set{Symbol} = Set{Symbol}()
    dragging::Bool = false
    paused::Bool = false
    steps::Int = 0                     # frame-steps requested with `.`
    scrub::Int = 0                     # requested jump (frames, ±)
    sens_pan3d::Float64 = 0.5          # ManimGL's pan_sensitivity
    sens_scroll::Float64 = 20.0        # ManimGL's scroll_sensitivity
    touched::Bool = false              # deltas ≠ identity? (invalidates cache)
    # Navigation by MEANING rather than by seconds. `hop` is a pending
    # jump expressed in steps of a landmark (±1 animation, ±1 checkpoint);
    # it is resolved in `live_step!`, where the map is known.
    hop_anims::Int = 0
    hop_marks::Int = 0
    home::Bool = false                 # jump back to frame 1
    stop_at_marks::Bool = false        # pause on reaching a checkpoint
    quit::Bool = false                 # Esc/q asked to leave the session
end

# ── the composed frame, which is the one ManimGL's handlers act on ─────
# ManimGL has ONE CameraFrame per session; Janim keeps the user's deltas apart
# so the preview never edits the scene's own camera (compose_camera!).
# These four bridge the two models: the composed orientation/scale for the
# handlers, and the re-derivation that stores a handler's result back as a
# pure delta — so the delta group (apply_user_delta!) never notices.

"""
    cursor_delta!(last, reseed, x, y; cap = 150.0) → (dx, dy) | nothing

Window-side delta hygiene. The cursor callback derives deltas as
`position − last position`, and that subtraction LIES twice: on the very
first event (`last` was never real) and on every RE-ENTRY — leave the
window, come back, and the first event carries the whole journey as one
delta (measured live under sway: dx=−670, dy=−309 px in ONE event, which
with `d` held is several radians: φ slammed into its 0/π clamps and the
view teleported). `nothing` means "this event seeds the tracker, there is
no motion to apply". The `cap` is the belt for a pointer WARPED while
inside the window (no leave/enter fires): real events arrive at compositor
granularity and stay small — ~50 px is a violent human fling — so 150 px
passes every real gesture and bounds a teleport.
"""
function cursor_delta!(last::Base.RefValue, reseed::Base.RefValue{Bool},
                       x::Real, y::Real; cap::Real = 150.0)
    if reseed[]
        reseed[] = false
        last[] = (Float64(x), Float64(y))
        return nothing
    end
    dx, dy = Float64(x) - last[][1], Float64(y) - last[][2]
    last[] = (Float64(x), Float64(y))
    return (clamp(dx, -cap, cap), clamp(dy, -cap, cap))
end

"The composed (user ∘ scene) orientation — ManimGL's actual frame."
_composed_orientation(ctrl::Controls) =
    quat_mul(ctrl.camera.orientation, ctrl.scene_orientation)

"The composed scale (compose_camera! multiplies frame heights)."
_composed_scale(ctrl::Controls) = get_scale(ctrl.camera) * ctrl.scene_scale

"Store a new COMPOSED orientation as the user delta that produces it.
Renormalised: this is one seam of the event↔tick product CYCLE."
_set_composed_orientation!(ctrl::Controls, q::Quat) =
    (ctrl.camera.orientation =
        quat_normalize(quat_mul(q, quat_conj(ctrl.scene_orientation))); ctrl)

"""
    _refresh_scene_base!(ctrl, composed, ucam)

Feeds the pair the handlers need from what the delta group already keeps: the
parked camera is ALREADY composed (scene ∘ the `ucam` snapshot), so the pure
scene part is `ucam⁻¹ ∘ composed`. The live loop calls this once per tick,
before the window's events are polled.
"""
function _refresh_scene_base!(ctrl::Controls, composed::Camera, ucam)
    # renormalised: the other seam of the event↔tick cycle — one ulp
    # of drift here compounded to the ZERO quaternion in ~80 rounds, measured
    ctrl.scene_orientation = quat_normalize(quat_mul(quat_conj(ucam.orientation),
                                                     composed.orientation))
    ctrl.scene_scale = get_scale(composed) /
                       (ucam.frame_height / FRAME_HEIGHT_DEF)
    return ctrl
end

"ManimGL's `from_fixed_frame_point(d, relative=true)`: screen → world = R·(s·d)."
_world_delta(ctrl::Controls, d) =
    quat_to_matrix(_composed_orientation(ctrl)) * (d .* _composed_scale(ctrl))

"""
on_mouse_motion (scene.py:738): `d` rotates, `f` pans. `d_point` arrives in
FIXED-frame units — pixels × nominal-frame/window, ManimGL's `coords`, blind
to any zoom.

The rotate is ManimGL's to the letter: its window maps the screen delta
world-ward (`from_fixed_frame_point`) only for the handler to map it straight
back (`to_fixed_frame_point`) — the round trip cancels rotation AND scale
(measured: max |Δ| = 2.8e-17), so the real semantics are a TURNTABLE in
screen units, `dθ = −sens·dx, dφ = +sens·dy`, applied to the COMPOSED
frame's euler angles with ManimGL's φ clamp. Incrementing the USER delta's
own euler instead would be wrong, since a left-composition of two zxz
triples is not a euler sum: 30 horizontal events at φ₀ = 70° would grow
γ = 7.24° of roll (ManimGL: 0, the horizon never rolls) and push φ past the
vertical.

The pan is the one place the world mapping is REAL — a pan follows the
view plane — so it multiplies by the composed rotation and scale.
"""
function mouse_move!(ctrl::Controls, d_point)
    d = SVector{3,Float64}(d_point[1], d_point[2], length(d_point) > 2 ? d_point[3] : 0.0)
    if :d in ctrl.keys_down
        ff = d .* ctrl.sens_pan3d
        e = euler_zxz_from_quat(_composed_orientation(ctrl))
        _set_composed_orientation!(ctrl, quat_from_euler_zxz(
            e[1] - ff[1],
            clamp(e[2] + ff[2], 0.0, Float64(PI)),
            e[3]))
        ctrl.touched = true
    elseif :f in ctrl.keys_down
        ctrl.camera.center_point = Point3f(SVector{3,Float64}(ctrl.camera.center_point) -
                                           _world_delta(ctrl, d))
        ctrl.touched = true
    end
    return ctrl
end

"on_mouse_drag (scene.py:762): dragging pans (ManimGL's drag_to_pan, same map)."
function mouse_drag!(ctrl::Controls, d_point)
    d = SVector{3,Float64}(d_point[1], d_point[2], length(d_point) > 2 ? d_point[3] : 0.0)
    ctrl.camera.center_point = Point3f(SVector{3,Float64}(ctrl.camera.center_point) -
                                       _world_delta(ctrl, d))
    ctrl.touched = true
    return ctrl
end

"on_mouse_scroll (scene.py:801): zooms about the cursor's point."
function scroll!(ctrl::Controls, point, dy_pixels::Real, height_pixels::Real)
    factor = 1 - ctrl.sens_scroll * dy_pixels / height_pixels
    scale_frame!(ctrl.camera, factor; about = point)
    ctrl.touched = true
    return ctrl
end

"on_key_press (scene.py:829) + the playback controls."
function key_press!(ctrl::Controls, key::Symbol)
    if key == :r                       # reset (ManimGL: to_default_state)
        reset_camera!(ctrl.camera)
        ctrl.touched = true            # the cache belonged to the old camera
    elseif key == :space
        ctrl.paused = !ctrl.paused
    elseif key == :period              # frame by frame (paused)
        ctrl.paused = true
        ctrl.steps += 1
    elseif key == :comma
        ctrl.paused = true
        ctrl.steps -= 1
    elseif key == :left                # scrub 1 s (resolved in live_step!)
        push!(ctrl.keys_down, :left)
    elseif key == :right
        push!(ctrl.keys_down, :right)
    # ── jumps by landmark. They PAUSE, because the point of landing on
    # an animation's first frame is to look at it; playing straight through
    # would make the jump invisible.
    elseif key == :bracket_left
        ctrl.hop_anims -= 1; ctrl.paused = true
    elseif key == :bracket_right
        ctrl.hop_anims += 1; ctrl.paused = true
    elseif key == :page_up
        ctrl.hop_marks -= 1; ctrl.paused = true
    elseif key == :page_down
        ctrl.hop_marks += 1; ctrl.paused = true
    elseif key == :home
        ctrl.home = true; ctrl.paused = true
    elseif key == :c
        ctrl.stop_at_marks = !ctrl.stop_at_marks
    elseif key == :escape || key == :q
        # ManimGL's exits, at any moment. A command, not a modifier: it must
        # NOT land in keys_down, where a held `q` would mean nothing.
        ctrl.quit = true
    else
        push!(ctrl.keys_down, key)
    end
    return ctrl
end

"""
    release!(ctrl, key)

Record that `key` came back up — the counterpart of [`key_press!`](@ref).

It matters because some keys are MODIFIERS while held: `d` turns dragging into
a 3D rotation and `f` into a pan, so a release that is never reported leaves
the window stuck in that mode.
"""
release!(ctrl::Controls, key::Symbol) = (delete!(ctrl.keys_down, key); ctrl)

"Composes the user's deltas ON TOP OF the scene's camera."
function compose_camera!(cam_scene::Camera, u::Camera)
    cam_scene.orientation = quat_normalize(quat_mul(u.orientation,
                                                    cam_scene.orientation))
    cam_scene.center_point = Point3f(SVector{3,Float64}(cam_scene.center_point) +
                                SVector{3,Float64}(u.center_point))
    zoom = u.frame_height / FRAME_HEIGHT_DEF
    cam_scene.frame_height *= zoom
    cam_scene.frame_width *= zoom
    return cam_scene
end

"The user camera's state, snapshotted at composition time."
user_cam_snapshot(u::Camera) =
    (orientation = u.orientation, center = u.center_point,
     frame_height = u.frame_height)

"""
Re-express the user's deltas on an ALREADY-composed camera — the group
quotient `to ∘ from⁻¹` applied on top. Because compose_camera! is a group
action (quaternion product, center sum, size scale), this equals recomposing
from birth EXACTLY whenever the scene does not animate its own camera — the
common case, and what lets a drag redraw the parked playhead in O(1) instead
of rebuilding O(idx). Scenes that do animate their camera drift only until
the next rebuild (any backward jump), which always recomposes from birth.
"""
function apply_user_delta!(cam_scene::Camera, from, to::Camera)
    # normalised: the parked camera sits inside the event↔tick
    # product cycle, and it is also the long-session accumulator
    cam_scene.orientation = quat_normalize(
        quat_mul(to.orientation, quat_mul(quat_conj(from.orientation),
                                          cam_scene.orientation)))
    cam_scene.center_point = Point3f(SVector{3,Float64}(cam_scene.center_point) +
        SVector{3,Float64}(to.center_point) - SVector{3,Float64}(from.center))
    z = to.frame_height / from.frame_height
    cam_scene.frame_height *= z
    cam_scene.frame_width *= z
    return cam_scene
end
