# Course 2 · 4.2 — Animation by gradient descent
#
# The second only-in-Julia trick: `ForwardDiff.gradient` differentiates
# ORDINARY Julia code, so an updater can descend a loss instead of following a
# script. The animation is not "a shape moving towards another shape" — it is
# an optimiser running in front of the viewer, and what you see is where the
# maths goes.
#
# The rules are the updater rules again: the parameters live OUTSIDE (they are
# state), the updater takes the steps, and the mobject is rebuilt from the
# parameters every frame — so it must be born with its final style.
#
# Here the curve is a truncated Fourier series
#
#     z(s) = Σ_{k=-K}^{K} c_k · e^{2πiks}
#
# and the loss is the mean squared distance to a target polygon, sampled at
# the same parameter values. The gradient is taken through the WHOLE thing,
# series evaluation included, with no derivative written by hand.
#
#   julia --project=. examples/tutorial/c2_04_simulations/02_gradient_descent.jl

using Janim
using ForwardDiff

const K = 10          # harmonics kept, each way
const S = 140         # samples along the curve
const M = 2K + 1      # coefficients

"A five-pointed star, sampled by arc length so the loss is not biased."
function star_target()
    verts = [(r * cos(θ), r * sin(θ))
             for (r, θ) in [((i % 2 == 1 ? 1.9 : 0.8), PI / 2 + (i - 1) * TAU / 10)
                            for i in 1:10]]
    sides = [hypot((verts[mod1(i + 1, 10)] .- verts[i])...) for i in 1:10]
    acc = cumsum([0.0; sides])
    out = zeros(S, 2)
    for (j, s) in enumerate(range(0, sum(sides); length = S + 1)[1:S])
        i = min(something(findlast(<=(s + 1e-12), acc), 1), 10)
        α = (s - acc[i]) / sides[i]
        out[j, :] .= verts[i] .+ α .* (verts[mod1(i + 1, 10)] .- verts[i])
    end
    return out
end

"The curve the parameters describe. Generic in `eltype` so ForwardDiff can dual it."
function fourier(params)
    T = eltype(params)
    pts = Matrix{T}(undef, S, 2)
    for (j, s) in enumerate(range(0, 1; length = S + 1)[1:S])
        x = zero(T); y = zero(T)
        for (i, k) in enumerate(-K:K)
            c, sn = cos(2π * k * s), sin(2π * k * s)
            x += params[i] * c - params[M+i] * sn
            y += params[i] * sn + params[M+i] * c
        end
        pts[j, 1] = x; pts[j, 2] = y
    end
    return pts
end

const PREVIEW_T = 4.0

function construct(scene)
    title = TextMobject("the shape is not scripted: it is descending a loss";
                        size = 0.42, color = GREY_A)
    to_edge!(title, UP; buff = 0.3)
    add!(scene, title)

    target = star_target()
    loss(p) = sum(abs2, fourier(p) .- target) / S

    ghost = VMobject()
    set_points_as_corners!(ghost, [Point3f(target[j, 1], target[j, 2], 0)
                                   for j in [1:S; 1]])
    set_stroke!(ghost; color = "#3A4558", width = 2.0)
    add!(scene, ghost)

    params = zeros(2M); params[K+2] = 1.0        # start: the unit circle
    curve = VMobject()
    set_stroke!(curve; color = "#FFD25E", width = 4.0)   # final style at birth
    running = Ref(false)

    add_updater!(curve, function (m, dt)
        if running[] && dt > 0
            for _ in 1:2                          # two steps per frame
                params .-= 0.35 .* ForwardDiff.gradient(loss, params)
            end
        end
        pts = fourier(params)
        set_points_as_corners!(m, [Point3f(pts[j, 1], pts[j, 2], 0) for j in [1:S; 1]])
        nothing
    end)
    add!(scene, curve)

    readout = DecimalNumber(loss(params); num_decimal_places = 5, size = 0.5,
                            color = "#FFD25E")
    move_to!(readout.group, Point3f(4.6, 2.2, 0))
    add_updater!(readout, d -> set_number!(d, loss(params)))
    caption = TextMobject("loss"; size = 0.34, color = GREY_C)
    move_to!(caption, Point3f(4.6, 2.7, 0))
    add!(scene, readout, caption)

    wait!(scene, 0.6)
    running[] = true
    wait!(scene, 6.0)
    running[] = false
    println("final loss: ", round(loss(params); digits = 6))
    wait!(scene, 0.6)
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__),
                   "02_gradient_descent.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
