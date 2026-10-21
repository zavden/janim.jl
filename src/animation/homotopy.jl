# animation/homotopy.jl — animating by a function of the POINTS.
#
# One mechanism, eight names. Everything here is "evaluate f at every control
# point and put the point there", and the family splits on exactly two
# questions:
#
#   · Is the function of TIME as well as position? A `Homotopy` takes
#     f(x, y, z, t) and is re-evaluated from the ORIGINAL points every frame,
#     so the path each point takes is f's business and the animation is
#     reversible, seekable and stateless. `ApplyPointwiseFunction` and its
#     relatives take f(p) once and interpolate towards the result instead.
#   · Does it INTEGRATE? `PhaseFlow` is the odd one: it reads f as a velocity
#     field and steps the points forward by dt·f(p) each frame, so it
#     accumulates and is NOT seekable the way the others are. That is
#     manimlib's behaviour and it is kept, with the consequence written down.
#
# THE FRAME every one of them deforms in. `f` is
# handed ABSOLUTE coordinates, so every call below passes
# `about_point = ORIGIN` — the POINT (0,0,0). Both engines force exactly that
# before applying a point function, with the same sentence in both sources:
# «Default to applying matrix about the origin, not mobjects center»
# (manimlib/mobject/mobject.py:1013, manim/mobject/mobject.py:1460).
#
# The trap is a collision of spellings, and it is worth naming because it
# causes four wrong behaviours at once. `apply_points_function!` defaults to
# `about_edge = ORIGIN`, and an EDGE of `ORIGIN` means "the centre of the
# bounding box" — which is right for `scale!` and `rotate!`, whose whole point
# is to pivot on the shape. `about_point = ORIGIN` is the opposite thing under
# the same name. Deforming about each member's own centre would make the family
# position-dependent in ways that no width, no constant field and no centred
# square could reveal: `ApplyMatrix` would silently ignore its `about_point`,
# `ApplyWave`'s phase would depend on where the word sat on screen, and
# `PhaseFlow` would transport nothing at all, because a centre always sees the
# field at its own location subtracted away.
#
# THE RESAMPLING PROBLEM. A
# quadratic Bézier through three control points is NOT the image of that curve
# under a non-affine f: bending a straight side needs points along it, and
# there are none. Manim's answer is `make_smooth`, which re-fits the handles
# after the deformation; it does not add points either. So a shape with long
# straight edges deforms into straight edges, and the fix is the caller's:
# subdivide before deforming. Said in the docstrings rather than papered over.

"Evaluate a homotopy at one time, as a point → point function."
_homotopy_at(h::F, t::Real) where {F} =
    p -> Point3f(h(Float64(p[1]), Float64(p[2]), Float64(p[3]), Float64(t)))

"""
    Homotopy(f, mobject; run_time = 3, smooth_handles = false)

Deform a mobject by a function of position AND time: `f(x, y, z, t)` returns
the new `(x, y, z)`, with `t` running 0 → 1.

```julia
swirl(x, y, z, t) = (x * cos(t * PI) - y * sin(t * PI),
                     x * sin(t * PI) + y * cos(t * PI), z)
play!(scene, Homotopy(swirl, square))
```

Each frame starts from the ORIGINAL points and applies `f(·, α)`, so the
animation holds no state: seeking to any α gives the same picture, and a
`rate_func` reshapes time without the shape drifting.

`smooth_handles = true` re-fits the Bézier handles after each deformation —
that is ManimGL's `SmoothedVectorizedHomotopy`, available here as a keyword
and as its own name.

**What it cannot do**: a path is made of quadratic Béziers, and `f` only ever
sees the CONTROL POINTS. A straight side has none in its middle, so it stays
straight however hard `f` bends the space around it. If you need a side to
bow, give it points first — `Polyline` through several intermediate corners,
or `insert_n_curves!` if the shape already exists.
"""
mutable struct Homotopy <: Animation
    base::AnimBase
    f::Function
    smooth_handles::Bool
    pairs::Vector{NTuple{2,Mobject}}
end

function Homotopy(f::Function, mob::Mobject; run_time::Real = 3.0,
                  smooth_handles::Bool = false, kw...)
    return Homotopy(AnimBase(; mobject = mob, run_time = Float64(run_time), kw...),
                    f, smooth_handles, NTuple{2,Mobject}[])
end

function begin!(h::Homotopy)
    h.base.starting_mobject = copy(h.base.mobject)
    h.pairs = _families(h.base.mobject, h.base.starting_mobject)
    interpolate!(h, 0.0)
    return h
end

function interpolate!(h::Homotopy, alpha::Real)
    n = length(h.pairs)
    for (i, (sub, from)) in enumerate(h.pairs)
        (sub isa VMobject && from isa VMobject) || continue
        a = _sub_alpha(h.base, alpha, i, n)
        # Back to the ORIGINAL points first: the deformation is a function of
        # α alone, never of the previous frame. That is what makes it seekable.
        set_points!(sub, get_points(from))
        has_points(sub) || continue
        apply_points_function!(_homotopy_at(h.f, a), sub; about_point = ORIGIN)
        h.smooth_handles && make_smooth!(sub; recurse = false)
    end
    return h
end

"""
    SmoothedVectorizedHomotopy(f, mobject; run_time = 3)

[`Homotopy`](@ref) with the Bézier handles re-fitted after every step —
ManimGL's name for `Homotopy(f, m; smooth_handles = true)`, and the same
object.

Use it when the deformation puts corners where the shape had smooth curves.
It re-fits handles; it does not add control points, so the straight-side
limit described in `Homotopy` still applies.
"""
SmoothedVectorizedHomotopy(f::Function, mob::Mobject; kw...) =
    Homotopy(f, mob; smooth_handles = true, kw...)

"""
    ComplexHomotopy(f, mobject; run_time = 3)

A [`Homotopy`](@ref) written in the complex plane: `f(z, t)` takes a `Complex`
and the time, and returns the new `Complex`. The z coordinate rides along
untouched.

```julia
play!(scene, ComplexHomotopy((z, t) -> z^(1 + t), grid))
```

The whole of conformal mapping is one line here, which is what the wrapper is
for; everything else is [`Homotopy`](@ref)'s.
"""
function ComplexHomotopy(f::Function, mob::Mobject; kw...)
    g(x, y, z, t) = begin
        w = f(complex(x, y), t)
        (real(w), imag(w), z)
    end
    return Homotopy(g, mob; kw...)
end

"""
    ApplyWave(mobject; direction = UP, amplitude = 0.2, ripples = 1, run_time = 2)

Send a wave across a mobject: a travelling displacement along `direction`,
sweeping from its left edge to its right.

```julia
play!(scene, ApplyWave(title))
play!(scene, ApplyWave(title; direction = RIGHT, amplitude = 0.4, ripples = 3))
```

The shape returns exactly to where it started — the displacement is zero at
both ends of the animation, which is what makes it an emphasis and not a move.
Manim CE's; ManimGL has no equivalent.

It rides on [`Homotopy`](@ref), so the same limit applies and matters here more
than anywhere: a wave crossing a plain `Square` moves its four corners and
nothing else. On text, on a plot or on any shape with many control points it
reads as a wave.
"""
function ApplyWave(mob::Mobject; direction = UP, amplitude::Real = 0.2,
                   ripples::Int = 1, run_time::Real = 2.0, kw...)
    ripples >= 1 || throw(ArgumentError("ripples must be at least 1, got $ripples"))
    left = Float64(get_bounding_box_point(mob, LEFT)[1])
    right = Float64(get_bounding_box_point(mob, RIGHT)[1])
    span = max(right - left, 1e-6)
    d = Point3f(direction)
    nrm = sqrt(sum(abs2, d))
    vect = nrm > 0 ? Float64(amplitude) .* (d ./ nrm) : Point3f(0, 0, 0)
    # A TRAVELLING WAVE, and the two factors are separate on purpose:
    #
    #   · `sin(TAU · ripples · (u − t))` is the shape in SPACE. `u` runs 0 → 1
    #     across the mobject, so `ripples` full crests fit along it whatever
    #     its width, and subtracting `t` makes them travel.
    #   · `sin(PI · t)` is the envelope in TIME: zero at both ends, so the
    #     mobject starts and finishes exactly where it was.
    #
    # WHY IT IS WRITTEN THIS WAY, because the obvious version is wrong and
    # looked right. The first draft used a window sliding in x, |phase| < 1
    # with phase spanning ONE unit across the mobject — so the whole mobject
    # sat inside half a window and every point saw nearly the same value. It
    # TRANSLATED the text instead of waving it. The maximum displacement said
    # 0.2694 and looked healthy; what gave it away was the MEAN, 0.268 over
    # 609 points, which is the same number. A wave whose mean displacement
    # equals its maximum is not a wave, and no render of a single frame shows
    # it — a uniformly shifted word looks like a word.
    function wave(x, y, z, t)
        u = (x - left) / span
        w = sin(TAU * ripples * (u - t)) * sin(PI * t)
        return (x + w * vect[1], y + w * vect[2], z + w * vect[3])
    end
    return Homotopy(wave, mob; run_time, kw...)
end

"""
    PhaseFlow(f, mobject; virtual_time = run_time, run_time = 3)

Let a VELOCITY FIELD carry the mobject: `f(p)` returns a vector, and every
frame the points move by `dt · f(p)`.

```julia
play!(scene, PhaseFlow(p -> Point3f(-p[2], p[1], 0), dots))   # rigid rotation
```

`virtual_time` is how much field-time passes over the animation; raise it to
travel further along the flow without making the animation longer.

**This one ACCUMULATES**, unlike every other animation in this family, and
that is manimlib's design rather than an oversight: integrating a field is
what makes a phase portrait, and the integral depends on the path. The
consequences are worth knowing: seeking to α = 0.5 is not the same as playing
to 0.5, the result depends on the frame rate, and its `rate_func` is `linear`
by default because a non-linear one would silently change how far the flow
travels rather than only when.

For a deformation that is a pure function of time, reach for
[`Homotopy`](@ref) instead.
"""
mutable struct PhaseFlow <: Animation
    base::AnimBase
    f::Function
    virtual_time::Float64
    last_alpha::Float64
end

function PhaseFlow(f::Function, mob::Mobject; run_time::Real = 3.0,
                   virtual_time = nothing, rate_func::Function = linear, kw...)
    rt = Float64(run_time)
    return PhaseFlow(AnimBase(; mobject = mob, run_time = rt, rate_func, kw...),
                     f, Float64(something(virtual_time, rt)), NaN)
end

function begin!(p::PhaseFlow)
    p.base.starting_mobject = copy(p.base.mobject)
    p.last_alpha = NaN                    # the first frame only sets the clock
    return p
end

function interpolate!(p::PhaseFlow, alpha::Real)
    if !isnan(p.last_alpha)
        dt = p.virtual_time * (Float64(alpha) - p.last_alpha)
        apply_points_function!(p.base.mobject; about_point = ORIGIN) do q
            q + Float32(dt) * Point3f(p.f(q))
        end
    end
    p.last_alpha = Float64(alpha)
    return p
end

# ── the ApplyMethod side of the family ──────────────────────────────────────
#
# These are NOT homotopies: they compute the FINAL state once and Transform
# towards it, which is Manim CE's `ApplyMethod` shape. Janim already has that
# mechanism — `animate(m, (f, args...))` — so each of these is the one line
# that says which function to apply, and they cost no machinery.

# `animate` calls op(target, args...), and `apply_points_function!` takes the
# FUNCTION first — this is the one-line adapter between the two orders.
# `about_point = ORIGIN` for the reason in THE FRAME at the top of this file.
_apply_to!(m::Mobject, f::F) where {F} =
    apply_points_function!(f, m; about_point = ORIGIN)

"""
    ApplyPointwiseFunction(f, mobject; run_time = 3)

Move every point of a mobject by `f(p)`, animating from where it was to where
`f` sends it:

```julia
play!(scene, ApplyPointwiseFunction(p -> 2 * p, square))
```

Unlike [`Homotopy`](@ref) this asks `f` ONCE and interpolates towards the
answer, so the points travel in straight lines however curved `f` is. Reach
for `Homotopy` when the path matters and for this when only the destination
does.
"""
ApplyPointwiseFunction(f::Function, mob::Mobject; run_time::Real = 3.0, kw...) =
    animate(mob, (_apply_to!, f); run_time, kw...)

"""
    ApplyMatrix(matrix, mobject; about_point = ORIGIN, run_time = 3)

Apply a linear map to a mobject — the animation every linear-algebra
explanation is made of:

```julia
play!(scene, ApplyMatrix([1 1; 0 2/3], plane))
play!(scene, ApplyMatrix([0 -1; 1 0], square))      # a quarter turn
```

A 2×2 matrix is lifted to 3×3 with the z axis left alone, as Manim CE does; a
3×3 is used as given, and anything else is an error rather than a guess.
`about_point` is the origin the map is taken about.
"""
function ApplyMatrix(matrix, mob::Mobject; about_point = ORIGIN,
                     run_time::Real = 3.0, kw...)
    M = Array{Float64}(matrix)
    if size(M) == (2, 2)
        full = zeros(Float64, 3, 3)
        full[1:2, 1:2] = M
        full[3, 3] = 1.0
        M = full
    end
    size(M) == (3, 3) || throw(ArgumentError(
        "ApplyMatrix takes a 2×2 or a 3×3 matrix, got $(size(M, 1))×$(size(M, 2))"))
    o = Point3f(about_point)
    f(p) = Point3f(M * (Float64.(p) - Float64.(o))) + o
    return ApplyPointwiseFunction(f, mob; run_time, kw...)
end

"""
    ApplyComplexFunction(f, mobject; run_time = 3)

Apply a complex map `f(z)` to a mobject, treating the xy plane as ℂ:

```julia
play!(scene, ApplyComplexFunction(z -> z^2, grid))
play!(scene, ApplyComplexFunction(exp, square))
```

The z coordinate is untouched. For a map that should be watched DEFORMING
rather than jumping to its result, use [`ComplexHomotopy`](@ref) — the same
function with `t` interpolating towards it.
"""
function ApplyComplexFunction(f::Function, mob::Mobject; kw...)
    g(p) = begin
        w = f(complex(Float64(p[1]), Float64(p[2])))
        Point3f(real(w), imag(w), p[3])
    end
    return ApplyPointwiseFunction(g, mob; kw...)
end

# ── the animations over save_state!/generate_target! ────────────────────────
#
# Three one-liners over `Transform`, and that is the point: the mechanism is
# the photograph (core/states.jl), and these just say which copy to travel to.

"""
    Restore(m; run_time = 1, …)

Animate `m` back to the state [`save_state!`](@ref) photographed:

```julia
save_state!(formula)
play!(scene, animate(formula, (scale!, 2.0), (center!,)))
wait!(scene, 1.0)
play!(scene, Restore(formula))
```

The pair `save_state!` / `Restore` is what makes "go and come back" one line
instead of a record of every change you made on the way out.

Restoring without having saved is an error naming the mobject, not a silent
no-op — a scene that quietly does not come back is worse than one that stops.
"""
Restore(m::Mobject; kw...) = Transform(m, get_saved_state(m); kw...)

"""
    MoveToTarget(m; run_time = 1, …)

Animate `m` towards the target built with [`generate_target!`](@ref):

```julia
t = generate_target!(dots)
for (i, d) in enumerate(t)
    shift!(d, 0.4 * i * UP)
end
play!(scene, MoveToTarget(dots))
```

Use it when the end state takes a loop or a handful of statements to describe.
For one or two calls, [`animate`](@ref) says the same thing shorter.
"""
MoveToTarget(m::Mobject; kw...) = Transform(m, get_target(m); kw...)

"""
    ApplyFunction(f, m; run_time = 1, …)

Animate `m` towards `f(copy(m))` — a whole transformation written as a
function of the mobject:

```julia
play!(scene, ApplyFunction(square) do m
    shift!(m, 2 * RIGHT)
    set_fill!(m; color = YELLOW, opacity = 1.0)
    rotate!(m, PI / 4)
    m
end)
```

`f` receives a COPY and must return a mobject — returning something else is an
error, because the alternative is a `Transform` towards `nothing` that fails
somewhere far from the mistake.

Against [`generate_target!`](@ref): the same idea with the copy handled for
you, and the end state written as an expression instead of a variable.
"""
function ApplyFunction(f::Function, m::Mobject; kw...)
    target = f(copy(m))
    target isa Mobject || throw(ArgumentError(
        "the function passed to ApplyFunction must return a mobject, and " *
        "this one returned a $(typeof(target)) — mutating verbs like shift! " *
        "return the mobject, so ending the function with `m` is usually it"))
    return Transform(m, target; kw...)
end

"""
    ApplyMethod(m, (f, args...), …; run_time = 1, …)

Manim CE's name for what Janim spells [`animate`](@ref):

```julia
play!(scene, ApplyMethod(square, (shift!, 2 * RIGHT), (rotate!, PI / 4)))
play!(scene, animate(square, (shift!, 2 * RIGHT), (rotate!, PI / 4)))
```

The two are the SAME object, so a scene ported from CE reads unchanged.
`animate` is the name to prefer in new code: `.animate` is what both engines
now push, and CE keeps `ApplyMethod` for compatibility.

Note the shape of the arguments. CE writes `ApplyMethod(m.shift, RIGHT)` — a
BOUND method — which Julia has no equivalent for, so here the mobject and the
function are separate and the call is a tuple: `(shift!, RIGHT)`.
"""
ApplyMethod(m::Mobject, ops...; kw...) = animate(m, ops...; kw...)
