# core/states.jl — photograph a mobject, and go back to it.
#
# Manim's `m.save_state()` … `Restore(m)` and `m.generate_target()` …
# `MoveToTarget(m)`. Two names for the same shape: keep a copy of a mobject
# somewhere, change the original, then animate towards the copy.
#
# WHERE THE COPY LIVES, because that is the only design decision here.
# ManimGL hangs `saved_state` and `target` off the mobject as Python
# attributes, which Julia has no equivalent for: a `VMobject` is a struct with
# fixed fields. The two ways out were adding two fields to that struct or
# keeping the copies beside it. This is the second, and the reasons are:
#
#   · The struct is load-bearing. Its many-field constructor is what `vmob()`
#     calls, and widening it touches every shape in the engine for a feature
#     most scenes never use.
#   · A `WeakKeyDict` lets the collector take the copy when the mobject it
#     belongs to dies. A plain Dict would keep every mobject a scene ever
#     photographed alive until the process ended.
#   · Determinism is untouched: these tables are keyed BY IDENTITY and
#     never iterated, so there is no unordered traversal on any render path.
#     The rule that matters is "no unordered iteration", and there is none.

const _SAVED_STATES = WeakKeyDict{Any,Any}()
const _TARGETS = WeakKeyDict{Any,Any}()

"""
    save_state!(m) → m

Photograph `m` as it is now, so [`Restore`](@ref) can bring it back:

```julia
save_state!(group)
play!(scene, animate(group, (scale!, 0.4), (to_corner!, UR)))
wait!(scene, 1.0)
play!(scene, Restore(group))          # back to the photograph
```

The copy is DEEP over the family, so changing the original afterwards — its
points, its colours, its children — leaves the photograph untouched. Saving
again replaces the previous one; there is one photograph per mobject, as in
Manim.

**One trap, and it is [`become!`](@ref)'s rather than this function's.**
Restoring uses `become!`, which is recursive and REPLACES the children when
the two structures differ. So if you save a group of two, add a third child,
and then restore, the group comes back with two children — but they are NEW
objects, and a reference you were holding to one of the originals is now
orphaned:

```julia
g = VGroup(Square(), Circle())
first_child = g[1]
save_state!(g)
add!(g, Triangle())        # the structure changes
restore!(g)
g[1] === first_child       # false: become! rebuilt the children
```

It only bites when the CHILD COUNT changed between the photograph and the
restore; a group whose structure stayed put keeps its children. If you need
the references to survive, hold the group and index it after restoring.
"""
function save_state!(m::Mobject)
    s = copy(m)
    _SAVED_STATES[m] = s
    haskey(_TARGETS, m) && (_TARGETS[s] = _TARGETS[m])   # GL: saved_state.target = target
    return m
end

"""
    get_saved_state(m) → Mobject

The photograph [`save_state!`](@ref) took, or an error naming the mobject if
none was taken. Rarely needed directly — [`Restore`](@ref) and
[`restore!`](@ref) consume it.
"""
function get_saved_state(m::Mobject)
    haskey(_SAVED_STATES, m) || throw(ArgumentError(
        "this $(m isa VMobject ? tag(m) : typeof(m)) has no saved state — " *
        "call save_state!(m) before restoring it"))
    return _SAVED_STATES[m]
end

"Whether `m` carries a photograph."
has_saved_state(m::Mobject) = haskey(_SAVED_STATES, m)

"""
    restore!(m) → m

Put `m` back where [`save_state!`](@ref) left it, IMMEDIATELY and without
animating. [`Restore`](@ref) is the animated version.
"""
restore!(m::Mobject) = become!(m, get_saved_state(m))

"""
    generate_target!(m) → target

Make a copy of `m` for you to modify, and remember it as `m`'s target:

```julia
t = generate_target!(square)
shift!(t, 3 * RIGHT)
set_fill!(t; color = YELLOW, opacity = 1.0)
play!(scene, MoveToTarget(square))
```

It is the alternative to [`animate`](@ref) for a change that takes several
statements or a loop: you build the end state as a normal mobject, with every
verb available, and then animate towards it in one go.

The returned target is a real mobject — it is simply not in the scene. It
holds a copy of everything, so modifying it never touches the original.
"""
function generate_target!(m::Mobject)
    t = copy(m)
    _TARGETS[m] = t
    _share_saved_state!(t, m)
    return t
end

"""
A working copy — a target, or the copy `animate` mutates — carries the
ORIGINAL's photograph, shared: ManimGL's `copy` drops `saved_state`
(mobject.py:672) and `generate_target` hands it over (:707), which is why
`m.animate.restore().move_to(p)` composes there. Sharing is safe
because nobody mutates a photograph: `restore!` copies FROM it.
"""
function _share_saved_state!(dst::Mobject, src::Mobject)
    haskey(_SAVED_STATES, src) && (_SAVED_STATES[dst] = _SAVED_STATES[src])
    return dst
end

"""
    get_target(m) → Mobject

The target [`generate_target!`](@ref) made, or an error if there is none.
"""
function get_target(m::Mobject)
    haskey(_TARGETS, m) || throw(ArgumentError(
        "this $(m isa VMobject ? tag(m) : typeof(m)) has no target — " *
        "call generate_target!(m), change what it returns, then MoveToTarget(m)"))
    return _TARGETS[m]
end

"Whether `m` carries a target."
has_target(m::Mobject) = haskey(_TARGETS, m)

"""
    clear_states!(m) → m

Forget `m`'s photograph and target. Only useful when a long-running scene
holds big mobjects and you want the copies collected early; otherwise the
weak tables take care of it.
"""
function clear_states!(m::Mobject)
    delete!(_SAVED_STATES, m)
    delete!(_TARGETS, m)
    return m
end
