# core/colorspace.jl — the exact IEC 61966-2-1 transfer pair.
#
# The compositor composes in LINEAR premultiplied light; the sRGB encoding
# exists only at its borders (decode when painted content enters a layer, one
# encode when the finished composition leaves for fbo_scene). These two
# functions ARE that border, and they live here — pure Julia, no GPU — so the
# contract can be checked headless and users can reach it.
#
# Two homes, ONE set of constants: the scalar pair below and the shader snippet
# beside it (string-interpolated into every shader that converts). If these
# ever disagree the specimen shows it: 50%-opacity red over black → byte 188,
# where raw-sRGB arithmetic says 128.
#
# The piecewise IEC definition, not the gamma-2.2 approximation: the linear
# toe below 0.04045/0.0031308 is what keeps blacks from collapsing, and both
# branches meet there (0.04045/12.92 == 0.0031308… to the digit).

"""
    srgb_to_linear(x) → Float64

The exact IEC 61966-2-1 EOTF: one normalized sRGB component into linear
light. `srgb_to_linear(0.5) == 0.21404114048223255`. Inverse of
[`linear_to_srgb`](@ref).
"""
srgb_to_linear(x::Real) =
    x <= 0.04045 ? x / 12.92 : ((x + 0.055) / 1.055)^2.4

"""
    linear_to_srgb(x) → Float64

The exact IEC 61966-2-1 OETF: one linear-light component encoded as sRGB.
Inverse of [`srgb_to_linear`](@ref).
"""
linear_to_srgb(x::Real) =
    x <= 0.0031308 ? 12.92 * x : 1.055 * x^(1 / 2.4) - 0.055

# The same pair for shaders, with the same constants. `mix(high, low, mask)`
# picks `low` where the component sits at or below the toe. The encode guards
# pow against negatives (f16 blur ringing can dip a hair under zero).
const SRGB_GLSL = """
vec3 srgb_to_linear(vec3 c) {
    vec3 low = c / 12.92;
    vec3 high = pow(max((c + 0.055) / 1.055, vec3(0.0)), vec3(2.4));
    return mix(high, low, lessThanEqual(c, vec3(0.04045)));
}
vec3 linear_to_srgb(vec3 c) {
    vec3 low = 12.92 * c;
    vec3 high = 1.055 * pow(max(c, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055;
    return mix(high, low, lessThanEqual(c, vec3(0.0031308)));
}
"""

"""
A PREMULTIPLIED sRGB rgba (a clear colour, a background) decoded into
premultiplied linear. The encoding rides on the straight colour, so it is
undone there — alpha receives no gamma, ever. Fully
transparent stays exactly zero.
"""
function _decode_premult_srgb(c::NTuple{4,<:Real})
    a = Float64(c[4])
    a <= 0 && return (0f0, 0f0, 0f0, 0f0)
    dec(x) = Float32(srgb_to_linear(clamp(Float64(x) / a, 0.0, 1.0)) * a)
    return (dec(c[1]), dec(c[2]), dec(c[3]), Float32(a))
end
