# Course 3 · 1.1 — The layer, the one primitive
#
# Manim draws EVERYTHING into the final framebuffer in z order. There are no
# intermediate textures, so there is nowhere to apply a blend mode or an
# effect "to this group and not that one". It is not a missing feature — it
# follows from the architecture.
#
# Janim's compositing primitive is the LAYER: a texture plus its compositing
# parameters. Everything in course 3 is a consequence.
#
#     Layer(mobjects...; blend, opacity, effects, mask, matte)
#     Composition(layers...; background = (r, g, b, a))
#     use_composition!(scene, comp)
#
# THE RULE TO INTERNALISE FIRST: once a composition is mounted, the scene
# renders IT and not `scene.mobjects`. Anything you want on screen has to be
# in a layer — titles and captions included. That is the honest shape of the
# design: there is no privileged "just draw this" path.
#
# `add!(scene, m)` still matters for one thing: UPDATERS. Mobjects inside
# layers are updated too (the compositor walks them), so in practice you add!
# only what has an updater and lives nowhere else.
#
#   julia --project=. examples/tutorial/c3_01_layers/01_one_layer.jl

using Janim

const PREVIEW_T = 1.6

function construct(scene)
    title = TextMobject("everything on screen is a layer"; size = 0.48, color = GREY_A)
    to_edge!(title, UP; buff = 0.4)

    back = Rectangle(width = 5.0, height = 3.2)
    set_fill!(back; color = "#2C5F8A", opacity = 1.0); set_stroke!(back; opacity = 0)
    move_to!(back, 0.4 * DOWN)

    front = Star(6; outer_radius = 1.5)
    set_fill!(front; color = "#FFD25E", opacity = 1.0); set_stroke!(front; opacity = 0)
    move_to!(front, 0.4 * DOWN)

    caption = TextMobject("layer 2 is blurred; layer 3 is not";
                          size = 0.36, color = GREY_B)
    move_to!(caption, 2.9 * DOWN)

    # Bottom to top, exactly as written. The blur belongs to the BACK layer,
    # so the star in front of it stays sharp even where they overlap — the
    # thing a single framebuffer cannot do.
    use_composition!(scene, Composition(
        Layer(back; effects = [Blur(0.12)]),
        Layer(front),
        Layer(title, caption);
        background = (0.02f0, 0.03f0, 0.05f0, 1f0)))

    play!(scene, GrowFromCenter(front); run_time = 1.0)
    wait!(scene, 1.0)
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "01_one_layer.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
