# Course 2 · 3.2 — The magnifier: a second camera on its own layer
#
# CE's `ZoomedScene` renders the scene TWICE: a second camera draws an inset
# "display". Janim has the real thing — a `Layer` can carry its own
# `CameraFrame` and a `window`:
#
#   Layer(world...; camera = zoom, window = display)
#
#   · `camera` says what the layer SEES: a real second render through a real
#     camera, so stroke widths do not grow with the zoom and nothing needs to
#     re-adopt geometry with `become!` every frame.
#   · `window` says where the finished picture SHOWS: the mobject's bounding
#     box on screen. The layer does not draw the mobject itself — give it a
#     stroke and put it in a layer on top, and that is the border. Animate
#     it and the window follows.
#
# What the window shows is the largest CENTRED cut of the camera's view that
# matches the window's aspect. Make the window the same shape as the camera
# frame — 16:9 here — and it shows exactly the camera's view, which is why
# the on-screen region indicator below is just a rectangle of the camera's
# own `get_width` × `get_height`, glued to its centre with an updater.
#
#   julia --project=. examples/tutorial/c2_03_camera/02_zoomed_camera.jl
#
# Course 3 owns layers properly; this lesson borrows the one it needs.

using Janim

const PREVIEW_T = 2.4

function construct(scene)
    # ── the world, with detail worth magnifying ──────────────────────────
    world = VGroup()
    plane = NumberPlane((-7.0, 7.0, 1.0), (-4.0, 4.0, 1.0); width = 14.0,
                        height = 8.0, background_line_color = "#25405C",
                        faded_opacity = 0.12)
    add!(world, plane.group)
    spiral = VMobject()
    set_points_as_corners!(spiral, [Point3f(-2.5 + 0.13t * cos(t), 0.35t * sin(t) - 0.6, 0)
                                    for t in 0:0.05:9])
    set_stroke!(spiral; color = "#58C4DD", width = 3.0)
    add!(world, spiral)
    for θ in range(0, TAU; length = 9)[1:8]
        d = Dot(Point3f(-2.5 + 0.22cos(θ), -0.6 + 0.22sin(θ), 0); radius = 0.03)
        set_fill!(d; color = "#FFD25E")
        add!(world, d)
    end
    fine = TextMobject("fine print"; size = 0.09, color = "#7FDD58")
    move_to!(fine, Point3f(-2.5, -1.1, 0))
    add!(world, fine)

    # ── the second camera, and where its picture lands ───────────────────
    focus = Ref(Point3f(-2.5, -0.6, 0))
    zoom = CameraFrame()
    set_frame_height!(zoom, 1.2)                # capture 1.2 scene units tall
    add_updater!(zoom, f -> move_to!(f, focus[]))

    display = Rectangle(
        width = 4.5,
        height = 4.5 * 9 / 16,                  # 16:9, the camera frame's shape
    )
    set_stroke!(display; color = GREY_A, width = 4.0)
    set_fill!(display; opacity = 0)             # it must not cover its window
    to_corner!(display, UR; buff = 0.4)

    reticle = Rectangle(
        width = get_width(zoom),                # the captured region, exactly
        height = get_height(zoom),
    )
    set_stroke!(reticle; color = GREY_A, width = 2.0)
    set_fill!(reticle; opacity = 0)
    add_updater!(reticle, m -> begin
        set_width!(m, get_width(zoom))          # …even while the zoom animates
        move_to!(m, focus[])
    end)

    caption = TextMobject("a second camera on its own layer — a render, not a copy";
                          size = 0.36, color = GREY_C)
    to_edge!(caption, DOWN; buff = 0.35)

    use_composition!(scene, Composition(
        Layer(world),
        Layer(reticle, caption),
        Layer(world; camera = zoom, window = display),
        Layer(display);
        background = (0.02f0, 0.03f0, 0.05f0, 1f0),
    ))

    wait!(scene, 0.8)
    # The focus moves; the camera's own updater keeps it centred, so the
    # inset follows — and unlike the old copy trick there is no “orbit small
    # or the inset shows empty grid” caveat to work around: the camera shows
    # whatever it is aimed at, like any camera.
    play!(scene, UpdateFromAlphaFunc(reticle, (m, a) ->
              (focus[] = Point3f(-2.5 + 0.45cos(TAU * a),
                                 -0.75 + 0.35sin(TAU * a), 0); nothing));
          run_time = 3.0)
    # A CameraFrame is a mobject: animating the zoom is animating it — while
    # the focus drifts back to the ring's centre and the reticle's updater
    # keeps the indicator matched with the tightening frame.
    p0 = focus[]
    ring = Point3f(-2.5, -0.6, 0)
    play!(scene,
          animate(zoom, (set_frame_height!, 0.7)),
          UpdateFromAlphaFunc(reticle, (m, a) ->
              (focus[] = Point3f(p0 + a * (ring - p0)); nothing));
          run_time = 1.2)
    wait!(scene, 0.6)
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "02_zoomed_camera.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
