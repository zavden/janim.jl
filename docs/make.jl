# The documentation site (Documenter.jl).
#
#   julia --project=docs -e 'import Pkg; Pkg.develop(path="."); Pkg.instantiate()'
#   julia --project=docs docs/make.jl
#
# Output: docs/build/ (static HTML; pretty URLs only when the CI variable is true).
#
# The manual is prose with `@ref` links; the reference pages are `@autodocs`
# over a PARTITION of src/, so every exported docstring is rendered exactly
# once and a new file with no page entry shows up as a checkdocs failure
# rather than disappearing quietly.

using Documenter
using Janim

makedocs(;
    modules = [Janim],
    sitename = "Janim.jl",
    authors = "Alexander Vazquez",
    remotes = nothing,      # no remote configured: no source links
    format = Documenter.HTML(;
        prettyurls = get(ENV, "CI", "false") == "true",
        edit_link = nothing,
        repolink = nothing,     # no remote configured: no repository link
        footer = "Janim.jl — a mathematical animation engine in Julia.",
        collapselevel = 1,
    ),
    pages = [
        "Home" => "index.md",
        "Manual" => [
            "Getting started"       => "getting_started.md",
            "Scenes"                => "scenes.md",
            "Mobjects"              => "mobjects.md",
            "The shape zoo"         => "shapes.md",
            "Layout"                => "layout.md",
            "Animations"            => "animations.md",
            "Rate functions"        => "rate_functions.md",
            "Updaters and trackers" => "updaters.md",
            "Text and formulas"     => "text.md",
            "Coordinate systems"    => "coordinates.md",
            "3D and the camera"     => "three_d.md",
            "The compositor"        => "compositor.md",
            "Rendering and output"  => "rendering.md",
            "The CLI"               => "cli.md",
            "Interactive session"   => "interactive.md",
        ],
        "Coming from Manim"     => "from_manim.md",
        "Performance"           => "performance.md",
        "Extending the engine"  => "extending.md",
        "Reference" => [
            "Mobjects"      => "api_mobjects.md",
            "Transforms and layout" => "api_layout.md",
            "Content"       => "api_content.md",
            "Palette"       => "api_palette.md",
            "Animation"     => "api_animation.md",
            "Coordinates"   => "api_coordinates.md",
            "Text"          => "api_text.md",
            "Scene"         => "api_scene.md",
            "Backend"       => "api_backend.md",
        ],
    ],
    checkdocs = :exports,   # every exported docstring must reach a page
    warnonly = false,       # …and a broken @ref or a stranded page FAILS the build
)
