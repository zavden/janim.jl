# Course 1 · 2.1 — Configuration: there is no config file, and that is the design
#
# Manim has `manim.cfg`, a global `config` object and `with tempconfig({…})`.
# Janim has none of them, on purpose. The precedence rule is one line:
#
#     CLI flag  >  the Scene kwargs in your script  >  engine defaults
#
# and it is resolved by BUILDING the scene with those kwargs. There is no
# ENGINE file to find, no environment to leak between runs, nothing to un-set
# — and no scene whose output depends on a config file you cannot see.
#
# (`janim.cfg` exists — but read what it is before calling it a config
# file: a CLIENT-side shortener of CLI flags, one per line, that the bash CLI
# prepends to your argv and ANNOUNCES on every use. The engine never reads
# it, your explicit flags always win, and `--only-cli` ignores it entirely.
# `--out_dir DIR` works in the same spirit: the CLI joins the path and
# mkdir -p's, and the engine still receives one plain `-o`.
# The rule above is untouched: nothing global ever reaches the Scene.)
#
# What you use instead is Julia: a `NamedTuple` of settings, splatted into
# `Scene`. That is lesson 2.3. This one is about the defaults themselves and
# about the one knob that IS global — and why.
#
#   julia --project=. examples/tutorial/c1_02_config_and_assets/01_configuration.jl

using Janim

const PREVIEW_T = 1.0

# The engine's defaults, spelled out (from src/scene/scene.jl):
#
#   fps = 60 · resolution = (1920, 1080) · crf = 23 · preset = "medium"
#   preview = false · output = nothing (headless) · motion_blur = 1 (off)
#
# The nominal FRAME, which is what `to_edge!` and FRAME_X_RADIUS talk about,
# is 8 scene units tall and 8·16/9 wide REGARDLESS of the resolution. Pixels
# are a rendering decision; scene units are the geometry.

function construct(scene)
    title = TextMobject("no config file: kwargs all the way down";
                        size = 0.5, color = GREY_A)
    to_edge!(title, UP; buff = 0.4)

    # `scene.camera` knows the pixels; the constants know the scene units.
    lines = [
        "resolution  $(scene.camera.width)×$(scene.camera.height) px",
        "fps         $(scene.fps)",
        "frame       $(round(FRAME_WIDTH; digits = 2)) × $(FRAME_HEIGHT) scene units",
        "aspect      $(round(scene.camera.width / scene.camera.height; digits = 3))",
    ]
    rows = VGroup()
    for s in lines
        add!(rows, TextMobject(s; size = 0.4, color = GREY_B))
    end
    arrange!(rows, DOWN; buff = 0.28, aligned_edge = LEFT)

    # The nominal frame drawn as a rectangle: at any resolution it is the
    # same 14.22 × 8 box, which is why `to_edge!` lands in the same place.
    border = Rectangle(width = FRAME_WIDTH - 0.2, height = FRAME_HEIGHT - 0.2)
    set_stroke!(border; color = "#37506B", width = 2.0)
    set_fill!(border; opacity = 0)

    corner = Dot(Point3f(FRAME_X_RADIUS - 0.1, FRAME_Y_RADIUS - 0.1, 0); radius = 0.09)
    set_fill!(corner; color = YELLOW)

    add!(scene, border, corner, title, rows)
    play!(scene, FadeIn(rows; shift = 0.3 * UP); run_time = 0.8)
    wait!(scene, 0.8)

    # The ONE global switch, and it is not styling: `strict_gl` pins the
    # driver's shader variant so byte-for-byte reproducibility survives
    # high-frequency content (noise effects, fine textures). It is global
    # because the DRIVER is, and it has to be set before the driver loads —
    # which is why `bin/janim` exports it for you and a bare `julia` cannot.
    # Ask with `strict_gl_status()`; opt out with JANIM_STRICT_GL=0.
    println("frame diagonal = ",
            round(hypot(FRAME_WIDTH, FRAME_HEIGHT); digits = 3), " scene units")
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "01_configuration.mp4")
    mkpath(dirname(out))
    # These kwargs ARE the configuration. A different film, a different call.
    Scene(construct; output = out, fps = 30, resolution = (854, 480),
          crf = 23, preset = "medium")
    println("→ ", out)
end
