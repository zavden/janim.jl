# backend/determinism.jl — strict determinism: the API for driver knobs, kept,
# with no knob to set.
#
# Two runs of the same code produce the same bytes. That holds for everything
# the engine does — and a DRIVER could break it underneath us, for instance by
# compiling every shader twice (a fast variant first, an optimised one on a
# background thread that replaces it once ready) so that WHICH ONE is live
# during frame k depends on thread scheduling. Pinning the variant at the
# driver's first context would then be the fix, and every process Janim spawns
# (the CLI, the farm's workers, child renders) would inherit it through
# `strict_gl_cmd`.
#
# The Vulkan drivers behind wgpu have no such race. RADV compiles its shaders
# with ACO inside vkCreateGraphicsPipelines, synchronously; lavapipe compiles
# with LLVM at pipeline creation; neither swaps a variant in later. So the
# list below is EMPTY, and the property is measured rather than pinned: six
# cold processes rendering the real mp4 path, with an effect with noise on
# every pixel, in RADV and in lavapipe, lossy and lossless, give ONE file
# each.
#
# The names stay because several callers use them, and because a knob a
# future driver needs has a home to arrive in: an entry here, a measurement
# beside it, nothing else to rewire.

"""
Driver knobs that pin the shader variant, by vendor — EMPTY: the Vulkan
drivers behind wgpu have no variant race to pin. An entry goes in only with
a measurement beside it (six cold processes, same recipe, same bytes), never
guessed.
"""
const STRICT_GL_ENV = Pair{String,String}[]

const _STRICT_GL = Ref{Union{Nothing,Bool}}(nothing)

"""
    strict_gl() -> Bool

Is strict determinism ON for the processes Janim spawns from here?

Defaults to `ENV["JANIM_STRICT_GL"]` (`0`/`false`/`no` turn it off), and to
**on** when unset. With `STRICT_GL_ENV` empty the answer changes what the
children receive by nothing at all — the switch is kept for the day a driver
needs a knob, and so that the variable and the API survive.
Override at runtime with [`strict_gl!`](@ref).
"""
function strict_gl()
    _STRICT_GL[] === nothing || return _STRICT_GL[]::Bool
    v = lowercase(get(ENV, "JANIM_STRICT_GL", "1"))
    return !(v in ("0", "false", "no", "off"))
end

"""
    strict_gl!(on::Bool) -> Bool

Turn it on or off for every process spawned AFTER this call.
`strict_gl!(nothing)` goes back to reading the environment.
"""
strict_gl!(on::Union{Bool,Nothing}) = (_STRICT_GL[] = on; strict_gl())

"The knobs to inject into a child, or nothing at all when the feature is off (none either way today)."
strict_gl_env() = strict_gl() ? STRICT_GL_ENV : Pair{String,String}[]

"""
    strict_gl_cmd(cmd) -> Cmd

Wrap a command so the child inherits the knobs. Every place Janim spawns a
process goes through this — the farm, the CLI — which
is the point: a farm whose workers disagreed about a shader variant would
show its seams at the segment boundaries. With no knobs to hand out it is
the identity, and the command comes back untouched.
"""
strict_gl_cmd(cmd::Cmd) =
    strict_gl() && !isempty(STRICT_GL_ENV) ? addenv(cmd, strict_gl_env()...) : cmd

"""
    strict_gl_pinned() -> Bool

Is THIS process actually running with the knobs set? Vacuously true when
there is nothing to set.
"""
strict_gl_pinned() = all(get(ENV, k, "") == v for (k, v) in STRICT_GL_ENV)

"""
    strict_gl_status([io])

Print what is on, what this process actually has, and what to do about it.
Written for the moment someone asks "why are my two renders not identical?"
— and the honest answer is that no driver knob is involved: the backend's
determinism is measured, not pinned, and a difference between two renders is
the engine's or x264's, never a shader variant's.
"""
function strict_gl_status(io::IO = stdout)
    println(io, "strict GL determinism")
    println(io, "  mode for spawned processes : ", strict_gl() ? "ON" : "OFF",
            " (JANIM_STRICT_GL / strict_gl!)")
    println(io, "  this process               : ", strict_gl_pinned() ? "pinned" : "NOT pinned")
    if isempty(STRICT_GL_ENV)
        println(io, "  driver knobs               : none — the WebGPU backend has no")
        println(io, "    shader-variant race to pin; RADV and lavapipe compile at pipeline creation.")
        println(io, "    Determinism between processes is measured, not pinned.")
        println(io, "    Two renders that differ differ in the engine or in x264 (encoder_threads),")
        println(io, "    never in a driver variant.")
    end
    for (k, v) in STRICT_GL_ENV
        println(io, "    ", k, " = ", get(ENV, k, "<unset>"), "   (wanted: ", v, ")")
    end
    return nothing
end
