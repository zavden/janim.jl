# Ejemplo 04 · GEOMETRÍA EN EL ESPACIO — ~60 s usando todo el stack 3D:
# superficies uv con luz (esfera, toro y un MAR de ondas animadas por
# updater con normales analíticas), oclusión real a tres vías (los anillos
# depth-testeados atraviesan la escena), cámara de cuaterniones ORBITANDO
# con cambios de φ y zoom (piloto por updater), y fórmulas HUD fijas a
# pantalla (fix_in_frame) morfando entre sí.
#
#   julia --project=. examples/scenes/04_space.jl      # render en 4 procesos

using Janim

function construct(scene)
    reorient!(scene.camera, 15, 68)

    # ── el mar: superficie animada con normales analíticas ──────────────
    X, Y, NU, NV = 6.5, 4.6, 61, 41
    olas = PlaneXY(x_range = (-X, X), y_range = (-Y, Y), resolution = (NU, NV),
                   color = "#16324F", opacity = 1.0, shading = (0.45, 0.55, 0.35))
    tw = Ref(0.0)
    add_updater!(olas, (m, dt) -> begin
        tw[] += dt
        t = tw[]
        k = 0
        for u in range(-X, X; length = NU), v in range(-Y, Y; length = NV)
            k += 1
            z = -1.35 + 0.22sin(1.3u + 1.8t) * cos(1.1v + 1.3t) + 0.10sin(2.1u - 1.1t)
            dzx = 0.286cos(1.3u + 1.8t) * cos(1.1v + 1.3t) + 0.21cos(2.1u - 1.1t)
            dzy = -0.242sin(1.3u + 1.8t) * sin(1.1v + 1.3t)
            inv = 1e-3 / sqrt(dzx^2 + dzy^2 + 1)
            m.points[k] = Point3f(u, v, z)
            m.d_normal_points[k] = Point3f(u - dzx * inv, v - dzy * inv, z + inv)
        end
        nothing
    end)

    # ── los sólidos ──────────────────────────────────────────────────────
    esf = Sphere(radius = 1.15, color = "#58C4DD")
    shift!(esf, Point3f(-1.9, 0, 0.35))
    tor = Torus(r1 = 1.5, r2 = 0.42, color = "#F0A045")
    shift!(tor, Point3f(1.9, 0, -0.1))

    # anillos DEPTH-TESTEADOS que atraviesan la escena
    anillos = VGroup()
    for (r, col, tilt) in ((3.0, "#FFD25E", 0.35), (3.55, "#DD58C4", -0.25))
        a = Circle(radius = r)
        set_stroke!(a; color = col, width = 4.0)
        rotate!(a, tilt; axis = RIGHT)
        shift!(a, Point3f(0, 0, 0.25))
        apply_depth_test!(a)
        add!(anillos, a)
    end
    giro = Ref(0.0)
    add_updater!(anillos, (m, dt) -> begin
        dt > 0 || return
        for a in m.submobjects
            rotate!(a, 0.25dt; axis = OUT, about_point = Point3f(0, 0, 0.25))
        end
        nothing
    end)

    # ── el piloto: la cámara como coreografía (orbita, sube, zoom) ──────
    tc = Ref(0.0)
    piloto = VGroup()
    add_updater!(piloto, (m, dt) -> begin
        dt > 0 || return
        tc[] += dt
        t = tc[]
        increment_euler_angles!(scene.camera; dtheta = 0.30dt)
        14 <= t < 22 && increment_euler_angles!(scene.camera; dphi = -0.075dt)
        40 <= t < 50 && increment_euler_angles!(scene.camera; dphi = 0.055dt)
        26 <= t < 34 && Janim.scale_frame!(scene.camera, 1 - 0.095dt)
        46 <= t < 56 && Janim.scale_frame!(scene.camera, 1 + 0.082dt)
        nothing
    end)

    # ── el HUD fijo a pantalla ───────────────────────────────────────────
    hud = Tex(raw"S^2 \times T^2 \subset \mathbb{R}^3"; color = "#FFFFFF", size = 0.85)
    fix_in_frame!(hud)
    move_to!(hud, Point3f(-3.9, 3.05, 0))
    hacer_hud(s, color) = begin
        t = Tex(s; color, size = 0.85)
        move_to!(t, Point3f(-3.9, 3.05, 0)); t
    end
    marca = TextMobject("Janim.jl")
    set_height!(marca, 0.32)
    set_fill!(marca; color = "#44536A", opacity = 0.85)
    fix_in_frame!(marca)
    move_to!(marca, Point3f(5.5, -3.25, 0))

    add!(scene, olas, esf, tor, anillos, marca, piloto)

    # ── la coreografía temporal (60 s exactos) ──────────────────────────
    play!(scene, FadeIn(hud; shift = 0.25 * DOWN); run_time = 1.2)
    wait!(scene, 12.8)
    play!(scene, Transform(hud, hacer_hud(raw"A_{S^2} = 4\pi r^2", "#58C4DD")); run_time = 1.2)
    wait!(scene, 12.8)
    play!(scene, Transform(hud, hacer_hud(raw"A_{T^2} = 4\pi^2 R\, r", "#F0A045")); run_time = 1.2)
    wait!(scene, 12.8)
    play!(scene, Transform(hud, hacer_hud(raw"\chi(T^2) = 0", "#FFD25E")); run_time = 1.2)
    wait!(scene, 10.6)
    play!(scene, AnimationGroup(FadeOut(hud), FadeOut(marca)); run_time = 1.6)
    wait!(scene, 4.6)
end

if abspath(PROGRAM_FILE) == @__FILE__
    path = joinpath(@__DIR__, "output", "04_space.mp4")
    mkpath(dirname(path))
    render_parallel(@__FILE__, path; n = 4, frames_total = 1800, fps = 30,
                    resolution = (1280, 720))
    println("→ ", path)
end
