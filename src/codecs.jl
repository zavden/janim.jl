# codecs.jl — which encoders ship in the FFMPEG_jll that VideoIO depends on?
# If NVENC/VAAPI are missing, the fallback is an optional subprocess backend
# using the system ffmpeg (Manim's pipe, scene_file_writer.py:230).

using FFMPEG_jll

"""
    codec_report() -> NamedTuple

Lists FFMPEG_jll's video encoders and checks the ones we care about: libx264
(the workhorse), aom/svt (AV1), and the hardware ones (nvenc/vaapi/qsv), which
are normally absent.
"""
function codec_report()
    output = read(`$(FFMPEG_jll.ffmpeg()) -hide_banner -encoders`, String)
    lines = [strip(l) for l in split(output, '\n')]
    video_encoders = [l for l in lines if startswith(l, "V")]

    has(pattern) = any(occursin(pattern, l) for l in video_encoders)
    notable = filter(video_encoders) do l
        any(occursin(p, l) for p in
            ("264", "265", "hevc", "av1", "vp9", "nvenc", "vaapi", "qsv", "amf"))
    end
    return (; total_video = length(video_encoders),
            libx264 = has("libx264"),
            libx265 = has("libx265"),
            av1     = has("libaom") || has("libsvtav1") || has("librav1e"),
            nvenc   = has("nvenc"),
            vaapi   = has("vaapi"),
            qsv     = has("qsv"),
            notable)
end
