# Course 1 · 2.6 — Importing audio
#
#     add_sound(scene, "clap.wav"; time = nothing, gain = 0.0)
#
# `time` defaults to NOW — wherever the scene's clock has got to — and `gain`
# is in dB. The tracks are queued and mixed into the mp4 when the scene
# CLOSES: one ffmpeg call with `adelay` per track, `amix` to add them and
# `-c:v copy`, so not a single video frame is re-encoded. The render loop does
# not change at all, which is how the video stays byte-deterministic while
# carrying sound.
#
# It needs an `output =` mp4. On a headless render with no output (a
# single-frame render, for instance) it warns and carries on, because
# there is nowhere to put the audio.
#
# This lesson SYNTHESISES its wav — a tone written by 20 lines of Julia is a
# better lesson than a file you cannot inspect.
#
#   julia --project=. examples/tutorial/c1_02_config_and_assets/06_audio_import.jl

using Janim

const PREVIEW_T = 1.4

"""
    write_wav(path, samples; rate = 44100)

A 16-bit mono PCM wav, by hand: 44 bytes of RIFF header and the samples.
`htol` spells the byte order out rather than trusting the machine's.
"""
function write_wav(path::String, samples::Vector{Float64}; rate::Int = 44100)
    n = length(samples)
    mkpath(dirname(path))
    open(path, "w") do io
        write(io, "RIFF"); write(io, htol(UInt32(36 + 2n))); write(io, "WAVE")
        write(io, "fmt "); write(io, htol(UInt32(16)))
        write(io, htol(UInt16(1)))              # 1 = PCM
        write(io, htol(UInt16(1)))              # mono
        write(io, htol(UInt32(rate)))
        write(io, htol(UInt32(2rate)))          # bytes per second
        write(io, htol(UInt16(2)))              # block align
        write(io, htol(UInt16(16)))             # bits per sample
        write(io, "data"); write(io, htol(UInt32(2n)))
        for s in samples
            write(io, htol(Int16(clamp(round(Int, 32767 * s), -32768, 32767))))
        end
    end
    return path
end

"A plucked note: a sine at `freq` Hz under an exponential decay."
function pluck(freq::Real; seconds::Real = 0.45, rate::Int = 44100)
    n = round(Int, seconds * rate)
    return [0.6 * sin(2pi * freq * k / rate) * exp(-3.5k / n) for k in 0:n-1]
end

function construct(scene)
    title = TextMobject("sound is muxed at the end, not rendered";
                        size = 0.48, color = GREY_A)
    to_edge!(title, UP; buff = 0.4)
    add!(scene, title)

    here = joinpath(@__DIR__, "..", "output", basename(@__DIR__))
    notes = [("A4", 440.0, "#58C4DD"), ("C#5", 554.37, "#E8A33D"),
             ("E5", 659.25, "#7FDD58")]

    bars = VGroup()
    for (k, (name, freq, colour)) in enumerate(notes)
        bar = Rectangle(width = 1.4, height = 0.6 + 0.5k)
        set_fill!(bar; color = colour, opacity = 1.0)
        set_stroke!(bar; opacity = 0)
        move_to!(bar, Point3f(-2.6 + 2.6 * (k - 1), -0.6 + 0.25k, 0))
        lab = TextMobject(name; size = 0.4, color = GREY_A)
        next_to!(lab, bar, DOWN; buff = 0.2)
        add!(bars, VGroup(bar, lab))
    end
    add!(scene, bars)

    for (k, (name, freq, _)) in enumerate(notes)
        wav = write_wav(joinpath(here, "note_$name.wav"), pluck(freq))
        # `time` left out = NOW: the note is queued at the scene's clock, so
        # it lands exactly when this animation starts.
        add_sound(scene, wav; gain = -3.0)
        play!(scene, GrowFromEdge(bars[k], DOWN); run_time = 0.5)
        wait!(scene, 0.25)
    end
    wait!(scene, 0.6)
    println("queued sounds: ", length(scene.sounds),
            " — they are mixed in when the scene closes")
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "06_audio_import.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out, "   (play it: the mp4 has a track)")
end
