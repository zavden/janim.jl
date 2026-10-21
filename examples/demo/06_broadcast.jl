# Demo 06 · LA EMISIÓN — glitch, tubo de rayos catódicos y cinta VHS sobre
# una fórmula que sigue morfando debajo.
#
# Los efectos de editor (`Glitch`, `CRT`, `VHS`, `ColorAdjust`) van en
# la lista `effects` de UNA capa, y cada uno es un struct mutable: animarlos
# es escribir en sus campos desde un updater. Tres propiedades que hacen que
# esto sea usable y no un truco:
#
#   · el CERO de cada dial es un no-op EXACTO: la pasada se salta, y la
#     imagen vuelve limpia byte a byte cuando la interferencia termina;
#   · la aleatoriedad es un hash de (píxel, frame, semilla), nunca `rand()`:
#     el mismo glitch sale en el mismo frame en cada render (A2), y se puede
#     rebobinar hasta él;
#   · `CRT.roll` no tiene reloj interno: la televisión pierde el sincronismo
#     porque TÚ escribes el desplazamiento cada frame.
#
# Manim no tiene post-proceso de ningún tipo — ni siquiera un blur.
#
#   julia --project=. examples/demo/06_broadcast.jl

using Janim

function construct(scene)
  # ── el monitor: barras de color, la fórmula y los rótulos del canal ───
  bars = VGroup()
  for (k, c) in enumerate(("#FFFFFF", "#FFFF00", "#00FFFF", "#00FF00", "#FF00FF", "#FF0000", "#0000FF"))
    r = Rectangle(width = 1.6, height = 0.8)
    set_fill!(r; color = c, opacity = 1.0)
    set_stroke!(r; opacity = 0)
    move_to!(r, Point3f(-4.8 + 1.6(k - 1), -2.95, 0))
    add!(bars, r)
  end

  make_formula(s, color) = begin
    t = Tex(s; color, size = 1.25)
    get_width(t) > 10.5 && set_width!(t, 10.5)
    move_to!(t, 0.35 * UP)
    t
  end
  formula = make_formula(raw"\nabla \times B = \mu_0 J + \mu_0 \varepsilon_0 \, \partial_t E", WHITE)

  channel = TextMobject("JANIM · CHANNEL 7"; size = 0.36, color = "#7FDD58")
  to_corner!(channel, UL; buff = 0.5)
  make_status(s, color) = begin
    t = TextMobject(s; size = 0.36, color)
    to_corner!(t, UR; buff = 0.5)
    t
  end
  status = make_status("SIGNAL", GREY_B)

  # ── los efectos, todos apagados: cero = pasada saltada ────────────────
  glitch = Glitch(; intensity = 0.0, seed = 7, rate = 2, slices = 18)
  tube = CRT(;
    intensity = 0.0,
    scanlines = 220,
    scan_depth = 0.4,
    curvature = 0.12,
    vignette = 0.4,
  )
  tape = VHS(; intensity = 0.0, seed = 3, rate = 2)
  grade = ColorAdjust()

  use_composition!(
    scene,
    Composition(
      Layer(bars, formula, channel, status; effects = [glitch, tube, tape, grade]);
      background = (0.02f0, 0.02f0, 0.03f0, 1f0),
    ),
  )

  # ── el guion de la interferencia, como función de scene.t ─────────────
  ramp(t, t0, t1) = clamp((t - t0) / (t1 - t0), 0.0, 1.0)
  clock = VGroup()
  add_updater!(clock, (m, dt) -> begin
    dt > 0 || return
    t = scene.t

    # 1 · ráfagas (3–7 s): un pico, no una subida, y vuelta al cero exacto.
    # Irregular pero determinista: el hash del propio motor sobre el frame.
    if 3.0 <= t < 7.0
      window = scene.frames ÷ 6
      fire = Janim._noise_hash(1, 1, window, 4) > 0.5
      phase = (scene.frames % 6) / 6
      glitch.intensity = fire ? 0.95 * (1 - phase)^2 : 0.0
    else
      glitch.intensity = 0.0
    end

    # 2 · el tubo (7–12.5 s): se enciende en medio segundo, pierde el
    # sincronismo entre 8 y 11 s y se recupera solo.
    tube.intensity = ramp(t, 7.0, 7.5) * (1 - ramp(t, 12.5, 13.0))
    if 8.0 <= t < 11.0
      speed = 0.2 + 0.9 * max(0.0, sin(TAU * (t - 8.0) / 3.0))
      tube.roll = mod(tube.roll + speed * dt, 1.0)
    elseif tube.roll > 0.0
      # de vuelta al cuadro: por el lado más corto, y 1.0 ≡ 0.0
      tube.roll = tube.roll < 0.5 ? max(tube.roll - 1.2dt, 0.0) : min(tube.roll + 1.2dt, 1.0)
      tube.roll >= 1.0 && (tube.roll = 0.0)
    end

    # 3 · la cinta (13–17 s), con el color subido de saturación y contraste
    tape.intensity = 0.8 * ramp(t, 13.0, 13.4) * (1 - ramp(t, 17.0, 17.6))
    grade.saturation = 1.0 + 0.35 * tape.intensity / 0.8
    grade.contrast = 1.0 + 0.15 * tape.intensity / 0.8
    nothing
  end)
  add!(scene, clock)

  # ── la fórmula sigue su curso debajo de todo ──────────────────────────
  play!(scene, Write(formula); run_time = 2.0)
  wait!(scene, 1.2)
  play!(scene, Transform(status, make_status("INTERFERENCE", "#FF3D8B")); run_time = 0.4)
  wait!(scene, 1.4)
  play!(scene, Transform(formula, make_formula(raw"\nabla \cdot B = 0", "#58C4DD")); run_time = 1.2)
  wait!(scene, 1.0)
  play!(scene, Transform(status, make_status("NO SYNC", "#FFD25E")); run_time = 0.4)
  wait!(scene, 2.2)
  play!(
    scene,
    Transform(formula, make_formula(raw"\nabla \times E = - \partial_t B", "#FFD25E"));
    run_time = 1.2,
  )
  wait!(scene, 2.0)
  play!(scene, Transform(status, make_status("TAPE", "#F0A045")); run_time = 0.4)
  wait!(scene, 1.2)
  play!(
    scene,
    Transform(formula, make_formula(raw"\nabla \cdot E = \rho / \varepsilon_0", "#7FDD58"));
    run_time = 1.2,
  )
  wait!(scene, 2.0)
  play!(scene, Transform(status, make_status("SIGNAL", GREY_B)); run_time = 0.4)
  wait!(scene, 1.6)
end

if abspath(PROGRAM_FILE) == @__FILE__
  Scene(
    construct;
    output = joinpath(@__DIR__, "06_broadcast.mp4"),
    fps = 30,
    resolution = (1280, 720),
    encoder_threads = 1,      # ruido de alta frecuencia: mp4 reproducible byte a byte
  )
end
