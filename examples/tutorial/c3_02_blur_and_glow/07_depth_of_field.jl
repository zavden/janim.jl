# Course 3 · 2.7 — Depth of field
#
#     Dof(focus = nothing; aperture = 0.4, max_sigma = 4.0)
#
# A blur whose σ is recomputed EVERY FRAME from the layer's distance to the
# camera's focal plane:
#
#     σ = min(aperture · |d − focus|, max_sigma)
#
# where `d` is the camera→layer-centre distance measured along the view axis.
# `focus = nothing` means the camera's own focal distance, so with the default
# camera the plane through the origin is in focus.
#
# It is PER LAYER, which is the honest scope: a layer is composited to one
# texture, so it has one depth. A real lens blurs per pixel; this blurs per
# layer, and for a scene built out of planes at different depths — which is
# most explanatory 3D — the two agree.
#
# Two ways to drive it, both here:
#
#   · MOVE THE CAMERA and leave `focus = nothing`: the layers go in and out of
#     focus by themselves, because `_focus!` resolves every `Dof` against the
#     camera of the frame being composited;
#   · RACK FOCUS: keep the camera still and animate `dof.focus`, which is what
#     a camera operator actually does.
#
#   julia --project=. examples/tutorial/c3_02_blur_and_glow/07_depth_of_field.jl

using Janim

const PREVIEW_T = 3.4

"A row of dots at depth z, placed up the frame so all three are visible."
function card(z, y, colour, label)
    g = VGroup()
    for k in 0:5
        c = Circle(radius = 0.32)
        set_fill!(c; color = colour, opacity = 1.0); set_stroke!(c; opacity = 0)
        move_to!(c, Point3f(-3.2 + 1.05k, y, z))
        add!(g, c)
    end
    t = TextMobject(label; size = 0.32, color = colour)
    move_to!(t, Point3f(3.6, y, z))
    add!(g, t)
    return g
end

function construct(scene)
    # The DEFAULT camera: it looks straight down −z, so depth IS the z
    # coordinate and the arithmetic above is easy to check by eye.
    near = card(2.0, 1.7, "#7FDD58", "z = +2")
    mid = card(0.0, 0.0, "#FFD25E", "z =  0")
    far = card(-2.0, -1.7, "#58C4DD", "z = -2")

    title = TextMobject("rack focus: one field, animated"; size = 0.42, color = GREY_A)
    to_edge!(title, UP; buff = 0.3)

    d_near = Dof(; aperture = 0.5, max_sigma = 3.0)
    d_mid = Dof(; aperture = 0.5, max_sigma = 3.0)
    d_far = Dof(; aperture = 0.5, max_sigma = 3.0)

    use_composition!(scene, Composition(
        Layer(far; effects = [d_far]),
        Layer(mid; effects = [d_mid]),
        Layer(near; effects = [d_near]),
        Layer(title);
        background = (0.02f0, 0.03f0, 0.05f0, 1f0)))

    focal = get_focal_distance(scene.camera)
    println("focal distance ", round(focal; digits = 3),
            " — with focus = nothing, the z = 0 plane is the sharp one")
    wait!(scene, 1.0)

    # Rack the focus from the far plane to the near one and back.
    rack(a) = begin
        f = focal + 2.0 - 4.0a                 # focal+2 (far) → focal−2 (near)
        for d in (d_near, d_mid, d_far)
            d.focus = f
        end
        nothing
    end
    play!(scene, UpdateFromAlphaFunc(mid, (m, a) -> rack(a)); run_time = 2.5)
    wait!(scene, 0.4)
    play!(scene, UpdateFromAlphaFunc(mid, (m, a) -> rack(1 - a)); run_time = 2.5)
    wait!(scene, 0.4)
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__),
                   "07_depth_of_field.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
