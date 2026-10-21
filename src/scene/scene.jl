# Scene — the game loop.
#
# The same Scene runs with two sinks, without forking the renderer:
#   · mp4 through FramePipeline (FIXED dt = 1/fps: deterministic production)
#   · a GLFW window (preview): with an output it shows what is being written;
#     without one, REAL dt — ManimGL's actual game loop
# plus the first two agent hooks:
#   · render_frame(construct, t) → headless image/PNG
#   · describe(scene) → a stable textual tree

using PNGFiles
using Printf
using Colors: RGBA                  # the alpha branch of save_png

mutable struct Scene
    camera::Camera
    fps::Int
    mobjects::Vector{Mobject}
    t::Float64
    frames::Int
    last_alphas::Vector{Float64}
    window::Any                 # a GLFW window for a preview; `nothing` for a render to a file
    preview::Bool
    rv::Any                     # GPURenderVM
    pipeline::Union{Nothing,FramePipeline}
    capture_t::Union{Nothing,Float64}
    capture_img::Union{Nothing,Array{UInt8,3}}
    capture_txt::Union{Nothing,String}   # describe(construct, t) reads it
    frame_range::Union{Nothing,UnitRange{Int}}   # only draw/encode these frames
    # The animation range. `anim_index` is which numbered animation we
    # are on — `wait!` counts, because in Manim a wait IS an animation and the
    # numbering has to be TOTAL for "the slice" to mean anything. `anim_range`
    # gates the DRAWING exactly like `frame_range` does, which is the whole
    # design: the simulation is untouched, so determinism holds and the result
    # is byte-identical to the same frames of the full render.
    anim_index::Int
    anim_range::Union{Nothing,UnitRange{Int}}
    # The map the preview navigates by. Both are filled by ANY run, so
    # `live`'s per-frame re-simulation gets them for free — it already runs the
    # whole `construct` to draw one frame. `anim_starts[k]` is the frame
    # animation k begins on; `checkpoint_frames` pairs each label with the
    # frame that follows it.
    anim_starts::Vector{Int}
    checkpoint_frames::Vector{Tuple{String,Int}}
    borrowed::Bool                        # someone else's window and VM (do not destroy)
    closed::Bool
    composition::Union{Nothing,Composition}   # the scene AS a composition
    cg::Any                                   # GPUCompositor (when there is a composition)
    # The camera as an animatable mobject. It is a VIEW onto `camera`, not
    # a copy, so `animate(scene.frame, …)` moves the camera this scene renders
    # with — ManimGL's `self.frame.animate.scale(0.5)` idiom.
    frame::CameraFrame
    # Checkpoints. `scene_path` is the script this scene came from — the
    # snapshot store is keyed by it; "" when the scene was built by hand.
    scene_path::String
    # Which function of that script this scene is. The snapshot store is
    # keyed by it too: two scenes of one file may reuse a checkpoint label, and
    # a snapshot served across scenes is a valid video of the WRONG scene.
    scene_name::String
    skip_until::Union{Nothing,String}   # the label we are fast-forwarding to
    skipping::Bool                      # currently in no-op mode
    # Audio: (path, start second, gain in dB). The mp4 is written
    # by the video pipeline as always; the sound is muxed in at close.
    sounds::Vector{Tuple{String,Float64,Float64}}
    # Motion blur: there is no in-loop blur. The fields exist so the CLI, the
    # daemon and the farm keep their protocol, and the constructor refuses
    # `motion_blur > 1` by name. `render_frame_motion` accumulates sub-frames
    # on the CPU and is the way to a blurred frame.
    motion_blur::Int
    shutter::Float64
    # The live playhead's per-frame hook. Called at the END of every
    # `_advance!`, drawn or not. The live window parks `construct` here
    # between frames (a coroutine handshake), which makes forward playback
    # O(1) per tick instead of an O(total) replay — and it is where an abort
    # lands INSIDE a running simulation instead of after it.
    frame_hook::Any
    # The CE-style per-animation bar (scene/progress.jl), or nothing. Writes
    # to stderr or the daemon's socket — never into the render.
    progress::Any
    # Alpha output. Set once at construction; it decides the camera's
    # clear alpha, the readback width (3 or 4 channels) and the encoder.
    transparent::Bool
    # MSAA for hard geometry (manimlib's `samples`; its 3D scenes use 4).
    # 0 is the default (4 samples, the fill's own antialiasing), 1 the aliased
    # control. Kept on the Scene because `use_composition!` builds the
    # compositor lazily and must know it.
    samples::Int
end

"The live mobjects of a composition (content, precomps, masks — and the
layers' cameras and windows, so their updaters run too)."
function _mobjects_of(comp::Composition)
    mobs = _content_mobjects(comp)
    _view_extras!(mobs, comp)
    return mobs
end

function _content_mobjects(comp::Composition)
    mobs = Mobject[]
    for layer in comp.layers
        if layer.content isa Composition
            append!(mobs, _content_mobjects(layer.content))
        elseif layer.content isa Vector
            append!(mobs, layer.content)
        end
        layer.mask === nothing || append!(mobs, layer.mask.content)
    end
    return mobs
end

# GUARDED, unlike the lists above: the window rect is usually also in some
# content list (drawn as the display's border), and _update_all! does not
# deduplicate — without the guard its updater would run twice per frame.
function _view_extras!(mobs::Vector{Mobject}, comp::Composition)
    for layer in comp.layers
        layer.content isa Composition && _view_extras!(mobs, layer.content)
        for extra in (layer.camera, layer.window)
            extra === nothing && continue
            extra in mobs || push!(mobs, extra)
        end
    end
    return mobs
end

"""
    Scene(; output=nothing, preview=false, fps=60, resolution=(1920,1080),
            crf=23, preset="medium", encoder_threads=nothing)

`encoder_threads` is x264's thread count: `nothing` (the default) lets it pick
its own, `1` pins it. The FRAMES are deterministic either way; the mp4
CONTAINER is bit-identical run to run only as a property of one thread count
on one machine — measured 10 of 10 identical at 1080p60 with the default,
and a single thread at 4.3× the wall time (24 s → 104 s), which is why the
default stays multithreaded and `render_parallel` pins 1.

`motion_blur` is not supported in the loop: the kwarg is accepted at its
default `1` so the CLI, the daemon and the farm keep their protocol, and any
other value is refused by name. [`render_frame_motion`](@ref) averages
sub-frames on the CPU for a blurred still.

`anim_range=3:5` turns on the animation range (the CLI's `-n 3,5`): only
the frames belonging to animations 3 to 5 are drawn and encoded. The scene is
still simulated in FULL — that is what makes the result byte-identical to
those same frames of the whole video, and it is why `-n` saves the drawing and
the encoding but not the simulation. To skip the simulation too, use a
checkpoint (`--from label`).

`samples` is the multisampling of the scene target. The default 0 renders
with the fill's own 4× resolve, `1` is the aliased control, and `4` is
manimlib's `ThreeDScene` value. It matters on HARD geometry: surface
silhouettes and image edges, because strokes and dots already antialias in
their shaders.

`output="x.mp4"` writes through the mp4 pipeline (fixed dt); its directory is
created if it does not exist (ManimGL's `guarantee_existence`), and an
output that still cannot be written fails by name instead of hanging the
render. `preview=true` opens the window (with an output it mirrors what is
written; without one it runs on real dt). Neither: headless (verification,
render_frame). Usable as a do-block: `Scene(output="x.mp4") do scene … end`
closes itself.
"""
function Scene(; output::Union{Nothing,String} = nothing, preview::Bool = false,
               fps::Int = 60, resolution::Tuple{Int,Int} = (1920, 1080),
               crf::Int = 23, preset::String = "medium",
               encoder_threads::Union{Nothing,Int} = nothing,
               composition::Union{Nothing,Composition} = nothing,
               motion_blur::Int = 1, shutter::Real = 0.5,
               anim_range::Union{Nothing,UnitRange{Int}} = nothing,
               context = nothing,   # (window, rv) borrowed from the live loop
               progress = :auto,    # :auto = bar on stderr iff it is a TTY
               transparent::Bool = false,   # alpha channel out (ProRes 4444)
               samples::Int = 0)    # MSAA (0 = default 4×; 1 = aliased; 4 = manimlib's 3D)
    width, height = resolution
    prog = progress === :auto  ? _auto_progress(output !== nothing) :
           progress === true   ? RenderProgress(stderr) :
           progress === false  ? nothing : progress
    # `transparent` makes the camera clear to alpha 0 instead of opaque
    # black. Everything downstream already handles it: the compositor has
    # always worked in premultiplied alpha, and `Composition`'s own background
    # was transparent by default from the start ("precomp-friendly").
    cam = transparent ? Camera(; width, height, background = (0f0, 0f0, 0f0, 0f0)) :
                        Camera(; width, height)
    # There is no in-loop motion blur: `render_frame_motion` accumulates
    # sub-frames on the CPU.
    motion_blur > 1 && error("motion_blur = $motion_blur: in-loop motion blur is not supported; render_frame_motion(construct, t; n) averages sub-frames on the CPU for a blurred still")
    if context === nothing
        # ONE GPU per process (`_shared_gpu`: the daemon serves
        # `janim frame` without creating a device per request), a VM of
        # the scene's own on it, and a window ONLY for a preview — a
        # render to a file opens no window at all
        gpu = _shared_gpu()
        window = preview ? create_window(width, height; title = "Janim", visible = true) : nothing
        rv = setup_render_vm(gpu, width, height; samples)
    else
        window, rv = context      # the live loop's window and VM (borrowed)
        gpu = rv.gpu
    end
    # The directory is created BEFORE the encoder opens the file —
    # ManimGL's `guarantee_existence` (scene_file_writer.py:99), CE's too.
    # Without it an output whose directory does not exist would kill the
    # encoder task without a word and hang the render on its seventh frame;
    # what still cannot be opened fails by name through the pipeline's own
    # check.
    output === nothing || _guarantee_output_dir(output)
    pipeline = output === nothing ? nothing :
               _open_pipeline(rv, output; fps, crf, preset, encoder_threads, transparent)
    cg = composition === nothing ? nothing : setup_compositor(gpu, width, height; samples)
    return Scene(cam, fps, Mobject[], 0.0, 0, Float64[], window, preview,
                 rv, pipeline, nothing, nothing, nothing, nothing, 0, anim_range,
                 Int[], Tuple{String,Int}[],
                 context !== nothing,
                 false, composition, cg, CameraFrame(cam), "", "construct",
                 nothing, false,
                 Tuple{String,Float64,Float64}[],
                 max(motion_blur, 1), Float64(shutter), nothing, prog,
                 transparent, samples)
end

"""
    _guarantee_output_dir(path) → path

`mkpath` of the file's directory, which is ManimGL's
`guarantee_existence` (`Path.mkdir(parents=True, exist_ok=True)`):
`Scene(output = "renders/x.mp4")` does not need `renders/` to exist, and
the still a scene with no animations writes (`x.png`, same directory) finds
it too. A bare file name has no directory and needs nothing.
"""
function _guarantee_output_dir(path::AbstractString)
    dir = dirname(path)
    isempty(dir) && return path
    try
        mkpath(dir)
    catch err
        # `mkpath` under a FILE says «file already exists» about the file,
        # which explains nothing: name the output and the directory
        throw(ArgumentError("output = $(repr(path)): its directory $(repr(dir)) " *
                            "cannot be created ($(sprint(showerror, err)))"))
    end
    return path
end

"""
The mp4 pipeline of a render VM: the `FramePipeline` copies the VM's
target one frame behind. The Scene opens its own through this, and so does
anything that drives a VM by hand.
"""
_open_pipeline(rv::GPURenderVM, path::String; fps::Int = 60, crf::Int = 23, preset::String = "medium",
               encoder_threads::Union{Nothing,Int} = nothing, transparent::Bool = false) =
    FramePipeline(rv.gpu, rv.target, path; fps, crf, preset, encoder_threads, transparent)

function Scene(f::Function; kw...)
    scene = Scene(; kw...)
    try
        f(scene)
    finally
        close(scene)
    end
    return scene
end

"""
    add!(scene, mobs...; recurse = true)

Put mobjects on the stage — with ManimGL's semantics (`scene.py:331`):
`add` is `remove` followed by an append, so what arrives
never ends up drawn twice. Its family leaves the root list first (a group
that held part of it is replaced, in place, by its remaining children) and
then it goes on TOP of everything.

`_stage_list` is the only thing touched: under a composition the layers keep
their content, because there the roots are just what `play!` registers.

`recurse = false` appends if absent and leaves every group whole.
"""
function add!(scene::Scene, mobs::Mobject...; recurse::Bool = true)
    isempty(mobs) && return scene
    if !recurse
        for m in mobs
            m in scene.mobjects || push!(scene.mobjects, m)
        end
        return scene
    end
    _add_gl!(scene.mobjects, mobs)
    return scene
end
_stage_list(scene::Scene) = scene.mobjects

"""
    use_composition!(scene, comp)

Mount a composition FROM construct(scene) — this way a scene with a
compositor lives in an ordinary file and works with render_parallel and the
live window (both of which build the Scene for you).
"""
function use_composition!(scene::Scene, comp::Composition)
    scene.composition = comp
    scene.cg === nothing &&
        (scene.cg = _setup_compositor_for(scene.rv, scene.camera.width, scene.camera.height;
                                          samples = scene.samples))
    return scene
end

"""
    remove!(scene, mobs...)

Take mobjects off the stage — with ManimGL's semantics (scene.py:374):
the whole family of each leaves, and a root that CONTAINED one of them is
replaced, in its place, by its remaining children (ungrouped). And since the
compositor is part of the scene, a mobject a `Layer` or a `Mask` drew
leaves that list too, precomps included — what a `FadeOut` fades is gone,
wherever it lived. With `recurse = false` only the roots named leave, no
group is ungrouped and no layer is touched.
"""
function remove!(scene::Scene, mobs::Mobject...; recurse::Bool = true)
    isempty(mobs) && return scene
    if !recurse
        filter!(x -> !any(m -> m === x, mobs), scene.mobjects)
        return scene
    end
    gone = _family_set(mobs)
    _remove_from_list!(scene.mobjects, gone)
    scene.composition === nothing || _remove_from_composition!(scene.composition, gone)
    return scene
end

function _remove_from_composition!(comp::Composition, gone::IdDict{Mobject,Nothing})
    for layer in comp.layers
        if layer.content isa Composition
            _remove_from_composition!(layer.content, gone)
        elseif layer.content isa Vector
            _remove_from_list!(layer.content, gone)
        end
        layer.mask === nothing || _remove_from_list!(layer.mask.content, gone)
    end
    return comp
end

# Put `new` where `old` stood: inside the layer that drew it — a
# composition does not draw the roots, so ReplacementTransform,
# TransformMatchingTex and FadeTransform of a layered mobject end with the
# target IN the layer — or, without one, among the roots (ManimGL's remove+add).
function _stage_replace!(scene::Scene, old::Mobject, new::Mobject)
    if scene.composition !== nothing && _replace_in_composition!(scene.composition, old, new)
        remove!(scene, old)                  # its root entry too, if play! made one
        return scene
    end
    remove!(scene, old)
    add!(scene, new)
    return scene
end

function _replace_in_composition!(comp::Composition, old::Mobject, new::Mobject)
    done = false
    for layer in comp.layers
        if layer.content isa Composition
            done |= _replace_in_composition!(layer.content, old, new)
        elseif layer.content isa Vector
            done |= _replace_in_list!(layer.content, old, new)
        end
        layer.mask === nothing || (done |= _replace_in_list!(layer.mask.content, old, new))
    end
    return done
end

# ── draw order ─────────────────────────────────────────────────────────
# The scene draws its list in order, so ordering is reordering. The sort is
# STABLE and only happens when someone actually set a z-index: a scene that
# never touches it allocates nothing and draws in list order.
#
# And a list draws each mobject ONCE. The compositor shares this
# function (`_content!`: a layer's list, a mask's), and a layer holds what the
# user passed: `Layer(a, a)` painted `a` twice (a red square at α 0.6, centre
# (233, 90, 78) against Layer(a)'s (201, 77, 66)). The first occurrence wins,
# by identity, BEFORE the sort. The scene's
# roots are already unique (`_add_gl!`): there the scan finds nothing, nothing
# is copied and the unique z = 0 list still allocates 0 bytes. The list itself
# is never modified.

function _draw_order(mobs)
    u = _has_duplicate(mobs) ? _unique_first(mobs) : mobs
    return any(m -> get_z_index(m) != 0, u) ? _by_z(u) : u
end

"Whether `mobs` lists a mobject twice, by identity: a pairwise scan up to 64 entries (no allocation on the per-frame path), an `IdDict` above."
function _has_duplicate(mobs)
    n = length(mobs)
    if n <= 64
        for j in 2:n
            mj = mobs[j]
            for i in 1:(j - 1)
                mobs[i] === mj && return true
            end
        end
        return false
    end
    seen = IdDict{Any,Nothing}()
    for m in mobs
        haskey(seen, m) && return true
        seen[m] = nothing
    end
    return false
end

"A new list of the same type with each mobject of `mobs` at its FIRST occurrence, by identity, in order; `mobs` is not touched."
function _unique_first(mobs)
    out = empty(mobs)
    seen = IdDict{Any,Nothing}()
    for m in mobs
        haskey(seen, m) && continue
        seen[m] = nothing
        push!(out, m)
    end
    return out
end

# CAREFUL, and it costs a frame to get wrong: `bring_to_front!`/`bring_to_back!`
# reorder `scene.mobjects`, which is the UPDATE order as well as the draw
# order. Sending a `TracedPath` to the back therefore makes it sample the
# previous frame's position and lag one frame behind what it follows (measured:
# 0.618 scene units, exactly one frame of travel).
# `set_z_index!` changes only the drawing and has no such effect — prefer it
# for anything whose updater reads another mobject's state.

"""
    bring_to_front!(scene, mobs...)

Draw `mobs` last (on top of everything else in the scene). ManimGL's
`bring_to_front` IS `add` (`scene.py:392-394`), and so is this one: the
family of each mobject leaves the root list first — a group that
held it is replaced, in place, by its remaining children — and then it goes
on top. A child of a group on stage therefore leaves that group's root entry
and its siblings stay as roots; the group itself is not modified. What is not
on stage yet is added.

Also moves it LAST in the update order. Use `set_z_index!` instead when the
mobject's updater reads state that another updater writes.
"""
function bring_to_front!(scene::Scene, mobs::Mobject...)
    return add!(scene, mobs...)
end

"""
    bring_to_back!(scene, mobs...)

Draw `mobs` first (underneath everything else in the scene). ManimGL's
`bring_to_back` is `remove` followed by prepending the list as given
(`scene.py:397-400`), and so is this one: the family of each
mobject leaves the root list — a group that held it is replaced, in place, by
its remaining children — and then they go FIRST, in the order given. The
compositor's layers are not touched (the rule `add!` follows). What is
not on stage yet is added, underneath.

Also moves it FIRST in the update order, so its updater now runs before
everything else's. That is what puts a `TracedPath` one frame behind the thing
it traces — `set_z_index!(m, -1)` puts it behind visually without touching the
updaters.
"""
function bring_to_back!(scene::Scene, mobs::Mobject...)
    isempty(mobs) && return scene
    _prepend_gl!(scene.mobjects, mobs)
    return scene
end

# ── sound ──────────────────────────────────────────────────────────────

"""
    add_sound(scene, path; time_offset=0.0, time=nothing, gain=0.0)

Queue an audio file to play `time_offset` seconds from NOW — wherever the
scene's clock has got to. `gain` is in dB. The tracks are mixed into the mp4
when the scene closes, so nothing about the render loop changes: video stays
deterministic and the audio is a mux at the end.

Three things follow ManimGL:

  * **`time_offset` is RELATIVE** (`scene.py:656`: `self.get_time() +
    time_offset`), which is what makes a sound survive an edit upstream of
    it. `time = t` is still here and is still the ABSOLUTE instant, for a
    cue that belongs to the clock rather than to the moment.
  * **The extension is resolved** the way ManimGL's `find_file` does, trying
    `.wav` and `.mp3` — `add_sound(scene, "clap")` finds `clap.wav`.
  * **The video is not cut** to the last sound (a `-shortest` mux would cut
    it: a 0.4 s cue at the end of a 17 s scene would take seven seconds of
    animation with it). The mux asks for exactly the scene's own duration.

Needs an `output=` mp4; on a headless render with no output it is ignored
with a warning, because there is nowhere to put it.
"""
function add_sound(scene::Scene, path::AbstractString; time_offset::Real = 0.0,
                   time = nothing, gain::Real = 0.0)
    file = _resolve_sound(path)
    at = time === nothing ? scene.t + Float64(time_offset) : Float64(time)
    at >= 0 || throw(ArgumentError(
        "a sound cannot start before the scene does (got $at s)"))
    push!(scene.sounds, (abspath(file), at, Float64(gain)))
    return scene
end

"ManimGL's `find_file` extension list, minus the search path Janim has no config for."
function _resolve_sound(path::AbstractString)
    isfile(path) && return String(path)
    for ext in (".wav", ".mp3")
        cand = string(path, ext)
        isfile(cand) && return cand
    end
    throw(ArgumentError("there is no sound file at «$path» " *
                        "(tried it as given, plus .wav and .mp3)"))
end

"""
The still a video path becomes when the scene turns out to have no
animations: the same path with a `.png` extension. `out.mp4` → `out.png`, and
`out.mov` → `out.png` as well (an RGBA one, since the alpha survives).
"""
_still_path(video::AbstractString) = string(splitext(video)[1], ".png")

"""
Manim's rule, ported: a scene that never advanced its clock has no video to
write, so it is written as a STILL instead of as an empty container.

`scene.frames` is the right question to ask, and it has to be asked AFTER
`construct` has run. It counts SIMULATED frames — `_advance!` increments it
above the `should_draw` gate — so it is zero exactly when nothing ever called
`play!` or `wait!`, and it is NOT zero when `-n`, `--from`/`--to` or a
frame range merely selected nothing to draw. That distinction is the whole
point: an empty selection is a mistake the user should see, while a scene with
no animations is a picture they asked for without saying so.

Without it such a scene would produce a 262-byte mp4 with ZERO streams — a
valid container holding nothing, written without a word of warning.
"""
function _write_still!(scene::Scene)
    still = _still_path(scene.pipeline.path)
    try
        _draw_frame!(scene)                  # composition-aware, like render_frame
        save_png(still, scene.transparent ? read_rgba_topdown(scene.rv) :
                                            read_rgb_topdown(scene.rv))
    finally
        # The encoder comes down WHATEVER happened above. It has eaten nothing
        # — no frame was ever enqueued, so `close_pipeline!` has nothing to
        # drain — and leaving it open behind a failed still would strand an
        # ffmpeg process. It goes in a `finally` rather than simply first
        # because the drawing has to happen while the pipeline's readback
        # buffers are still alive.
        close_pipeline!(scene.pipeline)
        rm(scene.pipeline.path; force = true)    # and the empty container goes
    end
    @info "the scene has no animations, so it was written as a still" still
    return still
end

"""
Close the pipeline (drain and wait for the encoder), release the VM and the
window. A scene with no animations writes a still instead of a video — see
[`_write_still!`](@ref); ask `_still_path(output)` for the path it took.
"""
function Base.close(scene::Scene)
    scene.closed && return scene
    scene.closed = true          # first, so a close that throws is not retried on released objects
    out = scene.pipeline === nothing ? nothing : scene.pipeline.path
    still = false
    try
        if scene.pipeline !== nothing
            if scene.frames == 0
                out, still = _write_still!(scene), true
            else
                close_pipeline!(scene.pipeline)
            end
        end
    finally
        # The GPU comes down WHATEVER the encoder did. A pipeline whose
        # file could not be written throws here (by name), and without this
        # `finally` the VM and the window would stay behind it — one leaked VM
        # per failed render in the daemon, which serves many scenes a process.
        _close_compositor!(scene.cg)                    # the compositor is the Scene's OWN, borrowed VM or not
        scene.borrowed || _close_render_vm!(scene.rv)   # wgpu releases its objects before the device
        scene.borrowed || close_context(scene.window)   # the live loop owns it
    end
    # Behind an inference barrier — `_mux_sounds!` builds an ffmpeg filter graph
    # with string interpolation that costs ~31 ms to infer, and a scene with
    # no sound (all of them, nearly always) never runs a line of it. Once per
    # scene close, so the dispatch is free.
    if !isempty(scene.sounds)
        # A still carries no time, so there is nowhere to put the audio. Saying
        # so is the honest answer: `_mux_sounds!` would hand ffmpeg a PNG as
        # the video input and fail with a codec error that explains nothing.
        still ? @warn("the scene has no animations, so it was written as a " *
                      "still and its $(length(scene.sounds)) sound(s) were " *
                      "dropped: audio needs a video", out) :
                Base.invokelatest(_mux_sounds!, out, scene.sounds,
                                  scene.frames / scene.fps)
    end
    return scene
end

# ── the frame step ─────────────────────────────────────────────────────

"Updater phase: mobjects whose updaters are all parallel go to @threads."
function _update_all!(scene::Scene, dt::Real)
    parallel_mobs = Mobject[]
    # `unique!` by identity, keeping first-occurrence order. The same
    # world in N layers is the multicam pattern, and without this its
    # updaters ran N times per frame — the same silent trap a mask shared
    # with a content list always had. `scene.mobjects` alone needs no dedup:
    # `add!` refuses duplicates and so does every removal
    # (`_without` keeps a root once) — the list never holds a root twice.
    # As in ManimGL's `update_mobjects`, the ROOT LIST is the
    # snapshot, taken once, and each root's eligibility is read AT ITS TURN.
    # An updater that registers another on a later root (b, from a's tick)
    # runs b in this same frame; a root added during the step waits for the
    # next one, a root removed during it is still on the copy and updates.
    # (A preselected `sequential` list would leave b for the next frame.)
    alive = scene.composition === nothing ? copy(scene.mobjects) :
            unique!(vcat(scene.mobjects, _mobjects_of(scene.composition)))
    for m in alive                           # insertion order, like Manim
        has_updaters(m) || continue
        all_parallel = all(get_family(m)) do sub
            all(u -> u.parallel, get_updaters(sub))   # any Mobject
        end
        all_parallel ? push!(parallel_mobs, m) : update!(m, dt)
    end
    Threads.@threads for m in parallel_mobs  # contract: you only touch YOUR mobject
        update!(m, dt)
    end
    return scene
end

"One draw of the current state into the scene framebuffer."
function _draw_frame!(scene::Scene)
    if scene.composition === nothing
        draw_scene!(scene.rv, _draw_order(scene.mobjects), scene.camera; flip_y = true)
    else
        draw_composition!(scene.rv, scene.cg, scene.composition, scene.camera;
                          flip_y = true, frame = scene.frames)
    end
    return scene
end

"""
    _advance!(scene, dt; alpha_at = nothing)

One frame. `alpha_at(u)` — supplied by `play!` — places the animation at the
fraction `u` of this frame (the hook for an in-loop motion blur, which does
not exist); it is accepted and never called, so `play!` keeps its shape.
"""
function _advance!(scene::Scene, dt::Real; alpha_at = nothing, draw::Bool = true)
    t_prev = scene.t
    scene.t += dt
    scene.frames += 1

    # Four independent gates on the DRAWING, never on the simulation: the
    # single captured frame, the frame range, the animation range and
    # `draw = false`. They AND together because they are the same kind of
    # statement — "this frame does not need to leave the GPU" — and every one
    # of them relies on determinism for the frames that DO get drawn to be
    # identical to the full render's. (`draw = false` is the skipped prefix of
    # `--from` simulating a conditional wait — state only, no GPU.)
    should_draw = draw &&
                  (scene.capture_t === nothing ||
                   (t_prev < scene.capture_t <= scene.t + 1e-12)) &&
                  (scene.frame_range === nothing || scene.frames in scene.frame_range) &&
                  (scene.anim_range === nothing || scene.anim_index in scene.anim_range)

    _update_all!(scene, dt)
    should_draw && _draw_frame!(scene)

    if should_draw
        scene.pipeline === nothing || enqueue!(scene.pipeline)
        if scene.capture_t !== nothing
            scene.capture_img = scene.transparent ? read_rgba_topdown(scene.rv) :
                                                    read_rgb_topdown(scene.rv)
            # describe(construct, t): the TEXT is captured at the same
            # frame as the pixels — describing after construct returns would
            # describe the FINAL state.
            scene.capture_txt = describe(scene)
        end
        scene.preview && present!(scene.rv, scene.window)
    end
    # The playhead's hook: runs for EVERY frame, drawn or skipped —
    # a skipped frame still advanced the state, and the live window needs to
    # be offered control after each one.
    scene.frame_hook === nothing || scene.frame_hook(scene)
    return scene
end

# ── play / wait ────────────────────────────────────────────────────────

"""
    play!(scene::Scene, anims...; run_time=nothing)

With an output (or headless): n frames of fixed dt with α=(k+½)/n.
Preview without an output: a REAL clock — α advances with the midpoint of the
measured dt.

`run_time = T` means **each** of the animations lasts T seconds, as in
ManimGL. For several animations that should share T between
them, keeping their relative windows, group them yourself:
`play!(scene, AnimationGroup(a, b; run_time = T))`.
"""
function play!(scene::Scene, anims::Animation...; run_time = nothing)
    isempty(anims) && throw(ArgumentError(
        "play! without animations — did you mean wait!(scene, seconds)?"))
    # BEFORE the skip branch, so `--from label` and `-n X,Y` compose —
    # the numbering is ABSOLUTE and does not shift because a prefix was
    # skipped. This is also why the counter cannot live in `_advance!`: a
    # skipped animation draws no frames and would never be counted.
    # ManimGL's `play` (`scene.py:579`) hands its `run_time` to
    # every animation through `update_rate_info` (`animation.py:132`), so an
    # explicit `run_time = T` means "each of these lasts T", not "the whole
    # thing lasts T with the windows scaled to fit": a 1 s FadeIn beside a 2 s
    # Write under `run_time = 3` both last 3 s. The proportional form is
    # spelled out — `play!(stage, AnimationGroup(a, b; run_time = T))`, which
    # keeps the proportional windows. Validated BEFORE anything is mutated.
    if run_time !== nothing
        given = _check_duration(run_time, scene.fps, "run_time")
        for a in anims
            a.base.run_time = given
        end
    end
    anim = length(anims) == 1 ? anims[1] : AnimationGroup(anims...)
    # Validate BEFORE reserving anything — the counter bump,
    # the map entry and the roots all come after a duration that made sense.
    rt = _check_duration(get_run_time(anim), scene.fps, "run_time")
    scene.anim_index += 1
    push!(scene.anim_starts, scene.frames + 1)     # the preview's map
    # The LEAF mobjects become roots, never a group's
    # synthetic container — ManimGL adds each one to scene.mobjects
    # separately, and every departure from that had a measured consequence.
    # ManimGL's guard (`scene.py:554`) — only what is NOWHERE on the
    # stage joins it. A leaf that already lives inside a root stays there.
    _add_animated!(scene, (mobject_of(leaf) for leaf in _leaf_animations(anim)))
    begin!(anim)

    # Skip mode: everything before the target checkpoint costs only the
    # construction of its objects. The animation is still begun and finished,
    # so the mobjects land on their final pose and the user's variables stay
    # meaningful; the clock advances arithmetically. What is skipped is what
    # actually costs: the updater loop, the draw and the encode.
    if scene.skipping
        finish!(anim)
        n = max(1, round(Int, rt * scene.fps))
        scene.t += n / scene.fps
        scene.frames += n
        clean_up!(anim, scene)
        return scene
    end

    if scene.pipeline === nothing && scene.preview
        t_local = 0.0                          # REAL dt (ManimGL's game loop)
        clock = time()
        while t_local < rt
            now = time()
            dt = clamp(now - clock, 1e-4, 0.25)
            clock = now
            interpolate!(anim, clamp((t_local + dt / 2) / rt, 0.0, 1.0))
            _advance!(scene, dt)
            t_local += dt
        end
    else
        n = max(1, round(Int, rt * scene.fps))   # FIXED dt (production)
        scene.last_alphas = [(k + 0.5) / n for k in 0:n-1]
        label = string(nameof(typeof(anim)))
        for (j, alpha) in enumerate(scene.last_alphas)
            interpolate!(anim, alpha)
            # `alpha_at` places an exposure inside the frame: u is the
            # fraction of frame j, so α = (j−1+u)/n, and u = ½ gives back
            # exactly `alpha`.
            _advance!(scene, 1 / scene.fps;
                      alpha_at = u -> interpolate!(anim, (j - 1 + u) / n))
            _progress!(scene, label, j, n)
        end
    end

    finish!(anim)
    # The fourth act, ManimGL's clean_up_from_scene: removers, the
    # Transform variants' swap, FadeTransform's restore — one method per
    # animation (animations.jl), the same under a Timeline.
    clean_up!(anim, scene)
    return scene
end

"""
wait!(scene, t): the scene stays alive — updaters and frames, no animation.

It DOES take an animation number: in Manim a wait is a `Wait`
animation, and the numbering has to cover every frame of the video or `-n X,Y`
would leave orphan frames belonging to no numbered step.
"""
function wait!(scene::Scene, t::Real = 1.0; stop_condition = nothing)
    t = _check_duration(t, scene.fps, "wait duration")
    scene.anim_index += 1
    push!(scene.anim_starts, scene.frames + 1)
    if scene.skipping                       # fast-forward, clock only
        n = max(1, round(Int, t * scene.fps))
        if stop_condition === nothing
            scene.t += n / scene.fps
            scene.frames += n
            return scene
        end
        # A CONDITIONAL wait is never skipped — ManimGL passes
        # `override_skip_animations=True` for it (`scene.py:518`), because the
        # condition needs the simulation. The updaters run and the clock moves
        # frame by frame, nothing is drawn or encoded, and the count is the
        # full render's: moving the clock by `max_time` whole (1800 frames for
        # a wait the full render stops after 15) would put the act map after
        # the checkpoint out of step with the video's.
        for _ in 1:n
            _advance!(scene, 1 / scene.fps; draw = false)
            stop_condition() && break
        end
        return scene
    end
    if scene.pipeline === nothing && scene.preview
        t_local = 0.0
        clock = time()
        while t_local < t
            now = time()
            dt = clamp(now - clock, 1e-4, 0.25)
            clock = now
            _advance!(scene, dt)
            t_local += dt
            # the live window honours it too, so `wait_until!` does not become
            # "works in a render, hangs in a preview"
            stop_condition === nothing || (stop_condition() && break)
        end
    else
        n = max(1, round(Int, t * scene.fps))
        for j in 1:n
            _advance!(scene, 1 / scene.fps)
            _progress!(scene, "Wait", j, n)
            # ManimGL emits the frame and THEN asks (`scene.py:618-622`), so the
            # frame in which the condition first holds is part of the video
            # and a condition true from the start still costs one frame.
            stop_condition === nothing || (stop_condition() && break)
        end
    end
    return scene
end

"""
    wait_until!(scene, condition; max_time = 60)

Hold the scene — updaters running, frames going out — until `condition()`
answers `true`, and no longer than `max_time` seconds (`scene.py:630`).

```julia
wait_until!(scene, () -> get_y(ball) < -3)      # until it lands
```

It is [`wait!`](@ref)`(scene, max_time; stop_condition = condition)`, which is
literally what ManimGL's is. The condition is asked once per frame, AFTER the
frame is emitted, so it never skips the moment it describes; `max_time` is what
keeps a condition that never holds from running forever, and 60 s is
ManimGL's default.

**It is still deterministic**: the clock is the frame counter, as in every
other verb here, so the same condition stops on the same frame every run.

**Under `--from` it is not free**: the skipped prefix fast-forwards
an ordinary `wait!` by arithmetic, but a conditional one is SIMULATED —
updaters running, nothing drawn — exactly as ManimGL never skips it
(`override_skip_animations`, `scene.py:518`). That is what keeps the frame
numbering after the checkpoint equal to the full render's.
"""
wait_until!(scene::Scene, condition; max_time::Real = 60.0) =
    wait!(scene, max_time; stop_condition = condition)

# ── agent hooks ────────────────────────────────────────────────────────

"""
Save a 3×width×height image (row 1 on top) as a PNG — or a 4×width×height one
as a PNG WITH ALPHA.

The 4-channel branch un-premultiplies first, for the same reason the video
path does: the engine composites premultiplied, and every viewer and editor
reads a PNG's alpha as straight. Handing it the raw buffer would darken every
partially transparent pixel.
"""
function save_png(path::String, img::Array{UInt8,3})
    W, H = size(img, 2), size(img, 3)
    if size(img, 1) == 4
        bytes = copy(vec(img))               # never mutate the caller's frame
        _unpremultiply!(bytes)
        mat = PermutedDimsArray(reshape(reinterpret(RGBA{N0f8}, bytes), W, H), (2, 1))
        PNGFiles.save(path, mat)
        return path
    end
    mat = PermutedDimsArray(reshape(reinterpret(RGB{N0f8}, vec(img)), W, H), (2, 1))
    PNGFiles.save(path, mat)
    return path
end

"""
    render_frame(construct, t; fps=30, resolution=(854,480), png=nothing)

The agent's closed loop. Runs the scene headless SKIPPING the drawing of
every frame except the one containing `t` (interpolation and updaters do run:
determinism). Returns the 3×W×H image; with `png=` it also writes it. A `t`
beyond the end gives the final state.
"""
function render_frame(construct::Function, t_target::Real;
                      fps::Int = 30, resolution::Tuple{Int,Int} = (854, 480),
                      png::Union{Nothing,String} = nothing,
                      transparent::Bool = false, samples::Int = 0)
    scene = Scene(; fps, resolution, transparent, samples)
    scene.capture_t = max(Float64(t_target), 0.5 / fps)
    try
        construct(scene)
        if scene.capture_img === nothing         # t falls after the end
            # With a compositor the scene's own mobject list is empty (they
            # live in the layers), so a plain draw_scene! fallback would
            # produce a black frame. Compose exactly like _advance! does.
            if scene.composition === nothing
                draw_scene!(scene.rv, _draw_order(scene.mobjects), scene.camera;
                            flip_y = true)
            else
                draw_composition!(scene.rv, scene.cg, scene.composition,
                                  scene.camera; flip_y = true,
                                  frame = scene.frames)
            end
            scene.capture_img = scene.transparent ? read_rgba_topdown(scene.rv) :
                                                    read_rgb_topdown(scene.rv)
        end
        png === nothing || save_png(png, scene.capture_img)
        return scene.capture_img
    finally
        close(scene)
    end
end

"""
    animation_map(construct; fps=30, resolution=(854,480)) → (starts, frames)

The act map, without presenting anything. Runs the scene with every
frame's drawing skipped (the same shortcut render_frame uses for all frames
but one) and returns `scene.anim_starts` — the first frame of each numbered
animation, `wait!` included — plus the total frame count. This is the
preview's map computed without presenting anything; an agent can use it to
pick meaningful frames to look at.

"Without presenting" is not "without a GPU": the scene is simulated by a real
`Scene`, which opens a GPU context on construction — the Mesa line you may
see is that. On a shared GPU, do not run it beside a timing measurement.
"""
function animation_map(construct::Function; fps::Int = 30,
                       resolution::Tuple{Int,Int} = (854, 480))
    scene = Scene(; fps, resolution)
    scene.capture_t = 1.0e9          # beyond any end: simulate all, draw nothing
    try
        construct(scene)
        return copy(scene.anim_starts), scene.frames
    finally
        close(scene)
    end
end

"""
    render_frame_motion(construct, t; n=8, shutter=0.5, fps=30, resolution, png=nothing)

Motion blur by ACCUMULATION — averages n sub-frames inside the shutter
(a fraction of the frame interval, 0.5 = 180°), centred on t (symmetric
sampling). It multiplies one frame's cost by n, a render that has room to
spare. It is the only motion blur: there is none in the loop.
"""
function render_frame_motion(construct::Function, t::Real; n::Int = 8,
                             shutter::Real = 0.5, fps::Int = 30,
                             resolution::Tuple{Int,Int} = (854, 480),
                             png::Union{Nothing,String} = nothing)
    dtf = shutter / fps
    acc = zeros(Float64, 3, resolution...)
    for k in 0:n-1
        tk = t - dtf / 2 + dtf * (k + 0.5) / n
        # An exposure integrates LIGHT — decode each sub-frame, average in
        # linear, encode once.
        frame = render_frame(construct, max(tk, 1e-3); fps, resolution)
        acc .+= srgb_to_linear.(Float64.(frame) ./ 255)
    end
    img = UInt8.(clamp.(round.(Int, 255 .* linear_to_srgb.(acc ./ n)), 0, 255))
    png === nothing || save_png(png, img)
    return img
end

# ── segment rendering across N processes ───────────────────────────────

"""
    render_segment(construct, path; frames, fps=30, resolution=(1280,720))

Runs the WHOLE scene (interpolation and updaters on EVERY frame —
determinism is what makes the slicing valid) but draws and encodes ONLY
`frames` (1-based, inclusive). The resulting mp4 is a segment ready to be
concatenated without re-encoding.

`anim_range` intersects with `frames`: both are gates on the drawing,
so a segment of an animation range is just the two conditions ANDed. Note that
the intersection CAN be empty, which yields an mp4 with no frames — fine when
you asked for it, which is why `render_parallel` refuses the combination
instead (it would silently hand `ffmpeg -f concat` an empty segment).

`transparent` composes for the same reason: `frames` gates the drawing
and the alpha decides what the drawn pixels carry, so a transparent segment is
byte-identical to the same frames of the full transparent render. The output is
then ProRes 4444 in a `.mov`, and the caller owns the extension.
"""
function render_segment(construct::Function, path::String; frames::UnitRange{Int},
                        fps::Int = 30, resolution::Tuple{Int,Int} = (1280, 720),
                        crf::Int = 23, preset::String = "medium",
                        encoder_threads::Union{Nothing,Int} = nothing,
                        motion_blur::Int = 1, shutter::Real = 0.5,
                        anim_range::Union{Nothing,UnitRange{Int}} = nothing,
                        transparent::Bool = false, samples::Int = 0)
    scene = Scene(; output = path, fps, resolution, crf, preset, encoder_threads,
                  motion_blur, shutter, anim_range, transparent, samples)
    scene.frame_range = frames
    try
        construct(scene)
    finally
        close(scene)
    end
    # A scene with NO animations was written as a still, so the caller is told
    # the path that exists. An animated scene whose `frames`/`anim_range`
    # intersection is empty is NOT that case and still gets its empty mp4 —
    # see the note above: there, you asked for it.
    return scene.frames == 0 ? _still_path(path) : path
end

"""
    _scene_address(address) → (path, name)

The one reading of `file.jl:scene_name`, shared by every door (daemon
verbs, `live`, the farm's caller). Split at the LAST `:` and only when what is
left of it ends in `.jl` — so `C:\\path\\x.jl` stays a whole path,
`C:\\path\\x.jl:scene_a` splits at the last colon, and `/p/odd:dir/x.jl`
never splits at all. No suffix (or an empty one) means `construct`, the name
every scene file uses. `bin/janim` carries the same rule in bash
(`_scene_path`/`_scene_suffix`): the client needs the path half for `-o`'s
default and the cfg lookup, while the address travels the protocol whole.
"""
function _scene_address(address::AbstractString)
    s = String(address)
    i = findlast(==(':'), s)
    if i !== nothing
        left = s[1:prevind(s, i)]
        if endswith(left, ".jl")
            name = s[nextind(s, i):end]
            return left, (isempty(name) ? "construct" : name)
        end
    end
    return s, "construct"
end

"""
    _scene_fn(mod, name, path) → the scene function

Resolve scene `name` inside `mod` (where `path` was included), or fail naming
the FILE and the SYMBOL — `getfield`'s bare `UndefVarError` names only the
anonymous module, which tells the user nothing. No candidate list on purpose:
a helper like `style!(m)` is indistinguishable from a scene by signature, so
an enumeration would either lie or guess (which is why there is no
`janim scenes` listing).
"""
function _scene_fn(mod::Module, name::String, path::String)
    sym = Symbol(name)
    isdefined(mod, sym) ||
        error("scene «$name» is not defined by $(basename(path)) — expected " *
              "`function $name(scene) … end` in that file (with no `:$name` " *
              "suffix the name is `construct`)")
    return Base.invokelatest(getfield, mod, sym)
end

"""
    render_parallel(scene_jl, output; n=4, frames_total, fps=30, resolution=(1280,720))

Splits `frames_total` across `n` julia PROCESSES (each with its own GPU
context and its own x264 encoder) and concatenates the segments with `ffmpeg -f concat -c copy` (no re-encoding).
`scene_jl` defines the scene function — `construct(scene)` by default, or the
one `scene_name` picks (the CLI's `file.jl:name`). The scene must be a
pure function of time (no external state): determinism guarantees the
segments fit together.

`encoder_threads=1` by default: the FARM configuration (one single-threaded
x264 per process, scaling ~linearly with n). MEASURED FINDING (16
cores): with x264's default threading a SINGLE process already saturates the
machine (900f 720p slow in ~2.7 s) and slicing adds nothing — slicing wins
when the encoder does not scale across threads (AV1, 4K, or machines with
more cores than the codec can use).
"""
function render_parallel(scene_jl::String, output::String; n::Int = 4,
                         frames_total::Int, fps::Int = 30,
                         resolution::Tuple{Int,Int} = (1280, 720),
                         crf::Int = 23, preset::String = "medium",
                         encoder_threads::Union{Nothing,Int} = 1,
                         threads_per_process::Int = 2,
                         motion_blur::Int = 1, shutter::Real = 0.5,
                         samples::Int = 0, scene_name::String = "construct")
    # The name is INTERPOLATED into the workers' code below, so it must
    # be an identifier and nothing else — this door is what keeps a crafted
    # `x.jl:foo(); run(…)` address from becoming code inside the workers.
    Base.isidentifier(scene_name) || throw(ArgumentError(
        "scene_name = «$scene_name» is not a Julia identifier — after " *
        "`file.jl:` write the scene function's name as the file defines it"))
    # The worker count is bounded AT THE DOOR, like every other input:
    # each worker costs ~862 MB of RSS as a measured FLOOR (720p, light
    # scene), so `-j 40` instead of `-j 4` would be a one-keystroke OOM. The
    # cap is the machine's thread count — the value
    # past which more workers cannot help and the memory bill still grows.
    1 <= n <= Sys.CPU_THREADS || throw(ArgumentError(
        "n = $n render workers: this machine has $(Sys.CPU_THREADS) " *
        "threads, and each worker costs ~862 MB of RSS as a floor — " *
        "use 1 ≤ n ≤ $(Sys.CPU_THREADS)"))
    ranges = [(round(Int, frames_total * (k - 1) / n) + 1):round(Int, frames_total * k / n)
              for k in 1:n]
    segs = [output * ".seg$k.mp4" for k in 1:n]
    jl = joinpath(Sys.BINDIR, "julia")
    proj = pkgdir(Janim)
    procs = map(zip(ranges, segs)) do (r, seg)
        code = """
        using Janim
        include(raw"$(abspath(scene_jl))")
        Janim.render_segment($scene_name, raw"$seg";
                             frames = $(first(r)):$(last(r)), fps = $fps,
                             resolution = $resolution, crf = $crf,
                             preset = "$preset",
                             encoder_threads = $(encoder_threads === nothing ? "nothing" : encoder_threads),
                             motion_blur = $motion_blur, shutter = $shutter,
                             samples = $samples)
        """
        # strict_gl_cmd: every worker must agree with every other about the
        # driver's shader variant, or the segments show their seams.
        run(strict_gl_cmd(`$jl --project=$proj --startup-file=no
                           -t $threads_per_process -e $code`); wait = false)
    end
    for p in procs
        wait(p)
        success(p) || error("a render_parallel process failed")
    end
    list = output * ".list.txt"
    open(list, "w") do io
        for seg in segs
            println(io, "file '", abspath(seg), "'")
        end
    end
    # The concat goes through the SAME ffmpeg as every other byte the
    # package writes (FFMPEG_jll), not whatever the PATH holds: on a machine
    # with no PATH ffmpeg `-j` would otherwise die at the finish line.
    ffm = FFMPEG_jll.ffmpeg()
    run(pipeline(`$ffm -y -loglevel error -f concat -safe 0 -i $list -c copy $output`))
    foreach(rm, segs)
    rm(list)
    return output
end

_hex(c) = "#" * join(string.(round.(Int, 255 .* (c[1], c[2], c[3])), base = 16, pad = 2)) *
          @sprintf(" α%.2f", c[4])

function _describe(io::IO, m::VMobject, level::Int)
    b = get_bounding_box(m)
    print(io, "  "^level, "- ", tag(m), " · ", get_num_points(m), " points")
    if has_points(m)
        @printf(io, " · bbox [%.3f, %.3f]×[%.3f, %.3f]", b[1][1], b[3][1], b[1][2], b[3][2])
        print(io, " · stroke ", _hex(m.stroke_rgba[1]), " w",
              round(m.stroke_width[1]; digits = 2),
              " · fill ", _hex(m.fill_rgba[1]))
    end
    has_updaters(m) && print(io, " · ", length(m.updaters), " updater(s)")
    println(io)
    for sub in m.submobjects
        sub isa VMobject && _describe(io, sub, level + 1)
    end
end

"""
    _describe_composition(io, comp, depth = 0, prefix = "")

The layers of `comp` as `describe` lists them, bottom to top: one
line per layer, then the tree of each VMobject it draws and its mask.
`depth` indents a precomp's layers under the layer that holds them, and
`prefix` numbers them (`layer 2.1`, `layer 2.2`).
"""
function _describe_composition(io::IO, comp::Composition, depth::Int = 0, prefix::String = "")
    pad = "  "^depth
    for (k, layer) in enumerate(comp.layers)
        name = string(prefix, k)
        content = layer.content
        if content === nothing
            println(io, pad, "layer ", name, " · adjustment · ", length(layer.effects), " effects")
        elseif content isa Composition
            println(io, pad, "layer ", name, " · blend=", repr(layer.blend), " · opacity=",
                    layer.opacity, " · precomp · ", length(content.layers), " layers")
            _describe_composition(io, content, depth + 1, string(name, "."))
        else
            println(io, pad, "layer ", name, " · blend=", repr(layer.blend), " · opacity=",
                    layer.opacity, " · ", length(content), " mobjects")
            for m in content
                m isa VMobject && _describe(io, m, depth + 2)
            end
        end
        if layer.mask !== nothing
            println(io, pad, "  mask · ", length(layer.mask.content), " mobjects")
            for m in layer.mask.content
                m isa VMobject && _describe(io, m, depth + 2)
            end
        end
    end
    return io
end

"""
    describe(scene::Scene) → String

The agent's textual introspection — a stable, readable tree (type, points,
bbox, colours) without rendering. Same state ⇒ same text.

The header and the roots come first. Under a composition (`use_composition!`)
the roots are only what `play!` registered and the drawing lives in the
layers, so the layers follow, bottom to top: `layer k ·
blend=:normal · opacity=1.0 · n mobjects` and the tree of each VMobject it
draws; `layer k · adjustment · m effects` for a layer with no content;
`layer k · … · precomp · n layers` with the precomp's own layers nested below
as `layer k.1`, `layer k.2`…; and a layer's mask as `mask · n mobjects` with
the mask's VMobjects. Without a composition there are no layer lines.
"""
function describe(scene::Scene)
    io = IOBuffer()
    @printf(io, "Scene %d×%d · t=%.3f s · %d frames · %d mobjects\n",
            scene.camera.width, scene.camera.height, scene.t, scene.frames,
            length(scene.mobjects))
    for m in scene.mobjects
        m isa VMobject && _describe(io, m, 1)
    end
    scene.composition === nothing || _describe_composition(io, scene.composition)
    return String(take!(io))
end

"""
    describe(construct, t; fps=30, resolution=(854,480)) → String

The same textual introspection at a TIME `t`, captured at the frame
containing `t`. The text is taken AT the capture frame, exactly where
[`render_frame`](@ref) takes its pixels: describing after `construct`
returns would describe the FINAL state, not `t`'s. A `t` beyond the end
describes the final state, same as `render_frame`.

Unlike `describe(scene)`, this form SIMULATES the scene and so opens a GPU
context, exactly as [`render_frame`](@ref) does (the drawing of every frame
but the captured one is skipped, not the context). See [`animation_map`](@ref).
"""
function describe(construct::Function, t_target::Real;
                  fps::Int = 30, resolution::Tuple{Int,Int} = (854, 480))
    scene = Scene(; fps, resolution)
    scene.capture_t = max(Float64(t_target), 0.5 / fps)
    try
        construct(scene)
        return something(scene.capture_txt, describe(scene))
    finally
        close(scene)
    end
end
