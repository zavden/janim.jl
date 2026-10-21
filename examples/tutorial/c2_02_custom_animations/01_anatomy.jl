# Course 2 · 2.1 — The anatomy of an animation
#
# An animation is a struct that subtypes `Animation`, carries an `AnimBase`
# named `base`, and answers three verbs:
#
#     begin!(a)               snapshot whatever you will need; put α = 0
#     interpolate!(a, α)      the whole animation, as a function of α
#     finish!(a)              the default is `interpolate!(a, 1)` + cleanup
#
# `AnimBase` gives you `mobject`, `run_time`, `rate_func`, `lag_ratio`,
# `remover` and `starting_mobject` for free, and with them `get_run_time`,
# `is_remover` and `mobject_of` already work on your type.
#
# TWO RULES, both learned by breaking them:
#
#   1. SNAPSHOT IN `begin!`, never in the constructor. `play!` may be handed
#      your animation long after it was built — inside a `Succession`, for
#      instance — and the state to capture is the one at that moment.
#   2. APPLY THE RATE FUNCTION YOURSELF, or inherit it: `Transform` applies it
#      through `_sub_alpha` (which also spreads `lag_ratio` over the family).
#      If your animation does neither, `rate_func` silently does nothing.
#
# Nothing here knows about the scene. That is deliberate: it is why the same
# animation behaves identically under `play!`, `Timeline`, `render_frame`, the
# render farm and the daemon.
#
#   julia --project=. examples/tutorial/c2_02_custom_animations/01_anatomy.jl

using Janim
import Janim: begin!, interpolate!, finish!, AnimBase, Animation

"""
    Unroll(m; from_edge = LEFT, kw...)

Reveal `m` by sliding a straight cut across it: at α the mobject is squashed
to `α` of its width against `from_edge` and grows out. Not a Transform — the
target is recomputed each frame from the snapshot, so it composes with any
rate function and never accumulates drift.
"""
mutable struct Unroll <: Animation
    base::AnimBase
    from_edge::Point3f
    snapshot::Union{Nothing,Mobject}     # filled in begin!, RULE 1
end

Unroll(m::Mobject; from_edge = LEFT, kw...) =
    Unroll(AnimBase(; mobject = m, kw...), Point3f(from_edge), nothing)

function begin!(u::Unroll)
    u.snapshot = copy(u.base.mobject)     # RULE 1: the state as of NOW
    interpolate!(u, 0.0)
    return u
end

function interpolate!(u::Unroll, alpha::Real)
    a = u.base.rate_func(clamp(alpha, 0, 1))   # RULE 2: apply it yourself
    m, s = u.base.mobject, u.snapshot
    become!(m, s)                              # back to the snapshot…
    edge = get_bounding_box_point(s, u.from_edge)
    scale!(m, (max(a, 1e-3), 1.0, 1.0); about_point = edge)   # …then squash
    return u
end

# `finish!` has a perfectly good default (interpolate! at α = 1); it is worth
# overriding only when there is cleanup to do — a remover restoring the
# mobject it consumed, say.

const PREVIEW_T = 1.4

function construct(scene)
    title = TextMobject("an animation is three verbs"; size = 0.46, color = GREY_A)
    to_edge!(title, UP; buff = 0.35)
    add!(scene, title)

    bars = VGroup()
    for (k, colour) in enumerate(("#58C4DD", "#7FDD58", "#E8A33D", "#FF5E5E"))
        b = Rectangle(width = 3.0 + 0.9k, height = 0.7)
        set_fill!(b; color = colour, opacity = 1.0); set_stroke!(b; opacity = 0)
        add!(bars, b)
    end
    arrange!(bars, DOWN; buff = 0.35, aligned_edge = LEFT)
    move_to!(bars, 0.3 * DOWN)
    add!(scene, bars)

    # The custom animation, with every AnimBase dial working on it: run_time,
    # rate_func and lag_ratio all come for free.
    play!(scene, LaggedStart([Unroll(b; rate_func = ease_out_cubic)
                              for b in bars.submobjects]...;
                             lag_ratio = 0.18); run_time = 2.2)
    wait!(scene, 0.5)

    # …and it composes with the rest, because it speaks the same protocol.
    play!(scene, AnimationGroup([Unroll(b; from_edge = RIGHT,
                                        rate_func = t -> 1 - smooth(t))
                                 for b in bars.submobjects]...; lag_ratio = 0.1);
          run_time = 1.4)
    println("Unroll answers get_run_time: ",
            get_run_time(Unroll(bars[1]; run_time = 3.0)), " s")
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "01_anatomy.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
