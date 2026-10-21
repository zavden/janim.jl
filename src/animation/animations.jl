# The animation system — a port of manimlib/animation/{animation,transform,
# creation,fading,composition}.py with this life cycle:
#
#     begin!(anim)                 ← snapshot the start, align, α=0
#     interpolate!(anim, α) × N    ← the rate_func lives INSIDE (get_sub_alpha)
#     finish!(anim)                ← exact α=1 and cleanup
#
# Scene.play and Timeline both make exactly these three calls.

"Fields shared by every animation (composition: Julia does not inherit fields)."
Base.@kwdef mutable struct AnimBase
    mobject::Mobject
    run_time::Float64 = 1.0
    rate_func::Function = smooth
    lag_ratio::Float64 = 0.0
    remover::Bool = false
    starting_mobject::Union{Nothing,Mobject} = nothing
    # What `finish!` interpolates TO (GL's `final_alpha_value`): 1.0 for
    # everything that should end on its target, 0.0 for a FadeOut, which
    # hands the mobject back as it was and lets the STAGE hide it (remover).
    final_alpha::Float64 = 1.0
    # The (mobject, starting) pairs the generic `begin!` photographs
    # for an animation written with `interpolate_submobject` alone (GL's
    # `families`).
    families::Vector{NTuple{2,Mobject}} = NTuple{2,Mobject}[]
end

"""
    Animation

The abstract supertype of everything [`play!`](@ref) can play.

An animation is a plan, not an effect: building one changes nothing, and it is
`play!` that runs its three-call life cycle —

    begin!(a)                 snapshot the starting state, align, jump to α = 0
    interpolate!(a, α) × N    once per frame, α from the rate function
    finish!(a)                land exactly on α = 1 and clean up

Every animation carries the same shared fields, and they are all keywords of
every constructor:

| keyword | what it does |
|---|---|
| `run_time` | how many seconds (`play!` can override it) |
| `rate_func` | how α moves inside that time — see [`smooth`](@ref) |
| `lag_ratio` | delay between one child and the next, as a fraction |
| `remover` | take the mobject off stage when it finishes |
| `final_alpha` | where [`finish!`](@ref) lands: `1.0` on the target, `0.0` back at the start — a [`FadeOut`](@ref) hands the mobject back intact and the remover hides it (ManimGL's `final_alpha_value`) |

A fourth call closes the cycle on stage: `play!` follows `finish!` with
[`clean_up!`](@ref)`(a, stage)`, where removers leave and the Transform
variants swap source for target — the same on a `Scene` and on a
[`Timeline`](@ref).

**`rate_func` belongs here and never to `play!`.** `play!` knows about time;
how progress is spread over that time is the animation's business, and that
split is what makes the same animation behave identically under `play!`, under
[`Timeline`](@ref) and under [`render_frame`](@ref).

To write one of your own, see [`UpdateFromAlphaFunc`](@ref) first — it covers
most cases without a new type. When it does not, a struct with a `base::AnimBase`
plus ONE method, [`interpolate_submobject`](@ref), is a complete animation:
the generic `begin!` photographs the family and the generic `interpolate!`
hands each member its [`sub_alpha`](@ref) (ManimGL's `Animation` base class).
"""
abstract type Animation end

"""
    get_run_time(a) → Float64

How many seconds the animation asks for. [`play!`](@ref) can override it, and
composed animations compute theirs from their children — an
[`AnimationGroup`](@ref) is as long as its longest member finishing last.
"""
get_run_time(a::Animation) = a.base.run_time

"""
    is_remover(a) → Bool

Whether the scene should take the mobject OFF stage when this animation
finishes. True for [`FadeOut`](@ref), [`Uncreate`](@ref) and
[`Unwrite`](@ref) — which is why the thing that faded out does not reappear on
the next frame, and why it is not enough to leave it at opacity zero.
"""
is_remover(a::Animation) = a.base.remover
mobject_of(a::Animation) = a.base.mobject

"""
    _check_duration(rt, fps, what) → Float64

Reject a non-finite, negative or counter-overflowing duration BEFORE any
frame is reserved: `max(1, round(Int, rt * fps))` would turn `run_time = -0.1`
into one frame without a word, and a real-clock preview loop would turn a NaN
into zero frames. Every `play!`/`wait!` entry — Timeline and Scene — passes through
here first, which is what covers all of those branches at once.
"""
function _check_duration(rt::Real, fps::Real, what::AbstractString)
    isfinite(rt) && rt >= 0 || throw(ArgumentError(
        "$what must be finite and ≥ 0, got $rt"))
    rt * fps < 4.0e18 || throw(ArgumentError(
        "$what = $rt at $fps fps overflows the frame counter"))
    return Float64(rt)
end

"""
    sub_alpha(base, α, i, n) → Float64
    sub_alpha(anim, α, i, n)

The α family member `i` of `n` sees at global progress `α`: `lag_ratio`
staggers the members — member `i` starts when `α·((n − 1)·lag_ratio + 1)`
passes `(i − 1)·lag_ratio` — and the `rate_func` is applied INSIDE, per
member (animation.py:168 `get_sub_alpha`). This is what every animation
here calls in its `interpolate!`, and what an animation of your own gets
for free through [`interpolate_submobject`](@ref). Identical to ManimGL's
`get_sub_alpha`.
"""
function sub_alpha(b::AnimBase, alpha::Real, i::Int, n::Int)
    total = (n - 1) * b.lag_ratio + 1
    raw = clamp(alpha * total - (i - 1) * b.lag_ratio, 0, 1)
    return b.rate_func(raw)
end
sub_alpha(a::Animation, alpha::Real, i::Int, n::Int) = sub_alpha(a.base, alpha, i, n)
const _sub_alpha = sub_alpha           # internal alias

"Paired families, checked for compatible trees (as ManimGL demands)."
function _families(mobs::Mobject...)
    fams = map(get_family, mobs)
    n = length(fams[1])
    all(f -> length(f) == n, fams) || throw(ArgumentError(
        "the families do not match ($(join(length.(fams), " vs ")) members) — " *
        "both mobjects must have the same tree of children"))
    return [Tuple(f[i] for f in fams) for i in 1:n]
end

# ═══════════════════════════════════════════════════════════════════════
# Transform — the heart of it (transform.py:54)
# ═══════════════════════════════════════════════════════════════════════

mutable struct Transform <: Animation
    base::AnimBase
    target::Union{Nothing,Mobject}
    target_copy::Union{Nothing,Mobject}
    # both ends are created IN begin! (GL's create_target/
    # create_starting_mobject) — they capture the mobject's state at that
    # moment, not when the animation was built: crucial for chaining in
    # Succession
    create_target::Any                  # () -> Mobject (fresh, ours)
    create_starting::Any                # nothing | () -> Mobject
    pairs::Vector{NTuple{3,Mobject}}
    animatable::Vector{Bool}            # the contract trait, resolved in begin!
    # What the SCENE should do when this ends. Defaults to false: a plain
    # Transform leaves the scene holding the original mobject.
    replace_in_scene::Bool              # ReplacementTransform: swap mob → target
    # The trajectory each point follows. 0 = the straight lerp (the plain code
    # path); anything else bends every point onto an arc of that angle — what
    # SpinInFromNothing is made of.
    path_arc::Float64
    path_arc_axis::Point3f
    # How `align_data!` pads a shorter family: `:invisible` copies as
    # ManimGL, or `:visible` copies.
    padding::Symbol
end

# The 7-argument form: the replace flag and the path arc default to "off".
Transform(base::AnimBase, target, target_copy, create_target, create_starting,
          pairs::Vector{NTuple{3,Mobject}}, animatable::Vector{Bool}) =
    Transform(base, target, target_copy, create_target, create_starting,
              pairs, animatable, false, 0.0, Point3f(OUT), :invisible)
# The 10-argument form (sugar.jl's CyclicReplace) takes no padding.
Transform(base::AnimBase, target, target_copy, create_target, create_starting,
          pairs::Vector{NTuple{3,Mobject}}, animatable::Vector{Bool},
          replace_in_scene::Bool, path_arc::Real, path_arc_axis) =
    Transform(base, target, target_copy, create_target, create_starting,
              pairs, animatable, replace_in_scene, Float64(path_arc),
              Point3f(path_arc_axis), :invisible)

"""
    Transform(mob, target; path_arc=0, path_arc_axis=OUT, padding=:invisible, kw...)

Morph `mob` into `target`. With `path_arc`, every point travels along an arc
of that angle instead of the straight chord — manimlib's `path_arc`, and the
reason `Transform(a, b; path_arc=PI/2)` reads as a swing rather than a slide.

When the two families differ in size, the shorter one is padded so that
every child has a partner — with INVISIBLE copies, as ManimGL does, so in
the middle of a formula morph a glyph travels and its extra partner emerges
from nothing where the target needs one. `padding = :visible` pads with
visible copies instead (one glyph splits in two that travel). See [`align_data!`](@ref).
"""
function Transform(mob::Mobject, target::Mobject; remover::Bool = false,
                   path_arc::Real = 0.0, path_arc_axis = OUT,
                   padding::Symbol = :invisible, kw...)
    _check_padding(padding)
    t = Transform(AnimBase(; mobject = mob, remover, kw...),
                  target, nothing, () -> copy(target), nothing,
                  NTuple{3,Mobject}[], Bool[])
    t.path_arc = Float64(path_arc)
    t.path_arc_axis = Point3f(path_arc_axis)
    t.padding = padding
    return t
end

# Transform speaks ONLY the interpolation contract (core/interpolable.jl):
# is_interpolable / copy / align_data! / interpolate!. It never mentions
# VMobject — that is why ValueTracker and the animatable 2D camera each need
# only a few lines and no edits to this file.
"""
    begin!(a) → a

Start an animation: snapshot whatever it needs to interpolate FROM, align the
structures involved, and put the mobject at α = 0.

[`play!`](@ref) calls this for you. You call it yourself when you drive an
animation by hand — the whole life cycle is `begin!`, then
[`interpolate!`](@ref) once per frame, then [`finish!`](@ref):

```julia
a = Transform(c, Square())
begin!(a)
for α in range(0, 1; length = 30)
    interpolate!(a, α)
end
finish!(a)
```

The snapshot is why order matters: everything the animation is going to read
off the mobject is read HERE, so styling it afterwards changes the target and
not the starting point.
"""
function begin!(t::Transform)
    mob = t.base.mobject
    is_interpolable(mob) || throw(ArgumentError(
        "I do not know how to interpolate a $(typeof(mob)): it does not " *
        "fulfil the interpolation contract (is_interpolable/copy/" *
        "interpolate!/become!). Wrap it in something that does, or implement " *
        "the contract."))
    # the target materialises NOW; the user's target is never mutated
    t.target_copy = t.create_target()
    t.create_starting === nothing || become!(mob, t.create_starting())
    _align_pair!(mob, t.target_copy, t.padding)      # the contract hook (padded)
    t.base.starting_mobject = copy(mob)              # the snapshot, ALREADY aligned
    t.pairs = _families(mob, t.base.starting_mobject, t.target_copy)
    # A wrapper (a DecimalNumber, an Axes) is not in its own family —
    # the renderer only ever meets VMobjects — but its OWN state, a number's
    # value, has to move too: pair the root itself when the family did not.
    if isempty(t.pairs) || t.pairs[1][1] !== mob
        pushfirst!(t.pairs, (mob, t.base.starting_mobject, t.target_copy))
    end
    # A non-interpolable member of the family (a Surface inside a VGroup) is
    # SKIPPED, not fatal — and index i is preserved so lag_ratio spreads
    # exactly as if it were there.
    t.animatable = [all(is_interpolable, pair) for pair in t.pairs]
    interpolate!(t, 0.0)
    return t
end

function interpolate!(t::Transform, alpha::Real)
    n = length(t.pairs)
    for i in 1:n
        t.animatable[i] || continue
        sub, from, to = t.pairs[i]
        a = _sub_alpha(t.base, alpha, i, n)
        interpolate!(sub, from, to, a)
        _apply_path_arc!(sub, from, to, a, t.path_arc, t.path_arc_axis)
    end
    return t
end

# ── curved trajectories (manimlib/utils/paths.py:path_along_arc) ──────
# Below this angle manimlib returns the straight path outright: the arc centre
# goes to infinity as the angle goes to zero (it divides by tan(θ/2)).
const _STRAIGHT_PATH_THRESHOLD = 0.01

"""
Bend the already-interpolated points onto an arc: each point rides the circle
through its start and end whose central angle is `arc`.

The α ∈ {0,1} short circuit is not an optimisation — it is the contract. The
closed form lands ~1e-7 off its own endpoints, whereas `interpolate!` copies
the ends literally precisely so animations END on their targets. A curved path
must not give that up.
"""
function _apply_path_arc!(sub, from, to, alpha::Real, arc::Real, axis::Point3f)
    abs(arc) < _STRAIGHT_PATH_THRESHOLD && return
    (alpha == 0 || alpha == 1) && return
    (sub isa VMobject && from isa VMobject && to isa VMobject) || return
    u = axis / Float32(norm(axis))
    half = tan(arc / 2)
    ca, sa = cos(alpha * arc), sin(alpha * arc)
    @inbounds for i in eachindex(sub.points)
        s, e = from.points[i], to.points[i]
        mid = (e - s) / 2
        centre = s + mid + Point3f(cross(u, mid) / half)
        c2s = s - centre
        c2p = Point3f(cross(u, c2s))
        sub.points[i] = Point3f(centre + ca * c2s + sa * c2p)
    end
    _note_data_changed!(sub)
    return
end

# ═══════════════════════════════════════════════════════════════════════
# ShowCreation / Create — partial drawing as an animation (creation.py:33)
# ═══════════════════════════════════════════════════════════════════════

"""
    ShowCreation(m; run_time, rate_func, lag_ratio)

Draw `m` as if by a pen: the path grows from its start to its end.

```julia
play!(scene, ShowCreation(c); run_time = 2)
play!(scene, ShowCreation(g; lag_ratio = 0.2))   # one child after another
```

It works on the POINTS, so where the drawing starts is where the path starts —
a [`Circle`](@ref)'s `start_angle` decides where the pen touches down. For text
and formulas the equivalent is [`Write`](@ref), which draws glyph by glyph
instead of stroke by stroke.

`lag_ratio` staggers the children of a group, which is what turns "draw these
five things" into a cascade rather than five simultaneous scribbles.
[`Uncreate`](@ref) is this in reverse, and it hands the mobject back INTACT
rather than leaving an empty husk.
"""
mutable struct ShowCreation <: Animation
    base::AnimBase
    pairs::Vector{NTuple{2,Mobject}}
end

# `lag_ratio = 1.0`, ManimGL's (`creation.py:49`) — over a group
# the children are drawn ONE AFTER ANOTHER, which is what makes a formula
# write itself glyph by glyph instead of blooming all at once. It goes BEFORE
# `kw...` so `ShowCreation(g; lag_ratio = 0.0)` still asks for all at once
# (the later keyword wins), and `Uncreate` inherits it, as in GL.
ShowCreation(mob::Mobject; kw...) =
    ShowCreation(AnimBase(; mobject = mob, lag_ratio = 1.0, kw...), NTuple{2,Mobject}[])

"""
    Create(m; kw...)

Manim CE's name for [`ShowCreation`](@ref) — the SAME object, not a wrapper, so
a scene ported from either dialect runs unchanged. ManimGL spells it
`ShowCreation`; both names are exported.
"""
const Create = ShowCreation           # CE's name, same mechanism

function begin!(c::ShowCreation)
    c.base.starting_mobject = copy(c.base.mobject)
    c.pairs = _families(c.base.mobject, c.base.starting_mobject)
    interpolate!(c, 0.0)
    return c
end

function interpolate!(c::ShowCreation, alpha::Real)
    n = length(c.pairs)
    for (i, (sub, from)) in enumerate(c.pairs)
        # drawing "half a curve" is a vector-path notion, not part of the
        # interpolation contract: here the type DOES decide.
        sub isa VMobject || continue
        pointwise_become_partial!(sub, from, 0, _sub_alpha(c.base, alpha, i, n))
    end
    return c
end

# An UNdrawing (Uncreate) ends with every point collapsed onto the start
# of its path. Manim leaves that husk behind, so `self.add(sq)` after an
# Uncreate shows nothing and the bug looks like the renderer's. Since the
# mobject is on its way OUT of the scene anyway, we hand it back intact — the
# last drawn frame is unaffected (finish! runs after it).
function finish!(c::ShowCreation)
    interpolate!(c, c.base.final_alpha)
    is_remover(c) && c.base.starting_mobject !== nothing &&
        become!(c.base.mobject, c.base.starting_mobject)
    return c
end

# ═══════════════════════════════════════════════════════════════════════
# Fades — Transforms in disguise (fading.py:35)
# ═══════════════════════════════════════════════════════════════════════

# Through the contract, not through the stroke: `set_opacity!` exists for
# every type that draws (a Group reaches its members), while `set_stroke!`
# would fail INSIDE play! for an ImageMobject, a DotCloud or a Group.
function _faded_copy(mob::Mobject, shift_val, scale_val::Real = 1.0)
    m = copy(mob)
    # `scale` (fading.py:27): the far end of the fade is scaled about
    # its own centre; 1 is skipped so a plain fade touches no byte.
    scale_val == 1 || (applicable(scale!, m, Float64(scale_val)) &&
                       scale!(m, Float64(scale_val)))
    shift_val == ORIGIN || (applicable(shift!, m, Point3f(shift_val)) &&
                            shift!(m, Point3f(shift_val)))
    applicable(set_opacity!, m, 0.0) && set_opacity!(m, 0.0)
    return m
end

_check_fade_scale(s::Real) = (isfinite(s) && s > 0) || throw(ArgumentError(
    "scale must be a positive finite number, got $s"))

"""
    FadeIn(m; shift = ORIGIN, scale = 1, kw...)

Appear: fade in from a transparent copy displaced by `-shift` and scaled by
`1/scale` — `FadeIn(m; shift = UP)` rises into place, `FadeIn(m; scale = 2)`
grows into place from half its size (fading.py:35). It fades towards the
mobject's CURRENT state, so something already at opacity zero stays there;
[`Transform`](@ref) towards a copy carrying the target opacity is the idiom.
"""
function FadeIn(mob::Mobject; shift = ORIGIN, scale::Real = 1.0, kw...)
    _check_fade_scale(scale)
    t = Transform(AnimBase(; mobject = mob, kw...), nothing, nothing,
                  () -> copy(mob),                        # the end: as it stands
                  () -> _faded_copy(mob, -Point3f(shift), 1 / scale),  # the start
                  NTuple{3,Mobject}[], Bool[])
    return t
end

"""
    FadeOut(m; shift = ORIGIN, scale = 1, final_alpha = 0.0, kw...)

Disappear: fade to a transparent copy displaced by `shift` and scaled by
`scale`, and tell the stage to drop the mobject (a remover).

The mobject is handed back AS IT WAS — ManimGL's `final_alpha_value =
0.0` («put it back in original state when done», fading.py:53): `finish!`
lands on the start, and it is the stage that hides it. So a later
`ShowCreation` or `FadeIn` of the same mobject shows the real thing, a
`Succession(FadeOut(m), FadeIn(m))` ends visible, and [`Blink`](@ref) leaves
the scene as it found it. `FadeOut(m; final_alpha = 1.0)` leaves it at
opacity zero instead.
"""
function FadeOut(mob::Mobject; shift = ORIGIN, scale::Real = 1.0, kw...)
    _check_fade_scale(scale)
    Transform(AnimBase(; mobject = mob, remover = true, final_alpha = 0.0, kw...),
              nothing, nothing,
              () -> _faded_copy(mob, Point3f(shift), scale), nothing,
              NTuple{3,Mobject}[], Bool[])
end

# ═══════════════════════════════════════════════════════════════════════
# The algebra of time (composition.py:90): AnimationGroup and friends
# ═══════════════════════════════════════════════════════════════════════

mutable struct AnimationGroup <: Animation
    base::AnimBase
    animations::Vector{Animation}
    anims_with_timings::Vector{Tuple{Animation,Float64,Float64}}
    max_end_time::Float64
end

"""
    AnimationGroup(anims...; lag_ratio=0, run_time=-1)

start[k+1] = interpolate(start[k], end[k], lag_ratio):
lag 0 = all at once · lag 1 = one after another (Succession) · small lag = a
cascade (LaggedStart). run_time=-1 → the end of the last one.

**Never put two animations over the SAME mobject in one of these**, however
tempting the `lag_ratio = 1` shortcut looks. Every child is begun at once —
ManimGL and CE do the same, and the timings are only consulted afterwards — so
the second child snapshots the state the first one is about to leave, and then
restores that snapshot on every frame. [`Succession`](@ref) exists for this: it
begins each child when its turn arrives.

Built that way, `Flash` and `Circumscribe` would draw literally NOTHING at any
instant of their runs while every property one might check — line count, box
size, rate windows, remover-ness — stayed correct. `TransformMatchingTex`
composes over copies and `TypeWithCursor` over two different mobjects, which
is why they are safe.
"""
function AnimationGroup(anims::Animation...; lag_ratio::Real = 0.0,
                        run_time::Real = -1.0, kw...)
    awt = Tuple{Animation,Float64,Float64}[]
    t = 0.0
    for a in anims
        stop = t + get_run_time(a)
        push!(awt, (a, t, stop))
        t = t + lag_ratio * (stop - t)
    end
    met = maximum(last.(awt); init = 0.0)
    rt = run_time < 0 ? met : Float64(run_time)
    # VGroup only when every member is vector geometry; a group that has to
    # hold a ValueTracker or a CameraFrame needs the heterogeneous Group.
    mobs = [mobject_of(a) for a in anims]
    group = all(m -> m isa VMobject, mobs) ? VGroup(mobs...) : Group(mobs...)
    AnimationGroup(AnimBase(; mobject = group, run_time = rt,
                            lag_ratio = Float64(lag_ratio), kw...),
                   collect(Animation, anims), awt, met)
end

"""
    LaggedStart(anims...; lag_ratio = 0.05, run_time = -1)

Start the animations one shortly after another, overlapping — the cascade.

```julia
play!(scene, LaggedStart([FadeIn(d) for d in dots]...; lag_ratio = 0.1))
```

It is [`AnimationGroup`](@ref) with a small default lag, and the whole
difference between "five things appear" and "five things ripple into place" is
that number. `lag_ratio = 0` is simultaneous and `1` is
[`Succession`](@ref); anything between them overlaps.
"""
LaggedStart(anims::Animation...; lag_ratio::Real = 0.05, kw...) =
    AnimationGroup(anims...; lag_ratio, kw...)

# ── Succession: LAZY begin (composition.py:118) ─────────────────────────
# It chains over the SAME mobject: each animation starts when its turn comes
# (finish of the previous one → begin of the next). Starting them all at once
# — what AnimationGroup does — would snapshot the wrong states.

"""
    Succession(anims...; run_time = -1)

Play the animations strictly one after another, in one `play!`.

```julia
play!(scene, Succession(FadeIn(a), Transform(a, b), FadeOut(a)))
```

Not the same as [`AnimationGroup`](@ref) with `lag_ratio = 1`, even though the
timings match: a Succession begins each animation LAZILY, when its turn
arrives. That is what makes chaining several animations over the SAME mobject
correct — the second one snapshots the state the first one left, instead of the
state everything had at the start.
"""
mutable struct Succession <: Animation
    base::AnimBase
    animations::Vector{Animation}
    anims_with_timings::Vector{Tuple{Animation,Float64,Float64}}
    active::Int
end

function Succession(anims::Animation...; kw...)
    g = AnimationGroup(anims...; lag_ratio = 1.0, kw...)   # reuse the time algebra
    Succession(g.base, g.animations, g.anims_with_timings, 0)
end

function begin!(s::Succession)
    isempty(s.animations) && throw(ArgumentError("Succession without animations"))
    s.active = 1
    begin!(s.animations[1])
    return s
end

function interpolate!(s::Succession, alpha::Real)
    idx0, sub = integer_interpolate(0, length(s.animations), alpha)
    i = idx0 + 1
    if i != s.active
        finish!(s.animations[s.active])
        begin!(s.animations[i])
        s.active = i
    end
    interpolate!(s.animations[i], sub)
    return s
end

finish!(s::Succession) = (finish!(s.animations[s.active]); s)

"""
    _leaf_animations(a) → Vector{Animation}

The leaf animations under `a`, recursing through `AnimationGroup` and
`Succession` (`LaggedStart` IS an `AnimationGroup`; everything else — a
`TransformMatchingTex` included — is a leaf that owns its mobject).

What a scene registers as roots and what the removers act on are the
LEAVES' mobjects, exactly as ManimGL adds each one to `scene.mobjects`
separately. Registering the container's synthetic `VGroup`/`Group` instead
would make removers silently no-op, make `remove!` do nothing, draw a later
`add!`ed mobject twice, and stack a `ReplacementTransform`'s source over its
target.
"""
function _leaf_animations(a::Animation)
    a isa AnimationGroup || a isa Succession || return Animation[a]
    leaves = Animation[]
    for child in a.animations
        append!(leaves, _leaf_animations(child))
    end
    return leaves
end

function begin!(g::AnimationGroup)
    foreach(begin!, g.animations)
    interpolate!(g, 0.0)
    return g
end

"Spread global time: sub_α = clip((t − start)/duration, 0, 1)."
function interpolate!(g::AnimationGroup, alpha::Real)
    t = alpha * g.max_end_time
    for (a, from, to) in g.anims_with_timings
        dur = to - from
        interpolate!(a, dur == 0 ? 0.0 : clamp((t - from) / dur, 0, 1))
    end
    return g
end

# ═══════════════════════════════════════════════════════════════════════

"""
    finish!(a) → a

The third act of the life cycle: land exactly on `final_alpha` (1.0 for
almost everything, 0.0 for a [`FadeOut`](@ref), which hands the mobject
back as it started) and do whatever the animation has to do to leave the
mobject usable. The stage's own clean-up is the fourth act,
[`clean_up!`](@ref).
"""
function finish!(a::Animation)
    interpolate!(a, a.base.final_alpha)
    return a
end
finish!(g::AnimationGroup) = (interpolate!(g, 1.0); foreach(finish!, g.animations); g)

# ═══════════════════════════════════════════════════════════════════════
# The generic life cycle (animation.py:63-160): an animation of your
# own needs a `base::AnimBase` and ONE method, interpolate_submobject.
# ═══════════════════════════════════════════════════════════════════════

"""
    interpolate_submobject(anim, sub, from, α)

The per-member hook of an animation written against the family (ManimGL's
`Animation.interpolate_submobject`): `sub` is one member of the animated
mobject's family, `from` its photograph taken by `begin!`, and `α` already
carries the rate function and the lag (see [`sub_alpha`](@ref)). The
default does nothing; define it for your type and the generic `begin!` and
`interpolate!` do the rest:

```julia
mutable struct Slide <: Animation
    base::AnimBase
end
Slide(m; kw...) = Slide(AnimBase(; mobject = m, kw...))
function Janim.interpolate_submobject(::Slide, sub, from, α)
    sub isa VMobject && set_points!(sub, [p + Float32(α) * RIGHT for p in from.points])
    nothing
end
play!(scene, Slide(group; lag_ratio = 0.3))
```
"""
interpolate_submobject(::Animation, ::Mobject, ::Mobject, ::Real) = nothing

function begin!(a::Animation)
    mob = mobject_of(a)
    a.base.starting_mobject = copy(mob)
    a.base.families = _families(mob, a.base.starting_mobject)
    interpolate!(a, 0.0)
    return a
end

function interpolate!(a::Animation, alpha::Real)
    fams = a.base.families
    n = length(fams)
    for (i, (sub, from)) in enumerate(fams)
        interpolate_submobject(a, sub, from, sub_alpha(a.base, alpha, i, n))
    end
    return a
end

# ═══════════════════════════════════════════════════════════════════════
# clean_up!: the fourth act, on the STAGE (animation.py:85
# clean_up_from_scene). It is shared by Scene and Timeline, so
# ReplacementTransform and TransformMatchingTex clean up after themselves on
# either.
# ═══════════════════════════════════════════════════════════════════════

"""
    clean_up!(anim, stage) → anim

What the STAGE does with an animation's mobjects once it has finished —
ManimGL's `clean_up_from_scene`. [`play!`](@ref) calls it right after
[`finish!`](@ref), on a `Scene` and on a [`Timeline`](@ref) alike: a
remover takes its mobject off the stage; [`ReplacementTransform`](@ref)
swaps the source for the target; [`TransformMatchingTex`](@ref) and
[`FadeTransform`](@ref) leave the REAL target where the source stood (its
layer, if a composition drew it); [`Wait`](@ref) removes its marker. A
composed animation hands it to its children — the group's own `remover`
flag is not consulted, exactly as in GL: the leaves remove.

`stage` is anything with `add!` and `remove!`. Write a method for an
animation of your own that has to add or remove something when it ends.
"""
function clean_up!(a::Animation, stage)
    is_remover(a) && remove!(stage, mobject_of(a))
    return a
end

function clean_up!(g::AnimationGroup, stage)
    for a in g.animations
        clean_up!(a, stage)
    end
    return g
end

function clean_up!(s::Succession, stage)     # GL: inherits AnimationGroup's
    for a in s.animations
        clean_up!(a, stage)
    end
    return s
end

# ReplacementTransform leaves the TARGET in the scene, not the source
# wearing the target's shape. Doing it here (and not inside interpolate!)
# keeps the animation ignorant of which stage is driving it.
function clean_up!(t::Transform, stage)
    is_remover(t) && remove!(stage, mobject_of(t))
    if t.replace_in_scene && t.target !== nothing
        _stage_replace!(stage, mobject_of(t), t.target)
    end
    return t
end

"""
Put `new` where `old` stood — GL's `scene.remove(old); scene.add(new)`. A
Scene with a composition swaps inside the layer that drew `old` (scene.jl),
since the roots are not what a composition draws.
"""
function _stage_replace!(stage, old::Mobject, new::Mobject)
    remove!(stage, old)
    add!(stage, new)
    return stage
end

"""
    Wait(t = 1.0)

A pause as an animation, for composing: `AnimationGroup(Wait(1), FadeIn(x);
lag_ratio = 1)` starts the fade one second in, and a `Succession` reads as a
storyboard with its beats. On its own, `wait!(scene, t)` is the everyday
form (it takes an animation number too). Manim CE's name; ManimGL
writes `Animation(Mobject(), run_time = t)`. It carries an empty marker
mobject that `clean_up!` removes, so a Wait leaves nothing behind.
"""
mutable struct Wait <: Animation
    base::AnimBase
end
Wait(t::Real = 1.0; kw...) = Wait(AnimBase(; mobject = VGroup(), run_time = Float64(t), kw...))
clean_up!(w::Wait, stage) = (remove!(stage, mobject_of(w)); w)

"""
    turn_animation_into_updater(anim; cycle = false) → mobject

Run `anim` as an UPDATER of its own mobject instead of through `play!`
(mobject_update_utils.py:83): `begin!` now, then each frame advances the
animation by the frame's `dt`, and when the run time is up it calls
`finish!` and removes itself. With `cycle = true` it wraps around and never
stops. The frame's α is the time accumulated BEFORE that frame, as in GL —
so it lags `play!`'s midpoint sampling by half a frame, on purpose: it is
the same code path as ManimGL's.

```julia
turn_animation_into_updater(Rotating(wheel; run_time = 4); cycle = true)
add!(scene, wheel)
wait!(scene, 10)          # the wheel keeps turning through every wait
```
"""
function turn_animation_into_updater(anim::Animation; cycle::Bool = false)
    mob = mobject_of(anim)
    begin!(anim)
    total = Ref(0.0)
    update = nothing
    update = function (m, dt)
        rt = get_run_time(anim)
        ratio = rt > 0 ? total[] / rt : 1.0
        if cycle
            alpha = ratio - floor(ratio)
        else
            alpha = clamp(ratio, 0.0, 1.0)
            if alpha >= 1
                finish!(anim)
                remove_updater!(m, update)
                return nothing
            end
        end
        interpolate!(anim, alpha)
        total[] += dt
        return nothing
    end
    add_updater!(mob, update)
    return mob
end
