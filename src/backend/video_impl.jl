# backend/video_impl.jl — the VideoIO half of the engine.
#
# Included AT RUNTIME by `_ensure_video!` (video.jl), never at import: the
# `using VideoIO` below is the exact moment VideoIO loads, and with it about
# 350 ms — 130 of `Pkg` (VideoIO reaches it through FileIO) plus 219 of Pkg's
# REPL extension, which four third-party dependencies invalidate so it
# RE-compiles on every single start.
#
# Same shape as `window.jl`, and for the same reason: a dependency that only
# one feature needs must not be in the import path of every process. The
# difference is that GLFW would CRASH without a display, while VideoIO merely
# costs — which is why this lazy load is about time and not about correctness,
# and why it has no ordering trick to preserve.
#
# What may live here: anything naming a VideoIO type or calling into it.
# What may NOT: anything the static engine has to compile against. `_wrap`,
# `FramePipeline` and the readback cycle stay in wgpu/pipeline.jl on purpose
# — the struct holds no VideoIO field (the writer never escapes the encoder
# task's closure), which is what makes this seam a small one.

using VideoIO

"""
The encoder task of `FramePipeline`. Returns the `Task`; the writer `w` lives
and dies inside this closure, which is why `FramePipeline` needs no VideoIO
type in any of its fields.
"""
function _spawn_encoder(path::String, bufs::Vector{Vector{UInt8}},
                        width::Int, height::Int,
                        free::Channel{Int}, filled::Channel{Int},
                        fps::Int, crf::Int, preset::String,
                        encoder_threads::Union{Nothing,Int},
                        transparent::Bool = false)
    transparent && return _spawn_encoder_alpha(path, bufs, width, height,
                                               free, filled, fps)
    return Threads.@spawn begin
        # the first frame only CONFIGURES the encoder: open with
        # any buffer of the right size and write every frame explicitly
        opts = encoder_threads === nothing ? (crf = crf, preset = preset) :
               (crf = crf, preset = preset, threads = string(encoder_threads))
        w = VideoIO.open_video_out(path, _wrap(bufs[1], width, height);
                                   framerate = fps, scanline_major = true,
                                   encoder_options = opts,
                                   target_pix_fmt = VideoIO.AV_PIX_FMT_YUV420P)
        n = 0
        try
            for ib in filled
                write(w, _wrap(bufs[ib], width, height))
                n += 1
                put!(free, ib)
            end
        finally
            VideoIO.close_video_out!(w)
        end
        n
    end
end

"""
The alpha encoder. It does NOT go through VideoIO: VideoIO drops the alpha
channel at its door, by design:

    _coerce_encoding_img(img::AbstractMatrix{<:RGBA}) = RGB.(img)

(`VideoIO/src/encoding.jl:58`). No combination of `target_pix_fmt` or
`codec_name` gets around it: the file comes out tagged `yuva444p12le` with an
alpha plane that is uniformly opaque, which is worse than an error because it
looks like it worked.

So this path pipes raw RGBA into ffmpeg's stdin, which is what Manim does
too. ProRes 4444 in a `.mov` — the format `-t` produces there, and the one
every NLE reads. `crf`/`preset` are x264's vocabulary and are not passed:
ProRes has no use for them.
"""
function _spawn_encoder_alpha(path::String, bufs::Vector{Vector{UInt8}},
                              width::Int, height::Int,
                              free::Channel{Int}, filled::Channel{Int},
                              fps::Int)
    return Threads.@spawn begin
        cmd = `$(ffmpeg()) -y -v error
               -f rawvideo -pix_fmt rgba -s $(width)x$(height) -r $fps -i -
               -c:v prores_ks -profile:v 4444 -pix_fmt yuva444p10le $path`
        proc = open(cmd, "w")
        n = 0
        try
            for ib in filled
                # An ffmpeg that could not open its output prints why and
                # exits once stdin brings it bytes: the FIRST write goes
                # through, ffmpeg leaves with 254, and the second write dies
                # of EPIPE, which names nothing. Ask before writing, and turn
                # the broken pipe into the same answer.
                process_exited(proc) && _ffmpeg_died(proc, path, n)
                # The un-premultiply happens HERE, on the encoder's thread, so
                # the render thread never pays for it.
                _unpremultiply!(bufs[ib])
                try
                    write(proc, bufs[ib])   # already top-down, already RGBA
                catch err
                    err isa Base.IOError || rethrow()
                    close(proc.in)          # it closed our pipe: it is on its way out
                    wait(proc)
                    success(proc) && rethrow()
                    _ffmpeg_died(proc, path, n)
                end
                n += 1
                put!(free, ib)
            end
        finally
            close(proc.in)                  # EOF is how ffmpeg knows to finish
            wait(proc)
        end
        success(proc) ||
            error("ffmpeg failed while writing the transparent video at $path")
        n
    end
end

"""
The error of the transparent route when ffmpeg has already exited: names the
file, the exit code and how many frames got through, and points at ffmpeg's
own line above (`-v error` lets it speak). Without it the render thread would
learn nothing: the encoder task would die of a broken pipe two frames in and
the buffer pool would run dry (see pipeline.jl).
"""
_ffmpeg_died(proc, path::String, n::Int) =
    error("ffmpeg exited with code $(proc.exitcode) after $n frame(s) while " *
          "writing the transparent video at $path — its own message is above")

"The body of `demo_mp4` (a synthetic gradient, written and read back)."
function _demo_mp4(path::String; nframes = 90, width = 640, height = 360,
                    fps = 30)
    frame = Matrix{RGB{N0f8}}(undef, height, width)   # VideoIO: height × width

    function paint!(frame, k)
        t = k / fps
        for j in 1:width, i in 1:height
            x, y = j / width, i / height
            frame[i, j] = RGB{N0f8}(x,
                                    y,
                                    0.5 + 0.5 * sin(6.28318 * (x + t * 0.5)))
        end
        return frame
    end

    # CAREFUL: the first frame given to open_video_out only
    # CONFIGURES the encoder (size/format) — it is NOT written. It has to be
    # written separately.
    open_video_out(path, frame; framerate = fps,
                   encoder_options = (crf = 23, preset = "fast")) do writer
        for k in 0:nframes-1
            write(writer, paint!(frame, k))
        end
    end

    # Verification: read back what was written
    reader = VideoIO.openvideo(path)
    first_frame = read(reader)
    n = 1
    while !eof(reader)
        read(reader); n += 1
    end
    close(reader)
    return (; frames_read = n, width = size(first_frame, 2),
            height = size(first_frame, 1), bytes = filesize(path))
end

"""
First frame of anything ffmpeg's image demuxer can read (jpg/bmp/tiff/webp).
PNG never reaches here — `_load_pixels` decodes it natively through PNGFiles.
"""
function _read_first_frame(path::String)
    v = VideoIO.openvideo(path)
    f = read(v)
    close(v)
    return f
end
