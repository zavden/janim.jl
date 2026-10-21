# Galería · 06 — los once efectos de capa, uno por acto.
#
#   julia --project=. examples/gallery/06_effects.jl
#
# Glitch, CRT, VHS, ColorAdjust, Pixelate, Vignette, Grain,
# ChromaticAberration, Sharpen, Wave y EdgeDetect, de uno en uno: la MISMA
# placa bajo cada efecto durante un acto de 0,6 s, en el orden de effects_types.jl,
# así que cada acto es un efecto y cada keyframe cae en el centro de su acto.
# El rótulo va en otra capa, sin efecto.

using Janim

const ACT = 0.6                      # seconds per effect: 18 frames at 30 fps
# One entry per effect, in effects_types.jl's order. Seeds fixed; the dials strong
# enough to be SEEN at 640×360.
const EFFECTS = [
    ("Glitch", () -> Glitch(; intensity = 0.8, seed = 3, rate = 2, slices = 18)),
    ("CRT", () -> CRT(; scanlines = 120, scan_depth = 0.5, curvature = 0.3, vignette = 0.5)),
    ("VHS", () -> VHS(; intensity = 0.8, seed = 5, rate = 2)),
    ("ColorAdjust", () -> ColorAdjust(; hue = 2.1, saturation = 1.4, contrast = 1.2)),
    ("Pixelate", () -> Pixelate(0.18)),
    ("Vignette", () -> Vignette(; amount = 0.9, radius = 0.3, feather = 0.5)),
    ("Grain", () -> Grain(; amount = 0.35, seed = 9, rate = 2)),
    ("ChromaticAberration", () -> ChromaticAberration(0.2)),
    ("Sharpen", () -> Sharpen(1.5; sigma = 0.08)),
    ("Wave", () -> Wave(; amplitude = 0.15, wavelength = 1.2, angle = 0.4)),
    ("EdgeDetect", () -> EdgeDetect(; color = WHITE, amount = 1.6)),
]
# the centre of every act: 0.3, 0.9, … 6.3. Rounded, because the name of the
# keyframe carries the number and 4.5 × 0.6 prints as 2.6999999999999997.
const KEY_FRAMES = [round((k - 0.5) * ACT; digits = 2) for k in 1:length(EFFECTS)]
const RESOLUTION = (640, 360)

"The plate every effect works on: flat colour, a gradient, hard edges, type."
function plate()
    g = VGroup()
    sky = Rectangle(width = 6.4, height = 3.6)
    set_fill_by_gradient!(sky, "#1B4F8C", "#39D0FF")
    set_fill!(sky; opacity = 1.0); set_stroke!(sky; opacity = 0)
    move_to!(sky, 0.2 * DOWN)
    add!(g, sky)
    sun = Circle(radius = 0.7)
    set_fill!(sun; color = "#FFD25E", opacity = 1.0)
    set_stroke!(sun; color = WHITE, width = 3.0)
    move_to!(sun, Point3f(2.0, 0.9, 0))
    add!(g, sun)
    hill = Triangle(radius = 1.6)
    set_fill!(hill; color = "#3E8E52", opacity = 1.0); set_stroke!(hill; opacity = 0)
    move_to!(hill, Point3f(-1.6, -0.6, 0))
    add!(g, hill)
    bar = Rectangle(width = 6.4, height = 0.5)
    set_fill!(bar; color = "#FF3D8B", opacity = 1.0); set_stroke!(bar; opacity = 0)
    move_to!(bar, Point3f(0, -1.75, 0))
    add!(g, bar)
    for x in (-2.4, -0.8, 0.8, 2.4)
        l = Line(Point3f(x, -1.2, 0), Point3f(x + 0.6, 1.4, 0))
        set_stroke!(l; color = WHITE, width = 2.0, opacity = 0.8)
        add!(g, l)
    end
    t = TextMobject("JANIM"; size = 0.9, color = WHITE)
    move_to!(t, Point3f(0.2, 0.1, 0))
    add!(g, t)
    return g
end

function construct(scene)
    fx = Layer(plate(); effects = Any[])
    label = TextMobject("effects"; size = 0.32, color = GREY_B)
    to_edge!(label, DOWN; buff = 0.12)
    use_composition!(scene, Composition(fx, Layer(label);
                                        background = (0.02f0, 0.03f0, 0.05f0, 1f0)))
    for (name, make) in EFFECTS
        empty!(fx.effects)
        push!(fx.effects, make())            # the layer is a mutable struct: swap in place
        new = TextMobject(name; size = 0.32, color = GREY_B)
        to_edge!(new, DOWN; buff = 0.12)
        become!(label, new)
        wait!(scene, ACT)                    # one act = one effect
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    dir = joinpath(@__DIR__, "expected")
    mkpath(dir)
    for (i, t) in enumerate(KEY_FRAMES)
        name = i == 1 ? "06_effects.png" : "06_effects@$(t).png"
        path = joinpath(dir, name)
        render_frame(construct, t; fps = 30, resolution = RESOLUTION, png = path)
        println("→ ", path)
    end
end
