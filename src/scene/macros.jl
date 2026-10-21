# ── the scene macros: @scene / @play / @wait ───────────────────────────────
#
# Manim writes `self.play(...)` because the scene is a METHOD's receiver. Janim
# writes `play!(scene, ...)` because it is a function's first argument, and
# after thirty lines that argument is pure noise: the file IS one scene, so
# there is never a second one to point at.
#
# These macros remove it, and they do it LEXICALLY. `@scene sc` binds a name
# the other two read; there is no "current scene" global to set, to forget, or
# to leak between a render and the preview that follows it — the same reason
# Janim has no config object.
#
# The desugaring is exactly one substitution, which is why there is no third
# behaviour to learn:
#
#     @play(a, b; run_time = 2)      →      play!(sc, a, b; run_time = 2)
#
# so everything `play!` documents still holds, and anything the macros do not
# cover is written the long way in the same file with no ceremony.
#
# `play!` and `wait!` are defined for `Scene` AND for `Timeline`, and the
# macros never mention either type, so `@scene tl` sugars a timeline too.
#
# THERE IS DELIBERATELY NO `@add` / `@remove`, and this is the reason so that
# nobody adds them back for symmetry: `play!` and `wait!` only ever take a
# scene first, so `@play` has nowhere to be wrong. `add!` does NOT — it is
# equally a mobject's verb, `add!(parent, child)`. `@add(g, c)` would expand
# to `add!(sc, g, c)`, which does not fail: MEASURED, `g` ends with zero
# children and the scene with two mobjects, both on screen, and you find out
# when you move `g` and `c` stays behind. A macro that silently means the
# other thing is worse than the `sc` it saves. `add!(sc, m)` was never the
# line that hurt.

const _SCENE_VAR = :__janim_scene__

"""
Build `f(<the scene>, args...)`, sorting `k = v` and `; k = v` into keywords.

The scene slot is not the bare name: it is `@isdefined ? name : throw(…)`, so
forgetting `@scene` says what to write instead of `UndefVarError:
__janim_scene__`. On a scene that IS bound the branch is constant-folded — the
local is definitely assigned — so this costs nothing at run time.
"""
function _scene_call(mac::Symbol, f::Symbol, args)
    kws, pos = Any[], Any[]
    for a in args
        if a isa Expr && a.head === :parameters
            append!(kws, a.args)                       # @play(a; run_time = 2)
        elseif a isa Expr && a.head === :(=) && a.args[1] isa Symbol
            push!(kws, Expr(:kw, a.args[1], a.args[2]))  # @play(a, run_time = 2)
        else
            push!(pos, a)
        end
    end
    msg = "@$mac has no scene — write `@scene sc` once, right after " *
          "`function construct(sc)`; or call `$f(sc, …)` yourself"
    target = Expr(:if, Expr(:isdefined, _SCENE_VAR), _SCENE_VAR,
                  :(throw(ArgumentError($msg))))
    call = Expr(:call, f, target, pos...)
    isempty(kws) || insert!(call.args, 2, Expr(:parameters, kws...))
    return call
end

"""
    @scene sc

Name the scene that [`@play`](@ref) and [`@wait`](@ref) act on. **Write it
INSIDE the function, once, at the top of `construct`:**

```julia
function construct(sc)
    @scene sc

    c = Circle()
    add!(sc, c)
    @play FadeIn(c)
    @play(Transform(c, Square()); run_time = 1.2)
    @wait 0.5
end
```

It expands to a plain assignment, so the scene is still an ordinary variable —
`sc` keeps working everywhere, and the macros are opt-in sugar over the same
`play!`/`wait!` calls rather than a second way to drive a scene.

Being an assignment is where both of its sharp edges come from, and neither is
hidden:

  * **Inside a function is not a style preference.** At FILE level `@scene`
    writes a module global, and a function in that file that forgets its own
    `@scene` then finds it instead of failing. MEASURED: 60 frames went to the
    file-level scene and 0 to the one the function was handed, with no error —
    the `@isdefined` guard is satisfied by the global. Across files nothing
    leaks (the daemon builds one module per scene file); within a file it does.
  * A CLOSURE written inside a function that already said `@scene` and that
    says `@scene` again reassigns the enclosing binding, exactly as
    `sc = other` would. A separate function is unaffected — that is Julia's
    scoping.

`local` is not the fix for either: at top level `local x = v` is scoped to that
statement alone, so it would silently break scripts that drive a scene outside
any function.

Works on a [`Timeline`](@ref) too, which also answers `play!` and `wait!`.
"""
macro scene(s)
    esc(:($_SCENE_VAR = $s))
end

"""
    @play(anims...; kw...)

`play!(<the @scene>, anims...; kw...)`. Keywords pass straight through, with or
without the semicolon: `@play(a, run_time = 2)` and `@play(a; run_time = 2)`
are the same call.
"""
macro play(args...)
    esc(_scene_call(Symbol("play"), :play!, args))
end

"""
    @wait
    @wait t

`wait!(<the @scene>)` — one second, or `t` of them.
"""
macro wait(args...)
    esc(_scene_call(Symbol("wait"), :wait!, args))
end
