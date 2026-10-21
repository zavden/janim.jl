# backend/wgpu/context.jl — the base of the WebGPU backend: the GPU
# (instance, adapter, device, queue) without a window, the two routes chosen
# BY ADAPTER, errors as exceptions, and the driver identity.
#
#   · There is no window system in the path to a file. wgpu-native talks to
#     Vulkan (Metal, DX12) directly, so `using Janim` never touches the
#     driver: the bindings resolve the library at precompile time and open it
#     on the FIRST call, so the setup here is a one-time process setup
#     (`_ensure_wgpu!`), not a lazy `include`.
#   · The two routes are two ADAPTERS of the same instance:
#     `JANIM_HEADLESS=1` means «the CPU adapter» (lavapipe, which Mesa ships
#     with its Vulkan ICDs — no OSMesa to install); otherwise the discrete GPU
#     is pinned, and its identity is reported by `gpu_info`.
#     `JANIM_ADAPTER=<substring>` overrides both, by device name.
#   · Errors. wgpu-native reports validation errors through callbacks that
#     may arrive on one of ITS threads, and a panic of the library aborts the
#     whole process (32 functions in v24 are `unimplemented!()`; wgpu-hal
#     asserts on misuse). So: the callbacks are MUTE mailboxes that copy
#     bytes into preallocated buffers and touch atomics, nothing else;
#     `_check_gpu_errors!` reads the mailbox at the coarse seams and throws
#     `GPUValidationError`; `_error_scope` wraps the creation of shaders and
#     pipelines in Push/PopErrorScope so the message (naga's, with line and
#     column) is attributed to the call. A lost device is
#     `GPUDeviceLostError`: every object of that device is invalid, and the
#     GPU says so from then on.
#   · The identity string. `WGPUAdapterInfo` has no `driverDescription`; its
#     `description` is the driver's own string, and it is NOT empty on Mesa
#     (`Mesa 26.1.8` on RADV, `Mesa 26.1.8 (LLVM 22.1.8)` on lavapipe). The
#     `vendor` field is the driver's short name (`radv`, `llvmpipe`), which is
#     exactly the slug used to label per-driver reference files.

# ── the backend ─────────────────────────────────────────────────────────

"""
    backend() → :wgpu

Which renderer this process uses: WebGPU, the only one. `JANIM_BACKEND`
accepts `wgpu` / `webgpu`; any other value is an error.
"""
function backend()
    v = lowercase(get(ENV, "JANIM_BACKEND", "wgpu"))
    v in ("wgpu", "webgpu") && return :wgpu
    v in ("gl", "opengl") && error(
        "JANIM_BACKEND=$(repr(v)): there is no OpenGL backend — the only backend is `wgpu`")
    error("JANIM_BACKEND=$(repr(v)): the only backend is `wgpu`")
end

"""
    fill_mode() → :stencil

Which fill the renderer draws: stencil-then-cover, the only one. `JANIM_FILL`
accepts `stencil` (and changes nothing); any other value is an error.
"""
function fill_mode()
    v = lowercase(get(ENV, "JANIM_FILL", "stencil"))
    v == "stencil" && return :stencil
    v == "winding" && error(
        "JANIM_FILL=$(repr(v)): there is no winding fill — the only fill is `stencil`")
    error("JANIM_FILL=$(repr(v)): the only fill is `stencil`")
end

# ── exceptions ──────────────────────────────────────────────────────────

"""
A validation (or out-of-memory, or internal) error wgpu-native reported —
through an error scope, attributed to the call that caused it, or through
the device's uncaptured-error callback, collected at the next
`_check_gpu_errors!`. The message is the library's own text: for a WGSL
source that does not compile, naga's diagnostic with line and column.
"""
struct GPUValidationError <: Exception
    message::String
end
Base.showerror(io::IO, e::GPUValidationError) =
    print(io, "GPUValidationError: ", e.message)

"""
The device is gone (reason ≠ Destroyed) and every buffer, texture and
pipeline created from it is invalid. Nothing recovers this in place: the
`GPU` has to be closed and a new one created — a daemon that holds one has
to throw away its render VM and its pipeline cache with it.
"""
struct GPUDeviceLostError <: Exception
    reason::UInt32
    message::String
end
Base.showerror(io::IO, e::GPUDeviceLostError) =
    print(io, "GPUDeviceLostError (reason ", e.reason, "): ", e.message)

# ── the mute mailbox the callbacks write into ──────────────────────────
#
# A `@cfunction` may be invoked from a wgpu thread. Inside it nothing may
# allocate, print or throw; so the callback copies the message's bytes into a
# preallocated buffer, stores the kind, and bumps a counter. The first
# unread message is kept whole (it is the one that explains the rest); the
# others only count. Everything Julia does with it happens later, on the
# caller's thread, in `_check_gpu_errors!`.

const _MAILBOX_BYTES = 4096

mutable struct _Mailbox
    count::Threads.Atomic{Int}       # errors since the last check
    kind::Threads.Atomic{Int}        # WGPUErrorType / WGPUDeviceLostReason of the kept one
    len::Threads.Atomic{Int}         # bytes of the kept message
    buf::Vector{UInt8}
    _Mailbox() = new(Threads.Atomic{Int}(0), Threads.Atomic{Int}(0),
                     Threads.Atomic{Int}(0), zeros(UInt8, _MAILBOX_BYTES))
end

"Bytes of a WGPUStringView — null-terminated when the length is WGPU_STRLEN."
@inline function _sv_length(sv::WGPUStringView)
    sv.data == C_NULL && return 0
    sv.length == WGPU_STRLEN &&
        return Int(ccall(:strlen, Csize_t, (Ptr{Cchar},), sv.data))
    return Int(sv.length)
end

"Julia string of a WGPUStringView (allocates: never call this from a callback)."
function _sv_string(sv::WGPUStringView)
    n = _sv_length(sv)
    n == 0 && return ""
    return unsafe_string(Ptr{UInt8}(sv.data), n)
end

"The callback half: copy the message into the mailbox without allocating."
@inline function _mailbox_post!(mb::_Mailbox, kind::Integer, sv::WGPUStringView)
    if mb.count[] == 0
        n = min(_sv_length(sv), _MAILBOX_BYTES)
        n > 0 && unsafe_copyto!(pointer(mb.buf), Ptr{UInt8}(sv.data), n)
        mb.len[] = n
        mb.kind[] = Int(kind)
    end
    Threads.atomic_add!(mb.count, 1)
    return nothing
end

"The Julia half: the kept message, and the counter back to zero."
function _mailbox_take!(mb::_Mailbox)
    n = mb.count[]
    n == 0 && return (0, 0, "")
    msg = String(mb.buf[1:mb.len[]])
    kind = mb.kind[]
    mb.count[] = 0
    return (n, kind, msg)
end

function _on_uncaptured_error(::Ptr{WGPUDevice}, etype::WGPUErrorType,
                              message::WGPUStringView, ud1::Ptr{Cvoid}, ::Ptr{Cvoid})
    _mailbox_post!(unsafe_pointer_to_objref(ud1)::_Mailbox, etype, message)
    return nothing
end

function _on_device_lost(::Ptr{WGPUDevice}, reason::WGPUDeviceLostReason,
                         message::WGPUStringView, ud1::Ptr{Cvoid}, ::Ptr{Cvoid})
    _mailbox_post!(unsafe_pointer_to_objref(ud1)::_Mailbox, reason, message)
    return nothing
end

# wgpu-core's own log, kept by the same rule (mute, preallocated). Level from
# `JANIM_WGPU_LOG` (off · error · warn · info · debug · trace; default warn):
# the library is chatty at `info`. Nothing is printed; `wgpu_log()` hands the
# lines over.
const _LOG = _Mailbox()
const _LOG_LEVELS = Dict("off" => WGPULogLevel_Off, "error" => WGPULogLevel_Error,
                         "warn" => WGPULogLevel_Warn, "info" => WGPULogLevel_Info,
                         "debug" => WGPULogLevel_Debug, "trace" => WGPULogLevel_Trace)

function _on_log(level::WGPULogLevel, message::WGPUStringView, ::Ptr{Cvoid})
    _mailbox_post!(_LOG, level, message)
    return nothing
end

"""
    wgpu_log() → (count, level, first_message)

What wgpu-core logged since the last call at or above the level
`JANIM_WGPU_LOG` selects (default `warn`): how many lines, the level of the
first, and the first line itself. Diagnostics, not an error channel — errors
come as exceptions.
"""
wgpu_log() = _mailbox_take!(_LOG)

# ── the GPU ─────────────────────────────────────────────────────────────

"""
    GPU

An instance, the adapter it chose, the device on it and its queue. Created by
`create_gpu`, closed by `close_gpu!`. `info` is the
adapter's identity (see [`gpu_info`](@ref)); `errors` and `lost` are the
mailboxes the device's callbacks write into.
"""
mutable struct GPU
    instance::WGPUInstance
    adapter::WGPUAdapter
    device::WGPUDevice
    queue::WGPUQueue
    info::NamedTuple{(:vendor, :architecture, :device, :description,
                      :backend, :kind, :vendor_id, :device_id),
                     Tuple{String, String, String, String, Symbol, Symbol, Int, Int}}
    features::Vector{Symbol}     # the optional features the device was created WITH
    errors::_Mailbox
    lost::_Mailbox
    closed::Bool
    dead::Bool                   # a GPUDeviceLostError was thrown from it — the shared GPU replaces it
end

const _WGPU_READY = Ref(false)
const _WGPU_LOCK = ReentrantLock()

"""
    _ensure_wgpu!()

The one-time process setup, on the first GPU: the driver knobs that have to
be in the environment before the instance exists, and wgpu-core's log
callback. Idempotent, locked, cheap after the first call. `using Janim` does
not reach here, so the library is not even opened by an import.
"""
function _ensure_wgpu!()
    _WGPU_READY[] && return nothing
    lock(_WGPU_LOCK) do
        _WGPU_READY[] && return nothing
        # RADV prints «WARNING: radv is not a conformant Vulkan implementation,
        # testing use only.» on stderr at every instance for a chip whose
        # conformance submission Mesa has not made yet (GFX1201 on 26.1.8).
        # It is about certification, not about what the driver renders; one
        # line per process in every render is noise. Mesa's
        # own knob, `get!` so a user's value wins.
        get!(ENV, "MESA_VK_IGNORE_CONFORMANCE_WARNING", "1")
        lvl = get(_LOG_LEVELS, lowercase(get(ENV, "JANIM_WGPU_LOG", "warn")), WGPULogLevel_Warn)
        wgpuSetLogCallback(@cfunction(_on_log, Cvoid, (WGPULogLevel, WGPUStringView, Ptr{Cvoid})), C_NULL)
        wgpuSetLogLevel(lvl)
        _WGPU_READY[] = true
        return nothing
    end
    return nothing
end

const _EMPTY_SV = WGPUStringView(C_NULL, 0)

"The backends wgpu may enumerate: the platform's native API."
_instance_backends() = Sys.isapple() ? WGPUInstanceBackend_Metal :
                       Sys.iswindows() ? WGPUInstanceBackend_DX12 :
                                         WGPUInstanceBackend_Vulkan

function _create_instance()
    extras = Ref(WGPUInstanceExtras(WGPUChainedStruct(C_NULL, WGPUSType_InstanceExtras),
                                    _instance_backends(), WGPUInstanceFlag_Default,
                                    WGPUDx12Compiler_Undefined,
                                    WGPUGles3MinorVersion_Automatic,
                                    _EMPTY_SV, _EMPTY_SV))
    desc = Ref(WGPUInstanceDescriptor(
        Ptr{WGPUChainedStruct}(Base.unsafe_convert(Ptr{WGPUInstanceExtras}, extras)),
        WGPUInstanceCapabilities(C_NULL, 0, 0)))
    inst = GC.@preserve extras desc wgpuCreateInstance(desc)
    inst == C_NULL && error("wgpuCreateInstance returned NULL: no $(_instance_backends() == WGPUInstanceBackend_Vulkan ? "Vulkan" : "native") backend could be initialised")
    return inst
end

_adapter_kind(t) = t == WGPUAdapterType_DiscreteGPU   ? :discrete :
                   t == WGPUAdapterType_IntegratedGPU ? :integrated :
                   t == WGPUAdapterType_CPU           ? :cpu : :unknown
_backend_name(b) = b == WGPUBackendType_Vulkan ? :vulkan :
                   b == WGPUBackendType_Metal  ? :metal :
                   b == WGPUBackendType_D3D12  ? :dx12 :
                   b == WGPUBackendType_OpenGL ? :opengl : :other

"Identity of one adapter, as Julia values (the C members freed here)."
function _adapter_info(adapter::WGPUAdapter)
    info = Ref(WGPUAdapterInfo(C_NULL, _EMPTY_SV, _EMPTY_SV, _EMPTY_SV, _EMPTY_SV, 0, 0, 0, 0))
    wgpuAdapterGetInfo(adapter, info)
    i = info[]
    out = (vendor = _sv_string(i.vendor), architecture = _sv_string(i.architecture),
           device = _sv_string(i.device), description = _sv_string(i.description),
           backend = _backend_name(i.backendType), kind = _adapter_kind(i.adapterType),
           vendor_id = Int(i.vendorID), device_id = Int(i.deviceID))
    wgpuAdapterInfoFreeMembers(i)
    return out
end

"Every adapter of the instance, with its identity."
function _enumerate_adapters(inst::WGPUInstance)
    opts = Ref(WGPUInstanceEnumerateAdapterOptions(C_NULL, WGPUInstanceBackend_All))
    n = GC.@preserve opts wgpuInstanceEnumerateAdapters(inst, opts, C_NULL)
    ads = Vector{WGPUAdapter}(undef, n)
    n > 0 && (GC.@preserve opts ads wgpuInstanceEnumerateAdapters(inst, opts, ads))
    return ads, [_adapter_info(a) for a in ads]
end

"`JANIM_HEADLESS=1`: the CPU adapter."
_cpu_adapter_env() = get(ENV, "JANIM_HEADLESS", "") in ("1", "true")

"""
Which adapter, by the house rules: `JANIM_ADAPTER=<substring of the device
name>` first; then `JANIM_HEADLESS=1` → the CPU adapter (lavapipe); otherwise
the first discrete GPU, then the first integrated one, then anything that is
not the CPU, and the CPU last (a build machine with no GPU at all). Returns
the index into `infos`, or throws with the list it saw.
"""
function _choose_adapter(infos)
    seen = join(["$(i.device) [$(i.kind), $(i.backend)]" for i in infos], "; ")
    isempty(infos) && error("wgpu found no adapter at all (no Vulkan ICD? " *
                            "install mesa-vulkan-drivers, which brings lavapipe)")
    want = get(ENV, "JANIM_ADAPTER", "")
    if !isempty(want)
        k = findfirst(i -> occursin(lowercase(want), lowercase(i.device)), infos)
        k === nothing && error("JANIM_ADAPTER=$(repr(want)) matches none of: $seen")
        return k
    end
    if _cpu_adapter_env()
        k = findfirst(i -> i.kind == :cpu, infos)
        k === nothing && error("JANIM_HEADLESS=1 asks for the CPU adapter (lavapipe) " *
                               "and this machine exposes none; adapters: $seen")
        return k
    end
    for kind in (:discrete, :integrated)
        k = findfirst(i -> i.kind == kind, infos)
        k === nothing || return k
    end
    k = findfirst(i -> i.kind != :cpu, infos)
    return k === nothing ? 1 : k
end

# The reply of a request callback (adapter, device, pop, map): status,
# handle and message, written by the callback and read right after the
# call. Rooted by the caller; passed as userdata1 by address.
mutable struct _Reply
    status::UInt32
    handle::Ptr{Cvoid}
    fired::Bool
    len::Int
    buf::Vector{UInt8}
    _Reply() = new(0, C_NULL, false, 0, zeros(UInt8, _MAILBOX_BYTES))
end

@inline function _reply_post!(r::_Reply, status::Integer, handle::Ptr{Cvoid}, sv::WGPUStringView)
    r.status = UInt32(status)
    r.handle = handle
    n = min(_sv_length(sv), _MAILBOX_BYTES)
    n > 0 && unsafe_copyto!(pointer(r.buf), Ptr{UInt8}(sv.data), n)
    r.len = n
    r.fired = true
    return nothing
end
_reply_message(r::_Reply) = String(r.buf[1:r.len])

function _on_request_adapter(status::WGPURequestAdapterStatus, adapter::WGPUAdapter,
                             message::WGPUStringView, ud1::Ptr{Cvoid}, ::Ptr{Cvoid})
    _reply_post!(unsafe_pointer_to_objref(ud1)::_Reply, status, Ptr{Cvoid}(adapter), message)
    return nothing
end

function _on_request_device(status::WGPURequestDeviceStatus, device::WGPUDevice,
                            message::WGPUStringView, ud1::Ptr{Cvoid}, ::Ptr{Cvoid})
    _reply_post!(unsafe_pointer_to_objref(ud1)::_Reply, status, Ptr{Cvoid}(device), message)
    return nothing
end

const _DEVICE_LABEL = "Janim device"

"""
The limits to ask the device for: WebGPU's defaults everywhere (every field
at its `UNDEFINED` sentinel) except the two offset alignments, which are
asked for at the ADAPTER's value. A device created without asking gets the
spec's defaults — 256 for `minUniformBufferOffsetAlignment` — whatever the
adapter can do; common adapters do 32, and the mobject arena (a block per
run, 64 bytes, rounded up to this) is eight times smaller for it. Read from
the adapter, never assumed.
"""
function _required_limits(adapter::WGPUAdapter)
    have = Ref(WGPULimits(C_NULL, ntuple(_ -> 0, fieldcount(WGPULimits) - 1)...))
    st = GC.@preserve have wgpuAdapterGetLimits(adapter, have)
    vals = Any[WGPU_LIMIT_U32_UNDEFINED for _ in 2:fieldcount(WGPULimits)]
    for (k, name) in enumerate(fieldnames(WGPULimits))
        k == 1 && continue
        fieldtype(WGPULimits, k) == UInt64 && (vals[k - 1] = WGPU_LIMIT_U64_UNDEFINED)
        if st == WGPUStatus_Success && name in (:minUniformBufferOffsetAlignment,
                                                 :minStorageBufferOffsetAlignment)
            vals[k - 1] = getfield(have[], name)
        end
    end
    return WGPULimits(C_NULL, vals...)
end

"""
The optional feature the renderer asks the device for, when the adapter has
it: `float32-filterable` — the gradient's `rgba32float` ramp is sampled
LINEAR (records.jl's `_ensure_ramp!`). A device created without asking does
not have it, whatever the adapter can do — the same holds for the limits.
"""
const _OPTIONAL_FEATURES = (WGPUFeatureName_Float32Filterable => :float32_filterable,)

"A device on `adapter`, with the error mailboxes wired into its descriptor and the optional features it has."
function _request_device(adapter::WGPUAdapter, errors::_Mailbox, lost::_Mailbox)
    reply = _Reply()
    limits = Ref(_required_limits(adapter))
    features = WGPUFeatureName[f for (f, _) in _OPTIONAL_FEATURES if wgpuAdapterHasFeature(adapter, f) != 0]
    desc = Ref(WGPUDeviceDescriptor(
        C_NULL, WGPUStringView(pointer(_DEVICE_LABEL), sizeof(_DEVICE_LABEL)),
        length(features), isempty(features) ? C_NULL : pointer(features),
        Base.unsafe_convert(Ptr{WGPULimits}, limits),
        WGPUQueueDescriptor(C_NULL, _EMPTY_SV),
        WGPUDeviceLostCallbackInfo(C_NULL, WGPUCallbackMode_AllowSpontaneous,
            @cfunction(_on_device_lost, Cvoid,
                       (Ptr{WGPUDevice}, WGPUDeviceLostReason, WGPUStringView, Ptr{Cvoid}, Ptr{Cvoid})),
            pointer_from_objref(lost), C_NULL),
        WGPUUncapturedErrorCallbackInfo(C_NULL,
            @cfunction(_on_uncaptured_error, Cvoid,
                       (Ptr{WGPUDevice}, WGPUErrorType, WGPUStringView, Ptr{Cvoid}, Ptr{Cvoid})),
            pointer_from_objref(errors), C_NULL)))
    cbi = WGPURequestDeviceCallbackInfo(C_NULL, WGPUCallbackMode_AllowProcessEvents,
        @cfunction(_on_request_device, Cvoid,
                   (WGPURequestDeviceStatus, WGPUDevice, WGPUStringView, Ptr{Cvoid}, Ptr{Cvoid})),
        pointer_from_objref(reply), C_NULL)
    GC.@preserve reply desc limits features errors lost wgpuAdapterRequestDevice(adapter, desc, cbi)
    # wgpu-native invokes the callback INSIDE the call (`wgpuInstanceProcessEvents`,
    # the spec's way to pump it, is one of the 32 functions that abort).
    reply.fired || error("wgpuAdapterRequestDevice did not invoke its callback synchronously — this wgpu-native is not the v24 the bindings were written against")
    reply.status == WGPURequestDeviceStatus_Success ||
        error("wgpuAdapterRequestDevice failed (status $(reply.status)): $(_reply_message(reply))")
    return WGPUDevice(reply.handle)
end

"""
    create_gpu() → GPU

Instance, adapter and device, no window. The adapter is chosen by the
rules of `_choose_adapter` (`JANIM_HEADLESS=1` → CPU; else the discrete GPU;
`JANIM_ADAPTER` overrides); the device carries the error mailboxes. Costs
about 40 ms on this machine (instance 25, adapters 16), plus the device.
"""
function create_gpu()
    _ensure_wgpu!()
    inst = _create_instance()
    ads, infos = _enumerate_adapters(inst)
    k = try
        _choose_adapter(infos)
    catch
        foreach(wgpuAdapterRelease, ads)
        wgpuInstanceRelease(inst)
        rethrow()
    end
    for (j, a) in enumerate(ads)
        j == k || wgpuAdapterRelease(a)
    end
    errors, lost = _Mailbox(), _Mailbox()
    device = try
        _request_device(ads[k], errors, lost)
    catch
        wgpuAdapterRelease(ads[k])
        wgpuInstanceRelease(inst)
        rethrow()
    end
    features = Symbol[name for (f, name) in _OPTIONAL_FEATURES if wgpuDeviceHasFeature(device, f) != 0]
    gpu = GPU(inst, ads[k], device, wgpuDeviceGetQueue(device), infos[k], features, errors, lost, false, false)
    finalizer(close_gpu!, gpu)
    return gpu
end

"""
    close_gpu!(gpu)

Release the queue, the device, the adapter and the instance, in that order.
Idempotent; also the finalizer, for a GPU that was dropped without it.
"""
function close_gpu!(gpu::GPU)
    gpu.closed && return nothing
    gpu.closed = true
    wgpuQueueRelease(gpu.queue)
    wgpuDeviceRelease(gpu.device)
    wgpuAdapterRelease(gpu.adapter)
    wgpuInstanceRelease(gpu.instance)
    return nothing
end

# ── errors as exceptions ────────────────────────────────────────────────

"""
    _check_gpu_errors!(gpu)

Read the device's mailboxes and throw what they hold: `GPUDeviceLostError`
if the device is gone (a `Destroyed` is our own `close_gpu!` and not an
error), else `GPUValidationError` with the first uncaptured message and how
many more there were. Called at the coarse seams — after a submit, before a
readback — so that a mistake surfaces within the frame that made it.
"""
function _check_gpu_errors!(gpu::GPU)
    if gpu.lost.count[] > 0
        n, reason, msg = _mailbox_take!(gpu.lost)
        if reason != Int(WGPUDeviceLostReason_Destroyed)
            gpu.dead = true          # the shared GPU replaces a dead one
            throw(GPUDeviceLostError(UInt32(reason), msg))
        end
    end
    if gpu.errors.count[] > 0
        n, kind, msg = _mailbox_take!(gpu.errors)
        more = n > 1 ? " (+$(n - 1) more since the last check)" : ""
        throw(GPUValidationError(msg * more))
    end
    return nothing
end

function _on_pop_error_scope(status::WGPUPopErrorScopeStatus, etype::WGPUErrorType,
                             message::WGPUStringView, ud1::Ptr{Cvoid}, ::Ptr{Cvoid})
    _reply_post!(unsafe_pointer_to_objref(ud1)::_Reply, etype, Ptr{Cvoid}(UInt(status)), message)
    return nothing
end

"""
    _error_scope(f, gpu) → f()

Run `f` between a `PushErrorScope(Validation)` and its pop, and throw a
`GPUValidationError` carrying the library's message if anything inside
failed validation — attributed to THIS call, which is what makes a broken
WGSL source say where it is broken instead of being a NULL handle. The
scope also keeps that error out of the uncaptured mailbox.
"""
function _error_scope(f, gpu::GPU)
    wgpuDevicePushErrorScope(gpu.device, WGPUErrorFilter_Validation)
    result = try
        f()
    catch
        _pop_error_scope(gpu)      # keep the stack balanced, drop its message
        rethrow()
    end
    kind, msg = _pop_error_scope(gpu)
    kind == Int(WGPUErrorType_NoError) || throw(GPUValidationError(msg))
    return result
end

function _pop_error_scope(gpu::GPU)
    reply = _Reply()
    cbi = WGPUPopErrorScopeCallbackInfo(C_NULL, WGPUCallbackMode_AllowProcessEvents,
        @cfunction(_on_pop_error_scope, Cvoid,
                   (WGPUPopErrorScopeStatus, WGPUErrorType, WGPUStringView, Ptr{Cvoid}, Ptr{Cvoid})),
        pointer_from_objref(reply), C_NULL)
    GC.@preserve reply wgpuDevicePopErrorScope(gpu.device, cbi)
    reply.fired || error("wgpuDevicePopErrorScope did not invoke its callback synchronously")
    return (Int(reply.status), _reply_message(reply))
end

# ── waiting ─────────────────────────────────────────────────────────────

"""
Block until the queue's work up to `index` is done (every submission so far
when `nothing`), and let the callbacks of the maps that completed fire.
This is THE way to wait on wgpu-native v24: `wgpuInstanceProcessEvents` and
`wgpuInstanceWaitAny` are unimplemented and abort the process.
"""
function _wait_gpu!(gpu::GPU, index::Union{Nothing, UInt64} = nothing)
    if index === nothing
        wgpuDevicePoll(gpu.device, WGPUBool(1), C_NULL)
    else
        r = Ref{WGPUSubmissionIndex}(index)
        GC.@preserve r wgpuDevicePoll(gpu.device, WGPUBool(1), r)
    end
    return nothing
end

"Submit one command buffer and return its submission index."
function _submit!(gpu::GPU, cmd::WGPUCommandBuffer)
    cmds = Ref(cmd)
    idx = GC.@preserve cmds wgpuQueueSubmitForIndex(gpu.queue, 1, cmds)
    wgpuCommandBufferRelease(cmd)
    return UInt64(idx)
end

# ── the driver identity ─────────────────────────────────────────────────

"""
The file-name key for a wgpu adapter: the driver's short name as the adapter
reports it (`radv`, `llvmpipe`, `apple`, `nvidia`…), lowercased and stripped
to alphanumerics; the device name's first word when the driver gives none.
"""
function driver_slug_wgpu(info)
    v = lowercase(replace(info.vendor, r"[^A-Za-z0-9]" => ""))
    isempty(v) || return v
    w = lowercase(replace(first(split(strip(info.device * " "))), r"[^A-Za-z0-9]" => ""))
    return isempty(w) ? "unknown" : w
end

"""
    gpu_info() → (renderer, slug, backend, version, kind)

Driver identity, by the same adapter rules as `create_gpu` but
WITHOUT a device (an instance and an enumeration: ~40 ms), so callers can ask
before opening their own. `version` is the
driver's own description — `Mesa 26.1.8`, `Mesa 26.1.8 (LLVM 22.1.8)` — and
falls back to the architecture, then to `unknown`, when a driver leaves it
empty (none of Mesa's does; the fallback exists so the header never lies by
omission without saying so).
"""
function gpu_info()
    _ensure_wgpu!()
    inst = _create_instance()
    ads, infos = _enumerate_adapters(inst)
    try
        return gpu_info(infos[_choose_adapter(infos)])
    finally
        foreach(wgpuAdapterRelease, ads)
        wgpuInstanceRelease(inst)
    end
end

gpu_info(gpu::GPU) = gpu_info(gpu.info)

function gpu_info(info::NamedTuple)
    version = !isempty(info.description) ? info.description :
              !isempty(info.architecture) ? info.architecture : "unknown"
    return (renderer = info.device, slug = driver_slug_wgpu(info),
            backend = String(info.backend), version = version, kind = info.kind)
end

"""
The driver line for per-driver reference files: three fields,
`# driver: radv · vulkan · Mesa 26.1.8`. The backend is cheap information
(the same GPU through two graphics APIs is two drivers), and the version is
the driver's, LLVM included when it says so.
"""
driver_header(info) = string("# driver: ", info.slug, " · ", info.backend, " · ", info.version)
