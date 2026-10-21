# Course 3 · 1.7 — Layers vs z-index: which one you want
#
# Both change what is drawn on top. They are not interchangeable.
#
#   set_z_index!(m, z)     ORDER inside one texture. Cheap (a stable sort of a
#                          list), works anywhere, and it is what you want 90%
#                          of the time.
#   a separate Layer       a texture of its OWN. Costs one fullscreen buffer,
#                          and buys the only things a single framebuffer
#                          cannot give: a blend mode, an effect applied to
#                          this group and nothing else, a mask, a matte, and
#                          a group opacity that does not show internal seams.
#
# Rule of thumb: reach for z-index for ORDER, for a layer for TREATMENT.
#
# And the trap from course 1, which is really about update order:
# `bring_to_front!`/`bring_to_back!` move the mobject inside `scene.mobjects`,
# which is the UPDATE order too. A `TracedPath` sent to the back with
# `bring_to_back!` starts sampling the previous frame's position and lags a
# whole frame behind what it follows. `set_z_index!` does not touch updaters.
#
#   julia --project=. examples/tutorial/c3_01_layers/07_layers_vs_zindex.jl

using Janim

const PREVIEW_T = 1.6

"Three overlapping bars at x, in a single group."
function bars(x)
    g = VGroup()
    for (k, colour) in enumerate(("#3D7BC0", "#E8A33D", "#7FDD58"))
        r = RoundedRectangle(width = 2.6, height = 0.9, corner_radius = 0.18)
        set_fill!(r; color = colour, opacity = 1.0); set_stroke!(r; opacity = 0)
        move_to!(r, Point3f(x - 0.35 + 0.35k, 0.5 - 0.42k, 0))
        add!(g, r)
    end
    return g
end

function construct(scene)
    title = TextMobject("z-index for ORDER · a layer for TREATMENT";
                        size = 0.42, color = GREY_A)
    to_edge!(title, UP; buff = 0.3)

    # LEFT: one layer, ordering done with z-index. The middle bar is lifted.
    left = bars(-3.5)
    set_z_index!(left[2], 1)

    # RIGHT: the same three bars, but the middle one lives on its OWN layer
    # with a blend mode and a glow — impossible with z-index alone.
    right = bars(3.5)
    middle = right[2]
    remove!(right, middle)

    l1 = TextMobject("set_z_index!(bar, 1)"; size = 0.32, color = GREY_B)
    l2 = TextMobject("its own layer: :add + Bloom"; size = 0.32, color = GREY_B)
    move_to!(l1, Point3f(-3.5, -2.6, 0)); move_to!(l2, Point3f(3.5, -2.6, 0))

    use_composition!(scene, Composition(
        Layer(left),
        Layer(right),
        Layer(middle; blend = :add,
              effects = [Bloom(threshold = 0.25, intensity = 1.3, sigma = 0.13)]),
        Layer(title, l1, l2);
        background = (0.03f0, 0.04f0, 0.06f0, 1f0)))

    wait!(scene, 2.0)
    println("left group children: ", length(left.submobjects),
            " · right group children: ", length(right.submobjects),
            " (the third one moved to a layer of its own)")
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__),
                   "07_layers_vs_zindex.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
