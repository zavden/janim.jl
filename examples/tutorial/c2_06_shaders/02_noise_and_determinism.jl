# Course 2 · 6.2 — Randomness in a shader, without breaking determinism
#
# Janim's determinism rule: same code → same frames. That is what buys scrubbing,
# the frame cache, parallel segment rendering, and previews that really are
# the final film. `rand()` in a shader would break all four at once, and so
# would a wall clock.
#
# So an effect that needs randomness uses the shared piece:
#
#   · `janim_noise_px(position, frame, seed)` — spliced into every effect's
#     module (`shaders/inserts/noise.wgsl`): a hash of (PIXEL, frame, seed).
#     Indexed by `in.position.xy`, never by uv, so it does not stretch with
#     the aspect ratio.
#   · a field `current_frame::Int`. THAT FIELD IS THE DECLARATION — the
#     compositor's `_tick!` fills it in before compositing, and an effect
#     without it is not touched. The index is the SCENE's frame counter, so a
#     video rendered in segments across processes has no seam.
#   · `Janim._noise_seed(ef, ef.seed)` — the user's seed mixed with the
#     effect's TYPE NAME. That is why a `Sparkle(seed=1)` and a `Grain(seed=1)`
#     on the same layer do not draw the same pattern, without either of them
#     having to think about it. It travels to the shader in `P.i0` as an
#     `i32`, negative half the time: the shader `bitcast`s it, never `u32()`s
#     it, and `seed_plus(seed, k)` is how to derive a second stream.
#
# The hash is Wellons' lowbias32, and its output has 24 significant bits —
# exactly what a Float32 holds without rounding. So the CPU and the GPU do not
# agree "to some tolerance": they return THE SAME Float32: compared on the
# GPU, pixel by pixel, with `===`.
#
#   julia --project=. examples/tutorial/c2_06_shaders/02_noise_and_determinism.jl

using Janim
import Janim: _apply_effect!

"""
    Sparkle(; amount = 0.6, density = 0.002, seed = 1, rate = 4)

Bright specks at random pixels, re-rolled every `rate` frames. `amount = 0`
is an exact no-op.
"""
mutable struct Sparkle
    amount::Float64
    density::Float64
    seed::Int
    rate::Int
    current_frame::Int      # ← the declaration: _tick! fills this in
end
Sparkle(; amount::Real = 0.6, density::Real = 0.002, seed::Integer = 1,
        rate::Integer = 4) =
    Sparkle(Float64(amount), Float64(density), Int(seed), Int(rate), 0)

const SPARKLE_WGSL = """
@fragment
fn fs_sparkle(in: QuadOut) -> @location(0) vec4<f32> {
    let c = sample_a(in.uv);
    let frame = P.i0.x;
    let seed = P.i0.y;
    let rate = P.i0.z;
    let amount = P.f0.x;
    let density = P.f0.y;
    // the pattern is held for `rate` frames: dividing the frame index is the
    // whole mechanism, and it costs nothing
    let held = janim_frame_step(frame, rate);
    let n = janim_noise_px(in.position.xy, held, seed);
    let hit = step(1.0 - density, n);
    // STAY INSIDE THE LAYER. The pass covers the whole frame, including the
    // parts where this layer is empty (alpha 0) — adding a speck there paints
    // over everything below it. Multiplying by c.a keeps the effect where the
    // layer actually is, and leaves the alpha channel alone.
    return vec4<f32>(min(c.rgb + hit * amount * c.a, vec3<f32>(1.0)), c.a);
}
"""
effect_shader!(:sparkle, SPARKLE_WGSL)

function _apply_effect!(cg::Janim.GPUCompositor, rv, ef::Sparkle, src::Int)
    ef.amount <= 0 && return src
    return Janim._quad!(cg, rv, :sparkle, Janim._scratch(cg, src); a = src,
                        params = Janim.QuadParams(
                            i0 = (Int32(ef.current_frame), Janim._noise_seed(ef, ef.seed), Int32(ef.rate)),
                            f0 = (Float32(ef.amount), Float32(ef.density))))
end

const PREVIEW_T = 1.5

function construct(scene)
    title = TextMobject("deterministic randomness: hash(pixel, frame, seed)";
                        size = 0.42, color = GREY_A)
    to_edge!(title, UP; buff = 0.3)

    "A dark panel to sparkle over."
    function panel(x, label)
        p = RoundedRectangle(width = 5.2, height = 3.4, corner_radius = 0.2)
        set_fill!(p; color = "#101A26", opacity = 1.0)
        set_stroke!(p; color = "#25405C", width = 2.0)
        move_to!(p, Point3f(x, -0.2, 0))
        t = TextMobject(label; size = 0.34, color = GREY_B)
        move_to!(t, Point3f(x, -2.4, 0))
        return (p, t)
    end

    left, lab_l = panel(-3.1, "Sparkle(seed = 1)")
    right, lab_r = panel(3.1, "Sparkle(seed = 2)")

    use_composition!(scene, Composition(
        Layer(left; effects = [Sparkle(; seed = 1, density = 0.004, rate = 3)]),
        Layer(right; effects = [Sparkle(; seed = 2, density = 0.004, rate = 3)]),
        Layer(title, lab_l, lab_r);
        background = (0.02f0, 0.03f0, 0.05f0, 1f0)))

    wait!(scene, 2.5)

    # The CPU version of the shader's hash. Same numbers, exactly — which is what
    # lets a test check a shader without a GPU in the loop.
    vals = [Janim._noise_hash(px, 7, 3, 1) for px in 1:4]
    println("janim_noise(px, 7, frame 3, seed 1) = ", vals)
    println("…and the same call again: ", [Janim._noise_hash(px, 7, 3, 1) for px in 1:4])
    println("seed domains differ: Sparkle → ",
            Janim._noise_seed(Sparkle(), 1), " · Grain → ",
            Janim._noise_seed(Grain(), 1))
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__),
                   "02_noise_and_determinism.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
