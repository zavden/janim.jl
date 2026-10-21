# Course 2 · 2.2 — A custom animation worth keeping
#
# `TraceGraph`: draw a curve while a dot rides it and a readout follows. Manim
# needs three coordinated animations plus an updater for this; here it is one
# object with one α, which means one `run_time`, one `rate_func`, and no way
# for the three parts to drift apart.
#
# The lesson inside the lesson: an animation may drive SEVERAL mobjects. Its
# `base.mobject` is the one the scene adds and removes — so make that a group
# containing everything the animation touches, exactly as `AnimationGroup`
# does.
#
#   julia --project=. examples/tutorial/c2_02_custom_animations/02_a_real_one.jl

using Janim
import Janim: begin!, interpolate!, AnimBase, Animation

"""
    TraceGraph(ax, f, dot, readout; x_range = nothing, kw...)

Draw the graph of `f` over `ax` from left to right, keeping `dot` on the pen
and `readout` showing the current y. One animation, one α, no drift.
"""
mutable struct TraceGraph <: Animation
    base::AnimBase
    ax::Axes
    f::Any
    graph::VMobject
    dot::VMobject
    readout::DecimalNumber
    x0::Float64
    x1::Float64
end

function TraceGraph(ax::Axes, f, graph::VMobject, dot::VMobject,
                    readout::DecimalNumber; x_range = nothing, kw...)
    x0, x1 = x_range === nothing ? (ax.x_axis.x_min, ax.x_axis.x_max) :
             (Float64(x_range[1]), Float64(x_range[2]))
    group = Group(graph, dot, readout)      # Group: a DecimalNumber is not a VMobject
    TraceGraph(AnimBase(; mobject = group, kw...), ax, f, graph, dot, readout, x0, x1)
end

function begin!(t::TraceGraph)
    # Nothing to snapshot here — the graph is rebuilt from f every frame — so
    # `begin!` only has to put the animation at α = 0.
    interpolate!(t, 0.0)
    return t
end

function interpolate!(t::TraceGraph, alpha::Real)
    a = t.base.rate_func(clamp(alpha, 0, 1))
    x = t.x0 + a * (t.x1 - t.x0)
    if a <= 0
        # a degenerate path still needs points, or the renderer has nothing
        set_points!(t.graph, fill(coords_to_point(t.ax, t.x0, t.f(t.x0)), 3))
    else
        n = max(3, round(Int, 160a))
        set_points_as_corners!(t.graph,
            [coords_to_point(t.ax, ξ, t.f(ξ))
             for ξ in range(t.x0, x; length = n)])
    end
    move_to!(t.dot, coords_to_point(t.ax, x, t.f(x)))
    set_number!(t.readout, t.f(x))
    move_to!(t.readout.group, coords_to_point(t.ax, x, t.f(x)) + Point3f(0.55, 0.4, 0))
    return t
end

const PREVIEW_T = 2.2

function construct(scene)
    title = TextMobject("one animation, three mobjects, one alpha";
                        size = 0.44, color = GREY_A)
    to_edge!(title, UP; buff = 0.35)
    add!(scene, title)

    ax = Axes((-4.0, 4.0, 1.0), (-2.0, 2.0, 1.0); width = 9.0, height = 4.0,
              include_numbers = true, num_decimal_places = 0,
              numbers_to_exclude = [0.0], color = "#37506B", stroke_width = 2.0,
              label_size = 0.3)
    move_to!(ax, 0.4 * DOWN)
    add!(scene, ax.group)

    f = x -> 1.5 * sin(1.6x) * exp(-0.12x^2)

    graph = VMobject()
    set_stroke!(graph; color = "#58C4DD", width = 4.0)   # born with its style
    set_fill!(graph; opacity = 0)
    dot = Dot(ORIGIN; radius = 0.12)
    set_fill!(dot; color = "#FFD25E")
    readout = DecimalNumber(0.0; num_decimal_places = 2, size = 0.45, color = "#FFD25E")

    play!(scene, TraceGraph(ax, f, graph, dot, readout;
                            rate_func = ease_in_out_sine); run_time = 3.5)
    wait!(scene, 0.4)

    # Because it is an ordinary Animation, it composes: run it backwards by
    # inverting the rate function, and the three parts still agree.
    play!(scene, TraceGraph(ax, f, graph, dot, readout;
                            rate_func = t -> 1 - smooth(t)); run_time = 1.6)
    println("graph anchors at the end: ", (get_num_points(graph) + 1) ÷ 2)
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "02_a_real_one.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
