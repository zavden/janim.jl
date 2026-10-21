# Course 2 · 1.1 — Alpha updaters
#
# An UPDATER runs every frame for as long as the mobject is in the scene. An
# ALPHA updater runs only while an animation is playing, and it is handed how
# far through that animation it is:
#
#     UpdateFromAlphaFunc(m, (m, α) -> …)    α ∈ [0,1], rate function applied
#     UpdateFromFunc(m, m -> …)              no α — for "follow that other
#                                            mobject while IT is animated"
#
# `UpdateFromAlphaFunc` takes NO snapshot of the mobject, and that is the
# whole point: every other animation captures a start and an end and lerps
# between them, which needs the mobject to be interpolable. This one does not
# — so it drives a `Surface`, an `ImageMobject`, a camera, or a type of your
# own, with no contract to implement.
#
# When to reach for which:
#
#   the state is a closed form of α          → UpdateFromAlphaFunc
#   the state depends on something else       → UpdateFromFunc
#   the state must persist after the animation → add_updater! (lesson 1.2)
#
#   julia --project=. examples/tutorial/c2_01_updaters_and_custom_mobjects/01_alpha_updaters.jl

using Janim

const PREVIEW_T = 2.0

function construct(scene)
    title = TextMobject("alpha updaters take no snapshot"; size = 0.46, color = GREY_A)
    to_edge!(title, UP; buff = 0.35)
    add!(scene, title)

    # A Surface cannot be Transformed (it does not implement the contract),
    # but an alpha updater drives it happily.
    blob = Surface((u, v) -> (cos(u) * sin(v), sin(u) * sin(v), -cos(v));
                   u_range = (0.0, TAU), v_range = (0.0, PI),
                   resolution = (61, 31), color = "#2C5F8A")
    shift!(blob, Point3f(-3.4, -0.3, 0) - get_center(blob))
    apply_depth_test!(blob)
    add!(scene, blob)

    # A dot travelling a Lissajous figure — a closed form of α, so no state.
    dot = Dot(ORIGIN; radius = 0.13)
    set_fill!(dot; color = "#FFD25E")
    trail = TracedPath(() -> get_center(dot); stroke_color = "#FFD25E",
                       stroke_width = 2.5)
    add!(scene, dot, trail)
    set_z_index!(trail, -1)

    lissajous = (m, a) -> move_to!(m, Point3f(3.2 + 1.6 * sin(3TAU * a),
                                              -0.3 + 1.3 * sin(2TAU * a), 0))

    # A label that FOLLOWS the dot: it has no α of its own, it just reads the
    # dot each frame. That is UpdateFromFunc.
    tag_ = TextMobject("(x, y)"; size = 0.34, color = GREY_B)
    add!(scene, tag_)
    follow = (m) -> move_to!(m, get_center(dot) + Point3f(0, 0.45, 0))

    play!(scene, AnimationGroup(
              UpdateFromAlphaFunc(blob, (m, a) -> begin
                  # rebuild the mesh's radius from α — a Transform could not
                  # do this, because a Surface is not interpolable
                  r = 0.9 + 0.35 * sin(2TAU * a)
                  c = get_center(m)
                  s = Surface((u, v) -> (r * cos(u) * sin(v), r * sin(u) * sin(v),
                                         -r * cos(v));
                              u_range = (0.0, TAU), v_range = (0.0, PI),
                              resolution = (61, 31), color = "#2C5F8A")
                  m.points .= s.points .+ Ref(c)
                  m.d_normal_points .= s.d_normal_points .+ Ref(c)
                  nothing
              end),
              UpdateFromAlphaFunc(dot, lissajous),
              UpdateFromFunc(tag_, follow);
              run_time = 4.0);
          run_time = 4.0)
    wait!(scene, 0.4)
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "01_alpha_updaters.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
