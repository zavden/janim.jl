# Ejemplo 03 · EL CAMPO Y EL CAOS — ~62 s usando todo el stack 2D:
# streamlines Tsit5, doble péndulo DiffEq en updater con estela
# Bloom en layer :add, spotlight = MÁSCARA ANIMADA siguiendo al
# péndulo, DOF por layer en el background, blur animado de transición,
# fórmulas morfando y el final: una curve_at de Fourier que
# DESCIENDE POR EL GRADIENTE hasta una estrella (ForwardDiff).
#
#   julia --project=. examples/scenes/03_field_and_chaos.jl          # render directo
#   (o vía render_parallel: ver el bloque final — 4 procesos)

using Janim
using OrdinaryDiffEqTsit5
using ForwardDiff

# ── física: el doble péndulo ─────────────────────────────────────────────
const G03 = 9.8
function _dp!(du, u, p, t)
    θ1, θ2, ω1, ω2 = u
    Δ = θ1 - θ2
    den = 3 - cos(2Δ)
    du[1] = ω1; du[2] = ω2
    du[3] = (-3G03 * sin(θ1) - G03 * sin(θ1 - 2θ2) - 2sin(Δ) * (ω2^2 + ω1^2 * cos(Δ))) / den
    du[4] = 2sin(Δ) * (2ω1^2 + 2G03 * cos(θ1) + ω2^2 * cos(Δ)) / den
end

# ── la estrella target y la curve_at de Fourier ──────────────────────────
const KF, SF = 12, 160
function _estrella()
    verts = [(r * cos(θ), r * sin(θ))
             for (r, θ) in [((i % 2 == 1 ? 2.0 : 0.85), PI / 2 + (i - 1) * TAU / 10) for i in 1:10]]
    lados = [hypot((verts[mod1(i + 1, 10)] .- verts[i])...) for i in 1:10]
    acum = cumsum([0.0; lados])
    obj = zeros(SF, 2)
    for (j, s) in enumerate(range(0, sum(lados); length = SF + 1)[1:SF])
        i = min(something(findlast(<=(s + 1e-12), acum), 1), 10)
        α = (s - acum[i]) / lados[i]
        obj[j, :] .= verts[i] .+ α .* (verts[mod1(i + 1, 10)] .- verts[i])
    end
    obj
end
function _fourier(params)
    M = 2KF + 1
    T = eltype(params)
    pts = Matrix{T}(undef, SF, 2)
    for (j, s) in enumerate(range(0, 1; length = SF + 1)[1:SF])
        x = zero(T); y = zero(T)
        for (i, k) in enumerate(-KF:KF)
            c, sn = cos(2π * k * s), sin(2π * k * s)
            x += params[i] * c - params[M+i] * sn
            y += params[i] * sn + params[M+i] * c
        end
        pts[j, 1] = x; pts[j, 2] = y
    end
    pts
end

function construct(scene)
    # ── el reparto ───────────────────────────────────────────────────────
    background = Rectangle(width = 16.0, height = 9.0, fill_color = "#0B0E14",
                      fill_opacity = 1.0, stroke_opacity = 0, stroke_width = 0)

    # streamlines del campo rotacional (Tsit5 — círculos de verdad)
    lines = VGroup()
    for r in 0.7:0.45:3.4
        prob = ODEProblem((du, u, p, t) -> (du[1] = -u[2]; du[2] = u[1]),
                          [r, 0.0], (0.0, 2π))
        sol = solve(prob, Tsit5(); reltol = 1e-8, abstol = 1e-8, saveat = 0.06)
        v = VMobject()
        set_points_as_corners!(v, [Point3f(u[1], u[2], 0) for u in sol.u])
        set_stroke!(v; color = "#58C4DD", width = 3.0, opacity = 0.95)
        add!(lines, v)
    end

    # rejilla revelada por el SPOTLIGHT (máscara animada)
    rejilla = VGroup()
    for x in -7.2:0.8:7.2
        l = VMobject(); start_new_path!(l, Point3f(x, -4.2, 0)); add_line_to!(l, Point3f(x, 4.2, 0))
        set_stroke!(l; color = "#2A3B55", width = 1.6); add!(rejilla, l)
    end
    for y in -4.0:0.8:4.0
        l = VMobject(); start_new_path!(l, Point3f(-7.2, y, 0)); add_line_to!(l, Point3f(7.2, y, 0))
        set_stroke!(l; color = "#2A3B55", width = 1.6); add!(rejilla, l)
    end
    foco = Circle(radius = 1.35, fill_opacity = 1.0)
    move_to!(foco, Point3f(99, 99, 0))            # aparcado: la rejilla no se ve

    # péndulo doble + estela
    pivote = Point3f(0, 1.55, 0)
    scale_factor = 1.25
    varilla = VMobject(); set_stroke!(varilla; color = "#C8D2DC", width = 3.5)
    bob1 = Circle(radius = 0.11, fill_opacity = 1.0)
    set_fill!(bob1; color = "#C8D2DC", opacity = 0.0); set_stroke!(bob1; opacity = 0)
    bob2 = Circle(radius = 0.13, fill_opacity = 1.0)
    set_fill!(bob2; color = "#FFD25E", opacity = 0.0); set_stroke!(bob2; opacity = 0)
    estela = VMobject(); set_stroke!(estela; color = "#58C4DD", width = 2.6, opacity = 0.85)

    integ = init(ODEProblem(_dp!, [2.1, 2.6, 0.0, 0.0], (0.0, 1e4)), Tsit5();
                 reltol = 1e-9, abstol = 1e-9)
    rastro = Point3f[]
    p2_ref = Ref(Point3f(99, 99, 0))
    pendulo_on = Ref(false)
    add_updater!(varilla, (m, dt) -> begin
        (pendulo_on[] && dt > 0) || return
        step!(integ, dt, true)
        u = integ.u
        p1 = pivote + Point3f(scale_factor * sin(u[1]), -scale_factor * cos(u[1]), 0)
        p2 = p1 + Point3f(scale_factor * sin(u[2]), -scale_factor * cos(u[2]), 0)
        set_points_as_corners!(m, [pivote, p1, p2])
        move_to!(bob1, p1); move_to!(bob2, p2)
        p2_ref[] = p2
        push!(rastro, p2)
        length(rastro) > 260 && popfirst!(rastro)
        length(rastro) > 1 && set_points_as_corners!(estela, copy(rastro))
        nothing
    end)
    add_updater!(foco, (m, dt) -> (pendulo_on[] && move_to!(m, p2_ref[]); nothing))

    # curve_at de Fourier vs estrella fantasma
    target = _estrella()
    perdida(p) = sum(abs2, _fourier(p) .- target) / SF
    params = zeros(2 * (2KF + 1)); params[KF+2] = 1.0
    curve_at = VMobject(); set_stroke!(curve_at; color = "#FFD25E", width = 4.0)
    fantasma = VMobject()
    set_points_as_corners!(fantasma, [Point3f(target[j, 1], target[j, 2], 0) for j in [1:SF; 1]])
    shift!(fantasma, 0.6 * DOWN); set_stroke!(fantasma; color = "#3A4558", width = 2.0, opacity = 0.0)
    gradiente_on = Ref(false)
    add_updater!(curve_at, (m, dt) -> begin
        gradiente_on[] || return
        for _ in 1:2
            params .-= 0.33 .* ForwardDiff.gradient(perdida, params)
        end
        pts = _fourier(params)
        set_points_as_corners!(m, [Point3f(pts[j, 1], pts[j, 2] - 0.6, 0) for j in [1:SF; 1]])
        nothing
    end)

    title = Tex(raw"\frac{dx}{dt} = F(x)"; color = "#FFFFFF", size = 1.05)
    move_to!(title, 3.0 * UP)
    hacer_titulo(s, color) = (t = Tex(s; color, size = 1.05); move_to!(t, 3.0 * UP); t)

    blur_adj = Blur(0.001)

    use_composition!(scene, Composition(
        Layer(background),
        crop(rejilla; inside = foco, feather = 0.3),
        Layer(lines; effects = [Dof(get_focal_distance(scene.camera) - 1.5; aperture = 0.04)]),
        Layer(estela; blend = :add, effects = [Bloom(threshold = 0.25, intensity = 1.5, sigma = 0.16)]),
        Layer(varilla, bob1, bob2),
        Layer(fantasma, curve_at; blend = :add,
              effects = [Bloom(threshold = 0.3, intensity = 1.2, sigma = 0.12)]),
        Layer(; effects = [blur_adj]),
        Layer(title),
    ))

    aparecer(m, op) = Transform(m, (c = copy(m); set_stroke!(c; opacity = op); c))
    aparecer_fill(m, op) = Transform(m, (c = copy(m); set_fill!(c; opacity = op); c))

    # ── acto 1 · el campo (0–9 s) ────────────────────────────────────────
    play!(scene, AnimationGroup(FadeIn(title; shift = 0.3 * DOWN),
                              LaggedStart([ShowCreation(l) for l in lines.submobjects]...;
                                          lag_ratio = 0.12)); run_time = 4.0)
    wait!(scene, 2.4)

    # ── acto 2 · el caos (9–36 s) ────────────────────────────────────────
    play!(scene, AnimationGroup(Transform(title, hacer_titulo(raw"E = T + V", "#C8D2DC")),
                              aparecer(lines, 0.16),
                              aparecer_fill(bob1, 1.0), aparecer_fill(bob2, 1.0));
          run_time = 1.4)
    pendulo_on[] = true
    wait!(scene, 9.0)
    play!(scene, Transform(title, hacer_titulo(raw"\dot\theta_1, \; \dot\theta_2", "#FFD25E"));
          run_time = 1.0)
    wait!(scene, 18.0)

    # ── transición soñada: blur animado (36–41 s) ────────────────────────
    subiendo = Ref(true)
    reloj_blur = VGroup()
    add_updater!(reloj_blur, (m, dt) -> begin
        blur_adj.sigma = clamp(blur_adj.sigma + (subiendo[] ? 0.09 : -0.11) * dt, 0.001, 0.22)
        nothing
    end)
    add!(scene, reloj_blur)
    pendulo_on[] = false                # congelar: si no, el updater re-estampa
    move_to!(foco, Point3f(99, 99, 0))  # el estilo default y el fade no se ve
    play!(scene, AnimationGroup(FadeOut(varilla), FadeOut(bob1), FadeOut(bob2),
                              FadeOut(estela), aparecer(lines, 0.0)); run_time = 2.2)
    subiendo[] = false
    wait!(scene, 1.6)

    # ── acto 3 · el gradiente (41–58 s) ──────────────────────────────────
    play!(scene, AnimationGroup(Transform(title, hacer_titulo(raw"\theta \leftarrow \theta - \eta \nabla L", "#FFD25E")),
                              aparecer(fantasma, 0.8)); run_time = 1.4)
    gradiente_on[] = true
    wait!(scene, 14.0)
    gradiente_on[] = false
    play!(scene, Transform(title, hacer_titulo(raw"L(\theta) \to 0", "#7FDD58")); run_time = 1.0)
    wait!(scene, 2.6)

    # ── coda (58–62 s) ───────────────────────────────────────────────────
    play!(scene, AnimationGroup(FadeOut(curve_at), FadeOut(fantasma), FadeOut(title));
          run_time = 1.6)
    wait!(scene, 1.4)
end

if abspath(PROGRAM_FILE) == @__FILE__
    path = joinpath(@__DIR__, "output", "03_field_and_chaos.mp4")
    mkpath(dirname(path))
    # el render FINAL, por segmentos en 4 procesos
    render_parallel(@__FILE__, path; n = 4, frames_total = 1848, fps = 30,
                    resolution = (1280, 720))
    println("→ ", path)
end
