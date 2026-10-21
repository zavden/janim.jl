# Geometric algebra for the core — the subset of manimlib/utils/space_ops.py
# and utils/bezier.py that the core needs. Everything is computed in Float64 and
# converted to Float32 on entering the mobject (same scheme as GL: numpy f64 →
# f32 data).

using LinearAlgebra: normalize, norm, cross, dot
using StaticArrays: SMatrix, SVector

"""
    rotation_matrix(angle, axis) → SMatrix{3,3,Float64}

Rodrigues: R = I + sin·K + (1−cos)·K². Equivalent to GL's
`rotation_matrix_transpose` applied as `p_row @ Rᵀ == R * p_column`.
"""
const I3 = SMatrix{3,3,Float64}(1, 0, 0, 0, 1, 0, 0, 0, 1)

"""
A zero (or non-finite) axis would normalize into NaN, and that NaN walks
silently into every point the rotation touches. Both doors an axis can enter
through — Rodrigues and the quaternion constructor — refuse it here, naming
the axis, BEFORE any geometry is written.
"""
function _unit_axis(axis)
    v = SVector{3,Float64}(axis[1], axis[2], axis[3])
    n = norm(v)
    isfinite(n) && n > 0 || throw(ArgumentError(
        "rotation axis must be nonzero and finite, " *
        "got ($(v[1]), $(v[2]), $(v[3]))"))
    return v / n
end

"One Rodrigues body for both doors; `a` is already unit (or deliberately NaN)."
function _rotation_matrix_unit(angle::Real, a::SVector{3,Float64})
    K = SMatrix{3,3,Float64}(0, a[3], -a[2], -a[3], 0, a[1], a[2], -a[1], 0)
    c, s = cos(Float64(angle)), sin(Float64(angle))
    I3 + s * K + (1 - c) * (K * K)
end

"""
Rodrigues WITHOUT the axis check — the renderer's joint machinery
(`joint_angles_of`) feeds normals from degenerate geometry (a glyph mid
`DrawBorderThenFill`, a one-point `TracedPath`), the NaN flows through the
whole matrix, and the renderer's output depends on it flowing exactly that
way. Internal to the backend on purpose: a USER axis enters through
[`rotation_matrix`](@ref) and is refused at the door.
"""
_rotation_matrix_unchecked(angle::Real, axis) =
    _rotation_matrix_unit(angle,
                          normalize(SVector{3,Float64}(axis[1], axis[2], axis[3])))

"""
    rotation_matrix(angle, axis) → SMatrix{3,3,Float64}

The matrix that rotates by `angle` radians about `axis`, right-handed.

Rodrigues' formula, in `Float64` and column-major, so `R * p` is the rotated
column vector. [`rotate!`](@ref) is what you normally want; this is for when
you need the matrix itself — composing several rotations, or feeding
[`apply_points_function!`](@ref) a transform of your own.
"""
rotation_matrix(angle::Real, axis) =
    _rotation_matrix_unit(angle, _unit_axis(axis))

"Rotate `v` by `angle` around `axis` (OUT by default, as in GL)."
rotate_vector(v, angle::Real; axis = OUT) =
    Point3f(rotation_matrix(angle, axis) * SVector{3,Float64}(v[1], v[2], v[3]))

"The n vertices of a regular polygon starting at `start_vect` (space_ops.py:244)."
compass_directions(n::Int, start_vect = RIGHT) =
    [rotate_vector(start_vect, k * TAU / n) for k in 0:n-1]

"""
    quadratic_bezier_points_for_arc(angle; n_components=8) → Vector{Point3f}

GL's arc (bezier.py:174): 2n+1 samples on the unit circle with the handles
(even indices) pushed outwards by 1/cos(θ/2) so the quadratic passes EXACTLY
through the midpoint of the arc.
"""
function quadratic_bezier_points_for_arc(angle::Real; n_components::Int = 8)
    n = 2n_components + 1
    pts = [SVector{3,Float64}(cos(a), sin(a), 0) for a in range(0, angle; length = n)]
    nudge = 1 / cos(angle / n_components / 2)
    for i in 2:2:n
        pts[i] = pts[i] * nudge
    end
    return Point3f.(pts)
end

"Point-wise lerp — the hottest operation in the engine."
interpolate(a, b, alpha::Real) = a + Float32(alpha) * (b - a)

"""
    inverse_interpolate(a, b, value) → Float64

Where `value` sits between `a` and `b`, as a proportion — the inverse of
[`interpolate`](@ref). `inverse_interpolate(2, 6, 3)` is `0.25`.

It answers in `Float64` even when the inputs are `Float32`, because what comes
out is a PROPORTION that then multiplies a length: the engine computes in 64
bits and stores in 32 (see [`TAU`](@ref)).

There is no guard against `a == b`, on purpose — it would cost a branch in a
function this small, and the two callers that can reach that case
([`point_from_proportion`](@ref) and its helper) already answer for a path of
zero length before getting here.
"""
inverse_interpolate(a, b, value) = (Float64(value) - Float64(a)) / (Float64(b) - Float64(a))

# ── angles between vectors (space_ops.py), used by Line/Arrow ───────────────

"The polar θ of the vector projected on xy (GL's angle_of_vector)."
angle_of_vector(v) = atan(Float64(v[2]), Float64(v[1]))

"Unoriented angle between two vectors, in [0, π]."
function angle_between_vectors(v1, v2)
    a = SVector{3,Float64}(v1[1], v1[2], v1[3])
    b = SVector{3,Float64}(v2[1], v2[2], v2[3])
    na, nb = norm(a), norm(b)
    (na == 0 || nb == 0) && return 0.0
    return acos(clamp(dot(a, b) / (na * nb), -1.0, 1.0))
end

"""
    rotation_between_vectors(v1, v2) → SMatrix{3,3,Float64}

The rotation taking v1 onto v2 (space_ops.py:161). When they are parallel it
falls back to an auxiliary axis (RIGHT, and UP if they are parallel to that
too) — exactly as GL does.
"""
function rotation_between_vectors(v1, v2)
    atol = 1e-8
    a = SVector{3,Float64}(v1[1], v1[2], v1[3])
    b = SVector{3,Float64}(v2[1], v2[2], v2[3])
    norm(a - b) < atol && return I3
    axis = cross(a, b)
    norm(axis) < atol && (axis = cross(a, SVector(1.0, 0.0, 0.0)))
    norm(axis) < atol && (axis = cross(a, SVector(0.0, 1.0, 0.0)))
    return rotation_matrix(angle_between_vectors(a, b), axis)
end

# ═══════════════════════════════════════════════════════════════════════
# Quaternions. scipy convention (x, y, z, w), Hamilton product.
# GL's CameraFrame keeps the WHOLE orientation as a quaternion
# (camera_frame.py:37); the euler angles are derived, never stored.
# ═══════════════════════════════════════════════════════════════════════

const Quat = SVector{4,Float64}

quat_identity() = Quat(0, 0, 0, 1)

"Rotation quaternion of `angle` around `axis` (Rotation.from_rotvec)."
function quat_axis_angle(axis, angle::Real)
    a = _unit_axis(axis)                       # same door policy as Rodrigues
    s, c = sincos(Float64(angle) / 2)
    Quat(s * a[1], s * a[2], s * a[3], c)
end

"Unit-quaternion inverse: the conjugate (scipy layout: x, y, z, w)."
quat_conj(q::Quat) = Quat(-q[1], -q[2], -q[3], q[4])

"""
    quat_normalize(q) → Quat

Back onto the unit sphere. This is LOAD-BEARING wherever quaternion products
CYCLE: `quat_conj` is the inverse of a UNIT quaternion only, so a
loop like user → parked → base → user multiplies any norm deviation on every
round — measured in a real drag session, one ulp of seed grew to |q| = 0
(the zero quaternion, whose matrix is the identity: the frontal-plane snap)
in ~80 event↔tick alternations. A product CHAIN drifts linearly and can
wait; a product CYCLE must renormalise at the seam.
"""
function quat_normalize(q::Quat)
    n = sqrt(q[1]^2 + q[2]^2 + q[3]^2 + q[4]^2)
    n > 0 || return quat_identity()
    return Quat(q[1] / n, q[2] / n, q[3] / n, q[4] / n)
end

"Hamilton product a⊗b — like scipy: (a*b) applies b FIRST, then a."
function quat_mul(a::Quat, b::Quat)
    x1, y1, z1, w1 = a
    x2, y2, z2, w2 = b
    Quat(w1 * x2 + w2 * x1 + y1 * z2 - z1 * y2,
         w1 * y2 + w2 * y1 + z1 * x2 - x1 * z2,
         w1 * z2 + w2 * z1 + x1 * y2 - y1 * x2,
         w1 * w2 - x1 * x2 - y1 * y2 - z1 * z2)
end

"""
    quat_slerp(a, b, α) → Quat

Spherical linear interpolation: the SHORT arc from `a` to `b` at constant
angular speed. The animatable camera needs it — a component-wise lerp of two
quaternions leaves the unit sphere, so a rotating camera would speed up in the
middle and wobble.

Two details that are easy to get wrong and both matter on screen: `q` and `−q`
are the same rotation, so the sign of `b` is flipped when the dot product is
negative (otherwise the camera takes the long way round, up to a full extra
turn); and for nearly-parallel quaternions the sines underflow, so it falls
back to a normalised lerp, which is accurate to well under a pixel there.
"""
function quat_slerp(a::Quat, b::Quat, alpha::Real)
    α = Float64(alpha)
    d = a[1] * b[1] + a[2] * b[2] + a[3] * b[3] + a[4] * b[4]
    q2 = d < 0 ? -b : b            # same rotation, short way round
    d = abs(d)
    if d > 0.9995                  # nearly parallel: sines underflow
        r = a + α * (q2 - a)
        n = sqrt(sum(x -> x * x, r))
        return n == 0 ? a : Quat(r / n)
    end
    theta = acos(clamp(d, -1.0, 1.0))
    s = sin(theta)
    return Quat((sin((1 - α) * theta) / s) * a + (sin(α * theta) / s) * q2)
end

"3×3 rotation matrix of a unit quaternion."
function quat_to_matrix(q::Quat)
    x, y, z, w = q
    SMatrix{3,3,Float64}(
        1 - 2(y^2 + z^2), 2(x * y + z * w), 2(x * z - y * w),   # col 1
        2(x * y - z * w), 1 - 2(x^2 + z^2), 2(y * z + x * w),   # col 2
        2(x * z + y * w), 2(y * z - x * w), 1 - 2(x^2 + y^2),   # col 3
    )
end

"""
EXTRINSIC zxz euler angles, GL style: set_euler_angles(θ,φ,γ) composes
R = Rz(θ)·Rx(φ)·Rz(γ) (scipy from_euler("zxz", [γ,φ,θ]) — GL reverses the
triple, camera_frame.py:145).
"""
quat_from_euler_zxz(theta::Real, phi::Real, gamma::Real) =
    quat_mul(quat_axis_angle(SVector(0.0, 0.0, 1.0), theta),
             quat_mul(quat_axis_angle(SVector(1.0, 0.0, 0.0), phi),
                      quat_axis_angle(SVector(0.0, 0.0, 1.0), gamma)))

"""
    euler_zxz_from_quat(q) → (θ, φ, γ)

Inverse of quat_from_euler_zxz with GL's gimbal-lock handling
(camera_frame.py:76-82): if φ≈0 or φ≈π (atol 1e-2), θ absorbs ±γ and γ=0.
From R = Rz(θ)Rx(φ)Rz(γ): col3 = (sθ·sφ, −cθ·sφ, cφ) and row3 = (sφ·sγ, sφ·cγ, cφ).
"""
function euler_zxz_from_quat(q::Quat)
    q == quat_identity() && return (0.0, 0.0, 0.0)
    R = quat_to_matrix(q)
    phi = acos(clamp(R[3, 3], -1.0, 1.0))
    if min(phi, π - phi) > 1e-2
        theta = atan(R[1, 3], -R[2, 3])
        gamma = atan(R[3, 1], R[3, 2])
        return (theta, phi, gamma)
    end
    # lock: R ≈ Rz(θ±γ)·Rx(0|π) — the whole z spin goes into θ, γ=0 (as in GL)
    theta = atan(R[2, 1], R[1, 1])
    return (theta, phi < 1e-2 ? 0.0 : phi, 0.0)
end

"""
    complex_to_R3(z) → Point3f
    R3_to_complex(p) → ComplexF64

The plane as ℂ and back (`space_ops.py:252-257`): `complex_to_R3(1 + 2i)` is
`(1, 2, 0)`, and `R3_to_complex` reads the first two coordinates and DROPS z,
exactly as GL's `complex(*point[:2])` does.

```julia
move_to!(dot, complex_to_R3(exp(im * TAU / 3)))
```

They are the pair a [`ComplexValueTracker`](@ref) is usually read through, and
what a ported `.py` calls when it treats the screen as the complex plane.
"""
complex_to_R3(z::Number) = Point3f(real(z), imag(z), 0)

@doc (@doc complex_to_R3)
R3_to_complex(p) = ComplexF64(Float64(p[1]), Float64(p[2]))
