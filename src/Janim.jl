"""
Janim.jl — a mathematical animation engine in Julia.

Manim's narrated API (`Circle`, `Transform`, `play!`) on top of an engine
written from scratch: a deterministic WebGPU renderer (same code → same
bytes, in RADV and in lavapipe alike), a layer compositor with masks and
effects, text and math without LaTeX, 3D with a quaternion camera, SciML
integrators inside updaters, a render farm of processes and a TCP daemon for
agents.

The backend seam is a folder convention: everything that speaks the
graphics API — the `wgpu…(` calls, the `WGPU…` constants, WGSL — lives under
`src/backend/wgpu/`, and the ENGINE speaks only in our own types. "The
engine" is `core/`, `animation/`, `scene/` and `text/`, and for those four
the rule is absolute. The window system is a seam of
its own: GLFW's library is spoken through raw ccalls in `backend/glfw.jl`
and GLFW.jl in `backend/window.jl`, and nowhere else but ONE DECLARED
EXCEPTION, outside the engine and on purpose:

  · `interactive/live.jl` — the preview's input layer (GLFW callbacks and key
    codes). Window-system events ARE the window system's vocabulary;
    wrapping them in an interface of our own would be ceremony until a second
    window system exists to justify it. Supporting another window system
    means rewriting this file.

The seam has a clasp in time as well: GLFW.jl loads at the FIRST window,
never at `using Janim`, and a render to a file opens no window at all: a
machine with no display imports, and renders through the CPU adapter
(lavapipe).
"""
module Janim

# geometric core — pure geometry, family tree, transforms, bbox
include("core/constants.jl")
include("core/colorspace.jl")       # the exact IEC sRGB transfer pair
include("core/palette.jl")          # both engines' palettes, GL where they differ
include("core/palette_catalogs.jl") # GENERATED: ManimCE + CE's six catalogues
include("core/algebra.jl")
include("core/mobject.jl")
include("core/interpolable.jl")  # the contract every animation hangs from
include("core/bbox.jl")
include("core/transforms.jl")
include("core/paths.jl")
include("core/shapes.jl")
include("core/functions.jl")  # ParametricCurve / FunctionGraph
include("core/implicit.jl")   # ImplicitFunction (ported from isosurfaces)
include("core/coordinates.jl")   # Line/Arrow/Dot and their geometry
include("core/layout.jl")        # next_to!/arrange!/to_edge!/match_*
include("core/rates.jl")
include("core/trackers.jl")   # ValueTracker / DecimalNumber / always_redraw
include("core/axes.jl")       # NumberLine / Axes / NumberPlane + c2p
include("core/annotations.jl")# Brace / DashedLine / BackgroundRectangle …
include("core/tables.jl")     # MatrixMobject / Table over the grid layout
include("core/colors.jl")     # colour by gradient + colour maps
include("core/alignment.jl")
include("core/states.jl")     # save_state!/generate_target!
include("core/decor.jl")      # composed text, Cutout, ornaments
include("core/surface.jl")       # uv meshes (Sphere, Torus, …)
include("core/image.jl")         # ImageMobject / TexturedSurface
include("core/model.jl")         # ThreeDModel (OBJ → Group of meshes)
include("core/dots.jl")          # DotCloud / TrueDot / GlowDots
include("core/fields.jl")        # VectorField / StreamLines
include("core/wrappers.jl")      # the five wrapped types, delegated ONCE

# animation — begin!/interpolate!/finish! life cycle + the timeline
include("animation/animations.jl")
include("animation/animate.jl")    # the `animate` idiom + Transform variants
include("animation/creation.jl")   # Write/DrawBorderThenFill + appearances
include("animation/matching.jl")   # TransformMatchingTex over the parts' keys
include("animation/emphasis.jl")   # Indicate/Flash/Circumscribe/FocusOn/Wiggle
include("animation/homotopy.jl")   # deforming by a function of points
include("animation/sugar.jl")      # names for animations already writable
include("animation/passing.jl")    # animations made of partial strokes
include("animation/timeline.jl")

# The renderer-independent half of the backend, in files of its own: the
# Camera and its uniforms, the compositor's types and geometry, the noise and
# the eleven effects, the CPU side every render VM is built from.
include("core/camera.jl")            # the Camera: geometry, angles, camera_uniforms
include("core/compositor_types.jl")  # Layer, Composition, Mask, the blurs, the windows' geometry
include("core/effects_types.jl")     # the noise + frame clock, the eleven effects as types
include("backend/expanded.jl")       # expanded_data, the run vocabulary, the counters
include("backend/glfw.jl")           # GLFW through raw ccalls, the lazy loading, the platform choice
include("backend/determinism.jl")    # strict_gl's names, with no knob behind them: determinism is a property
# The WebGPU backend. `bindings.jl` is GENERATED — from wgpu-native v24's
# headers — and opens the library on the FIRST call, never at import; the
# other four are the base: GPU without a window, render targets and the
# readback, the demo triangle, the mp4 pipeline.
include("backend/wgpu/bindings.jl")
include("backend/wgpu/context.jl")
include("backend/wgpu/targets.jl")
include("backend/wgpu/triangle.jl")
include("backend/wgpu/pipeline.jl")
include("backend/wgpu/uniforms.jl")    # the two uniform blocks and the mobject arena
include("backend/wgpu/pipelines.jl")   # the WGSL sources and the eleven pipelines
include("backend/wgpu/records.jl")     # per-mobject records over wgpu buffers, the render VM
include("backend/wgpu/render.jl")      # the draw loop and the frame's one pass
include("backend/wgpu/compositor.jl")  # the compositor, its effects and MSAA; effect_shader!
include("backend/wgpu/window.jl")       # the preview's window, surface and present pass
# The camera as an animatable mobject — after the backend, because a
# CameraFrame is a live view onto a Camera.
include("animation/camera_frame.jl")
include("video.jl")
include("codecs.jl")

# game loop — Scene with two sinks and the agent hooks
include("scene/progress.jl")      # the CE-style per-animation bar
include("scene/scene.jl")
include("scene/checkpoints.jl")   # named checkpoints + resume
include("scene/macros.jl")        # @scene/@play/@wait — the receiver, gone

# text and math — font outlines → quadratic VMobjects
include("text/tex_labelling.jl")   # ManimGL's string labelling (the parser)
include("text/text.jl")
# The SVG importer lives in core but is included after text/ and backend/
# because <text> uses the text pipeline and clip_layers speaks Layer/Mask
include("core/svg.jl")

# interactivity — the pure input state is static; the live window
# itself (GLFW callbacks, the playhead) is included AT RUNTIME by the lazy
# loader in backend/glfw.jl, so `using Janim` never loads GLFW.jl
include("interactive/controls.jl")
include("interactive/daemon.jl")

export demo_triangle, demo_mp4, codec_report

# ── the WebGPU backend ───────────────────────────────────────────────────────
# `backend()` says which renderer this process uses (`:wgpu`, the only one);
# the two exceptions are how wgpu's errors reach Julia; `gpu_info` is the
# driver identity; `demo_triangle_wgpu` is the demo triangle again
# (`demo_triangle` names it too); `effect_shader!` is the door for a layer
# effect's own WGSL.
export backend, gpu_info, GPUValidationError, GPUDeviceLostError, demo_triangle_wgpu,
    effect_shader!

# ── render ──────────────────────────────────────────────────────────────────
export Camera, render_mobjects, save_ppm

# ── game loop ───────────────────────────────────────────────────────────────
export Scene, render_frame, animation_map, describe, save_png, use_composition!,
    checkpoint!, render_from, checkpoint_states, checkpoint_valid,
    clear_checkpoints!

# ── real LaTeX with your own packages ───────────────────────────────────────
export TexTemplate, add_to_preamble!, add_to_document!, tex_source,
    TEX_BASE_PREAMBLE, LTex, LMathTex

# ── the scene macros: `@scene sc` once, then no receiver ────────────────────
# No @add/@remove on purpose — `add!` is also a mobject's verb, so `@add(g, c)`
# would silently mean `add!(sc, g, c)`. The reason is in scene/macros.jl.
export @scene, @play, @wait

# ── segment rendering ───────────────────────────────────────────────────────
export render_segment, render_parallel

# ── interactivity ───────────────────────────────────────────────────────────
export live, setup_live, live_step!, live_status, daemon,
    Controls, mouse_move!, mouse_drag!, scroll!, key_press!, release!,
    scale_frame!, reset_camera!, compose_camera!

# ── compositor ──────────────────────────────────────────────────────────────
export Layer, Composition, Blur, render_composition

# the linear-light borders of the sRGB transfer pair
export srgb_to_linear, linear_to_srgb

# editor effects per layer
export Glitch, CRT, VHS, ColorAdjust, Pixelate, Vignette, Grain,
    ChromaticAberration, Sharpen, Wave, EdgeDetect

# The strict-determinism switch: its names are kept with no knob behind them —
# determinism is a property of the renderer, not a mode.
# Toggle with JANIM_STRICT_GL or strict_gl!; ask with strict_gl_status.
export strict_gl, strict_gl!, strict_gl_status

# ── effects ─────────────────────────────────────────────────────────────────
export Mask, crop, BoxBlur, DirectionalBlur, RadialBlur, Bloom,
    render_frame_motion

# ── text ────────────────────────────────────────────────────────────────────
export Tex, TextMobject, config_tex!, TransformMatchingTex, TransformMatchingShapes

# ── 3D ──────────────────────────────────────────────────────────────────────
export Surface, Sphere, Torus, PlaneXY, unit_normals, SurfaceMesh,
    ImplicitFunction, ThreeDModel,
    set_shading!, apply_depth_test!, fix_in_frame!, set_color!,
    reorient!, set_euler_angles!, increment_euler_angles!, get_euler_angles,
    get_theta, get_phi, get_gamma, get_view_matrix, get_implied_camera_location,
    get_focal_distance, set_focal_distance!, get_scale, Dof

# ── public API (narrated Manim style) ───────────────────────────────────────
export Point3f,   # the engine's point type (GeometryBasics)
    Mobject, VMobject, VGroup,
    Arc, Circle, Polygon, RegularPolygon, Triangle, Rectangle, Square,
    # screen rectangles, the keyed group, the 3D group
    ScreenRectangle, FullScreenRectangle, FullScreenFadeRectangle,
    VDict, VGroup3D, PGroup,
    # shapes from a vertex list, and the polyhedra
    Polygram, RegularPolygram, ConvexHull, Polyline, CubicBezier, ArcPolygon,
    Polyhedron, Tetrahedron, Octahedron, Icosahedron, Dodecahedron,
    Cube, VCube, Square3D, Prism, VPrism, Prismify,
    # constants
    ORIGIN, UP, DOWN, LEFT, RIGHT, IN, OUT, UL, UR, DL, DR, TAU, PI, DEG, DEGREES,
    FRAME_WIDTH, FRAME_HEIGHT, FRAME_X_RADIUS, FRAME_Y_RADIUS,
    SMALL_BUFF, MED_SMALL_BUFF, MED_LARGE_BUFF, LARGE_BUFF, DEFAULT_DOT_RADIUS,
    DEFAULT_FONT_SIZE,
    DEFAULT_SMALL_DOT_RADIUS,
    # palette: ManimGL's 70 names ∪ Manim CE's 89, GL's values where they
    # differ (core/palette.jl). CE's six catalogues are submodules, not
    # exports — `Janim.XKCD.MUDDYGREEN` — and so is `Janim.ManimCE`.
    WHITE, BLACK,
    BLUE_A, BLUE_B, BLUE_C, BLUE_D, BLUE_E, BLUE,
    TEAL_A, TEAL_B, TEAL_C, TEAL_D, TEAL_E, TEAL,
    GREEN_A, GREEN_B, GREEN_C, GREEN_D, GREEN_E, GREEN,
    YELLOW_A, YELLOW_B, YELLOW_C, YELLOW_D, YELLOW_E, YELLOW,
    GOLD_A, GOLD_B, GOLD_C, GOLD_D, GOLD_E, GOLD,
    RED_A, RED_B, RED_C, RED_D, RED_E, RED,
    MAROON_A, MAROON_B, MAROON_C, MAROON_D, MAROON_E, MAROON,
    PURPLE_A, PURPLE_B, PURPLE_C, PURPLE_D, PURPLE_E, PURPLE,
    GREY_A, GREY_B, GREY_C, GREY_D, GREY_E, GREY,
    GRAY_A, GRAY_B, GRAY_C, GRAY_D, GRAY_E, GRAY,
    LIGHTER_GREY, LIGHTER_GRAY, LIGHT_GREY, LIGHT_GRAY,
    DARK_GREY, DARK_GRAY, DARKER_GREY, DARKER_GRAY,
    DARK_BLUE, PINK, LIGHT_PINK, ORANGE, GREEN_SCREEN,
    GREY_BROWN, GRAY_BROWN, DARK_BROWN, LIGHT_BROWN,
    PURE_RED, PURE_GREEN, PURE_BLUE, PURE_CYAN, PURE_MAGENTA, PURE_YELLOW,
    LOGO_WHITE, LOGO_GREEN, LOGO_BLUE, LOGO_RED, LOGO_BLACK,
    DEFAULT_VMOBJECT_STROKE_COLOR, DEFAULT_VMOBJECT_FILL_COLOR,
    DEFAULT_MOBJECT_COLOR, DEFAULT_LIGHT_COLOR,
    # points, style and family
    get_points, set_points!, append_points!, clear_points!,
    get_num_points, has_points, get_all_points, set_stroke!, set_fill!,
    set_style!, fade!, DEFAULT_STROKE_WIDTH,
    add!, remove!, get_family, tag,
    vmob,      # the base constructor IS the extension seam
    # paths
    start_new_path!, add_line_to!, add_quadratic_bezier_to!,
    set_points_as_corners!, set_anchors_and_handles!,
    make_smooth!, make_jagged!, is_smooth, set_points_smoothly!,
    smooth_quadratic_handles,
    get_subpaths, get_subpath_end_indices, get_num_curves,
    # curves
    reverse_points!, insert_n_curves!, get_subcurve, CurvesAsSubmobjects,
    get_nth_curve_points, get_anchors, get_handles, get_vertices,
    # bounding box
    get_bounding_box, get_bounding_box_point, get_center, get_center_of_mass,
    get_real_center_of_mass,
    get_left, get_right, get_top, get_bottom,
    get_x, get_y, get_z,
    get_corner, get_edge_center,
    get_width, get_height, get_depth, length_over_dim,
    # transforms
    apply_points_function!, shift!, scale!, rotate!, stretch!, flip!,
    move_to!, set_width!, set_height!, set_depth!, rescale_to_fit!,
    stretch_to_fit_width!, stretch_to_fit_height!, stretch_to_fit_depth!,
    # updaters — `Updater` itself is public: the custom-mobject
    # contract (course 2, lesson 1.3) asks for a field of this type
    Updater,
    add_updater!, remove_updater!, clear_updaters!, update!,
    suspend_updating!, resume_updating!, has_updaters, has_time_based_updaters,
    # algebra
    rotation_matrix, rotate_vector, compass_directions,
    quadratic_bezier_points_for_arc, interpolate, inverse_interpolate,
    angle_of_vector, angle_between_vectors, rotation_between_vectors

# ── cross-cutting foundations ───────────────────────────────────────────────
# the interpolation contract
export is_interpolable, align_data!, get_updaters
# Line/Arrow/Dot and their geometry
export Line, Arrow, Dot, SmallDot,
    # arrow and line variants (Vector → VectorMobject: Base)
    VectorMobject, DoubleArrow, CurvedArrow, CurvedDoubleArrow, TangentLine,
    StrokeArrow,
    get_start, get_end, get_start_and_end, get_vector, get_unit_vector,
    get_angle, get_arc_length, add_arc_to!, add_subpath!,
    set_points_by_ends!, put_start_and_end_on!,
    # a line's length and angle, the arc's centre, the one-point VMobject
    get_length, set_length!, set_angle!, append_vectorized_mobject!,
    point_at_angle, get_arc_center, get_start_angle, VectorizedPoint,
    # a point at a proportion of the path: the weighed one and the cheap one
    # the engine itself uses (MoveAlongPath rests on the second, like GL)
    point_from_proportion, quick_point_from_proportion,
    curve_and_prop_of_partial_point
# relative layout
export center!, align_on_border!, to_edge!, to_corner!, next_to!, align_to!,
    get_coord, set_coord!, set_x!, set_y!, set_z!,
    match_coord!, match_x!, match_y!, match_z!,
    match_dim_size!, match_width!, match_height!, match_depth!,
    match_color!, match_style!, get_color,
    arrange!, arrange_in_grid!, surround!, replace!,
    space_out_submobjects!
# addressing children by key
export set_key!, add_key!, get_keys, has_key, find_by_key, get_all_keys,
    get_parts_by_tex, get_part_by_tex

# coordinate objects and annotations
export NumberLine, Axes, NumberPlane, ComplexPlane, PolarPlane, ThreeDAxes,
    coords_to_point, point_to_coords, c2p, p2c, number_to_point, point_to_number,
    get_unit_size, get_tick_range, tick_range, get_origin,
    get_x_axis, get_y_axis, plot, plot!, get_area, get_graph_label,
    get_v_line, get_h_line, polar_to_point,
    # the free-standing curve, and the graph through the axes
    ParametricCurve, FunctionGraph, get_parametric_curve,
    get_tip, get_direction, get_tex, add_background_rectangle!,
    Brace, BraceLabel, BackgroundRectangle, Underline, Cross, DimensionLine,
    DashedLine, DashedVMobject, UnitInterval,
    # labels, braces between things, and the title
    AnnotationDot, LabeledDot, BraceBetweenPoints, LineBrace, BraceText,
    Label, LabeledLine, LabeledArrow, Title,
    # composed text, holes and the small ornaments
    Paragraph, BulletedList, TexText, Cutout, Checkmark, Exmark, Clock,
    VHighlight, TracingTail

# external assets
export SVGMobject, clip_layers, ImageMobject, TexturedSurface,
    set_opacity!, get_opacity, pixel_size

# particles: DotCloud and friends (ManimGL's true_dot, ported)
export DotCloud, TrueDot, GlowDot, GlowDots,
    set_radius!, set_radii!, get_radii, get_radius, scale_radii!,
    set_glow_factor!, get_glow_factor, set_colors!, make_3d!

# fields: one batched VMobject per field, RK4 + counter-hash flow
export VectorField, TimeVaryingVectorField, update_vectors!,
    StreamLines, AnimatedStreamLines, ode_solution_points

# the rest of the shape zoo
export Ellipse, AnnularSector, Sector, Annulus, ArcBetweenPoints, Elbow,
    RoundedRectangle, round_corners!, Star,
    Angle, RightAngle, angle_value, line_intersection, TracedPath,
    Cylinder, Cone, Dot3D, Line3D, Arrow3D,
    # matrices and tables
    MatrixMobject, Table, matrix_bracket, get_entries, get_rows, get_columns,
    get_brackets, get_cell, get_lines,
    # the typed constructors over Matrix and Table
    TexMatrix, MathTable, MobjectTable, IntegerTable, DecimalTable,
    # colour by gradient and draw order
    color_gradient, interpolate_color, interpolate_gradient,
    # the conversions of manimlib/utils/color.py
    color_to_rgb, color_to_rgba, rgb_to_color, rgba_to_color,
    rgb_to_hex, hex_to_rgb, color_to_hex, invert_color,
    colormap_colors, set_color_by_gradient!,
    set_fill_by_gradient!, set_stroke_by_gradient!,
    set_z_index!, get_z_index, bring_to_front!, bring_to_back!,
    add_to_back!,
    set_joint_type!, get_joint_type, JOINT_TYPES,
    # sound
    add_sound

# ── animation ───────────────────────────────────────────────────────────────
export Animation, Transform, ShowCreation, Create, FadeIn, FadeOut,
    AnimationGroup, Succession, LaggedStart,
    # deforming by a function of the points
    Homotopy, SmoothedVectorizedHomotopy, ComplexHomotopy, ApplyWave, PhaseFlow,
    ApplyPointwiseFunction, ApplyMatrix, ApplyComplexFunction,
    # photograph a mobject and animate back to it
    save_state!, restore!, get_saved_state, has_saved_state,
    generate_target!, get_target, has_target, clear_states!,
    Restore, MoveToTarget, ApplyFunction, ApplyMethod,
    # sugar (Broadcast → BroadcastRipple: Base has the module)
    FadeToColor, ScaleInPlace, FadeInFromPoint, FadeOutToPoint,
    CyclicReplace, Swap, CircleIndicate, LaggedStartMap, BroadcastRipple,
    Blink, VFadeIn, VFadeOut, VFadeInThenOut,
    ShowIncreasingSubsets, ShowSubmobjectsOneByOne, MaintainPositionRelativeTo,
    # partial strokes: the travelling window
    VShowPassingFlash, ShowPassingFlash, FlashAround, FlashUnder,
    ShowCreationThenDestruction, ShowCreationThenFadeOut, TurnInsideOut,
    AddTextLetterByLetter, TypeWithCursor,
    begin!, finish!, get_run_time, is_remover,
    # the life cycle as in ManimGL: its fourth act, your own animations
    clean_up!, AnimBase, sub_alpha, interpolate_submobject,
    turn_animation_into_updater, Wait, invisible_copy,
    Timeline, play!, wait!,
    # the `animate` idiom and the Transform variants
    animate, ReplacementTransform, TransformFromCopy, FadeTransform,
    Rotate, Rotating, MoveAlongPath,
    # emphasis
    Indicate, Flash, Circumscribe, FocusOn, Wiggle, SurroundingRectangle,
    # trackers and the numbers they drive
    ValueTracker, ComplexValueTracker, get_value, set_value!, increment_value!, Group,
    DecimalNumber, IntegerMobject, set_number!, always_redraw,
    # the camera as an animatable mobject
    CameraFrame, scale_frame!, set_frame_height!, set_frame_width!, reset_frame!,
    increment_theta!, increment_phi!, increment_gamma!,
    complex_to_R3, R3_to_complex, ParametricSurface, wait_until!, FadeTransformPieces,
    # drawing, appearing and disappearing
    DrawBorderThenFill, Write, Unwrite, Uncreate,
    GrowFromPoint, GrowFromCenter, GrowFromEdge, GrowArrow, DrawCurvedArrow,
    SpinInFromNothing, ShrinkToCenter,
    UpdateFromAlphaFunc, UpdateFromFunc,
    # rate functions
    linear, smooth, rush_into, rush_from, double_smooth, there_and_back,
    squish_rate_func,
    # the rest of the family
    bezier, slow_into, there_and_back_with_pause, running_start, overshoot,
    not_quite_there, wiggle, lingering, exponential_decay,
    ease_in_sine, ease_out_sine, ease_in_out_sine,
    ease_in_quad, ease_out_quad, ease_in_out_quad,
    ease_in_cubic, ease_out_cubic, ease_in_out_cubic,
    ease_in_quart, ease_out_quart, ease_in_out_quart,
    ease_in_quint, ease_out_quint, ease_in_out_quint,
    ease_in_expo, ease_out_expo, ease_in_out_expo,
    ease_in_circ, ease_out_circ, ease_in_out_circ,
    ease_in_back, ease_out_back, ease_in_out_back,
    ease_in_elastic, ease_out_elastic, ease_in_out_elastic,
    ease_in_bounce, ease_out_bounce, ease_in_out_bounce,
    # point surgery
    align_points!, interpolate!, pointwise_become_partial!, become!,
    match_points!, integer_interpolate

# Precompilation workload: exercise the engine at precompile time so the
# user's first render does not pay for JIT. The GPU stays out on purpose:
# precompiling must not require a display (and its first-use cost is the
# driver's, not the compiler's).
#
# Video is out of the workload too, and it has to be: calling `demo_mp4` here
# would `Base.include` video_impl.jl at precompile time, bake VideoIO's types
# into Janim's image, and force every `using Janim` to load VideoIO —
# undoing the lazy loading exactly. It would buy less than it looks: the
# first `demo_mp4` costs 5 ms, but the path that actually renders
# (`FramePipeline`, whose frame type is a reinterpreted buffer, not
# `Matrix{RGB}`) is not covered by it — 1141 ms with 1080 compiling. The
# workload would be precompiling the demo, not the engine.
using PrecompileTools
@setup_workload begin
    @compile_workload begin
        # the core: build, transform and query (whatever runs here does not
        # pay JIT in the user's first scene)
        let c = Circle(), g = VGroup(c, Square())
            shift!(g, 2 * RIGHT)
            rotate!(c, TAU / 8)
            scale!(c, 2.0; about_edge = LEFT)
            stretch!(g, 1.5, 1)
            move_to!(c, ORIGIN)
            get_width(g); get_center(c); get_subpaths(c)
            add_updater!(c, (m, dt) -> shift!(m, dt * RIGHT))
            update!(g, 1 / 60)
            v = VMobject()
            start_new_path!(v, ORIGIN); add_line_to!(v, UP)
            start_new_path!(v, RIGHT); add_line_to!(v, UR)
            get_subpaths(v)
        end
        # the animation life cycle and the timeline (no GPU, no video)
        let tl = Timeline(fps = 4)
            a = Circle()
            play!(tl, Transform(a, Square()); run_time = 0.5)
            play!(tl, ShowCreation(Circle()); run_time = 0.25)
            play!(tl, AnimationGroup(FadeIn(Square()), FadeOut(a); lag_ratio = 0.5))
        end
        # the first formula pays JIT + font loading (3.6 s measured) — let
        # precompilation pay it, not the user
        Tex(raw"x^2 + \frac{1}{2}")
    end
end

# The render path, compiled WITHOUT a display.
#
# The workload above runs code, and running the renderer needs a device —
# which is why the renderer is left out of it, and why the first frame would
# otherwise pay seconds of JIT (almost all of it the compiler's, very little
# the driver's). `precompile` is the way in: it asks for CODE for a
# signature, it does not CALL it, so no device, no display, nothing to fail
# on a build machine.
#
# Only concrete signatures are listed. The scene-building entries
# (`render_frame`, `Scene`) specialise on the user's own `construct` closure
# and cannot be precompiled for a type that does not exist yet — but almost
# nothing hangs off that specialisation: the expensive tree is reached
# through `_draw_frame!(::Scene)`, whose argument types are the same for
# every scene in the world.
#
# The list is the WebGPU renderer's: `GPURenderVM`, `FramePipeline`,
# `camera_uniforms(cam; flip_y = false)` because that is what `draw_scene!`
# computes (row 0 is the top already). Every signature is one `_draw_frame!`
# reaches; the counter below says they EXIST, and only a profile says they
# serve.
let ok = 0, tried = 0
    add(f, t) = (tried += 1; ok += precompile(f, t))

    # Shape-independent: the tree below these is the same for every scene.
    add(_draw_frame!, (Scene,))
    add(_update_all!, (Scene, Float64))
    add(setup_render_vm, (GPU, Int, Int))
    add(read_rgb_topdown, (GPURenderVM,))
    add(read_rgb_topdown!, (GPURenderVM, Array{UInt8,3}))
    add(draw_scene!, (GPURenderVM, Vector{Mobject}, Camera))
    add(camera_uniforms, (Camera,))

    # …and the handful that DO see the shape. The tag is a type
    # parameter (`VMobject{:Circle}`) so that `interpolate(::Circle, ::Square)`
    # can be a method — real dispatch, and worth it. The bill it quietly runs
    # up is here: anything taking a VMobject is compiled once PER SHAPE, so a
    # scene with a Square pays again for what the Circle already compiled.
    # `expanded_data` and its two helpers are the whole per-shape surface —
    # the records and the passes take the expanded NamedTuple, whose type is
    # the same for every shape.
    for tag in (:Circle, :Square, :Rectangle, :Line, :Arrow, :Dot, :Polygon,
                :RegularPolygon, :Triangle, :Ellipse, :Arc, :ArcBetweenPoints,
                :Annulus, :AnnularSector, :Sector, :RoundedRectangle, :Star,
                :Elbow, :Angle, :VGroup, :Tex, :TextMobject, :SVGMobject,
                :TracedPath, :Matrix, :Table)
        V = VMobject{tag}
        add(expanded_data, (V,))
        add(_draw_family, (V,))          # what _draw_list! walks
        add(active_fill_gradient, (V,))
        add(Core.kwcall,
            (NamedTuple{(:grad,),Tuple{Nothing}}, typeof(expanded_data), V))
    end

    # The walk and the records take the camera's uniform bundle, whose type
    # is long and would rot the moment a field moves. So COMPUTE it instead
    # of transcribing it: `camera_uniforms` is pure CPU, and running it here
    # costs nothing and needs no device.
    let C = typeof(camera_uniforms(Camera(); flip_y = false))
        add(_draw_list!, (GPURenderVM, Vector{Mobject}, C))
        add(_run_record!, (GPURenderVM, Vector{VMobject}, Nothing))
        add(_build_record, (GPURenderVM, Vector{VMobject}, Nothing, Vector{Int}))
        add(_draw_family, (Group,))
        add(get_family, (Group,))
    end

    # Not an assertion: a signature that stops being reachable must not break
    # someone's install. It has to be VISIBLE instead — ok == tried says every
    # signature exists, so a refactor that orphans one of these can say so out
    # loud rather than quietly handing the cost back to the user. (A wrong type
    # is NOT caught by that count — it precompiles fine and is simply never
    # called. The guard against those is measuring, and the way to see one is
    # `--trace-compile`: the signature shows up anyway.)
    global const _PRECOMPILE_GL = (; ok, tried)
end

# The UPDATE and ENTRY path.
#
# The list above covers the DRAW path (`_draw_frame!` and below); this one
# covers the frame loop that calls it, the pipeline that swallows the result
# and the scene entry points.
#
# The list is NOT the draw list plus guesses: it was derived from an
# inference profile, so it names only what is still expensive (precompiling
# something dead would be weight with the counter reading 100%). The top of
# the profile is not ours:
#
#   · `axes`/`size` on a `Vector{Union{Nothing,Function}}` — GLFW's callback
#     table — come to ~230 ms of inference between them, because `Function` is
#     abstract with thousands of subtypes and union-splitting explodes. The
#     TYPE is pure Base, so this can be cached from here even though GLFW
#     itself cannot.
#
# Every signature here was validated in a live session before being written,
# and the proof that they SERVE is the profile, never this counter (`precompile`
# returns true for any valid signature, called or not).
let ok = 0, tried = 0
    add(f, t) = (tried += 1; ok += precompile(f, t))

    # Base, but reached only through us — the union-split pathology above.
    add(axes, (Vector{Union{Nothing,Function}},))
    add(size, (Vector{Union{Nothing,Function}},))
    #
    # NOT here, and the reason is worth more than the entry: once those two
    # are cached the profile puts `getindex(::UnitRange, ::StepRange)` and
    # `Base.reindex` on top, at ~118 ms each. Adding them was measured — the
    # first frame moved 267 → 264 ms, which is noise. **The top of an
    # inference profile is a suspect, not a verdict**: instrumented times are
    # inflated per node and do not convert to wall clock, so a directive only
    # earns its place by moving the first-frame time.
    # The pipeline's buffer pool: both Channel paths, buffered or not.
    add(Base.put_unbuffered, (Channel{Int}, Int))
    add(Base.put_buffered, (Channel{Int}, Int))

    # The frame loop and the scene's entry points.
    add(wait!, (Scene, Float64))
    add(_progress!, (Scene, String, Int, Int))
    add(Core.kwcall, (NamedTuple{(:alpha_at,),Tuple{Nothing}},
                      typeof(_advance!), Scene, Float64))
    add(Core.kwcall, (NamedTuple{(:width, :height),Tuple{Int,Int}},
                      Type{Camera}))
    # The mp4 sink. Cheap to list and it is on every production render — the
    # encoder task itself stays out on purpose: it lives behind the lazy video
    # loading and naming it here would drag VideoIO back into the image.
    add(close_pipeline!, (FramePipeline,))
    add(enqueue!, (FramePipeline,))

    global const _PRECOMPILE_LOOP = (; ok, tried)
end

end # module Janim
