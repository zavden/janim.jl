# Course 1 · 5.4 — Extending Janim (Manim's "plugins")
#
# Manim has a plugin system: packages advertise themselves through entry
# points and `config` lists which are enabled. Janim has NO such registry, and
# there is nothing to install — extension happens through Julia's own
# mechanism, adding METHODS to existing generic functions. A "plugin" is just
# a package that does `using Janim` and defines some.
#
# The four seams, weakest to deepest:
#
#   1. A FUNCTION that builds mobjects. Most of what people call a plugin is
#      this: `my_flowchart(steps)` returning a VGroup. Nothing to declare.
#   2. A SHAPE: `const Hexagon = VMobject{:Hexagon}` plus a constructor. You
#      get real dispatch on the tag (`interpolate!(::Hexagon, ::Square, α)`
#      can be a method) with no inheritance — course 2, lesson 1.3.
#   3. A MOBJECT of your own: implement the interpolation contract
#      (`is_interpolable`, `Base.copy`, `interpolate!(dst, a, b, α)`,
#      `become!`) and every animation works on it, Transform included.
#   4. An EFFECT: a mutable struct, a fragment shader and one method of
#      `_apply_effect!` — course 2, chapter 6.
#
# What is missing compared with Manim, honestly: discovery. There is no list
# of available plugins and no `plugins = […]` to enable them. You add the
# package to your project and call it.
#
# This lesson does (1) and (2).
#
#   julia --project=. examples/tutorial/c1_05_utilities/04_extending_janim.jl

using Janim

const PREVIEW_T = 1.8

# ── seam 2: a new shape, with its own tag ──────────────────────────────────
#
# `VMobject(:Tag; kw...)` builds the empty mobject with its factory style —
# it is what every shape in the engine starts from, and it is public API: the
# most common extension seam needs no reaching into the module. (`vmob` is kept as an alias.)
const Chevron = VMobject{:Chevron}

"A chevron pointing RIGHT, `width` across and `height` tall."
function (::Type{Chevron})(; width::Real = 1.0, height::Real = 1.2,
                           thickness::Real = 0.35, kw...)
    m = VMobject(:Chevron; kw...)
    w, h, t = Float64(width), Float64(height) / 2, Float64(thickness)
    set_points_as_corners!(m, [Point3f(-w, h, 0), Point3f(0, 0, 0),
                               Point3f(-w, -h, 0), Point3f(-w + t, -h, 0),
                               Point3f(t, 0, 0), Point3f(-w + t, h, 0),
                               Point3f(-w, h, 0)])
    return m
end

# ── seam 1: a function that builds a composite ─────────────────────────────
"A labelled step: a rounded box with text inside, as one VGroup."
function step_box(text; width = 2.4, colour = "#2C5F8A")
    box = RoundedRectangle(width = width, height = 1.0, corner_radius = 0.18)
    set_fill!(box; color = colour, opacity = 1.0); set_stroke!(box; opacity = 0)
    lab = TextMobject(text; size = 0.34)
    move_to!(lab, get_center(box))
    return VGroup(box, lab)
end

"A row of steps with chevrons between them."
function pipeline_diagram(steps)
    g = VGroup()
    for (k, s) in enumerate(steps)
        add!(g, step_box(s))
        if k < length(steps)
            ch = Chevron(; width = 0.5, height = 0.7, thickness = 0.18)
            set_fill!(ch; color = "#FFD25E", opacity = 1.0)
            set_stroke!(ch; opacity = 0)
            add!(g, ch)
        end
    end
    arrange!(g, RIGHT; buff = 0.25)
    return g
end

function construct(scene)
    title = TextMobject("a plugin is a package that adds methods";
                        size = 0.44, color = GREY_A)
    to_edge!(title, UP; buff = 0.35)
    add!(scene, title)

    diagram = pipeline_diagram(["parse", "layout", "render"])
    scale!(diagram, 0.95)
    move_to!(diagram, 0.5 * UP)

    note = TextMobject("Chevron is a VMobject{:Chevron} — real dispatch, no inheritance";
                       size = 0.32, color = GREY_C)
    move_to!(note, 1.9 * DOWN)

    add!(scene, diagram, note)
    play!(scene, LaggedStart([FadeIn(part; shift = 0.3 * RIGHT)
                              for part in diagram.submobjects]...;
                             lag_ratio = 0.2); run_time = 2.0)
    play!(scene, Write(note); run_time = 1.0)

    # The new shape is a first-class mobject: it transforms like any other.
    lone = Chevron(; width = 1.6, height = 2.0, thickness = 0.5)
    set_fill!(lone; color = "#7FDD58", opacity = 1.0); set_stroke!(lone; opacity = 0)
    move_to!(lone, 4.6 * LEFT + 0.4 * UP)
    play!(scene, GrowFromCenter(lone); run_time = 0.8)
    println("tag: ", tag(lone), " · points: ", get_num_points(lone),
            " · subpaths: ", length(get_subpaths(lone)))
    wait!(scene, 0.4)
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "04_extending_janim.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
