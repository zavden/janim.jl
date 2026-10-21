# Course 1 · 3.1 — Group vs VGroup
#
#   VGroup(mobs...)   a VMobject that holds VMobjects. It accepts transforms
#                     and style (`shift!`, `scale!`, `set_color!` reach every
#                     child), it can be Transformed, and it has a bounding box
#                     — so all of the relative layout works on it.
#   Group(mobs...)    holds ANY Mobject: a ValueTracker, a CameraFrame, a
#                     Surface, an ImageMobject. It draws nothing itself and
#                     carries no style; it exists so things can live and
#                     update together.
#
# Rule of thumb: if everything in it is vector geometry, use VGroup. The
# moment one member is not, `add!` would throw (it writes into the child's
# `parents` field, which only a VMobject has) — that is when Group is the
# answer. `AnimationGroup` picks between them for you, for exactly this
# reason.
#
# Also here: a group is a real parent. `g[2]` is its second child, `g[1:3]` a
# memoised VGroup of the first three, and `get_family(g)` is the DFS the
# renderer and Transform both walk.
#
#   julia --project=. examples/tutorial/c1_03_groups_and_text/01_groups_vs_vgroups.jl

using Janim

const PREVIEW_T = 2.0

function construct(scene)
    title = TextMobject("VGroup transforms · Group only gathers";
                        size = 0.48, color = GREY_A)
    to_edge!(title, UP; buff = 0.4)
    add!(scene, title)

    # ── a VGroup: geometry, so it moves and paints as one ────────────────
    tiles = VGroup()
    for k in 1:6
        s = Square(side_length = 0.8)
        set_fill!(s; color = "#2C5F8A", opacity = 1.0)
        set_stroke!(s; color = "#0B0E14", width = 3.0)
        add!(tiles, s)
    end
    arrange_in_grid!(tiles; n_rows = 2, n_cols = 3, buff = 0.15)
    move_to!(tiles, 3.4 * LEFT)

    println("children: ", length(tiles.submobjects),
            " · family (DFS, parent included): ", length(get_family(tiles)))

    # ── a Group: a tracker and a surface, which no VGroup could hold ─────
    knob = ValueTracker(0.4)
    ball = Sphere(; radius = 0.9, resolution = (61, 31))
    set_color!(ball; color = "#E8A33D")
    # A Surface answers the whole transform family, `move_to!` included
    move_to!(ball, Point3f(3.4, 0.2, 0))
    apply_depth_test!(ball)
    mixed = Group(knob, ball)
    add_updater!(ball, m -> set_color!(m; opacity = get_value(knob)))

    add!(scene, tiles, mixed)

    # One animation over the whole VGroup: every child follows.
    play!(scene, animate(tiles, (rotate!, TAU / 16), (scale!, 1.15)); run_time = 1.2)
    # Addressing children: `tiles[2]` is a child, `tiles[4:6]` a memoised group.
    play!(scene, Indicate(tiles[4:6]; color = YELLOW); run_time = 1.0)
    # The Group's members are driven by whatever drives them — here, the
    # tracker the sphere's updater reads.
    play!(scene, animate(knob, (set_value!, 1.0)); run_time = 1.0)
    wait!(scene, 0.4)
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__),
                   "01_groups_vs_vgroups.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
