# Course 3 · 2.5 — RadialBlur (zoom blur)
#
#     RadialBlur(strength; center_point = (0.0, 0.0))
#
# 32 samples along the line from each pixel TOWARDS the centre, averaged. The
# centre stays sharp and everything smears outwards — the "warp speed" look,
# and the honest way to draw attention to a point.
#
# `strength ∈ [0, 1)` is how far along that line the last sample lands, so it
# is a fraction of the distance to the centre rather than a length: a pixel at
# the corner smears more than one near the middle, which is what makes the
# effect read as radial in the first place.
#
# `center_point` is in SCENE COORDINATES, so it can follow a mobject: put an
# updater on it and the zoom blur tracks whatever you are pointing at.
#
#   julia --project=. examples/tutorial/c3_02_blur_and_glow/05_radial_blur.jl

using Janim

const PREVIEW_T = 2.2

function construct(scene)
    title = TextMobject("the centre stays sharp; the rest smears outwards";
                        size = 0.42, color = GREY_A)
    to_edge!(title, UP; buff = 0.3)

    # A field of spokes and rings: the pattern a zoom blur eats best.
    field = VGroup()
    for k in 0:23
        θ = k * TAU / 24
        l = Line(Point3f(1.1cos(θ), 1.1sin(θ) - 0.2, 0),
                 Point3f(5.2cos(θ), 5.2sin(θ) - 0.2, 0))
        set_stroke!(l; color = "#3D7BC0", width = 3.0)
        add!(field, l)
    end
    for r in (1.6, 2.4, 3.2, 4.0)
        c = Circle(radius = r)
        set_stroke!(c; color = "#25405C", width = 2.5); set_fill!(c; opacity = 0)
        move_to!(c, Point3f(0, -0.2, 0))
        add!(field, c)
    end

    core = Circle(radius = 0.85)
    set_fill!(core; color = "#FFD25E", opacity = 1.0); set_stroke!(core; opacity = 0)
    move_to!(core, Point3f(0, -0.2, 0))

    zoom = RadialBlur(0.0; center_point = (0.0, -0.2))

    use_composition!(scene, Composition(
        Layer(field; effects = [zoom]),
        Layer(core),
        Layer(title);
        background = (0.02f0, 0.03f0, 0.05f0, 1f0)))

    # The strength swells and dies — one field, one animation.
    play!(scene, UpdateFromAlphaFunc(core, (m, a) ->
              (zoom.strength = 0.55 * there_and_back(a); nothing));
          run_time = 3.0)
    wait!(scene, 0.4)
    println("strength returned to ", round(zoom.strength; digits = 4))
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "05_radial_blur.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
