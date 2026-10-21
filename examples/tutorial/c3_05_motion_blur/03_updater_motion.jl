# Course 3 · 5.3 — Motion blur smears updaters too
#
# This is the difference between real motion blur and a directional smear.
# The scene STATE is advanced between sub-exposures, so anything that moves —
# `play!` animations, updaters, `always_redraw`, a camera move — is smeared
# along its own path.
#
# The frame loop does exactly this:
#
#     lead > 0 && _update_all!(scene, lead)     # the closed part of the frame
#     for sdt in subs                           # …then one exposure per step
#         _update_all!(scene, sdt)
#         draw and accumulate
#     end
#
# so `dt` reaches your updater in `n` pieces instead of one. Which is fine for
# anything that computes a position from time, and NOT fine for an integrator
# — that is lesson 5.5.
#
# One consequence worth naming: a `TracedPath` under motion blur samples once
# per SUB-EXPOSURE, so its trail gets n times as many points per frame. That
# is more accurate, and it is also n times the memory.
#
#   julia --project=. examples/tutorial/c3_05_motion_blur/03_updater_motion.jl

using Janim

const PREVIEW_T = 1.6
const PREVIEW_MOTION = 10

function construct(scene)
    title = TextMobject("the state advances between exposures";
                        size = 0.42, color = GREY_A)
    to_edge!(title, UP; buff = 0.35)
    add!(scene, title)

    # Nothing here is a `play!`: every motion comes from an updater.
    hub = Point3f(0, -0.3, 0)
    arms = VGroup()
    for k in 0:5
        d = Dot(hub; radius = 0.2)
        set_fill!(d; color = color_gradient(["#39D0FF", "#FF3D8B"], 6)[k+1])
        add!(arms, d)
    end
    add!(scene, arms)

    add_updater!(arms, function (m, dt)
        dt > 0 || return
        for (k, d) in enumerate(m.submobjects)
            θ = 2.2 * scene.t + (k - 1) * TAU / 6
            r = 1.5 + 0.6 * sin(1.7 * scene.t + k)
            move_to!(d, hub + Point3f(r * cos(θ), r * sin(θ), 0))
        end
        nothing
    end)

    # An always_redraw whose GEOMETRY changes every frame — it smears too.
    ripple = always_redraw() do
        r = 2.6 + 0.5 * sin(3.1 * scene.t)
        c = Circle(radius = r)
        set_stroke!(c; color = "#FFD25E", width = 3.0)
        set_fill!(c; opacity = 0)
        move_to!(c, hub)
        c
    end
    add!(scene, ripple)

    wait!(scene, 3.0)
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__),
                   "03_updater_motion.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480),
          motion_blur = 10, shutter = 0.5)
    println("→ ", out)
end
