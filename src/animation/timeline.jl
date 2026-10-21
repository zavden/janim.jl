# Timeline — play/wait over a time line WITHOUT a game loop (here time is
# discrete and deterministic: n frames per play).
#
# The sampling invariant, deliberately different from Manim's:
#
#     frame k of n evaluates α = (k + ½) / n      (SYMMETRIC sampling)
#
# CE samples t = k/n   (0.0 … 0.9: the last frame NEVER reaches the end) and
# GL samples t = (k+1)/n (0.1 … 1.0: the first frame has already moved). The
# midpoint commits neither fence-post error and is symmetric when reversed.

"""
    Timeline(; fps=60, sink=nothing)

`sink(mobjects, nframe)` is called once per emitted frame: a VideoIO encoder,
a window, or nothing (compute only). Scene is built on this same Timeline.
"""
Base.@kwdef mutable struct Timeline
    fps::Int = 60
    mobjects::Vector{Mobject} = Mobject[]
    sink::Any = nothing
    frames::Int = 0
    last_alphas::Vector{Float64} = Float64[]   # introspection: the alphas of the last play!
end

# ManimGL's `add` (scene.py:331): remove the family, then append on top.
# `recurse = false` only appends the roots. Same rule as Scene's, so a
# Timeline and a Scene draw the same list.
function add!(tl::Timeline, mobs::Mobject...; recurse::Bool = true)
    isempty(mobs) && return tl
    if !recurse
        for m in mobs
            m in tl.mobjects || push!(tl.mobjects, m)
        end
        return tl
    end
    _add_gl!(tl.mobjects, mobs)
    return tl
end
_stage_list(tl::Timeline) = tl.mobjects

# ManimGL's semantics (scene.py:374): the family leaves, and a root that held
# one of them is replaced by its remaining children, in place.
# `recurse = false` removes only the roots named.
function remove!(tl::Timeline, mobs::Mobject...; recurse::Bool = true)
    isempty(mobs) && return tl
    recurse || (filter!(x -> !any(m -> m === x, mobs), tl.mobjects); return tl)
    _remove_from_list!(tl.mobjects, _family_set(mobs))
    return tl
end

function _emit!(tl::Timeline)
    tl.frames += 1
    tl.sink === nothing || tl.sink(tl.mobjects, tl.frames)
    return tl
end

"""
    play!(tl, anims...; run_time=nothing)

The full life cycle: begin! → n frames with α=(k+½)/n → finish!.
Several animations at once = AnimationGroup(lag_ratio=0), as in Manim, and
`run_time = T` gives EACH of them T seconds (GL's
`update_rate_info`) — `AnimationGroup(a, b; run_time = T)` is the form that
shares T between them instead.
"""
function play!(tl::Timeline, anims::Animation...; run_time = nothing)
    isempty(anims) && throw(ArgumentError(
        "play! without animations — did you mean wait!(tl, seconds)?"))
    # ManimGL's `play` (`scene.py:579`) hands its `run_time` to
    # every animation through `update_rate_info` (`animation.py:132`), so an
    # explicit `run_time = T` means "each of these lasts T", not "the whole
    # thing lasts T with the windows scaled to fit". The difference is
    # visible: a 1 s FadeIn beside a 2 s Write under `run_time = 3` would
    # finish at the halfway mark otherwise. The proportional windows are
    # spelled out instead — `play!(stage, AnimationGroup(a, b; run_time = T))`.
    # Validated BEFORE anything is mutated.
    if run_time !== nothing
        given = _check_duration(run_time, tl.fps, "run_time")
        for a in anims
            a.base.run_time = given
        end
    end
    anim = length(anims) == 1 ? anims[1] : AnimationGroup(anims...)
    rt = _check_duration(get_run_time(anim), tl.fps, "run_time")
    # Register the LEAF mobjects, never a group's synthetic container — same
    # rule as Scene's play!, one mechanism for both.
    # GL's guard — see `_add_animated!` (core/wrappers.jl)
    _add_animated!(tl, (mobject_of(leaf) for leaf in _leaf_animations(anim)))
    n = max(1, round(Int, rt * tl.fps))
    begin!(anim)
    tl.last_alphas = [(k + 0.5) / n for k in 0:n-1]    # ← the sampling invariant
    for alpha in tl.last_alphas
        interpolate!(anim, alpha)
        _emit!(tl)
    end
    finish!(anim)
    clean_up!(anim, tl)                        # the same fourth act as Scene's
    return tl
end

"wait!(tl, t): t seconds of frames with the scene still."
function wait!(tl::Timeline, t::Real = 1.0)
    t = _check_duration(t, tl.fps, "wait duration")
    for _ in 1:max(1, round(Int, t * tl.fps))
        _emit!(tl)
    end
    return tl
end
