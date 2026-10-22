# The daemon — the warm process that kills TTFX.
#
# A julia process with Janim already loaded listens on local TCP; the `janim`
# CLI (pure bash, /dev/tcp — never starting julia) talks to it over a
# one-line protocol. With the daemon warm, `janim render scene.jl N out.png`
# answers in ~20 ms: the cost is render_frame's, not Julia's startup.
#
# Protocol (one line per request, answer "OK …" | "ERR …"). The `mp4` and
# `preview` verbs STREAM progress before the final line: `PROG <bar>` lines
# overwrite each other and `PROGN <bar>` commits one (scene/progress.jl
# renders the text; the bash client only moves the cursor).
#
# Every `<scene.jl>` field also accepts `<scene.jl:name>` — a file that
# defines several scene functions, addressed by name (`construct` when the
# suffix is absent). The address travels inside the EXISTING field and is
# split by `_scene_address` at each verb: zero new protocol fields, because
# a shifted field is how this protocol breaks.
#   ping
#   status
#   render  <scene.jl> <frame> <out.png> [fps] [WxH] [transparent] [samples]
#   mp4     <scene.jl> <out.mp4> [fps] [WxH] [jobs] [from]
#           [motion_blur[,shutter]] [n_range] [to] [transparent]
#           [still] [samples]                               a whole film
#           …or ONE frame as a png when `still` is true (the CLI's `-s`)
#   preview <scene.jl> [fps] [WxH] [stop_at_checkpoints] [max_seconds]
#           the live window, in THIS process; the reply comes when it
#           closes. max_seconds is for tests (the CLI never sends
#           it): it is the only way to READ the reply with a live client
#   states  <scene.jl>                                      checkpoints + validity
#   codecs
#   stop
#
# Note: the daemon is where checkpoints EARN their keep. The snapshot store
# lives in this warm process, so `mp4 … from=act2` on an unchanged prefix
# skips the expensive part outright.

using Sockets

# Keyed by (path, scene_name): one file may define several scenes, and
# the ADDRESS has to be seen by whoever caches — a construct cached by path
# alone would serve scene_a's function to a request for scene_b.
const _SCENES = Dict{Tuple{String,String},Tuple{Float64,Any}}()  # → (mtime, fn)
const _SCENE_GEN = Ref(0)      # a fresh module name per load — see `_scene`
# The frame cache. Its key carries `transparent` and `samples` because the
# same frame with and without alpha — or with and without MSAA — are DIFFERENT
# bytes, so they must not share a slot; and the scene NAME, for the strongest
# form of that reason: without it, the cached frame of scene_a would answer a
# request for scene_b — a valid PNG of the wrong scene.
const _CACHE_D =
    Dict{Tuple{String,String,Float64,Int,Int,Int,Int,Bool,Int},Vector{UInt8}}()
const _HITS_D = Ref(0)

"""
Load a scene file and hand back its scene function — `construct` by default,
or the one `name` picks — cached by ((path, name), mtime).

EACH SCENE GETS ITS OWN MODULE, and that is not tidiness. Including every
scene into `Main` would define `construct` in the SAME module. Julia does not
make two functions there: it makes one generic `Main.construct` and the second
file REPLACES the first one's method. The cached function object would stay
valid-looking and dispatch to whoever loaded last, so:

    janim render a.jl     # 30 frames · right
    janim render b.jl     #  6 frames · right
    janim render a.jl     #  6 frames · WRONG — you asked for a and got b

It takes two scenes in one warm daemon to show up.

The module gets `using Janim` injected BEFORE the include, and that is not a
convenience — it is what keeps scenes that never said it themselves working:
a file whose first line is `function construct(scene)` must work without
leaning on the daemon's own imports.
"""
function _scene(path::String, name::String = "construct")
    path = abspath(path)
    mt = mtime(path)
    key = (path, name)
    reg = get(_SCENES, key, nothing)
    if reg === nothing || reg[1] != mt
        _SCENE_GEN[] += 1
        mod = Module(Symbol("JanimScene_", _SCENE_GEN[]))
        Base.eval(mod, :(using Janim))
        Base.include(mod, path)
        # Each (path, name) gets its own module and its own include.
        # Sharing one module per file would save the extra include (~ms against
        # renders that cost seconds) at the price of a SECOND cache with its
        # own mtime invalidation — one more place to go stale. Not worth it.
        _SCENES[key] = (mt, _scene_fn(mod, name, path))
        # The file changed: every cached frame of EVERY scene it defines is
        # suspect, so the purge matches on path + old mtime, not on the name.
        filter!(kv -> !(kv[1][1] == path && kv[1][3] != mt), _CACHE_D)
    end
    return _SCENES[key][2]
end

"""
    _hangup_flag(sock) → Ref{Bool}

A flag that flips to `true` when the peer hangs up. The protocol is one line
per connection, so nothing legitimate ever arrives after the request line —
the pending `read` can only return because the client is gone. This is what
lets a Ctrl-C in the terminal (which kills the bash client and closes its
socket) close the daemon's live window.
"""
function _hangup_flag(sock)
    gone = Ref(false)
    @async begin
        try
            read(sock, UInt8)
        catch
        end
        gone[] = true
    end
    return gone
end

function _serve(line_str::String, sock = nothing)
    parts = split(strip(line_str))
    # Windows: bin/janim sends each space INSIDE a field as `|` (its `_send`),
    # because a home folder there is usually «C:/Users/Name Surname» and the
    # split above is on whitespace; no Win32 path can contain a `|`, so the
    # spaces come back without loss. Linux and macOS take the line as it came.
    Sys.iswindows() && (parts = [replace(p, '|' => ' ') for p in parts])
    isempty(parts) && return "ERR empty"
    cmd = parts[1]
    cmd == "ping" && return "OK pong"
    cmd == "stop" && return "OK bye"
    if cmd == "status"
        return "OK scenes=$(length(_SCENES)) frames_cached=$(length(_CACHE_D)) " *
               "hits=$(_HITS_D[]) checkpoints=$(length(Janim._CHECKPOINTS))"
    end
    if cmd == "codecs"
        c = codec_report()
        return "OK video_encoders=$(c.total_video) libx264=$(c.libx264) " *
               "libx265=$(c.libx265) av1=$(c.av1) nvenc=$(c.nvenc) vaapi=$(c.vaapi)"
    end
    if cmd == "states"
        length(parts) < 2 && return "ERR usage: states <scene.jl>"
        path, name = _scene_address(String(parts[2]))    # file.jl:scene
        isfile(path) || return "ERR no such file: $path"
        haskey(_SCENES, (abspath(path), name)) || _scene(path, name)   # a cold scene has none
        sts = checkpoint_states(path)
        isempty(sts) && return "OK (no checkpoints recorded for $path)"
        return "OK " * join(("$l=$(fresh ? "fresh" : "stale")" for (l, fresh) in sts), " ")
    end
    if cmd == "mp4"
        length(parts) < 3 && return "ERR usage: mp4 <scene.jl> <out.mp4> [fps] [WxH] " *
                                    "[jobs] [from] [motion_blur[,shutter]] [n_range] [to]"
        # The address travels INSIDE the existing scene field (zero new
        # protocol fields — a shifted field breaks the protocol) and is split
        # here.
        path, name = _scene_address(String(parts[2]))
        output = String(parts[3])
        fps = length(parts) >= 4 ? parse(Int, parts[4]) : 30
        W, H = length(parts) >= 5 ? parse.(Int, split(parts[5], "x")) : (1280, 720)
        jobs = length(parts) >= 6 ? parse(Int, parts[6]) : 1
        # `-` is the placeholder for an absent optional field. It has to be a
        # placeholder and not "": the line is split on whitespace RUNS, so an
        # empty field disappears and shifts everything after it left.
        from = length(parts) >= 7 && parts[7] != "-" ? String(parts[7]) : ""
        # Motion blur, appended at the END so an older client's message still parses.
        mb, sh = 1, 0.5
        if length(parts) >= 8 && !isempty(parts[8]) && parts[8] != "-"
            f = split(parts[8], ',')
            mb = something(tryparse(Int, f[1]), 1)
            length(f) >= 2 && (sh = something(tryparse(Float64, f[2]), 0.5))
        end
        # The animation range, appended at the END again, for the same reason.
        nrange = length(parts) >= 9 ? String(parts[9]) : ""
        to = length(parts) >= 10 ? String(parts[10]) : ""
        # `transparent`, appended at the END for the third time and for the same
        # reason: an older client's message still parses, it just does not ask
        # for alpha.
        transparent = length(parts) >= 11 && parts[11] == "true"
        # `-s`, appended at the END for the fourth time and for the same
        # reason: an older client's message still parses, it just never asks
        # for a still.
        still = length(parts) >= 12 && parts[12] == "true"
        # `--samples`, appended at the END for the fifth time.
        samples = length(parts) >= 13 ?
                  something(tryparse(Int, String(parts[13])), 0) : 0
        isfile(path) || return "ERR no such file: $path"
        return _render_mp4(path, name, output, fps, W, H, jobs, from, mb, sh,
                           nrange, to;
                           transparent, still, samples,
                           progress = sock === nothing ? nothing :
                                      RenderProgress(sock; socket = true))
    end
    if cmd == "preview"
        # The live window, in THIS warm process — a fresh Julia would pay the
        # ~4 s TTFX on every open. The reply is sent when the
        # window closes; the client hanging up (Ctrl-C in the terminal, a
        # killed shell) closes it too, via `abort` — see `_hangup_flag`.
        length(parts) < 2 &&
            return "ERR usage: preview <scene.jl> [fps] [WxH] [stop_at_checkpoints] [max_seconds] [samples]"
        # Split only to validate the FILE half early with a clean ERR;
        # the whole address goes on to `live`, which owns the same splitter.
        addr = String(parts[2])
        path, _ = _scene_address(addr)
        isfile(path) || return "ERR no such file: $path"
        fps = length(parts) >= 3 ? something(tryparse(Int, String(parts[3])), 30) : 30
        W, H = length(parts) >= 4 ? parse.(Int, split(parts[4], "x")) : (1280, 720)
        stopcp = length(parts) >= 5 && parts[5] == "true"
        maxs = length(parts) >= 6 ? something(tryparse(Float64, String(parts[6])), Inf) : Inf
        # `--samples` for the preview, appended at the END for the sixth time
        # and for the same reason: an older client's message still parses, it
        # just previews without MSAA — which is exactly what it asked for.
        samples = length(parts) >= 7 ?
                  something(tryparse(Int, String(parts[7])), 0) : 0
        gone = sock === nothing ? Ref(false) : _hangup_flag(sock)
        v = live(addr; fps, resolution = (W, H), stop_at_checkpoints = stopcp,
                 max_seconds = maxs, samples, abort = () -> gone[],
                 progress = sock === nothing ? nothing :
                            RenderProgress(sock; socket = true))
        # The total is lazy (known once the playhead reaches the end),
        # so it only appears in the reply when it exists.
        at = v.total > 0 ? "$(v.idx)/$(v.total)" : "$(v.idx)"
        return "OK preview closed (frame $at, $(v.hits) cache hits)"
    end
    if cmd == "render"
        length(parts) < 4 && return "ERR usage: render <scene.jl> <frame> <out.png> [fps] [WxH]"
        path, name = _scene_address(String(parts[2]))    # file.jl:scene
        frame, output = parse(Int, parts[3]), String(parts[4])
        fps = length(parts) >= 5 ? parse(Int, parts[5]) : 30
        W, H = length(parts) >= 6 ? parse.(Int, split(parts[6], "x")) : (1280, 720)
        transparent = length(parts) >= 7 && parts[7] == "true"
        samples = length(parts) >= 8 ?
                  something(tryparse(Int, String(parts[8])), 0) : 0
        isfile(path) || return "ERR no such file: $path"
        return _render_one_frame(path, name, frame, output, fps, W, H,
                                 transparent, samples)
    end
    return "ERR unknown command: $cmd (ping status render mp4 preview states codecs stop)"
end

"""
    _parse_anim_range(s) → nothing | UnitRange | :bad

The `-n` field. `"3,5"` → `3:5`; `"3"` → animation 3 to the end (Manim's
own reading of a bare `-n X`); `""` or `"-"` → absent. `:bad` rather than an
exception, because this comes off a socket and the answer has to be an
`ERR …` line the CLI can print.
"""
function _parse_anim_range(s::AbstractString)
    (isempty(s) || s == "-") && return nothing
    f = split(s, ',')
    length(f) > 2 && return :bad
    a = tryparse(Int, strip(f[1]))
    (a === nothing || a < 1) && return :bad
    length(f) == 1 && return a:typemax(Int)
    b = tryparse(Int, strip(f[2]))
    (b === nothing || b < a) && return :bad
    return a:b
end

"A frame number, or seconds when it ends in `s`. `nothing` if it is neither."
function _parse_frame(s::AbstractString, fps::Int)
    endswith(s, "s") || return tryparse(Int, s)
    v = tryparse(Float64, s[1:end-1])
    return v === nothing ? nothing : max(1, round(Int, v * fps))
end

"""
One frame to a PNG, with the frame cache. Extracted from the `render` verb so
that `mp4 … still=true` (the CLI's `-s`) can reuse it instead of growing a
second way to render one frame: one mechanism, not two.

`transparent` belongs in the cache key: the same frame with and without alpha
are DIFFERENT bytes, and serving one for the other is exactly the class of bug
that honest cache invalidation exists to prevent.
"""
function _render_one_frame(path::String, name::String, frame::Int,
                           output::String, fps::Int,
                           W::Int, H::Int, transparent::Bool, samples::Int = 0)
    # `samples` joins the key for the same reason as `transparent`: the same
    # frame with and without MSAA are different bytes. `name` joins it because
    # the same frame number of two scenes of one file are different PICTURES.
    key = (abspath(path), name, mtime(path), frame, fps, W, H, transparent,
           samples)
    if haskey(_CACHE_D, key)                      # frame already rendered
        _HITS_D[] += 1
        write(output, _CACHE_D[key])
        return "OK $output (cache, hits=$(_HITS_D[]))"
    end
    fn = _scene(path, name)
    t = (frame - 0.5) / fps
    Base.invokelatest(render_frame, fn, t; fps, resolution = (W, H), png = output,
                      transparent, samples)
    _CACHE_D[key] = read(output)
    return "OK $output"
end

"""
The `mp4` verb, and the place where the resume levels and the animation range
have to compose WITHOUT inventing a fourth mechanism:

  · `from` a NUMBER (or `12s`), and/or `to` → level 0: `render_segment` with a
    frame range. The whole scene is simulated with skip-draw; this is the
    segment machinery with a CLI verb in front.
  · `from` a LABEL → level 1: `render_from`, which skips the prefix outright
    when the snapshot is valid.
  · `nrange` (`-n X,Y`) → a gate on the DRAWING, so it rides along with
    all three above by being handed to the Scene, and never changes what is
    simulated.

`jobs > 1` sends it to the render farm, which needs a frame total and so
cannot be combined with any of them — saying so is better than silently
ignoring one of the two. For `-n` there is a second reason: the farm's workers
partition the frames, so a worker whose share falls entirely outside the range
would hand `ffmpeg -f concat` a segment with no frames.

`transparent` is orthogonal to all four levels
and rides every one of them except the farm: the flags above gate WHAT IS
DRAWN, the alpha decides WHAT THE PIXELS CARRY. `-j` is refused for a reason of
its own, below.
"""
function _render_mp4(path::String, name::String, output::String, fps::Int,
                     W::Int, H::Int,
                     jobs::Int, from::String, motion_blur::Int = 1,
                     shutter::Float64 = 0.5, nrange::String = "", to::String = "";
                     transparent::Bool = false, still::Bool = false,
                     samples::Int = 0, progress = nothing)
    fn = _scene(path, name)
    ar = _parse_anim_range(nrange)
    ar === :bad && return "ERR -n wants X or X,Y with 1 ≤ X ≤ Y (got «$nrange»)"
    to = to == "-" ? "" : to

    # ── `-s` · one frame instead of a video (Manim's `-s`) ──────────────
    # `-s` alone is the LAST frame, which is what CE's --save_last_frame and
    # ManimGL's --skip_animations both mean; `-s --to X` is frame X, reusing the
    # flag that already speaks frames and seconds. Everything below delegates
    # to `_render_one_frame`, so this is a NEW SPELLING of the `frame` verb
    # and not a second implementation of it — cache, alpha and all.
    if still
        # Three refusals, each because the flag would otherwise be silently
        # ignored, which is the failure mode this CLI avoids on principle.
        jobs > 1 && return "ERR -s cannot be combined with -j: one frame is " *
                           "not a video, so there is nothing to split"
        from == "" || return "ERR -s cannot be combined with --from: a still " *
                             "is addressed absolutely, so say which frame you " *
                             "want with --to instead"
        ar === nothing || return "ERR -s cannot be combined with -n: `-n` " *
                                 "selects ANIMATIONS and a still is one frame " *
                                 "— pick it with --to (a frame, or 1.5s)"
        total = _count_frames(fn, fps, (W, H))
        frame = total                              # `-s` alone: the last one
        if to != ""
            f = _parse_frame(to, fps)
            f === nothing && return "ERR --to wants a frame or seconds (got «$to»)"
            f > total && total > 0 &&
                return "ERR --to $to is past the end ($total frames)"
            frame = f
        end
        # A scene with no animations has no frames to be last; frame 1 is its
        # only state, and render_frame clamps t to the first frame anyway.
        return _render_one_frame(path, name, max(frame, 1), _still_path(output),
                                 fps, W, H, transparent, samples)
    end

    # Alpha rides `--from`/`--to` too: those flags only GATE the
    # drawing, while the alpha lives in the Scene and the pipeline, so the two
    # are orthogonal and the segment paths just forward the flag.
    #
    # `-j` is refused, and by DESIGN rather than for lack of plumbing:
    # concat does preserve the alpha plane over ProRes (measured), but the same
    # scene at 720p30 is 6 KB as h264 and 839 KB as ProRes 4444 — 137×. The farm
    # is for long renders; a long ProRes 4444 render is the file you do not want
    # on disk. Refusing is the honest answer: silently writing an opaque file
    # for a `-t` render is the kind of "it looked like it worked" that costs an
    # evening in an editor.
    if transparent && jobs > 1
        return "ERR -t cannot be combined with -j: the farm is for long renders " *
               "and ProRes 4444 is ~137× h264, so the two do not mix by design"
    end

    if jobs > 1
        from == "" || return "ERR -j and --from cannot be combined: the farm " *
                             "splits by frame ranges and needs the total"
        (ar === nothing && to == "") ||
            return "ERR -j cannot be combined with -n/--to: the farm partitions " *
                   "the frames, and a worker whose share falls outside the range " *
                   "would produce an empty segment"
        total = _count_frames(fn, fps, (W, H))
        # A scene with no animations has nothing to partition, and the farm
        # would hand `ffmpeg -f concat` $jobs empty segments. Refusing names
        # the situation instead of producing a broken file.
        total == 0 && return "ERR the scene has no animations, so there is " *
                             "nothing to split across $jobs processes — render " *
                             "it without -j and you get a still"
        Base.invokelatest(render_parallel, abspath(path), output;
                          n = jobs, frames_total = total, fps, resolution = (W, H),
                          motion_blur, shutter, samples, scene_name = name)
        return "OK $output ($total frames, $jobs processes)"
    end

    # A frame/second `--from`, or any `--to`, means the segment machinery.
    ffrom = from == "" ? nothing : _parse_frame(from, fps)
    if to != "" || ffrom !== nothing
        from == "" || ffrom !== nothing ||
            return "ERR --to takes a frame or seconds --from, not the label " *
                   "«$from» (a label has no frame number until the scene runs)"
        total = _count_frames(fn, fps, (W, H))
        first_frame = something(ffrom, 1)
        first_frame > total && return "ERR --from $from is past the end ($total frames)"
        last_frame = total
        if to != ""
            lf = _parse_frame(to, fps)
            lf === nothing && return "ERR --to wants a frame or seconds (got «$to»)"
            lf < first_frame && return "ERR --to $to lands before --from $from"
            last_frame = min(lf, total)
        end
        # The motion-blur kwargs are forwarded on this path as well, so a
        # `--from`/`--to` render never drops what it was asked for.
        Base.invokelatest(render_segment, fn, output;
                          frames = first_frame:last_frame, fps, resolution = (W, H),
                          motion_blur, shutter, anim_range = ar, transparent, samples)
        return "OK $output (frames $first_frame:$last_frame of $total)"
    end

    if from != ""                       # a LABEL: the checkpoint snapshot
        fresh = checkpoint_valid(path, name, from)
        Base.invokelatest(render_from, fn, output, from;
                          scene_path = abspath(path), scene_name = name,
                          fps, resolution = (W, H),
                          motion_blur, shutter, anim_range = ar, transparent, samples)
        return "OK $output (checkpoint $from, " *
               "$(fresh ? "skipped the prefix" : "cold: prefix simulated and snapshotted"))"
    end

    # The bar rides only the FULL render for now: the farm's workers own no
    # socket, and the segment/checkpoint paths build their scenes elsewhere.
    sc = Base.invokelatest(_render_full, fn, path, name, output, fps, (W, H),
                           motion_blur, shutter, ar; progress, transparent, samples)
    # ORDER MATTERS. The `-n` diagnostic goes first: someone who asked for
    # animations 9:9 of a scene that has none wants to be told so, not handed a
    # still that silently ignores the slice they typed.
    ar === nothing || first(ar) <= sc.anim_index ||
        return "ERR -n $nrange drew nothing: the scene has $(sc.anim_index) animations"
    # Manim's rule: no animations → a still, not an empty video. The path in
    # the OK line is the one that EXISTS, which is what `-p` opens.
    sc.frames == 0 &&
        return "OK $(_still_path(output)) (still: the scene has no animations)"
    ar === nothing && return "OK $output"
    return "OK $output (animations $(first(ar)):$(min(last(ar), sc.anim_index)) " *
           "of $(sc.anim_index))"
end

"A full render, recording any checkpoints the script declares. Returns the
SCENE, so the caller can report how many animations it turned out to have."
function _render_full(fn, path::String, name::String, output::String, fps::Int,
                      res::Tuple{Int,Int},
                      motion_blur::Int = 1, shutter::Float64 = 0.5,
                      anim_range::Union{Nothing,UnitRange{Int}} = nothing;
                      progress = nothing, transparent::Bool = false,
                      samples::Int = 0)
    scene = Scene(; output, fps, resolution = res, motion_blur, shutter, anim_range,
                  progress, transparent, samples)
    scene.scene_path = abspath(path)
    scene.scene_name = name             # checkpoints key on it
    try
        fn(scene)
    finally
        close(scene)
    end
    return scene
end

"How many frames the scene lasts, without drawing any (skip-draw)."
function _count_frames(fn, fps::Int, res::Tuple{Int,Int})
    scene = Scene(; fps, resolution = res)
    scene.capture_t = -1.0            # never matches: simulate, draw nothing
    try
        Base.invokelatest(fn, scene)
    finally
        close(scene)
    end
    return scene.frames
end

"""
    daemon(; port=7318)

Start the daemon (blocking). It prints `JANIM_DAEMON_READY <port>` once
it accepts connections — the `bin/janim` CLI talks to it over /dev/tcp.
"""
function daemon(; port::Int = 7318)
    # NO boot-time warmup of the preview path, and it was measured, not
    # assumed: warming Revise + a throwaway live session at boot moved ~4 s
    # from the first preview into `daemon start` (3.5 s → ~7.5 s) and still
    # left that first preview at 2.0 s — the residue is the scene's own
    # include and the compositor's JIT, which a generic warmup cannot cover.
    # Zero-sum on the total, so the daemon's pattern stays consistent
    # instead: the FIRST use of each path is cold (first frame, first mp4,
    # first preview ~6 s), everything after is warm (~0.05-0.1 s to open a
    # preview). An @async warmup is not an option at all: it would interleave
    # its GPU context with a real request's on this one thread.
    server = listen(IPv4(127, 0, 0, 1), port)
    println("JANIM_DAEMON_READY $port")
    flush(stdout)
    while true
        sock = accept(server)
        try
            line_str = readline(sock)
            answer = try
                _serve(line_str, sock)
            catch e
                "ERR $(sprint(showerror, e))"
            end
            println(sock, answer)
            flush(sock)
            startswith(answer, "OK bye") && (close(sock); break)
        catch
        finally
            isopen(sock) && close(sock)
        end
    end
    close(server)
    return nothing
end
