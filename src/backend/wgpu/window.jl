# backend/wgpu/window.jl — the preview's window and its presentation: a GLFW
# window opened WITHOUT an API, a WebGPU surface on it made from GLFW's
# native handles, the pass that puts `rv.target` on that surface, and the two
# writes into the target the live loop needs (a cached frame, the timeline
# strip).
#
#   · The window carries no context. `GLFW.CLIENT_API = NO_API`
#     (`_create_window_noapi`, backend/window.jl) gives the usual events,
#     keys, title and close button — the `GLFW.` calls of live.jl do not
#     care — and WebGPU presents on it through a surface built from
#     `glfwGetWaylandDisplay/Window` or `glfwGetX11Display/Window`, raw
#     ccalls into GLFW_jll — or, on macOS, from a `CAMetalLayer` put on the
#     `NSWindow`'s content view (`glfwGetCocoaWindow`, the Objective-C
#     runtime by ccall; the macOS section below).
#   · The format is the PLAIN form of what the surface prefers: both
#     platforms prefer `BGRA8UnormSrgb`; `rv.target` already holds
#     sRGB-encoded bytes (FINAL does the OETF), and an `-srgb` surface would
#     encode them twice. `Fifo` paces at the display's rate (60 Hz); both
#     platforms offer it.
#   · One pass presents: a triangle over the screen sampling the target
#     NEAREST (`present.wgsl`, ManimGL's). At 1:1 the surface receives the
#     bytes of the frame — the swapchain read back through `CopySrc` (which
#     both platforms offer) is byte-identical to the source, BGRA swizzled.
#     On a HiDPI framebuffer it stretches: no letterbox, no resize, the
#     window is born at the render's size.
#   · A surface only for a VISIBLE window on a native platform. Under the
#     Null platform (`JANIM_HEADLESS=1`, no display) and for a hidden
#     window (`setup_live(visible = false)`) there is no presenter: the frame
#     lives in `rv.target`, `present!` only pumps events. A surface on an
#     unmapped Wayland window never gets a frame callback and Fifo would
#     block the loop inside the acquire.
#   · The acquire's non-success statuses reconfigure and skip the frame,
#     they never throw (the window does not die) — except `DeviceLost`,
#     which is `GPUDeviceLostError` like everywhere else. Mesa's WSI returns
#     `SuccessOptimal` even through a window resize on both platforms; what
#     does happen is that an acquire on an UNCONFIGURED surface is a fatal
#     panic in wgpu-native v24 (`handle_error_fatal`, src/lib.rs:598: the
#     process aborts, the header's «returns Error» is not what this build
#     does) — hence `configured`, checked before every acquire.
#   · The presenter is released BEFORE `glfwDestroyWindow` (`close_context`
#     calls `_release_presenter!` first): a surface that outlives its
#     `wl_surface` is a use-after-free inside the WSI.
#   · The frame's bytes reach the target by `wgpuQueueWriteTexture` — the
#     cached frame of a scrub (`_blit_image!`) and the timeline strip
#     (`_paint_strip!`) — one write each, no texture and no framebuffer per
#     call. `loadOp = Clear` ignores the scissor in WebGPU, so the strip is
#     not a pass either.

const _PRESENTS = Ref(0)             # frames put on a surface
const _SURFACE_RECONFIGS = Ref(0)    # surface configurations after the first (size, status)

"""
    GPUPresenter

Everything that presents one window: the surface and its configuration
(format, size), the pass's pipeline for that format, the bind group over
the target it shows, the sampler. One per VISIBLE window on a native
platform, registered by the GLFW handle in `_PRESENTERS`; released by
`_release_presenter!` from `close_context`.
"""
mutable struct GPUPresenter
    gpu::GPU
    handle::Ptr{Cvoid}                # the GLFW window's handle: the registry's key
    surface::WGPUSurface
    platform::Symbol                  # :wayland | :x11 | :cocoa | :win32 — which source made the surface
    format::WGPUTextureFormat         # the plain form of the surface's preferred format
    width::Int                        # configured size, in physical pixels
    height::Int
    configured::Bool                  # NEVER acquire without it (v24 aborts)
    copy_src::Bool                    # the surface offers CopySrc (a test can read the swapchain)
    layout::WGPUBindGroupLayout
    pipeline_layout::WGPUPipelineLayout
    sampler::WGPUSampler
    shader::WGPUShaderModule
    pipeline::WGPURenderPipeline
    pipeline_format::WGPUTextureFormat
    bind_group::WGPUBindGroup
    bound_target::Any                 # the GPUTarget the bind group samples (identity)
    warned::Bool                      # the Error/OutOfMemory warning, once per presenter
    presents::Int
    reconfigures::Int
    closed::Bool
end

const _PRESENTERS = Dict{Ptr{Cvoid},GPUPresenter}()
const _PRESENT_LABEL = "Janim present"
const _PRESENT_VS = "vs_main"
const _PRESENT_FS = "fs_main"

# ── the window ──────────────────────────────────────────────────────────

"""
    create_window(width, height; title = "Janim", visible = true)

The preview window: a GLFW window opened WITHOUT a graphics API (the GLFW
package is loaded first, as for every window), and — when it is visible and
the platform is X11, Wayland or Cocoa — a presenter on it: the WebGPU surface
made from the window's native handles, configured on the process's GPU.
Hidden, or under the Null platform, the window has no presenter and
`present!` only pumps events. Closed by `close_context`, which releases
the presenter before destroying the window.
"""
function create_window(width::Int, height::Int; title = "Janim", visible = true)
    _ensure_gl!()
    window = Base.invokelatest(_create_window_noapi, width, height; title, visible)
    plat = gl_platform()
    if visible && !_NULL_PLATFORM[]
        if plat === :wayland || plat === :x11 || plat === :cocoa || plat === :win32
            try
                _attach_presenter!(_shared_gpu(), window, plat)
            catch
                close_context(window)
                rethrow()
            end
        else
            close_context(window)
            error("the preview surface on the $plat platform is not supported (X11, Wayland and Cocoa are): " *
                  "render to a file instead")
        end
    end
    return window
end

"The presenter of a window, or `nothing` (hidden, Null platform, not a window)."
_presenter(window) = window === nothing ? nothing :
                     get(_PRESENTERS, _glfw_handle(window), nothing)

"The surface from the window's native handles, by platform."
function _create_surface(inst::WGPUInstance, handle::Ptr{Cvoid}, plat::Symbol)
    if plat === :wayland
        display = ccall((:glfwGetWaylandDisplay, GLFW_jll.libglfw), Ptr{Cvoid}, ())
        wl = ccall((:glfwGetWaylandWindow, GLFW_jll.libglfw), Ptr{Cvoid}, (Ptr{Cvoid},), handle)
        (display == C_NULL || wl == C_NULL) &&
            throw(GPUValidationError("GLFW gave no Wayland display/surface for the window"))
        src = Ref(WGPUSurfaceSourceWaylandSurface(
            WGPUChainedStruct(C_NULL, WGPUSType_SurfaceSourceWaylandSurface), display, wl))
        desc = Ref(WGPUSurfaceDescriptor(Ptr{WGPUChainedStruct}(pointer_from_objref(src)), _EMPTY_SV))
        surface = GC.@preserve src desc wgpuInstanceCreateSurface(inst, desc)
    elseif plat === :x11
        display = ccall((:glfwGetX11Display, GLFW_jll.libglfw), Ptr{Cvoid}, ())
        xid = ccall((:glfwGetX11Window, GLFW_jll.libglfw), Culong, (Ptr{Cvoid},), handle)
        (display == C_NULL || xid == 0) &&
            throw(GPUValidationError("GLFW gave no X11 display/window for the window"))
        src = Ref(WGPUSurfaceSourceXlibWindow(
            WGPUChainedStruct(C_NULL, WGPUSType_SurfaceSourceXlibWindow), display, UInt64(xid)))
        desc = Ref(WGPUSurfaceDescriptor(Ptr{WGPUChainedStruct}(pointer_from_objref(src)), _EMPTY_SV))
        surface = GC.@preserve src desc wgpuInstanceCreateSurface(inst, desc)
    elseif plat === :cocoa
        layer = _cocoa_metal_layer!(handle)
        src = Ref(WGPUSurfaceSourceMetalLayer(
            WGPUChainedStruct(C_NULL, WGPUSType_SurfaceSourceMetalLayer), layer))
        desc = Ref(WGPUSurfaceDescriptor(Ptr{WGPUChainedStruct}(pointer_from_objref(src)), _EMPTY_SV))
        surface = GC.@preserve src desc wgpuInstanceCreateSurface(inst, desc)
    elseif plat === :win32
        hwnd = ccall((:glfwGetWin32Window, GLFW_jll.libglfw), Ptr{Cvoid}, (Ptr{Cvoid},), handle)
        hwnd == C_NULL && throw(GPUValidationError("GLFW gave no Win32 window for the window"))
        hinstance = ccall((:GetModuleHandleW, "kernel32"), Ptr{Cvoid}, (Ptr{Cvoid},), C_NULL)
        src = Ref(WGPUSurfaceSourceWindowsHWND(
            WGPUChainedStruct(C_NULL, WGPUSType_SurfaceSourceWindowsHWND), hinstance, hwnd))
        desc = Ref(WGPUSurfaceDescriptor(Ptr{WGPUChainedStruct}(pointer_from_objref(src)), _EMPTY_SV))
        surface = GC.@preserve src desc wgpuInstanceCreateSurface(inst, desc)
    else
        throw(ArgumentError("no surface source for the $plat platform"))
    end
    surface == C_NULL && throw(GPUValidationError("wgpuInstanceCreateSurface returned NULL on $plat"))
    return surface
end

"The plain form of the format the surface prefers, never the sRGB one."
_plain_format(fmt::WGPUTextureFormat) =
    fmt == WGPUTextureFormat_BGRA8UnormSrgb ? WGPUTextureFormat_BGRA8Unorm :
    fmt == WGPUTextureFormat_RGBA8UnormSrgb ? WGPUTextureFormat_RGBA8Unorm : fmt

"Is `fmt` an sRGB-encoding format? (what the surface must never be configured with)"
_is_srgb_format(fmt::WGPUTextureFormat) =
    fmt == WGPUTextureFormat_BGRA8UnormSrgb || fmt == WGPUTextureFormat_RGBA8UnormSrgb

"""
Configure the surface at `width × height` (physical pixels). The first
time, the capabilities are read: the preferred format (its plain form is
kept), whether `CopySrc` is offered, and that `Fifo` is there — and freed
with `wgpuSurfaceCapabilitiesFreeMembers`. wgpu-native v24 returns 0 from
`wgpuSurfaceGetCapabilities` (neither Success nor Error: measured), so the
struct is what says whether the adapter can present at all.
"""
function _configure!(p::GPUPresenter, width::Int, height::Int)
    (width > 0 && height > 0) || throw(ArgumentError("a surface needs a positive size, got $(width)×$(height)"))
    if p.format == WGPUTextureFormat_Undefined
        caps = Ref(WGPUSurfaceCapabilities(C_NULL, WGPUTextureUsage_None, 0, C_NULL, 0, C_NULL, 0, C_NULL))
        GC.@preserve caps wgpuSurfaceGetCapabilities(p.surface, p.gpu.adapter, caps)
        c = caps[]
        if c.formatCount == 0
            wgpuSurfaceCapabilitiesFreeMembers(c)
            throw(GPUValidationError("the adapter $(p.gpu.info.device) cannot present on this window's surface (no formats)"))
        end
        preferred = unsafe_load(c.formats, 1)
        modes = [unsafe_load(c.presentModes, k) for k in 1:c.presentModeCount]
        p.copy_src = c.usages & WGPUTextureUsage_CopySrc != 0
        wgpuSurfaceCapabilitiesFreeMembers(c)
        WGPUPresentMode_Fifo in modes ||
            throw(GPUValidationError("the surface offers no Fifo present mode (the one the spec guarantees)"))
        p.format = _plain_format(preferred)
    end
    usage = WGPUTextureUsage_RenderAttachment |
            (p.copy_src ? WGPUTextureUsage_CopySrc : WGPUTextureUsage_None)
    cfg = Ref(WGPUSurfaceConfiguration(C_NULL, p.gpu.device, p.format, usage, UInt32(width), UInt32(height),
                                       0, C_NULL, WGPUCompositeAlphaMode_Auto, WGPUPresentMode_Fifo))
    GC.@preserve cfg _error_scope(p.gpu) do
        wgpuSurfaceConfigure(p.surface, cfg)
    end
    p.width, p.height = width, height
    p.configured = true
    return p
end

"""
The pass's objects — layout, pipeline layout, the nearest sampler, the
shader — around `surface` (NULL for an offscreen presenter: a test can drive
the pass onto an ordinary texture to read what a surface would get).
"""
function _new_presenter(gpu::GPU, handle::Ptr{Cvoid}, surface::WGPUSurface, plat::Symbol)
    layout = _texture_layout(gpu, "Janim present layout")
    pl = _pipeline_layout(gpu, [layout], "Janim present pipeline layout")
    sdesc = Ref(WGPUSamplerDescriptor(C_NULL, _sv(_PRESENT_LABEL),
                                      WGPUAddressMode_ClampToEdge, WGPUAddressMode_ClampToEdge,
                                      WGPUAddressMode_ClampToEdge, WGPUFilterMode_Nearest,
                                      WGPUFilterMode_Nearest, WGPUMipmapFilterMode_Nearest,
                                      0f0, 32f0, WGPUCompareFunction_Undefined, 1))
    sampler = GC.@preserve sdesc _error_scope(gpu) do
        wgpuDeviceCreateSampler(gpu.device, sdesc)
    end
    sampler == C_NULL && throw(GPUValidationError("wgpuDeviceCreateSampler returned NULL for the presenter"))
    shader = compile_wgsl(gpu, PRESENT_WGSL; label = "present")
    return GPUPresenter(gpu, handle, surface, plat, WGPUTextureFormat_Undefined, 0, 0, false, false,
                        layout, pl, sampler, shader, WGPURenderPipeline(C_NULL), WGPUTextureFormat_Undefined,
                        WGPUBindGroup(C_NULL), nothing, false, 0, 0, false)
end

"A presenter on `window` (a GLFW window on platform `plat`), registered by handle."
function _attach_presenter!(gpu::GPU, window, plat::Symbol)
    handle = _glfw_handle(window)
    surface = _create_surface(gpu.instance, handle, plat)
    p = _new_presenter(gpu, handle, surface, plat)
    try
        _configure!(p, _framebuffer_size(handle)...)
    catch
        _release_presenter!(p)
        rethrow()
    end
    _PRESENTERS[handle] = p
    return p
end

"The pass's pipeline for the surface's format, made once per format."
function _ensure_pipeline!(p::GPUPresenter)
    (p.pipeline != C_NULL && p.pipeline_format == p.format) && return p.pipeline
    p.pipeline == C_NULL || wgpuRenderPipelineRelease(p.pipeline)
    gpu = p.gpu
    targets = [WGPUColorTargetState(C_NULL, p.format, C_NULL, WGPUColorWriteMask_All)]
    frag = Ref(WGPUFragmentState(C_NULL, p.shader, _sv(_PRESENT_FS), 0, C_NULL, length(targets), pointer(targets)))
    desc = Ref(WGPURenderPipelineDescriptor(
        C_NULL, _sv(_PRESENT_LABEL), p.pipeline_layout,
        WGPUVertexState(C_NULL, p.shader, _sv(_PRESENT_VS), 0, C_NULL, 0, C_NULL),
        WGPUPrimitiveState(C_NULL, WGPUPrimitiveTopology_TriangleList, WGPUIndexFormat_Undefined,
                           WGPUFrontFace_CCW, WGPUCullMode_None, 0),
        C_NULL, WGPUMultisampleState(C_NULL, 1, 0xffffffff, 0),
        Base.unsafe_convert(Ptr{WGPUFragmentState}, frag)))
    pipe = GC.@preserve targets frag desc _error_scope(gpu) do
        wgpuDeviceCreateRenderPipeline(gpu.device, desc)
    end
    pipe == C_NULL && throw(GPUValidationError("wgpuDeviceCreateRenderPipeline returned NULL for the present pass"))
    p.pipeline, p.pipeline_format = pipe, p.format
    return pipe
end

"The bind group over the target the pass samples, remade when the target changes."
function _ensure_bind_group!(p::GPUPresenter, target::GPUTarget)
    (p.bind_group != C_NULL && p.bound_target === target) && return p.bind_group
    p.bind_group == C_NULL || wgpuBindGroupRelease(p.bind_group)
    p.bind_group = _bind_group(p.gpu, p.layout,
        [WGPUBindGroupEntry(C_NULL, 0, WGPUBuffer(C_NULL), 0, 0, WGPUSampler(C_NULL), target.view),
         WGPUBindGroupEntry(C_NULL, 1, WGPUBuffer(C_NULL), 0, 0, p.sampler, WGPUTextureView(C_NULL))],
        _PRESENT_LABEL)
    p.bound_target = target
    return p.bind_group
end

"""
Release the presenter of the window with `handle`, if any: the pass's
objects, then the surface (unconfigured first), and the registry's entry.
Called by `close_context` BEFORE the GLFW window is destroyed.
"""
function _release_presenter!(handle::Ptr{Cvoid})
    p = pop!(_PRESENTERS, handle, nothing)
    p === nothing || _release_presenter!(p)
    return nothing
end

function _release_presenter!(p::GPUPresenter)
    p.closed && return nothing
    p.closed = true
    p.bind_group == C_NULL || wgpuBindGroupRelease(p.bind_group)
    p.pipeline == C_NULL || wgpuRenderPipelineRelease(p.pipeline)
    wgpuShaderModuleRelease(p.shader)
    wgpuSamplerRelease(p.sampler)
    wgpuPipelineLayoutRelease(p.pipeline_layout)
    wgpuBindGroupLayoutRelease(p.layout)
    if p.surface != C_NULL
        p.configured && wgpuSurfaceUnconfigure(p.surface)
        wgpuSurfaceRelease(p.surface)
    end
    p.configured = false
    return nothing
end

# ── macOS: the CAMetalLayer on the NSWindow's content view ──────────────
#
# wgpu-native presents on Metal through a `CAMetalLayer`
# (`WGPUSurfaceSourceMetalLayer`). GLFW gives the `NSWindow`
# (`glfwGetCocoaWindow`) and the layer goes on its `contentView` — the
# recipe of wgpu-native's triangle example and of GLFW's own Vulkan surface:
# `[view setLayer:[[CAMetalLayer alloc] init]]`, `[view setWantsLayer:YES]`,
# and `setContentsScale:` to the window's `backingScaleFactor`, or on a
# Retina screen the layer would be shown at half its resolution (wgpu-native
# sets `drawableSize` itself at every configure; the scale is ours to set).
# The Objective-C runtime is reached by ccall — `objc_getClass`,
# `sel_registerName`, `objc_msgSend` with each message's own signature; on
# arm64 there are no `_fpret`/`_stret` variants — and QuartzCore is
# dlopened first, or the CAMetalLayer class does not exist in the process
# (GLFW links Cocoa and AppKit, not QuartzCore). All of it runs on thread 1,
# where Cocoa wants its windows.

const _OBJC = "/usr/lib/libobjc.A.dylib"
const _QUARTZCORE = "/System/Library/Frameworks/QuartzCore.framework/QuartzCore"

_objc_class(name::String) = ccall((:objc_getClass, _OBJC), Ptr{Cvoid}, (Cstring,), name)
_objc_sel(name::String) = ccall((:sel_registerName, _OBJC), Ptr{Cvoid}, (Cstring,), name)
_objc_send(obj::Ptr{Cvoid}, sel::String) =
    ccall((:objc_msgSend, _OBJC), Ptr{Cvoid}, (Ptr{Cvoid}, Ptr{Cvoid}), obj, _objc_sel(sel))
_objc_send(obj::Ptr{Cvoid}, sel::String, arg::Ptr{Cvoid}) =
    ccall((:objc_msgSend, _OBJC), Cvoid, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}), obj, _objc_sel(sel), arg)
_objc_send(obj::Ptr{Cvoid}, sel::String, arg::Bool) =
    ccall((:objc_msgSend, _OBJC), Cvoid, (Ptr{Cvoid}, Ptr{Cvoid}, Bool), obj, _objc_sel(sel), arg)
_objc_send(obj::Ptr{Cvoid}, sel::String, arg::Float64) =
    ccall((:objc_msgSend, _OBJC), Cvoid, (Ptr{Cvoid}, Ptr{Cvoid}, Cdouble), obj, _objc_sel(sel), arg)
_objc_send_double(obj::Ptr{Cvoid}, sel::String) =
    ccall((:objc_msgSend, _OBJC), Cdouble, (Ptr{Cvoid}, Ptr{Cvoid}), obj, _objc_sel(sel))
_objc_is_kind(obj::Ptr{Cvoid}, class::Ptr{Cvoid}) =
    ccall((:objc_msgSend, _OBJC), Bool, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}), obj, _objc_sel("isKindOfClass:"), class)

"The NSWindow behind a GLFW window (Cocoa), never NULL."
function _cocoa_window(handle::Ptr{Cvoid})
    ns_window = ccall((:glfwGetCocoaWindow, GLFW_jll.libglfw), Ptr{Cvoid}, (Ptr{Cvoid},), handle)
    ns_window == C_NULL && throw(GPUValidationError("GLFW gave no NSWindow for the window"))
    return ns_window
end

"""
The `CAMetalLayer` of the window's content view, made and installed the
first time (idempotent: a view that already carries one keeps it), with
`contentsScale` at the window's backing scale.
"""
function _cocoa_metal_layer!(handle::Ptr{Cvoid})
    Base.Libc.Libdl.dlopen(_QUARTZCORE)
    ns_window = _cocoa_window(handle)
    view = _objc_send(ns_window, "contentView")
    view == C_NULL && throw(GPUValidationError("the NSWindow has no content view"))
    metal_class = _objc_class("CAMetalLayer")
    metal_class == C_NULL && throw(GPUValidationError("the CAMetalLayer class is not available (QuartzCore)"))
    layer = _objc_send(view, "layer")
    if layer == C_NULL || !_objc_is_kind(layer, metal_class)
        layer = _objc_send(_objc_send(metal_class, "alloc"), "init")
        layer == C_NULL && throw(GPUValidationError("[[CAMetalLayer alloc] init] returned nil"))
        _objc_send(view, "setLayer:", layer)       # the view retains it; our +1 lives as long as the window
        _objc_send(view, "setWantsLayer:", true)
    end
    _objc_send(layer, "setContentsScale:", _objc_send_double(ns_window, "backingScaleFactor"))
    return layer
end

"Keep the layer's `contentsScale` at the window's backing scale (a reconfigure may follow a screen change)."
function _cocoa_sync_scale!(handle::Ptr{Cvoid})
    ns_window = _cocoa_window(handle)
    layer = _objc_send(_objc_send(ns_window, "contentView"), "layer")
    layer == C_NULL && return false
    _objc_send(layer, "setContentsScale:", _objc_send_double(ns_window, "backingScaleFactor"))
    return true
end

# ── the presentation ────────────────────────────────────────────────────

"One acquire: the status and the surface's texture (NULL unless success)."
function _acquire!(p::GPUPresenter)
    p.configured || error("acquire on an unconfigured surface: wgpu-native v24 would abort the process")
    st = Ref(WGPUSurfaceTexture(C_NULL, WGPUTexture(C_NULL), WGPUSurfaceGetCurrentTextureStatus(0)))
    GC.@preserve st wgpuSurfaceGetCurrentTexture(p.surface, st)
    return st[].status, st[].texture
end

_acquire_ok(status) = status == WGPUSurfaceGetCurrentTextureStatus_SuccessOptimal ||
                      status == WGPUSurfaceGetCurrentTextureStatus_SuccessSuboptimal

"""
The pass: `target` onto `view` — a surface texture's, or any colour view
in the presenter's format — submitted. Returns the submission index.
"""
function _present_to_view!(p::GPUPresenter, target::GPUTarget, view::WGPUTextureView)
    gpu = p.gpu
    pipeline = _ensure_pipeline!(p)
    bg = _ensure_bind_group!(p, target)
    enc = wgpuDeviceCreateCommandEncoder(gpu.device, C_NULL)
    color = [WGPURenderPassColorAttachment(C_NULL, view, WGPU_DEPTH_SLICE_UNDEFINED, WGPUTextureView(C_NULL),
                                           WGPULoadOp_Clear, WGPUStoreOp_Store, WGPUColor(0, 0, 0, 1))]
    desc = Ref(WGPURenderPassDescriptor(C_NULL, _EMPTY_SV, 1, pointer(color), C_NULL, WGPUQuerySet(C_NULL), C_NULL))
    pass = GC.@preserve color desc wgpuCommandEncoderBeginRenderPass(enc, desc)
    _GPU_PASSES[] += 1
    wgpuRenderPassEncoderSetPipeline(pass, pipeline)
    wgpuRenderPassEncoderSetBindGroup(pass, 0, bg, 0, C_NULL)
    wgpuRenderPassEncoderDraw(pass, 3, 1, 0, 0)
    wgpuRenderPassEncoderEnd(pass)
    wgpuRenderPassEncoderRelease(pass)
    cmd = _error_scope(gpu) do
        wgpuCommandEncoderFinish(enc, C_NULL)
    end
    wgpuCommandEncoderRelease(enc)
    return _submit!(gpu, cmd)
end

"""
The pass onto the surface's `texture` (a successful acquire), submitted and
presented; the texture and its view released after the present.
"""
function _draw_present!(p::GPUPresenter, target::GPUTarget, texture::WGPUTexture)
    view = wgpuTextureCreateView(texture, C_NULL)
    _present_to_view!(p, target, view)
    wgpuSurfacePresent(p.surface)
    wgpuTextureViewRelease(view)
    wgpuTextureRelease(texture)
    p.presents += 1
    _PRESENTS[] += 1
    return nothing
end

"""
What one acquire's `status` leads to: success → the pass and the present;
`DeviceLost` → `GPUDeviceLostError`; anything else (`Timeout`, `Outdated`,
`Lost`, `Error`, `OutOfMemory`) → the texture released if one came, the
surface reconfigured at the window's current physical size, the frame
skipped — the loop goes on (the window does not die). `Error` and
`OutOfMemory` also warn, once per presenter.
"""
function _present_status!(p::GPUPresenter, target::GPUTarget, status, texture::WGPUTexture)
    if _acquire_ok(status)
        _draw_present!(p, target, texture)
        return true
    end
    texture == C_NULL || wgpuTextureRelease(texture)
    status == WGPUSurfaceGetCurrentTextureStatus_DeviceLost &&
        throw(GPUDeviceLostError(UInt32(status), "the preview surface's device is lost: nothing on it can be presented again"))
    if (status == WGPUSurfaceGetCurrentTextureStatus_Error ||
        status == WGPUSurfaceGetCurrentTextureStatus_OutOfMemory) && !p.warned
        p.warned = true
        @warn "the preview surface returned status $(Int(status)) on acquire; reconfiguring and skipping the frame (once per session)"
    end
    _reconfigure!(p)
    return false
end

"Reconfigure at the window's current physical size (skipped while minimised: 0×0)."
function _reconfigure!(p::GPUPresenter)
    w, h = _framebuffer_size(p.handle)
    (w > 0 && h > 0) || return false
    p.platform === :cocoa && _cocoa_sync_scale!(p.handle)   # the window may have changed screen
    _configure!(p, w, h)
    p.reconfigures += 1
    _SURFACE_RECONFIGS[] += 1
    return true
end

"""
    present!(rv::GPURenderVM, window)

The live sink: `rv.target` onto the window's surface (when it
has a presenter), then the window's events. A framebuffer that changed
size (HiDPI, a manager's resize) reconfigures the surface first; a
minimised window (0×0) presents nothing this tick.
"""
function present!(rv::GPURenderVM, window)
    p = _presenter(window)
    if p !== nothing
        w, h = _framebuffer_size(p.handle)
        if w > 0 && h > 0
            (w, h) == (p.width, p.height) || _reconfigure!(p)
            status, texture = _acquire!(p)
            _present_status!(p, rv.target, status, texture)
            _check_gpu_errors!(rv.gpu)
        end
    end
    _poll_events!()
    return nothing
end

# ── the writes into the target ──────────────────────────────────────────

"`4 × w × h` RGBA bytes at `x, y` (row 0 = the top) into the target, through the queue."
function _write_target!(rv::GPURenderVM, bytes::Vector{UInt8}, x::Int, y::Int, w::Int, h::Int)
    length(bytes) >= 4 * w * h || throw(ArgumentError("a $(w)×$(h) write needs $(4w * h) bytes, got $(length(bytes))"))
    t = rv.target
    (x + w <= t.width && y + h <= t.height) ||
        throw(ArgumentError("a $(w)×$(h) write at ($x, $y) falls outside the $(t.width)×$(t.height) target"))
    dst = Ref(WGPUTexelCopyTextureInfo(t.texture, 0, WGPUOrigin3D(UInt32(x), UInt32(y), 0), WGPUTextureAspect_All))
    layout = Ref(WGPUTexelCopyBufferLayout(0, UInt32(4w), UInt32(h)))
    ext = Ref(WGPUExtent3D(UInt32(w), UInt32(h), 1))
    GC.@preserve bytes dst layout ext wgpuQueueWriteTexture(rv.gpu.queue, dst, pointer(bytes), 4 * w * h, layout, ext)
    return nothing
end

"""
The blit: a `3×W×H` top-down frame back INTO the target
(a cache hit leaves ITS frame where `present!` reads), expanded to RGBA in
the VM's scratch and written with one `wgpuQueueWriteTexture`. Byte-exact
by construction: the same orientation on both sides, no flip.
"""
function _blit_image!(rv::GPURenderVM, img::Array{UInt8,3})
    W, H = rv.width, rv.height
    size(img) == (3, W, H) || throw(ArgumentError("a $(W)×$(H) VM cannot blit a $(size(img)) image"))
    n = 4 * W * H
    length(rv.scratch) == n || resize!(rv.scratch, n)
    s = rv.scratch
    k = 1
    @inbounds for y in 1:H, x in 1:W
        s[k] = img[1, x, y]; s[k+1] = img[2, x, y]; s[k+2] = img[3, x, y]; s[k+3] = 0xff
        k += 4
    end
    _write_target!(rv, s, 0, 0, W, H)
    return nothing
end

"""
The timeline strip's paint (live.jl computes the segments):
`bar` rows at the BOTTOM of the image — the target's last rows, row 0
being the top — filled segment by segment in the caller's order, and
written with one `wgpuQueueWriteTexture` (`round(255c)` per channel).
"""
function _paint_strip!(rv::GPURenderVM, W::Int, H::Int, bar::Int, segs)
    (W == rv.width && H == rv.height) || throw(ArgumentError("the strip's $(W)×$(H) is not the VM's $(rv.width)×$(rv.height)"))
    buf = Vector{UInt8}(undef, 4 * W * bar)
    for (x0, x1, r, g, b) in segs
        cr, cg, cb = round(UInt8, 255r), round(UInt8, 255g), round(UInt8, 255b)
        @inbounds for y in 0:bar-1, x in x0:x1-1
            k = 4 * (y * W + x) + 1
            buf[k] = cr; buf[k+1] = cg; buf[k+2] = cb; buf[k+3] = 0xff
        end
    end
    _write_target!(rv, buf, 0, H - bar, W, bar)
    return nothing
end

