# Course 2 · 6.1 — Writing a layer effect (basic shaders)
#
# ManimGL's shaders are per MOBJECT. Janim's are per LAYER: the compositor has
# already rendered the layer into a texture, so an effect is one fullscreen
# pass over an image — which is what an editor's effect actually is, and what
# makes "blur THIS group and not that one" possible at all.
#
# A layer effect is exactly three things:
#
#   1. a MUTABLE struct (mutable so it can be animated from an updater, and so
#      the frame clock can be handed to it — lesson 6.2);
#   2. a fragment shader in WGSL, registered once with `effect_shader!`;
#   3. ONE method of `Janim._apply_effect!(cg, rv, ef, src)` that writes a
#      scratch slot and RETURNS it.
#
# Four conventions worth copying from the built-ins:
#
#   · THE ZERO IS AN EXACT NO-OP. Return `src` untouched when the dial is at
#      identity so the pass is skipped and the layer comes out bit for bit as
#      it went in.
#   · SIZES IN SCENE UNITS, converted with `cg.ppu` (pixels per scene unit),
#      so the effect looks the same at 480p and at 1080p.
#   · THE TEXTURE IS PREMULTIPLIED. Divide by alpha before touching colour and
#      multiply back afterwards (`unpremult` is spliced in for you), or the
#      effect eats the edges.
#   · NEVER WRITE `src`. A frame is ONE command buffer and a pass already
#      recorded may still read that slot: write `_scratch(cg, src)` and hand
#      the new slot on. There is no copy back — the layer's CURRENT texture
#      travels as a slot index.
#
# The fragment is `fn fs_<entry>(in: QuadOut) -> @location(0) vec4<f32>` over
# the compositor's shared quad: it reads the layer through `sample_a(in.uv)`,
# its dials from `P.f0` / `P.f1` (four floats each) and `P.i0` (four ints),
# which `QuadParams(f0 = …, f1 = …, i0 = …)` fills on the Julia side. The
# engine splices the inserts every built-in effect sees (quad_common, noise,
# straight), so nothing has to be pasted into the string.
#
# `RadialBlur` in src/backend/wgpu/compositor.jl is the smallest complete
# example in the engine; this is the same shape.
#
#   julia --project=. examples/tutorial/c2_06_shaders/01_write_a_layer_effect.jl

using Janim
import Janim: _apply_effect!

# ── 1 · the struct ─────────────────────────────────────────────────────────

"""
    Posterize(levels = 6; tint = 0.0)

Quantise each channel to `levels` steps — the poster look. `levels ≤ 1` is an
exact no-op. `tint` pushes the result towards a warm/cool split, to show what
a second dial costs (nothing).
"""
mutable struct Posterize
    levels::Float64
    tint::Float64
end
Posterize(levels::Real = 6; tint::Real = 0.0) = Posterize(Float64(levels), Float64(tint))

# ── 2 · the shader ─────────────────────────────────────────────────────────

const POSTERIZE_WGSL = """
@fragment
fn fs_posterize(in: QuadOut) -> @location(0) vec4<f32> {
    let c = sample_a(in.uv);
    let levels = P.f0.x;
    let tint = P.f0.y;
    // PREMULTIPLIED in, premultiplied out: unpremultiply before touching the
    // colour or the quantisation eats the antialiased edges.
    var s = unpremult(c);
    s = floor(s * levels + 0.5) / levels;
    // a cheap grade: warm the highlights, cool the shadows
    let l = dot(s, vec3<f32>(0.2126, 0.7152, 0.0722));
    s = clamp(s + tint * (l - 0.5) * vec3<f32>(0.9, 0.2, -0.7), vec3<f32>(0.0), vec3<f32>(1.0));
    return vec4<f32>(s * c.a, c.a);
}
"""
effect_shader!(:posterize, POSTERIZE_WGSL)

# ── 3 · the method ─────────────────────────────────────────────────────────

function _apply_effect!(cg::Janim.GPUCompositor, rv, ef::Posterize, src::Int)
    ef.levels <= 1 && return src                     # the zero is an exact no-op
    return Janim._quad!(cg, rv, :posterize, Janim._scratch(cg, src); a = src,
                        params = Janim.QuadParams(f0 = (Float32(ef.levels), Float32(ef.tint))))
end

const PREVIEW_T = 2.4

function construct(scene)
    title = TextMobject("a layer effect is a struct, a shader and one method";
                        size = 0.42, color = GREY_A)
    to_edge!(title, UP; buff = 0.3)

    "The same content, built twice so each side owns its copy."
    function art(x)
        g = VGroup()
        for k in 0:6
            c = Circle(radius = 0.5 + 0.32k)
            set_stroke!(c; opacity = 0)
            set_fill!(c; color = color_gradient(["#0B0E14", "#2C5F8A", "#FFD25E"], 7)[k+1],
                      opacity = 1.0)
            add!(g, c)
        end
        # smallest on top, so the rings read as rings
        for (k, c) in enumerate(reverse(g.submobjects))
            set_z_index!(c, k)
        end
        move_to!(g, Point3f(x, -0.3, 0))
        return g
    end

    plain = art(-3.4)
    posted = art(3.4)
    poster = Posterize(3; tint = 0.0)

    left = TextMobject("as rendered"; size = 0.34, color = GREY_B)
    right = TextMobject("Posterize(3)"; size = 0.34, color = GREY_B)
    move_to!(left, Point3f(-3.4, -3.1, 0)); move_to!(right, Point3f(3.4, -3.1, 0))

    use_composition!(scene, Composition(
        Layer(plain),
        Layer(posted; effects = [poster]),
        Layer(title, left, right);
        background = (0.02f0, 0.03f0, 0.05f0, 1f0)))

    # The struct is mutable, so the effect is animatable from an updater —
    # no new mechanism, just a field changing over time.
    clock = VGroup()
    add_updater!(clock, function (m, dt)
        dt > 0 || return
        poster.levels = 2 + 6 * (0.5 + 0.5 * sin(1.2 * scene.t))
        poster.tint = 0.6 * (0.5 + 0.5 * sin(0.7 * scene.t))
        nothing
    end)
    add!(scene, clock)

    wait!(scene, 4.0)
    println("levels at the end: ", round(poster.levels; digits = 2))
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__),
                   "01_write_a_layer_effect.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
