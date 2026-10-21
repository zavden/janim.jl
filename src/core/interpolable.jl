# The interpolation contract.
#
# "Interpolate between two states of X" is the same job for Transform, for the
# `.animate` idiom, for a ValueTracker, for the animatable 2D camera and for
# anything added later. If each of them were written against VMobject in
# particular, every new one would force a rewrite of the earlier ones.
#
# So the contract is a handful of generic functions and FOUR lines per
# implementor:
#
#     is_interpolable(::MyType) = true                    # the trait
#     Base.copy(m::MyType)                                # snapshot a state
#     interpolate!(dst::MyType, a::MyType, b::MyType, α)  # the lerp
#     become!(dst::MyType, src::MyType)                   # adopt a state
#
# plus, if the type needs to prepare both ends before the lerp (VMobject has
# to equalise point counts), the optional hook:
#
#     align_data!(a::MyType, b::MyType)
#
# Transform, the fades, `animate`, ValueTracker and the camera frame talk ONLY
# to these functions. VMobject implements them in alignment.jl.

"""
    is_interpolable(m) → Bool

Does this mobject know how to interpolate itself? The trait that declares the
contract. `false` by default: a type that exists only to be drawn (Surface)
passes through animations without breaking them — Transform SKIPS it instead
of blowing up.
"""
is_interpolable(::Mobject) = false

"""
    align_data!(a, b)

Optional hook of the contract: leave `a` and `b` in a state where
`interpolate!` is valid (for VMobject: same number of points and children).
Does nothing by default — a scalar value needs no preparation.
"""
align_data!(a::Mobject, b::Mobject) = a

# ── teaching fallbacks ──────────────────────────────────────────────────────
# Only reached when a type declares is_interpolable=true and leaves something
# unimplemented (or when someone animates a type outside the contract).

_missing_contract(f, T) = throw(ArgumentError(
    "$T does not implement `$f`, part of the interpolation contract. For " *
    "Transform (and `.animate`, ValueTracker, the animatable camera…) to " *
    "animate your type, four lines are needed:\n" *
    "    is_interpolable(::$T) = true\n" *
    "    Base.copy(m::$T)\n" *
    "    interpolate!(dst::$T, a::$T, b::$T, α)\n" *
    "    become!(dst::$T, src::$T)"))

Base.copy(m::Mobject) = _missing_contract("Base.copy", typeof(m))
interpolate!(dst::Mobject, ::Mobject, ::Mobject, ::Real) =
    _missing_contract("interpolate!", typeof(dst))
become!(dst::Mobject, ::Mobject) = _missing_contract("become!", typeof(dst))

# ── the minimum to LIVE in a scene (not to interpolate: just to exist) ──────
# A leaf Mobject (a ValueTracker, a camera frame promoted to a mobject) goes
# into scene.mobjects and passes through the updater loop and the renderer.
# Both ask these three questions; with these defaults a new type lives in a
# scene without touching Scene or the backend.

get_family(m::Mobject) = Mobject[m]
has_updaters(::Mobject) = false
get_updaters(::Mobject) = Updater[]
update!(m::Mobject, ::Real = 0.0; recurse::Bool = true) = m
