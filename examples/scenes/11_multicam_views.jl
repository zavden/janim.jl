# Ejemplo 11 · CUATRO CÁMARAS, UN MUNDO — la multicámara 3D.
#
# El panel clásico de un editor 3D, hecho con la primitiva del compositor:
# CUATRO capas que comparten el MISMO vector de mobjects, cada una con su
# `CameraFrame` (`camera =`) y su rectángulo en pantalla (`window =`). No hay
# copias ni proyecciones falsas: cada vista es un render de verdad, con su
# z-buffer PROPIO — el satélite que enhebra el toro se esconde detrás del
# tubo en unas vistas mientras sigue visible en otras, que es exactamente lo
# que una copia escalada no puede hacer.
#
# Dos reglas que este fichero enseña:
#
#   · el mundo puede estar en las cuatro capas a la vez: los updaters corren
#     UNA sola vez por frame (la lista viva se deduplica por identidad);
#   · una ventana con la MISMA forma que el frame de su cámara (16:9 aquí)
#     muestra la vista entera de esa cámara, sin recorte que adivinar.
#
#   julia --project=. examples/scenes/11_multicam_views.jl

using Janim

function construct(scene)
    # ── el mundo: un toro, sus ejes, y un satélite que lo enhebra ────────
    torus = Torus(; r1 = 2.0, r2 = 0.55, resolution = (81, 41))
    set_color!(torus; color = "#3F6FB0")
    apply_depth_test!(torus)

    axes = VGroup()
    for (dir, col) in ((Point3f(3.2, 0, 0), "#E4573D"),
                       (Point3f(0, 3.2, 0), "#63B463"),
                       (Point3f(0, 0, 2.4), "#5AA8D8"))
        ln = Line(Point3f(0, 0, 0), dir)
        set_stroke!(ln; color = col, width = 2.5)
        apply_depth_test!(ln)
        add!(axes, ln)
    end

    sat = Sphere(; radius = 0.22)
    set_color!(sat; color = "#FFD25E")
    apply_depth_test!(sat)
    phase = Ref(0.0)
    add_updater!(sat, (m, dt) -> begin
        phase[] += 0.9 * dt
        move_to!(m, Point3f(2.0 + 1.1 * cos(phase[]), 0, 1.1 * sin(phase[])))
    end)

    world = [torus, axes, sat]

    # ── cuatro cámaras sobre ese mundo ───────────────────────────────────
    cam_top = CameraFrame()
    set_frame_height!(cam_top, 7.0)

    cam_front = CameraFrame()
    reorient!(cam_front, 0.0, 90.0)
    set_frame_height!(cam_front, 7.0)

    cam_side = CameraFrame()
    reorient!(cam_side, 90.0, 90.0)
    set_frame_height!(cam_side, 7.0)

    cam_persp = CameraFrame()
    reorient!(cam_persp, -35.0, 62.0)
    set_frame_height!(cam_persp, 8.5)
    sway = Ref(0.0)
    add_updater!(cam_persp, (f, dt) -> begin
        sway[] += dt
        reorient!(f, -35.0 + 18.0 * sin(0.35 * sway[]), 62.0)
    end)

    # ── el panel: cuatro ventanas 16:9 que tejan el cuadro ───────────────
    win(x, y) = begin
        r = Rectangle(
            width = 6.91,
            height = 6.91 * 9 / 16,
        )
        set_stroke!(r; color = GREY_B, width = 3.0)
        set_fill!(r; opacity = 0)
        move_to!(r, Point3f(x, y, 0))
        r
    end
    w_tl = win(-3.555, 2.0)
    w_tr = win(3.555, 2.0)
    w_bl = win(-3.555, -2.0)
    w_br = win(3.555, -2.0)

    tag(txt, w) = begin
        t = TextMobject(txt; size = 0.26, color = GREY_B)
        align_to!(t, w, UL)
        shift!(t, Point3f(0.18, -0.28, 0))
        t
    end
    tags = [tag("PLANTA", w_tl), tag("PERSPECTIVA", w_tr),
            tag("ALZADO", w_bl), tag("PERFIL", w_br)]

    use_composition!(scene, Composition(
        Layer(world...; camera = cam_top, window = w_tl),
        Layer(world...; camera = cam_persp, window = w_tr),
        Layer(world...; camera = cam_front, window = w_bl),
        Layer(world...; camera = cam_side, window = w_br),
        Layer(w_tl, w_tr, w_bl, w_br, tags...);
        background = (0.015f0, 0.02f0, 0.04f0, 1f0),
    ))

    # Todo el movimiento es de updaters: dos vueltas del satélite mientras
    # la perspectiva se mece. Las otras tres vistas ni se enteran — cada
    # cámara es suya.
    wait!(scene, 14.0)
end

if abspath(PROGRAM_FILE) == @__FILE__
    Scene(construct; output = joinpath(@__DIR__, "output", "11_multicam_views.mp4"),
          fps = 30, resolution = (1280, 720))
end
