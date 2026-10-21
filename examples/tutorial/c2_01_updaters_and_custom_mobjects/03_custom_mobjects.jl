# Course 2 · 1.3 — Custom mobjects
#
# There is no class hierarchy to inherit from. There are TWO seams instead,
# and which one you want depends on whether your thing is vector geometry.
#
# SEAM A — a new SHAPE. `const Gear = VMobject{:Gear}` plus a constructor.
# You get everything a VMobject has (points, style, family, transforms, the
# interpolation contract, every animation) and real dispatch on the tag:
# `interpolate!(::Gear, ::Square, α)` can be a method without touching
# Transform. The empty, styled mobject comes from `VMobject(:Gear; kw...)`,
# the public base constructor (`vmob(:Gear; kw...)` is the same call
# under another name, kept as an alias).
#
# ONE TRAP, and it is Julia's dispatch, not a defect: `VMobject{:Gear}` keeps
# its positional field constructor — the 25-field call `VMobject(:Gear)` ends
# in. Write your constructor with KEYWORDS, as below. A method
# `(::Type{Gear})(args...; kw...)` with a bare `args...` would intercept that
# positional call and recurse forever (measured: 7065 stack frames before
# the StackOverflowError). If you want a positional argument, TYPE it —
# `(::Type{Gear})(teeth::Int; kw...)` — exactly as `Polygon` restricts its
# vertices, and the field constructor stays out of reach.
#
# SEAM B — a new MOBJECT that is not vector geometry (a number, a camera, a
# mesh, a physical body). Subtype `Mobject` and implement:
#
#     the interpolation contract            the minimum to live in a scene
#     is_interpolable(::T) = true           get_family(m)
#     Base.copy(m::T)                       has_points(m) / get_num_points(m)
#     interpolate!(dst, a, b, α)            has_updaters / get_updaters
#     become!(dst, src)                     update!(m, dt)
#
# That is exactly how `ValueTracker` and `CameraFrame` are built — four lines
# each — and it is why `animate(vt, (set_value!, 10))` needed no change to
# `Transform`. If you find yourself editing Transform to support a new type,
# something has gone wrong.
#
#   julia --project=. examples/tutorial/c2_01_updaters_and_custom_mobjects/03_custom_mobjects.jl

using Janim
import Janim: is_interpolable, interpolate!, become!, get_family, has_points,
              get_num_points, has_updaters, get_updaters, update!, add_updater!

# ══ SEAM A · a shape ═══════════════════════════════════════════════════════

const Gear = VMobject{:Gear}

"""
    Gear(; teeth = 12, radius = 1.0, tooth = 0.22, bore = 0.3)

A gear as one closed path: the rim steps in and out `teeth` times, and the
bore is a SECOND subpath turning the other way — with winding fill that is
the hole, free (the same trick `Annulus` uses).
"""
function (::Type{Gear})(; teeth::Int = 12, radius::Real = 1.0, tooth::Real = 0.22,
                        bore::Real = 0.3, kw...)
    m = VMobject(:Gear; kw...)      # an unknown keyword here says «Gear does not take …»
    pts = Point3f[]
    for k in 0:(4teeth - 1)
        θ = k * TAU / (4teeth)
        r = (k % 4 in (0, 1)) ? radius + tooth : radius - tooth
        push!(pts, Point3f(r * cos(θ), r * sin(θ), 0))
    end
    push!(pts, pts[1])
    set_points_as_corners!(m, pts)
    add_subpath!(m, [Float32(bore) * p for p in quadratic_bezier_points_for_arc(-TAU)])
    return m
end

# ══ SEAM B · a mobject that is not geometry ════════════════════════════════

"""
    Thermometer(celsius)

A single number with a unit — like `ValueTracker`, but it knows what it is.
Nine short methods and it animates, lives in a scene, and drives updaters.
"""
mutable struct Thermometer <: Mobject
    celsius::Float64
    updaters::Vector{Updater}
end
Thermometer(c::Real = 20.0) = Thermometer(Float64(c), Updater[])

# ── the interpolation contract: this is what makes it animatable ──────────
is_interpolable(::Thermometer) = true
Base.copy(t::Thermometer) = Thermometer(t.celsius, Updater[])
interpolate!(dst::Thermometer, a::Thermometer, b::Thermometer, α::Real) =
    (dst.celsius = a.celsius + α * (b.celsius - a.celsius); dst)
become!(dst::Thermometer, src::Thermometer) = (dst.celsius = src.celsius; dst)

# ── the minimum to live in a scene: it draws nothing, so zero points ──────
get_family(t::Thermometer) = Mobject[t]
has_points(::Thermometer) = false
get_num_points(::Thermometer) = 0
has_updaters(t::Thermometer) = !isempty(t.updaters)
get_updaters(t::Thermometer) = t.updaters
update!(t::Thermometer, dt::Real = 0.0; recurse::Bool = true) =
    (for u in t.updaters; u(t, dt); end; t)
add_updater!(t::Thermometer, f; call::Bool = true, parallel::Bool = false) =
    (push!(t.updaters, Updater(f; parallel)); call && update!(t, 0.0); t)

"The verb `animate` will call: `animate(th, (set_celsius!, 100.0))`."
set_celsius!(t::Thermometer, c::Real) = (t.celsius = Float64(c); t)

const PREVIEW_T = 2.2

function construct(scene)
    title = TextMobject("two seams: a shape, or a contract"; size = 0.46, color = GREY_A)
    to_edge!(title, UP; buff = 0.35)
    add!(scene, title)

    gear = Gear(; teeth = 14, radius = 1.2, tooth = 0.22, bore = 0.45)
    set_fill!(gear; color = "#2C5F8A", opacity = 1.0)
    set_stroke!(gear; color = "#58C4DD", width = 2.5)
    move_to!(gear, 3.6 * LEFT)
    add!(scene, gear)
    println("Gear: tag = ", tag(gear), " · subpaths = ", length(get_subpaths(gear)))

    # Seam B in action: the thermometer drives a bar and a label.
    th = Thermometer(5.0)
    add!(scene, th)

    tube = Rectangle(width = 0.7, height = 4.0)
    set_stroke!(tube; color = GREY_B, width = 3.0); set_fill!(tube; opacity = 0)
    move_to!(tube, 2.6 * RIGHT)

    mercury = always_redraw() do
        h = 4.0 * clamp((th.celsius + 10) / 110, 0, 1)
        bar = Rectangle(width = 0.52, height = max(h, 0.02))
        set_fill!(bar; color = "#FF5E5E", opacity = 1.0)
        set_stroke!(bar; opacity = 0)
        move_to!(bar, Point3f(2.6, -2.0 + h / 2, 0))
        bar
    end

    readout = DecimalNumber(5.0; num_decimal_places = 1, size = 0.6,
                            color = "#FF5E5E", unit = " C")
    move_to!(readout.group, Point3f(4.6, 0.0, 0))
    add_updater!(readout, d -> set_number!(d, th.celsius))

    add!(scene, tube, mercury, readout)

    # It animates because of the four contract lines, not because Transform
    # knows anything about thermometers.
    play!(scene, AnimationGroup(
              animate(th, (set_celsius!, 96.0); rate_func = ease_in_out_cubic),
              Rotating(gear, TAU; run_time = 3.0));
          run_time = 3.0)
    wait!(scene, 0.4)
    println("thermometer ended at ", round(th.celsius; digits = 2), " °C")
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "03_custom_mobjects.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
