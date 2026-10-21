# Course 1 · 2.5 — Importing images
#
#     ImageMobject(path; height = 4.0, opacity = 1.0)
#     ImageMobject(matrix_of_colours; height = 4.0)      ← no file needed
#     TexturedSurface(surface, image; opacity = 1.0)     ← the 3D form
#
# PNG is decoded natively; everything else (jpg, bmp, tiff, webp) goes through
# ffmpeg's image demuxer, which is already a dependency.
#
# This lesson COMPUTES its image instead of loading one, for two reasons. It
# is the more interesting half of the API — an image made in Julia never
# touches the disk — and the lesson needs no image file next to it.
#
# The four corner points go through the ordinary transform machinery, so
# `shift!`, `rotate!`, `scale!`, `move_to!` and the interpolation contract all
# work — and the relative layout does too: `next_to!`,
# `to_edge!`, `align_to!` and friends read `get_bounding_box_point`, which
# ImageMobject and TexturedSurface now answer like Surface does. One thing
# still does NOT, and it is better to know it now:
#
#   · `set_fill!`/`set_stroke!` — an ImageMobject has pixels, not style rows.
#     Its one dial is `set_opacity!`.
#
#   julia --project=. examples/tutorial/c1_02_config_and_assets/05_image_import.jl

using Janim
using Colors: RGBA

const PREVIEW_T = 1.8

"A 128×128 complex-plane picture: |z| in the hue, arg(z) in the brightness."
function domain_colouring(n = 128)
    img = Matrix{RGBA{Float64}}(undef, n, n)
    for j in 1:n, i in 1:n
        z = complex((i - n / 2) / (n / 4), (n / 2 - j) / (n / 4))
        w = z^3 - 1                       # the function being coloured
        h = (angle(w) + pi) / (2pi)       # hue from the argument
        v = 0.35 + 0.65 * (1 - exp(-abs(w) / 3))
        # a cheap HSV→RGB, so the lesson needs no extra dependency
        k = h * 6
        c, x = v, v * (1 - abs(mod(k, 2) - 1))
        rgb = k < 1 ? (c, x, 0.0) : k < 2 ? (x, c, 0.0) : k < 3 ? (0.0, c, x) :
              k < 4 ? (0.0, x, c) : k < 5 ? (x, 0.0, c) : (c, 0.0, x)
        img[j, i] = RGBA(rgb..., 1.0)
    end
    return img
end

function construct(scene)
    title = TextMobject("an image computed in Julia needs no file";
                        size = 0.48, color = GREY_A)
    to_edge!(title, UP; buff = 0.4)
    add!(scene, title)

    picture = ImageMobject(domain_colouring(); height = 4.0)
    move_to!(picture, 3.2 * LEFT + 0.3 * DOWN)
    println("pixels: ", pixel_size(picture), " · height in scene units: ",
            round(get_height(picture); digits = 2))

    # `next_to!` against an image — the same call you would
    # write against any VMobject.
    caption = TextMobject("z^3 - 1"; size = 0.42, color = GREY_B)
    next_to!(caption, picture, DOWN; buff = 0.35)

    # The 3D form: the same raster sampled over a uv mesh.
    globe = TexturedSurface(Sphere(; radius = 1.5, resolution = (81, 41)),
                            domain_colouring(64))
    move_to!(globe, Point3f(3.4, 0.2, 0))
    apply_depth_test!(globe)

    add!(scene, picture, caption, globe)
    play!(scene, FadeIn(caption); run_time = 0.5)

    # ImageMobject is interpolable, so `animate` drives it like anything else.
    play!(scene, animate(picture, (rotate!, TAU / 16), (scale!, 0.85));
          run_time = 1.2)
    # …but the raster has one dial of its own:
    play!(scene, UpdateFromAlphaFunc(picture, (m, a) -> set_opacity!(m, 1 - 0.6a));
          run_time = 0.8)
    wait!(scene, 0.4)
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "05_image_import.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
