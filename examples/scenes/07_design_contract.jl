# Example 07 · DESIGN: the interpolation contract.
#
#   julia --project=. examples/scenes/07_design_contract.jl
#
# In Manim, `Transform` knows about VMobject. Animating anything else means
# either making it a VMobject or writing a new animation class.
#
# Here, `Transform` speaks only a contract of four functions. This file
# defines a type the engine has never heard of — a thermometer — IN USER
# CODE, gives it those four lines, and animates it with the ordinary
# `animate`. Not one line of `animation/` needs to know it exists.
#
# That is the whole point of the contract, and this is what it looks like from outside.

using Janim

const RESOLUTION = (1280, 720)

# ═══════════════════════════════════════════════════════════════════════
# A type the engine does not know about
# ═══════════════════════════════════════════════════════════════════════

mutable struct Termometro <: Janim.Mobject
    grupo::VGroup
    tubo::VMobject
    mercurio::VMobject
    nivel::Float64          # 0..1
    alto::Float64
end

function Termometro(; nivel = 0.2, alto = 3.0, ancho = 0.45)
    tubo = Rectangle(width = ancho, height = alto)
    set_stroke!(tubo; color = GREY_A, width = 3.0)
    set_fill!(tubo; opacity = 0)
    merc = Rectangle(width = ancho * 0.6, height = 0.01)
    set_fill!(merc; color = RED, opacity = 1.0)
    set_stroke!(merc; opacity = 0)
    t = Termometro(VGroup(), tubo, merc, Float64(nivel), Float64(alto))
    add!(t.grupo, tubo, merc)
    _redibujar!(t)
    return t
end

"Rebuild the mercury column for the current level, anchored at the bottom."
function _redibujar!(t::Termometro)
    h = max(1e-3, t.nivel * t.alto)
    base = get_bounding_box_point(t.tubo, DOWN)
    fresco = Rectangle(width = get_width(t.tubo) * 0.6, height = h)
    set_fill!(fresco; color = RED, opacity = 1.0)
    set_stroke!(fresco; opacity = 0)
    move_to!(fresco, base + Point3f(0, h / 2, 0))
    become!(t.mercurio, fresco)
    return t
end

set_level!(t::Termometro, x::Real) = (t.nivel = clamp(Float64(x), 0, 1); _redibujar!(t))
get_level(t::Termometro) = t.nivel

# ── LAS CUATRO LÍNEAS DEL CONTRATO ─────────────────────────────────────
# Con esto, `animate`, `Transform`, `AnimationGroup` y cualquier rate_func
# funcionan sobre este tipo. No hay que tocar el motor.

Janim.is_interpolable(::Termometro) = true

# OJO — `copy` tiene que copiar TODO el estado, y la posición es estado.
# Un `copy` que devuelve un termómetro nuevo en el origen hace que Transform
# interpole hacia el origen y el objeto se vaya al centro de la pantalla a
# mitad de animación. Es el error más fácil de cometer al implementar el
# contrato, y no lo dice ningún tipo: lo dice el render.
function Base.copy(t::Termometro)
    c = Termometro(; nivel = t.nivel, alto = t.alto, ancho = get_width(t.tubo))
    shift!(c, get_center(t.grupo) - get_center(c.grupo))
    return c
end

Janim.interpolate!(d::Termometro, a::Termometro, b::Termometro, α::Real) =
    set_level!(d, a.nivel + α * (b.nivel - a.nivel))
Janim.become!(d::Termometro, s::Termometro) = set_level!(d, s.nivel)

# ── y lo mínimo para VIVIR en una escena (dibujarse, moverse) ──────────
# La familia se incluye A SÍ MISMA: `Transform` aparea familias, y si el
# termómetro no está en la suya, su `interpolate!` no se llama nunca — solo
# se interpolarían sus hijos, como VMobjects cualesquiera.
Janim.get_family(t::Termometro) =
    vcat(Janim.Mobject[t], Janim.get_family(t.grupo))
Janim.has_points(::Termometro) = false      # dibuja a través de sus hijos
Janim.get_num_points(::Termometro) = 0
Janim.get_bounding_box(t::Termometro) = Janim.get_bounding_box(t.grupo)
Janim.get_bounding_box_point(t::Termometro, d) = Janim.get_bounding_box_point(t.grupo, d)
Janim.apply_points_function!(f, t::Termometro; kw...) =
    (Janim.apply_points_function!(f, t.grupo; kw...); t)
Janim.shift!(t::Termometro, d) = (shift!(t.grupo, d); t)

# ═══════════════════════════════════════════════════════════════════════

function construct(scene)
    title = TextMobject("El contrato de interpolación: 4 líneas y ya se anima";
                        size = 0.48, color = GREY_A)
    to_edge!(title, UP; buff = 0.3)

    term = Termometro(; nivel = 0.15)
    shift!(term, 3.6 * LEFT + 0.3 * DOWN)

    lectura = DecimalNumber(15.0; num_decimal_places = 0, size = 0.9, color = RED)
    add_updater!(lectura, d -> set_number!(d, 100 * get_level(term)))
    move_to!(lectura.group, Point3f(-2.2, -0.9, 0))

    # un VMobject normal, animado EN EL MISMO AnimationGroup que el
    # termómetro: para el motor los dos son "algo que cumple el contrato"
    bola = Circle(radius = 0.55, fill_opacity = 1.0)
    set_fill!(bola; color = BLUE)
    set_stroke!(bola; opacity = 0)
    move_to!(bola, Point3f(1.6, -0.4, 0))

    codigo = TextMobject("is_interpolable · copy · interpolate! · become!";
                         size = 0.34, color = GREY_B)
    move_to!(codigo, Point3f(0.0, -2.9, 0))
    nota = TextMobject("Transform no menciona este tipo en ninguna parte";
                       size = 0.3, color = GREY_C)
    next_to!(nota, codigo, DOWN; buff = 0.25)

    add!(scene, title, term, lectura, bola, codigo, nota)
    wait!(scene, 0.4)

    play!(scene, AnimationGroup(animate(term, (set_level!, 0.85)),
                               animate(bola, (shift!, 3.0 * RIGHT), (scale!, 1.5)));
          run_time = 1.8)
    wait!(scene, 0.5)
    # the rate_func belongs to the ANIMATION, not to play! — same as in Manim
    play!(scene, animate(term, (set_level!, 0.35); rate_func = there_and_back);
          run_time = 1.2)
    wait!(scene, 0.5)
end

if abspath(PROGRAM_FILE) == @__FILE__
    path = joinpath(@__DIR__, "output", "07_design_contract.mp4")
    mkpath(dirname(path))
    Scene(construct; output = path, fps = 30, resolution = RESOLUTION)
    println("written ", path)
end
