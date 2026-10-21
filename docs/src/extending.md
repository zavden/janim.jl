# Extending the engine

There is no plugin registry, no entry points and nothing to register. **Adding
a method IS the extension mechanism**, because dispatch decides which code runs
from the types of all the arguments — so a type of yours, in a package of
yours, can teach existing functions how to handle it without anyone editing
Janim.

That is the same reason there is no plugin system, and why `ZoomedScene`'s
job fell to an ordinary keyword (`Layer(…; camera = …)`) instead of a scene
subclass: what inheritance ladders exist for, dispatch and composition
already do.

## A shape of your own

The base constructor is the seam:

```julia
function Spiral(; turns = 3, radius = 1, kw...)
    m = VMobject(:Spiral; kw...)
    start_new_path!(m, ORIGIN)
    for t in range(0, turns * TAU; length = 200)
        r = radius * t / (turns * TAU)
        add_line_to!(m, Point3f(r * cos(t), r * sin(t), 0))
    end
    return m
end
```

`VMobject(:Tag; kw...)` gives an empty [`VMobject`](@ref) carrying the factory
style, tagged with a symbol of your choosing — so `VMobject{:Spiral}` dispatches
as its own type and everything in the engine (transforms, layout, animations,
the renderer) already works on it. [`vmob`](@ref) is an alias for the same call.
A keyword neither knows is an `ArgumentError` naming the tag («Spiral does not
take `turn`»).

One trap, and it is Julia's dispatch rather than the engine's: `VMobject{:Spiral}`
keeps its positional field constructor, which `VMobject(:Spiral)` ends in. Give
your constructor KEYWORDS (as above) or a typed positional argument; a method
`(::Type{Spiral})(args...; kw...)` with a bare `args...` intercepts that
positional call and recurses forever.

The path API: [`start_new_path!`](@ref), [`add_line_to!`](@ref),
[`add_quadratic_bezier_to!`](@ref), [`add_arc_to!`](@ref),
[`add_subpath!`](@ref), [`set_points_as_corners!`](@ref),
[`set_points_smoothly!`](@ref), [`set_anchors_and_handles!`](@ref).

## A mobject that is not a path

For something a Bézier path cannot describe, subtype [`Mobject`](@ref) and
implement the **interpolation contract** — four lines, and then
[`Transform`](@ref), the fades, `animate` and everything else work on it:

```julia
mutable struct Thermometer <: Mobject
    reading::Float64
    updaters::Vector{Updater}
end

is_interpolable(::Thermometer) = true
Base.copy(t::Thermometer) = Thermometer(t.reading, Updater[])
interpolate!(dst::Thermometer, a::Thermometer, b::Thermometer, α) =
    (dst.reading = a.reading + α * (b.reading - a.reading); dst)
become!(dst::Thermometer, src::Thermometer) = (dst.reading = src.reading; dst)
```

Plus one optional hook when both ends need preparing before the lerp —
`VMobject` uses it to equalise point counts:

```julia
align_data!(a::Thermometer, b::Thermometer) = a
```

[`Transform`](@ref) speaks ONLY these functions and never mentions `VMobject`,
which is why [`ValueTracker`](@ref) and the animatable camera each needed four
lines and no changes to the animation code.

[`is_interpolable`](@ref) is `false` by default on purpose: a type that exists
only to be drawn — a [`Surface`](@ref) — passes through an animation
untouched instead of blowing up. And if you declare the trait and forget a
method, the error tells you which four lines are missing rather than reporting
a `MethodError` from somewhere inside the engine.

The `updaters` field is why [`Updater`](@ref) is public: a custom mobject that
wants per-frame behaviour declares a vector of them.

## An animation of your own

Try [`UpdateFromAlphaFunc`](@ref) first. It takes no snapshot, so it drives
anything — including a [`Surface`](@ref), which a morph cannot:

```julia
play!(scene, UpdateFromAlphaFunc(m, (m, α) -> set_shading!(m; gloss = α)))
```

When you do need a type, it is a struct with an `AnimBase` and three methods:

```julia
mutable struct Pulse <: Animation
    base::AnimBase
    amplitude::Float64
end
Pulse(m; amplitude = 0.2, kw...) = Pulse(AnimBase(; mobject = m, kw...), amplitude)

begin!(p::Pulse) = (p.base.starting_mobject = copy(p.base.mobject);
                    interpolate!(p, 0.0); p)

function interpolate!(p::Pulse, α::Real)
    a = p.base.rate_func(clamp(α, 0, 1))
    become!(p.base.mobject, p.base.starting_mobject)
    scale!(p.base.mobject, 1 + p.amplitude * sin(a * TAU))
    return p
end
```

`AnimBase` carries the shared keywords (`run_time`, `rate_func`, `lag_ratio`,
`remover`), so your constructor gets all of them for free by splatting `kw...`
into it. Apply the `rate_func` INSIDE `interpolate!` — that is the convention
that keeps `play!` in charge of time and nothing else.

[`finish!`](@ref) has a default; define it when you have cleanup to do.

## A layer effect

A mutable struct, a WGSL fragment registered with `effect_shader!`, and one
method:

```julia
effect_shader!(:my_effect, MY_EFFECT_WGSL)
_apply_effect!(cg::GPUCompositor, rv, ef::MyEffect, src::Int) =
    _quad!(cg, rv, :my_effect, _scratch(cg, src); a = src, params = QuadParams(f0 = (Float32(ef.amount),)))
```

`RadialBlur` in `src/backend/wgpu/compositor.jl` is the smallest complete
example.

If it needs randomness or a per-frame pattern it must NOT call `rand` — the
render has to stay byte-reproducible. Instead:

- declare a field `current_frame::Int` — that field ALONE is what makes the
  engine fill it in each frame;
- call `janim_noise_px(in.position.xy, frame, seed)` in the fragment (the
  noise insert is spliced in for you);
- pass `Int32(ef.current_frame)` and `_noise_seed(ef, ef.seed)` in `P.i0`.

The seed is mixed with the effect's TYPE NAME, so two effects given the same
user seed do not draw the same pattern.

Keep the conventions the built-in effects follow: every dial's zero is an exact
no-op (skip the pass), `rate` counts FRAMES, and geometric sizes are in scene
units.

## The backend seam

Everything that speaks the graphics API — `wgpu*` calls, `WGPU_*`
constants, WGSL — lives under `src/backend/wgpu/`, the window system's
library under `src/backend/glfw.jl` and `src/backend/window.jl`, and the
engine — `core/`, `animation/`, `scene/`, `text/` — speaks only in Janim's
own types. That rule is absolute for those four directories.

There is one declared exception, outside the engine and on purpose: the
preview's input layer (`interactive/live.jl` — window-system events ARE the
window system's vocabulary).

If you are adding another backend, that seam is the map — and the
preview's input layer is the honest price, stated rather than discovered.

## Reference

[`vmob`](@ref) · [`is_interpolable`](@ref) · [`align_data!`](@ref) ·
[`interpolate!`](@ref) · [`become!`](@ref) · [`Animation`](@ref) ·
[`begin!`](@ref) · [`finish!`](@ref) · [`Updater`](@ref) ·
[`UpdateFromAlphaFunc`](@ref).
