# video.jl — write an mp4 of synthetic frames with VideoIO.
#
# This replaces Manim's ffmpeg pipe (scene_file_writer.py:230): in-process,
# with Julia exceptions instead of a mute BrokenPipeError. The encoder is
# the SAME libx264 — speed is not the gain; installation and errors are.
#
# This file is VideoIO-free: everything that names VideoIO lives in
# `backend/video_impl.jl`, included on first use. Reason: VideoIO drags in
# `Pkg` (through FileIO), and with `REPL` already loaded that activates Pkg's
# REPL extension — which RE-compiles on every start because four third-party
# dependencies invalidate it. That is 350 ms of a 927 ms import, so only the
# processes that write video pay it.

using Colors
using FixedPointNumbers: N0f8      # Colors does NOT re-export N0f8

# ── lazy loading ────────────────────────────────────────────────────────────

const _VIDEO_READY = Ref(false)
const _VIDEO_LOCK = ReentrantLock()
const _VIDEO_SOURCE = joinpath(@__DIR__, "backend", "video_impl.jl")

"""
    _ensure_video!()

Load the VideoIO-facing sources on first need. Idempotent, locked, cheap
after the first call. There is no ordering constraint — VideoIO loads fine
anywhere; it just costs, and only the processes that encode should pay.
"""
function _ensure_video!()
    _VIDEO_READY[] && return nothing
    lock(_VIDEO_LOCK) do
        _VIDEO_READY[] && return nothing
        Base.include(@__MODULE__, _VIDEO_SOURCE)
        _VIDEO_READY[] = true
        return nothing
    end
    return nothing
end

# Static names, runtime implementations. `invokelatest` jumps
# the world-age wall once per call — these are all coarse entry points (open
# an encoder, decode one image), never per-fragment work.
function _spawn_encoder end
function _demo_mp4 end
function _read_first_frame end

"""
    demo_mp4(path; nframes=90, width=640, height=360, fps=30)

Writes an mp4 with an animated gradient and VERIFIES it by reading it back
(frame count and size). Returns `(; frames_read, width, height, bytes)`.
"""
demo_mp4(path::String; kw...) =
    (_ensure_video!(); Base.invokelatest(_demo_mp4, path; kw...))

# ═══════════════════════════════════════════════════════════════════════
# Sound: mixing the queued tracks into the finished mp4
# ═══════════════════════════════════════════════════════════════════════
#
# Zero render work, by design: the video is encoded as usual (determinism
# intact) and the audio is a mux at the end — one ffmpeg call
# with `adelay` per track, `amix` to add them and `-c:v copy` so not a single
# video frame is re-encoded.

using FFMPEG_jll: ffmpeg

"""
    _mux_sounds!(path, sounds, duration)

Mix `[(file, start_seconds, gain_db), …]` into the mp4 at `path`, in place.

`duration` is the scene's own, in seconds, and it is what the output is cut
to. It is passed as `-t` rather than `-shortest`: `-shortest` cuts at the end
of the SHORTEST stream, and since the mixed audio ends with the last cue, a
sound near the end would silently take the rest of the video with it. `-t`
asks for the length we know, so the mp4 keeps every frame the scene simulated
whether the audio is shorter or longer.
"""
function _mux_sounds!(path::Union{Nothing,String},
                      sounds::Vector{Tuple{String,Float64,Float64}},
                      duration::Real)
    if path === nothing
        @warn "add_sound: this scene writes no mp4 (no output=), so there is " *
              "nowhere to put the audio — the sounds were ignored" maxlog = 1
        return nothing
    end
    isfile(path) || return nothing
    inputs = String[]
    filters = String[]
    labels = String[]
    for (k, (file, t, gain)) in enumerate(sounds)
        append!(inputs, ["-i", file])
        delay = max(0, round(Int, 1000t))          # adelay speaks milliseconds
        lbl = "a$k"
        push!(filters, "[$k:a]adelay=$delay|$delay,volume=$(gain)dB[$lbl]")
        push!(labels, "[$lbl]")
    end
    mix = length(labels) == 1 ? "$(labels[1])anull[aout]" :
          "$(join(labels))amix=inputs=$(length(labels)):normalize=0[aout]"
    graph = join([filters..., mix], ";")
    tmp = string(path, ".withsound.mp4")
    secs = string(round(Float64(duration); digits = 6))
    cmd = `$(ffmpeg()) -y -v error -i $path $inputs -filter_complex $graph
           -map 0:v -map "[aout]" -c:v copy -c:a aac -t $secs $tmp`
    try
        run(cmd)
        mv(tmp, path; force = true)
    catch err
        isfile(tmp) && rm(tmp; force = true)
        @warn "add_sound: ffmpeg could not mux the audio; the video is intact" err
    end
    return path
end
