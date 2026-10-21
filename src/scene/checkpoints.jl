# Checkpoints — named "save states" for a scene.
#
# The flow to beat is 3b1b's: `manimgl scene.py Scene -se <line>` jumps to a
# line and opens IPython; `checkpoint_paste()` runs a block whose first-line
# comment is the KEY of an in-memory snapshot, rewinding the scene to that
# state first. Checkpoints are the same thing anchored to the CLI/daemon rather
# than to an editor: stop re-simulating a 40-second prefix to iterate on the
# last ten seconds.
#
#     function construct(scene)
#         # … act 1: expensive (integrators, a long timeline) …
#         checkpoint!(scene, "act2")
#         # … the part you are actually iterating on …
#     end
#
#     janim render scene.jl --from act2 -o out.mp4
#
# TWO MODES, and `checkpoint!` is the same call in both:
#
#   · RECORD (a normal run): passing the marker stores a deep copy of the
#     scene's state under (file, label, prefix hash).
#   · SKIP (`--from act2`): every play!/wait! BEFORE the marker becomes a
#     no-op — it advances the clock and lands the animation on its final pose,
#     but simulates no updaters and draws no frames — and at the marker the
#     freshly built mobjects ADOPT the snapshot in place, so the user's own
#     variables keep pointing at valid objects.
#
# WHERE THIS BEATS manimgl: invalidation. The snapshot's key includes a hash
# of the file text BEFORE the checkpoint's line. Edit the prefix and the
# snapshot invalidates itself, so the next request re-simulates in full and
# re-snapshots. manimgl trusts the user and will happily serve stale state.
# Edit only the suffix — the normal case while iterating — and it is a hit.

using SHA

"A snapshot of a scene at a checkpoint: state, plus what makes it valid."
struct Checkpoint
    mobjects::Vector{Mobject}     # deep copies, detached from the live scene
    t::Float64
    frames::Int
    prefix_hash::String
    stamped::Float64              # mtime of the file when it was taken
end

# The store lives in the module, not in the Scene: its whole point is to
# outlive one run inside the daemon's warm process.
#
# The key is (path, scene_name, label) — the scene's NAME is in it
# because the address has to be seen by whoever caches. Two scenes of one
# file may both write `checkpoint!(scene, "act2")`; keyed by path alone,
# `x.jl:b --from act2` would either adopt scene_a's snapshot (a valid video
# of the WRONG scene) or skip forever toward a label only scene_a reaches.
const _CHECKPOINTS = Dict{Tuple{String,String,String},Checkpoint}()

"Escape `s` for a LITERAL match inside a `Regex`."
_regex_escape(s::AbstractString) = replace(s, r"([\\^$.|?*+()\[\]{}])" => s"\\\1")

"""
    prefix_hash(path, label) → String

SHA-256 of everything in `path` BEFORE the line that calls
`checkpoint!(…, "label")`. This is the honest invalidation key: it changes
when the prefix changes and does not when only the suffix does.

Returns `""` when the marker cannot be found in the text — OR when it is
found on MORE than one line: with several scenes in one file the same label may
be written twice, and "everything before the first occurrence" is the prefix of
somebody else's scene, so an edit between the two markers would not move the
hash and a stale snapshot would validate. In both cases the caller treats the
snapshot as never valid, which degrades to re-simulating rather than to
serving something wrong.
"""
function prefix_hash(path::String, label::String)
    isfile(path) || return ""
    lines = readlines(path)
    # the marker as it is written in the source; both quote styles, any spacing.
    # `escape_string` would escape for a Julia STRING, not for a regex — the
    # dot of `a.b` would match `axb`, a second marker would be "found" and the
    # snapshot of `a.b` would never validate (or, with `axb` alone, validate
    # against the wrong prefix).
    pat = Regex("checkpoint!\\s*\\(.*[\"']" * _regex_escape(label) * "[\"']")
    idxs = findall(l -> occursin(pat, l), lines)
    length(idxs) == 1 || return ""
    return bytes2hex(sha256(join(lines[1:idxs[1]-1], "\n")))
end

"Is there a snapshot for (path, scene_name, label) that matches the file as it
is now? The two-argument form asks about `construct`, the default scene."
function checkpoint_valid(path::String, scene_name::String, label::String)
    key = (abspath(path), scene_name, label)
    cp = get(_CHECKPOINTS, key, nothing)
    cp === nothing && return false
    h = prefix_hash(abspath(path), label)
    return h != "" && h == cp.prefix_hash
end
checkpoint_valid(path::String, label::String) =
    checkpoint_valid(path, "construct", label)

"""
    checkpoint_states(path) → Vector{(label, fresh)}

Every snapshot known for `path`, and whether it is still valid. This is what
`janim states scene.jl` prints. A snapshot that belongs to a NAMED scene
shows as `name:label`, so two scenes' checkpoints stay tellable apart.
"""
function checkpoint_states(path::String)
    ap = abspath(path)
    out = Tuple{String,Bool}[]
    for (k, _) in _CHECKPOINTS
        k[1] == ap || continue
        shown = k[2] == "construct" ? k[3] : k[2] * ":" * k[3]
        push!(out, (shown, checkpoint_valid(ap, k[2], k[3])))
    end
    return sort(out; by = first)
end

"""
    clear_checkpoints!()

Throw away every checkpoint snapshot held in this process.

The snapshots live in memory for the session, keyed by scene file and label, so
that `--from label` can resume without replaying the prefix. Clearing them
forces the next resume to simulate from the beginning — which is what you want
after changing something a snapshot could not have noticed, and what a long
warm daemon wants in order to give the memory back.

Checkpoints are also invalidated automatically when the scene file changes; see
[`checkpoint_valid`](@ref).
"""
clear_checkpoints!() = (empty!(_CHECKPOINTS); nothing)

"""
    checkpoint!(scene, label)

Mark a resume point. In a normal run it snapshots the scene here; under
`--from label` it is where the skipped prefix hands over to the real one.

Put it at TOP LEVEL of `construct` (not inside a loop or an `if`): the prefix
hash is computed from the marker's line in the source, so a marker that can be
reached by more than one path has no single prefix.
"""
function checkpoint!(scene::Scene, label::AbstractString)
    label = String(label)
    path = scene.scene_path
    key = (path, scene.scene_name, label)

    if scene.skip_until == label
        # SKIP mode reaching its target: adopt the snapshot and carry on live.
        cp = get(_CHECKPOINTS, key, nothing)
        if cp !== nothing && checkpoint_valid(path, scene.scene_name, label)
            _adopt_snapshot!(scene, cp)
            scene.t, scene.frames = cp.t, cp.frames
        end
        # Whether or not the snapshot was there, the skipping stops here: with
        # no snapshot the prefix already ran for real (the runner only enters
        # skip mode when the snapshot is valid), so the state is correct.
        scene.skipping = false
        scene.skip_until = nothing
        # The preview's mark goes AFTER the restore, or it would carry the frame
        # the fast-forward invented instead of the one the snapshot really holds.
        push!(scene.checkpoint_frames, (label, scene.frames + 1))
        return scene
    end

    # The preview's map. Recorded whether or not there is a `scene_path`
    # to key a snapshot by: navigation metadata is about THIS run, and a
    # hand-built Scene (every test, `render_frame`) has no path.
    push!(scene.checkpoint_frames, (label, scene.frames + 1))

    # RECORD mode: store the state. `copy` on a mobject is already deep,
    # so the snapshot cannot be mutated by the run that continues afterwards.
    if path != ""
        h = prefix_hash(path, label)
        h == "" || (_CHECKPOINTS[key] = Checkpoint([copy(m) for m in scene.mobjects],
                                                   scene.t, scene.frames, h, mtime(path)))
    end
    return scene
end

"""
Bring the live scene to the snapshot's state IN PLACE.

In place, and not by swapping the list, because the user's script holds its
own references (`c = Circle(); … ; checkpoint!(scene, "x"); play!(scene,
animate(c, …))`). Replacing the scene's vector would leave `c` pointing at an
orphan and the next `play!` would animate something invisible.

Pairing is by construction order, which determinism makes reliable: the
same script builds the same objects in the same order every time. When the
counts disagree (the prefix was edited in a way the hash did not catch, or a
mobject was added conditionally) the extra ones are appended as copies — a
degradation, never an error.
"""
function _adopt_snapshot!(scene::Scene, cp::Checkpoint)
    n = min(length(scene.mobjects), length(cp.mobjects))
    for i in 1:n
        live, saved = scene.mobjects[i], cp.mobjects[i]
        # same type → adopt in place; different type → take the copy, since
        # become! across types is not part of the contract
        if typeof(live) == typeof(saved)
            become!(live, saved)
        else
            scene.mobjects[i] = copy(saved)
        end
    end
    for i in (n+1):length(cp.mobjects)
        push!(scene.mobjects, copy(cp.mobjects[i]))
    end
    return scene
end

"""
    render_from(construct, path, label; kw...)

Render only the part of the scene AFTER checkpoint `label`.

If the snapshot is valid the prefix is skipped (no updaters, no frames, no
encoding); if it is not, this runs the scene in full — which also re-takes the
snapshot, so the next call is fast. Either way the output is correct: the
snapshot is an optimisation, never a source of truth.
"""
function render_from(construct::Function, output::String, label::AbstractString;
                     scene_path::String = "", scene_name::String = "construct",
                     fps::Int = 30,
                     resolution::Tuple{Int,Int} = (1280, 720), kw...)
    scene = Scene(; output, fps, resolution, kw...)
    scene.scene_path = scene_path == "" ? "" : abspath(scene_path)
    scene.scene_name = scene_name
    if scene.scene_path != "" &&
       checkpoint_valid(scene.scene_path, scene_name, String(label))
        scene.skip_until = String(label)
        scene.skipping = true
    end
    try
        construct(scene)
    finally
        close(scene)
    end
    return output
end
