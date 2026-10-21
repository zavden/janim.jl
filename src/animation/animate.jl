# The `.animate` idiom and the Transform variants.
#
# In CE/GL, `self.play(m.animate.shift(RIGHT).rotate(PI))` is about half of
# all `play` calls. Python gets there with a chainable proxy that records
# method calls; Julia has no equivalent that is worth the machinery, so there
# are no macros: a plain function does the job.
#
# So: `animate(m, (shift!, 2RIGHT), (rotate!, TAU/4))`. Under the hood it is
# exactly what Manim does — a Transform toward a COPY that has had those
# mutations applied. The copy is built inside `begin!` (not now), so chaining
# inside a Succession snapshots the right state.
#
# Everything here talks to the interpolation contract only. That is why
# `animate` works on a ValueTracker and on the camera frame without a single
# line here mentioning either.

"""
    animate(m, (f, args...), (g, args...), …; kw...) → Transform

The `.animate` idiom: animate `m` towards the state it would have after
applying those mutations in order.

    play!(scene, animate(sq, (shift!, 2RIGHT), (rotate!, TAU/4)))
    play!(scene, animate(vt, (set_value!, 10.0)); run_time = 2)

A bare function with no arguments is fine too: `animate(m, center!)`.

`kw...` goes to the Transform (`run_time`, `rate_func`, `lag_ratio`).
"""
function animate(mob::Mobject, ops...; kw...)
    isempty(ops) && throw(ArgumentError(
        "animate(m) with no operations: pass at least one, e.g. " *
        "animate(m, (shift!, 2RIGHT)) or animate(m, center!)"))
    make_target = function ()
        target = copy(mob)
        _share_saved_state!(target, mob)    # restore! composes
        for op in ops
            if op isa Tuple
                f = first(op)
                f(target, Base.tail(op)...)
            else
                op(target)                      # a bare function: animate(m, center!)
            end
        end
        return target
    end
    return Transform(AnimBase(; mobject = mob, kw...), nothing, nothing,
                     make_target, nothing, NTuple{3,Mobject}[], Bool[])
end

# ═══════════════════════════════════════════════════════════════════════
# Transform variants (transform.py / fading.py)
# ═══════════════════════════════════════════════════════════════════════

"""
    ReplacementTransform(mob, target; kw...)

Like `Transform`, but the SCENE ends up holding `target` instead of `mob`
(manimlib's `replace_mobject_with_target_in_scene`). Use it when the target is
the thing you will keep manipulating afterwards; plain `Transform` leaves you
holding `mob` wearing the target's shape, which is a classic source of
confusion later in a scene.
"""
function ReplacementTransform(mob::Mobject, target::Mobject; kw...)
    t = Transform(mob, target; kw...)
    t.replace_in_scene = true
    return t
end

"""
    TransformFromCopy(mob, target; kw...)

`mob` stays where it is; a COPY of it flies to `target`. The scene keeps the
copy (so the source is not consumed) — the animation's mobject IS that copy.
"""
function TransformFromCopy(mob::Mobject, target::Mobject; kw...)
    # play! adds the animation's mobject to the scene, and here that mobject
    # IS the copy — so the source stays put and the copy is what flies.
    # manimlib also sets replace_mobject_with_target_in_scene on this one: the
    # copy is scaffolding, and what you want left behind is the target.
    t = Transform(copy(mob), target; kw...)
    t.replace_in_scene = true
    return t
end

"""
    FadeTransform(mob, target; stretch=true, dim_to_match=2, remover=false, kw...)

Cross-fade: `mob` fades out while morphing into `target`'s place, and `target`
fades in from `mob`'s place. Unlike `Transform`, the two need no matching
structure at all — which is why it is the right tool between things that are
not really "the same shape moved".

When it ends the stage holds `target` ITSELF where `mob` stood, and
`mob` is off stage, restored to the photograph the constructor took
(ManimGL's `clean_up_from_scene`, fading.py:132: the constructor calls
`save_state!(mob)`, so a photograph of your own taken before is replaced).
With `remover = true` nothing is added. The animation runs over COPIES of
both — the live `mob` is hidden meanwhile — so it is drawn once, not as a
root AND inside the animated group (otherwise a half-red square would come
out `[190, 74, 64]` instead of `[127, 49, 43]`).

`dim_to_match` only does anything when `stretch = false`: it says which of the
ghost's dimensions is matched to the other's, `1 = x`, `2 = y`, `3 = z`, as
everywhere else in Janim (`docs/naming.md`, `stretch!`).

**The default follows CE's meaning, not its number.** CE spells the
same idea 0-based, so its documented default of `1` means **y**; Janim's
numbering is 1-based, so the default is `2`. Replacing a 4×1 rectangle by a
unit circle without stretching gives 4.0 for CE's `0` and Janim's `1`, 1.0 for
CE's `1` and Janim's `2`, 2.0 for CE's `2` and Janim's `3`.
"""
mutable struct FadeTransform <: Animation
    base::AnimBase              # shared with `transform`: same mobject, same clock
    transform::Transform        # over VGroup(copy(source), copy(target))
    source::Mobject
    target::Mobject
end

"GL's `ghost_to` (fading.py:117): put `source` where `target` is, invisible."
function _ghost_to!(source::Mobject, target::Mobject; stretch::Bool, dim_to_match::Int)
    replace!(source, target; stretch, dim_to_match)
    set_fill!(source; opacity = 0)
    set_stroke!(source; opacity = 0)
    return source
end

"`FadeTransformPieces`' ghost: the same, PIECE by piece down the two families."
function _ghost_pieces!(source::Mobject, target::Mobject; stretch::Bool, dim_to_match::Int)
    for (s, t) in zip(get_family(source), get_family(target))
        _ghost_to!(s, t; stretch, dim_to_match)
    end
    return source
end

FadeTransform(mob::Mobject, target::Mobject; kw...) =
    _fade_transform(mob, target, _ghost_to!; kw...)

"""
    FadeTransformPieces(mob, target; stretch=true, dim_to_match=2, kw...)

[`FadeTransform`](@ref) applied PIECE BY PIECE (`fading.py:140`): the two
families are aligned first, and then each child of the source cross-fades into
the matching child of the target instead of the whole group cross-fading into
the whole group.

```julia
play!(scene, FadeTransformPieces(row_of_terms, other_row))
```

Measured against ManimGL, with a square on the left and a circle on the right
becoming a square above and a circle below: pieces lands the ghosts on
`(0, 3, 0)` and `(0, -3, 0)` — each on its own counterpart — while the plain
[`FadeTransform`](@ref) puts them at `(∓0.5, 0, 0)`, the block replaced as one.
It is the right tool when the two sides are LISTS of things that correspond.
"""
FadeTransformPieces(mob::Mobject, target::Mobject; kw...) =
    _fade_transform(mob, target, _ghost_pieces!; align = true, kw...)

function _fade_transform(mob::Mobject, target::Mobject, ghost!::Function;
                         stretch::Bool = true, dim_to_match::Int = 2,
                         align::Bool = false, kw...)
    save_state!(mob)                       # GL: mobject.save_state() (fading.py:104)
    src = copy(mob)
    tgt = copy(target)
    # GL's `FadeTransformPieces.begin` aligns the two families before ghosting
    # (fading.py:142); the copies below inherit the alignment, which is the
    # same thing one step earlier.
    align && applicable(align_data!, src, tgt) && align_data!(src, tgt)
    group = VGroup(src, tgt)
    # start: the source as it is + the target ghosted onto the source's place
    make_start = function ()
        a = copy(src)
        b = copy(tgt)
        ghost!(b, a; stretch, dim_to_match)
        return VGroup(a, b)
    end
    # end: the source ghosted onto the target's place + the target as it is
    make_target = function ()
        a = copy(src)
        b = copy(tgt)
        ghost!(a, b; stretch, dim_to_match)
        return VGroup(a, b)
    end
    t = Transform(AnimBase(; mobject = group, kw...), nothing, nothing,
                  make_target, make_start, NTuple{3,Mobject}[], Bool[])
    return FadeTransform(t.base, t, mob, target)
end

function begin!(f::FadeTransform)
    # the live source stays a root of its own while the group of copies is
    # another (play! registers the leaves): hidden here, restored in
    # clean_up!, so it is drawn once
    applicable(set_opacity!, f.source, 0.0) && set_opacity!(f.source, 0.0)
    begin!(f.transform)
    return f
end
interpolate!(f::FadeTransform, alpha::Real) = (interpolate!(f.transform, alpha); f)
finish!(f::FadeTransform) = (finish!(f.transform); f)

function clean_up!(f::FadeTransform, stage)
    remove!(stage, mobject_of(f))          # the scaffolding group of copies
    restore!(f.source)                     # GL: self.mobject[0].restore()
    if is_remover(f)
        remove!(stage, f.source)
    else
        _stage_replace!(stage, f.source, f.target)
    end
    return f
end

# ── Rotating / Rotate: rotation AS an animation ────────────────────────────
# Not a Transform: interpolating between two rotated states moves the points
# along CHORDS, so a half-turn of a square visibly shrinks on the way. This
# re-applies the rotation from the start state each frame, which keeps every
# point on its arc — the reason manimlib has a separate class for it.

mutable struct Rotating <: Animation
    base::AnimBase
    angle::Float64
    axis::Point3f
    about_point::Union{Nothing,Point3f}
    about_edge::Point3f
    pairs::Vector{NTuple{2,Mobject}}
end

"""
    Rotating(m, angle=TAU; axis=OUT, about_point=nothing, about_edge=ORIGIN,
             rate_func=linear, run_time=5)

Rotation as an animation: each frame re-rotates the START state by
`rate_func(α)·angle`, so the points travel along arcs instead of chords.
`Rotate` is the same thing with Manim's turn-once defaults.
"""
function Rotating(mob::Mobject, angle::Real = TAU; axis = OUT,
                  about_point = nothing, about_edge = ORIGIN,
                  rate_func::Function = linear, run_time::Real = 5.0, kw...)
    Rotating(AnimBase(; mobject = mob, rate_func, run_time, kw...),
             Float64(angle), Point3f(axis),
             about_point === nothing ? nothing : Point3f(about_point),
             Point3f(about_edge), NTuple{2,Mobject}[])
end

"""
    Rotate(m, angle=PI; axis=OUT, about_point=nothing, about_edge=ORIGIN)

`Rotating` with Manim's `Rotate` defaults: half a turn, one second, `smooth`.
"""
Rotate(mob::Mobject, angle::Real = PI; rate_func::Function = smooth,
       run_time::Real = 1.0, kw...) =
    Rotating(mob, angle; rate_func, run_time, kw...)

function begin!(r::Rotating)
    r.base.starting_mobject = copy(r.base.mobject)
    r.pairs = _families(r.base.mobject, r.base.starting_mobject)
    interpolate!(r, 0.0)
    return r
end

function interpolate!(r::Rotating, alpha::Real)
    n = length(r.pairs)
    mob = r.base.mobject
    # restore the start, then rotate the WHOLE mobject once: rotating each
    # member separately about its own centre would tear the group apart.
    for (i, (sub, from)) in enumerate(r.pairs)
        sub isa VMobject && from isa VMobject && set_points!(sub, get_points(from))
    end
    theta = _sub_alpha(r.base, alpha, 1, max(n, 1)) * r.angle
    about = r.about_point === nothing ?
            get_bounding_box_point(r.base.starting_mobject, r.about_edge) :
            r.about_point
    rotate!(mob, theta; axis = r.axis, about_point = about)
    return r
end

# ── MoveAlongPath ──────────────────────────────────────────────────────────

"""
    MoveAlongPath(m, path; run_time, rate_func)

Move `m` along `path` — any VMobject, read as a trajectory.

```julia
route = ArcBetweenPoints(3 * LEFT, 3 * RIGHT; angle = -TAU / 4)
play!(scene, MoveAlongPath(dot, route; run_time = 3, rate_func = linear))
```

The mobject's CENTRE is placed at `quick_point_from_proportion(path, α)`, the
same sampling manimlib uses. Note what that does and does not promise: constant
α gives constant speed only as far as the path's own parametrisation is
uniform, so a shape built from arcs of different lengths will speed up and slow
down.

The default `rate_func` is [`smooth`](@ref), not [`linear`](@ref) — manimlib's
is too. For a dot that should travel at a steady pace, say `linear`
explicitly. The path is a trajectory, not a mobject in the scene: it is not
drawn unless you `add!` it yourself.
"""
mutable struct MoveAlongPath <: Animation
    base::AnimBase
    path::VMobject
end

# NOTE the rate_func: manimlib's MoveAlongPath does NOT override Animation's
# default, so it is `smooth`, not `linear`. Getting this wrong is invisible at
# α=0 and α=1 and wrong everywhere in between (at α=0.25 the two differ by
# 1.59 on a radius-2 circle).
MoveAlongPath(mob::Mobject, path::VMobject; kw...) =
    MoveAlongPath(AnimBase(; mobject = mob, kw...), path)

begin!(m::MoveAlongPath) = (m.base.starting_mobject = copy(m.base.mobject);
                            interpolate!(m, 0.0); m)

function interpolate!(m::MoveAlongPath, alpha::Real)
    p = quick_point_from_proportion(m.path, m.base.rate_func(clamp(alpha, 0, 1)))
    move_to!(m.base.mobject, p)
    return m
end
