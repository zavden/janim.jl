# backend/wgpu/bindings.jl — the C surface of wgpu-native v24.0.0.1 that Janim
# calls. Generated (do not edit by hand).
#
# Lifted from WGPUNative.jl 0.1.5's LibWGPU.jl (Clang.jl over the very
# `webgpu.h` / `wgpu.h` shipped in the artifact) and cut down to a whitelist:
# 89 functions — none of the 32 that are `unimplemented!()` in v24 and abort
# the process — with the structs, handles and enums they reach. Enums are
# `UInt32` aliases with `const` members; flags are `UInt64`.
# The library comes from `Artifacts.toml`, is resolved at precompile time and
# opened at the FIRST call: `using Janim` never loads it. Every struct's size
# and field offsets match the C compiler's reading of the headers.

using Artifacts

const libwgpu_native = joinpath(artifact"wgpu_native", "lib",
                                Sys.iswindows() ? "wgpu_native.dll" :
                                Sys.isapple()   ? "libwgpu_native.dylib" :
                                                  "libwgpu_native.so")

# The header's sentinels, with SIZE_MAX as the 64-bit value it is here
# (WGPUNative.jl has `SIZE_MAX = 2^32`, which would be wrong on 64 bits).
const WGPU_STRLEN = typemax(Csize_t)
const WGPU_WHOLE_MAP_SIZE = typemax(Csize_t)
const WGPU_WHOLE_SIZE = typemax(UInt64)
const WGPU_LIMIT_U64_UNDEFINED = typemax(UInt64)
const WGPU_LIMIT_U32_UNDEFINED = typemax(UInt32)
const WGPU_DEPTH_SLICE_UNDEFINED = typemax(UInt32)
const WGPU_COPY_STRIDE_UNDEFINED = typemax(UInt32)
const WGPU_MIP_LEVEL_COUNT_UNDEFINED = typemax(UInt32)
const WGPU_ARRAY_LAYER_COUNT_UNDEFINED = typemax(UInt32)
const WGPU_QUERY_SET_INDEX_UNDEFINED = typemax(UInt32)

const WGPUFlags = UInt64

const WGPUBufferUsage = WGPUFlags
const WGPUBufferUsage_None = WGPUBufferUsage(0x0000000000000000)
const WGPUBufferUsage_MapRead = WGPUBufferUsage(0x0000000000000001)
const WGPUBufferUsage_MapWrite = WGPUBufferUsage(0x0000000000000002)
const WGPUBufferUsage_CopySrc = WGPUBufferUsage(0x0000000000000004)
const WGPUBufferUsage_CopyDst = WGPUBufferUsage(0x0000000000000008)
const WGPUBufferUsage_Index = WGPUBufferUsage(0x0000000000000010)
const WGPUBufferUsage_Vertex = WGPUBufferUsage(0x0000000000000020)
const WGPUBufferUsage_Uniform = WGPUBufferUsage(0x0000000000000040)
const WGPUBufferUsage_Storage = WGPUBufferUsage(0x0000000000000080)
const WGPUBufferUsage_Indirect = WGPUBufferUsage(0x0000000000000100)
const WGPUBufferUsage_QueryResolve = WGPUBufferUsage(0x0000000000000200)

const WGPUColorWriteMask = WGPUFlags
const WGPUColorWriteMask_None = WGPUColorWriteMask(0x0000000000000000)
const WGPUColorWriteMask_Red = WGPUColorWriteMask(0x0000000000000001)
const WGPUColorWriteMask_Green = WGPUColorWriteMask(0x0000000000000002)
const WGPUColorWriteMask_Blue = WGPUColorWriteMask(0x0000000000000004)
const WGPUColorWriteMask_Alpha = WGPUColorWriteMask(0x0000000000000008)
const WGPUColorWriteMask_All = WGPUColorWriteMask(0x000000000000000F)

const WGPUMapMode = WGPUFlags
const WGPUMapMode_None = WGPUMapMode(0x0000000000000000)
const WGPUMapMode_Read = WGPUMapMode(0x0000000000000001)
const WGPUMapMode_Write = WGPUMapMode(0x0000000000000002)

const WGPUShaderStage = WGPUFlags
const WGPUShaderStage_None = WGPUShaderStage(0x0000000000000000)
const WGPUShaderStage_Vertex = WGPUShaderStage(0x0000000000000001)
const WGPUShaderStage_Fragment = WGPUShaderStage(0x0000000000000002)
const WGPUShaderStage_Compute = WGPUShaderStage(0x0000000000000004)

const WGPUTextureUsage = WGPUFlags
const WGPUTextureUsage_None = WGPUTextureUsage(0x0000000000000000)
const WGPUTextureUsage_CopySrc = WGPUTextureUsage(0x0000000000000001)
const WGPUTextureUsage_CopyDst = WGPUTextureUsage(0x0000000000000002)
const WGPUTextureUsage_TextureBinding = WGPUTextureUsage(0x0000000000000004)
const WGPUTextureUsage_StorageBinding = WGPUTextureUsage(0x0000000000000008)
const WGPUTextureUsage_RenderAttachment = WGPUTextureUsage(0x0000000000000010)

struct WGPUStringView
    data::Ptr{Cchar}
    length::Csize_t
end

const WGPUBool = UInt32

mutable struct WGPUAdapterImpl end

const WGPUAdapter = Ptr{WGPUAdapterImpl}

mutable struct WGPUBindGroupImpl end

const WGPUBindGroup = Ptr{WGPUBindGroupImpl}

mutable struct WGPUBindGroupLayoutImpl end

const WGPUBindGroupLayout = Ptr{WGPUBindGroupLayoutImpl}

mutable struct WGPUBufferImpl end

const WGPUBuffer = Ptr{WGPUBufferImpl}

mutable struct WGPUCommandBufferImpl end

const WGPUCommandBuffer = Ptr{WGPUCommandBufferImpl}

mutable struct WGPUCommandEncoderImpl end

const WGPUCommandEncoder = Ptr{WGPUCommandEncoderImpl}

mutable struct WGPUDeviceImpl end

const WGPUDevice = Ptr{WGPUDeviceImpl}

mutable struct WGPUInstanceImpl end

const WGPUInstance = Ptr{WGPUInstanceImpl}

mutable struct WGPUPipelineLayoutImpl end

const WGPUPipelineLayout = Ptr{WGPUPipelineLayoutImpl}

mutable struct WGPUQuerySetImpl end

const WGPUQuerySet = Ptr{WGPUQuerySetImpl}

mutable struct WGPUQueueImpl end

const WGPUQueue = Ptr{WGPUQueueImpl}

mutable struct WGPURenderPassEncoderImpl end

const WGPURenderPassEncoder = Ptr{WGPURenderPassEncoderImpl}

mutable struct WGPURenderPipelineImpl end

const WGPURenderPipeline = Ptr{WGPURenderPipelineImpl}

mutable struct WGPUSamplerImpl end

const WGPUSampler = Ptr{WGPUSamplerImpl}

mutable struct WGPUShaderModuleImpl end

const WGPUShaderModule = Ptr{WGPUShaderModuleImpl}

mutable struct WGPUSurfaceImpl end

const WGPUSurface = Ptr{WGPUSurfaceImpl}

mutable struct WGPUTextureImpl end

const WGPUTexture = Ptr{WGPUTextureImpl}

mutable struct WGPUTextureViewImpl end

const WGPUTextureView = Ptr{WGPUTextureViewImpl}

const WGPUAdapterType = UInt32
const WGPUAdapterType_DiscreteGPU = WGPUAdapterType(1)
const WGPUAdapterType_IntegratedGPU = WGPUAdapterType(2)
const WGPUAdapterType_CPU = WGPUAdapterType(3)
const WGPUAdapterType_Unknown = WGPUAdapterType(4)

const WGPUAddressMode = UInt32
const WGPUAddressMode_Undefined = WGPUAddressMode(0)
const WGPUAddressMode_ClampToEdge = WGPUAddressMode(1)
const WGPUAddressMode_Repeat = WGPUAddressMode(2)
const WGPUAddressMode_MirrorRepeat = WGPUAddressMode(3)

const WGPUBackendType = UInt32
const WGPUBackendType_Undefined = WGPUBackendType(0)
const WGPUBackendType_Null = WGPUBackendType(1)
const WGPUBackendType_WebGPU = WGPUBackendType(2)
const WGPUBackendType_D3D11 = WGPUBackendType(3)
const WGPUBackendType_D3D12 = WGPUBackendType(4)
const WGPUBackendType_Metal = WGPUBackendType(5)
const WGPUBackendType_Vulkan = WGPUBackendType(6)
const WGPUBackendType_OpenGL = WGPUBackendType(7)
const WGPUBackendType_OpenGLES = WGPUBackendType(8)

const WGPUBlendFactor = UInt32
const WGPUBlendFactor_Undefined = WGPUBlendFactor(0)
const WGPUBlendFactor_Zero = WGPUBlendFactor(1)
const WGPUBlendFactor_One = WGPUBlendFactor(2)
const WGPUBlendFactor_Src = WGPUBlendFactor(3)
const WGPUBlendFactor_OneMinusSrc = WGPUBlendFactor(4)
const WGPUBlendFactor_SrcAlpha = WGPUBlendFactor(5)
const WGPUBlendFactor_OneMinusSrcAlpha = WGPUBlendFactor(6)
const WGPUBlendFactor_Dst = WGPUBlendFactor(7)
const WGPUBlendFactor_OneMinusDst = WGPUBlendFactor(8)
const WGPUBlendFactor_DstAlpha = WGPUBlendFactor(9)
const WGPUBlendFactor_OneMinusDstAlpha = WGPUBlendFactor(10)
const WGPUBlendFactor_SrcAlphaSaturated = WGPUBlendFactor(11)
const WGPUBlendFactor_Constant = WGPUBlendFactor(12)
const WGPUBlendFactor_OneMinusConstant = WGPUBlendFactor(13)
const WGPUBlendFactor_Src1 = WGPUBlendFactor(14)
const WGPUBlendFactor_OneMinusSrc1 = WGPUBlendFactor(15)
const WGPUBlendFactor_Src1Alpha = WGPUBlendFactor(16)
const WGPUBlendFactor_OneMinusSrc1Alpha = WGPUBlendFactor(17)

const WGPUBlendOperation = UInt32
const WGPUBlendOperation_Undefined = WGPUBlendOperation(0)
const WGPUBlendOperation_Add = WGPUBlendOperation(1)
const WGPUBlendOperation_Subtract = WGPUBlendOperation(2)
const WGPUBlendOperation_ReverseSubtract = WGPUBlendOperation(3)
const WGPUBlendOperation_Min = WGPUBlendOperation(4)
const WGPUBlendOperation_Max = WGPUBlendOperation(5)

const WGPUBufferBindingType = UInt32
const WGPUBufferBindingType_BindingNotUsed = WGPUBufferBindingType(0)
const WGPUBufferBindingType_Undefined = WGPUBufferBindingType(1)
const WGPUBufferBindingType_Uniform = WGPUBufferBindingType(2)
const WGPUBufferBindingType_Storage = WGPUBufferBindingType(3)
const WGPUBufferBindingType_ReadOnlyStorage = WGPUBufferBindingType(4)

const WGPUCallbackMode = UInt32
const WGPUCallbackMode_WaitAnyOnly = WGPUCallbackMode(1)
const WGPUCallbackMode_AllowProcessEvents = WGPUCallbackMode(2)
const WGPUCallbackMode_AllowSpontaneous = WGPUCallbackMode(3)

const WGPUCompareFunction = UInt32
const WGPUCompareFunction_Undefined = WGPUCompareFunction(0)
const WGPUCompareFunction_Never = WGPUCompareFunction(1)
const WGPUCompareFunction_Less = WGPUCompareFunction(2)
const WGPUCompareFunction_Equal = WGPUCompareFunction(3)
const WGPUCompareFunction_LessEqual = WGPUCompareFunction(4)
const WGPUCompareFunction_Greater = WGPUCompareFunction(5)
const WGPUCompareFunction_NotEqual = WGPUCompareFunction(6)
const WGPUCompareFunction_GreaterEqual = WGPUCompareFunction(7)
const WGPUCompareFunction_Always = WGPUCompareFunction(8)

const WGPUCompositeAlphaMode = UInt32
const WGPUCompositeAlphaMode_Auto = WGPUCompositeAlphaMode(0)
const WGPUCompositeAlphaMode_Opaque = WGPUCompositeAlphaMode(1)
const WGPUCompositeAlphaMode_Premultiplied = WGPUCompositeAlphaMode(2)
const WGPUCompositeAlphaMode_Unpremultiplied = WGPUCompositeAlphaMode(3)
const WGPUCompositeAlphaMode_Inherit = WGPUCompositeAlphaMode(4)

const WGPUCullMode = UInt32
const WGPUCullMode_Undefined = WGPUCullMode(0)
const WGPUCullMode_None = WGPUCullMode(1)
const WGPUCullMode_Front = WGPUCullMode(2)
const WGPUCullMode_Back = WGPUCullMode(3)

const WGPUDeviceLostReason = UInt32
const WGPUDeviceLostReason_Unknown = WGPUDeviceLostReason(1)
const WGPUDeviceLostReason_Destroyed = WGPUDeviceLostReason(2)
const WGPUDeviceLostReason_InstanceDropped = WGPUDeviceLostReason(3)
const WGPUDeviceLostReason_FailedCreation = WGPUDeviceLostReason(4)

const WGPUErrorFilter = UInt32
const WGPUErrorFilter_Validation = WGPUErrorFilter(1)
const WGPUErrorFilter_OutOfMemory = WGPUErrorFilter(2)
const WGPUErrorFilter_Internal = WGPUErrorFilter(3)

const WGPUErrorType = UInt32
const WGPUErrorType_NoError = WGPUErrorType(1)
const WGPUErrorType_Validation = WGPUErrorType(2)
const WGPUErrorType_OutOfMemory = WGPUErrorType(3)
const WGPUErrorType_Internal = WGPUErrorType(4)
const WGPUErrorType_Unknown = WGPUErrorType(5)

const WGPUFeatureLevel = UInt32
const WGPUFeatureLevel_Compatibility = WGPUFeatureLevel(1)
const WGPUFeatureLevel_Core = WGPUFeatureLevel(2)

const WGPUFeatureName = UInt32
const WGPUFeatureName_Undefined = WGPUFeatureName(0)
const WGPUFeatureName_DepthClipControl = WGPUFeatureName(1)
const WGPUFeatureName_Depth32FloatStencil8 = WGPUFeatureName(2)
const WGPUFeatureName_TimestampQuery = WGPUFeatureName(3)
const WGPUFeatureName_TextureCompressionBC = WGPUFeatureName(4)
const WGPUFeatureName_TextureCompressionBCSliced3D = WGPUFeatureName(5)
const WGPUFeatureName_TextureCompressionETC2 = WGPUFeatureName(6)
const WGPUFeatureName_TextureCompressionASTC = WGPUFeatureName(7)
const WGPUFeatureName_TextureCompressionASTCSliced3D = WGPUFeatureName(8)
const WGPUFeatureName_IndirectFirstInstance = WGPUFeatureName(9)
const WGPUFeatureName_ShaderF16 = WGPUFeatureName(10)
const WGPUFeatureName_RG11B10UfloatRenderable = WGPUFeatureName(11)
const WGPUFeatureName_BGRA8UnormStorage = WGPUFeatureName(12)
const WGPUFeatureName_Float32Filterable = WGPUFeatureName(13)
const WGPUFeatureName_Float32Blendable = WGPUFeatureName(14)
const WGPUFeatureName_ClipDistances = WGPUFeatureName(15)
const WGPUFeatureName_DualSourceBlending = WGPUFeatureName(16)

const WGPUFilterMode = UInt32
const WGPUFilterMode_Undefined = WGPUFilterMode(0)
const WGPUFilterMode_Nearest = WGPUFilterMode(1)
const WGPUFilterMode_Linear = WGPUFilterMode(2)

const WGPUFrontFace = UInt32
const WGPUFrontFace_Undefined = WGPUFrontFace(0)
const WGPUFrontFace_CCW = WGPUFrontFace(1)
const WGPUFrontFace_CW = WGPUFrontFace(2)

const WGPUIndexFormat = UInt32
const WGPUIndexFormat_Undefined = WGPUIndexFormat(0)
const WGPUIndexFormat_Uint16 = WGPUIndexFormat(1)
const WGPUIndexFormat_Uint32 = WGPUIndexFormat(2)

const WGPULoadOp = UInt32
const WGPULoadOp_Undefined = WGPULoadOp(0)
const WGPULoadOp_Load = WGPULoadOp(1)
const WGPULoadOp_Clear = WGPULoadOp(2)

const WGPUMapAsyncStatus = UInt32
const WGPUMapAsyncStatus_Success = WGPUMapAsyncStatus(1)
const WGPUMapAsyncStatus_InstanceDropped = WGPUMapAsyncStatus(2)
const WGPUMapAsyncStatus_Error = WGPUMapAsyncStatus(3)
const WGPUMapAsyncStatus_Aborted = WGPUMapAsyncStatus(4)
const WGPUMapAsyncStatus_Unknown = WGPUMapAsyncStatus(5)

const WGPUMipmapFilterMode = UInt32
const WGPUMipmapFilterMode_Undefined = WGPUMipmapFilterMode(0)
const WGPUMipmapFilterMode_Nearest = WGPUMipmapFilterMode(1)
const WGPUMipmapFilterMode_Linear = WGPUMipmapFilterMode(2)

const WGPUOptionalBool = UInt32
const WGPUOptionalBool_False = WGPUOptionalBool(0)
const WGPUOptionalBool_True = WGPUOptionalBool(1)
const WGPUOptionalBool_Undefined = WGPUOptionalBool(2)

const WGPUPopErrorScopeStatus = UInt32
const WGPUPopErrorScopeStatus_Success = WGPUPopErrorScopeStatus(1)
const WGPUPopErrorScopeStatus_InstanceDropped = WGPUPopErrorScopeStatus(2)
const WGPUPopErrorScopeStatus_EmptyStack = WGPUPopErrorScopeStatus(3)

const WGPUPowerPreference = UInt32
const WGPUPowerPreference_Undefined = WGPUPowerPreference(0)
const WGPUPowerPreference_LowPower = WGPUPowerPreference(1)
const WGPUPowerPreference_HighPerformance = WGPUPowerPreference(2)

const WGPUPresentMode = UInt32
const WGPUPresentMode_Undefined = WGPUPresentMode(0)
const WGPUPresentMode_Fifo = WGPUPresentMode(1)
const WGPUPresentMode_FifoRelaxed = WGPUPresentMode(2)
const WGPUPresentMode_Immediate = WGPUPresentMode(3)
const WGPUPresentMode_Mailbox = WGPUPresentMode(4)

const WGPUPrimitiveTopology = UInt32
const WGPUPrimitiveTopology_Undefined = WGPUPrimitiveTopology(0)
const WGPUPrimitiveTopology_PointList = WGPUPrimitiveTopology(1)
const WGPUPrimitiveTopology_LineList = WGPUPrimitiveTopology(2)
const WGPUPrimitiveTopology_LineStrip = WGPUPrimitiveTopology(3)
const WGPUPrimitiveTopology_TriangleList = WGPUPrimitiveTopology(4)
const WGPUPrimitiveTopology_TriangleStrip = WGPUPrimitiveTopology(5)

const WGPUQueueWorkDoneStatus = UInt32
const WGPUQueueWorkDoneStatus_Success = WGPUQueueWorkDoneStatus(1)
const WGPUQueueWorkDoneStatus_InstanceDropped = WGPUQueueWorkDoneStatus(2)
const WGPUQueueWorkDoneStatus_Error = WGPUQueueWorkDoneStatus(3)
const WGPUQueueWorkDoneStatus_Unknown = WGPUQueueWorkDoneStatus(4)

const WGPURequestAdapterStatus = UInt32
const WGPURequestAdapterStatus_Success = WGPURequestAdapterStatus(1)
const WGPURequestAdapterStatus_InstanceDropped = WGPURequestAdapterStatus(2)
const WGPURequestAdapterStatus_Unavailable = WGPURequestAdapterStatus(3)
const WGPURequestAdapterStatus_Error = WGPURequestAdapterStatus(4)
const WGPURequestAdapterStatus_Unknown = WGPURequestAdapterStatus(5)

const WGPURequestDeviceStatus = UInt32
const WGPURequestDeviceStatus_Success = WGPURequestDeviceStatus(1)
const WGPURequestDeviceStatus_InstanceDropped = WGPURequestDeviceStatus(2)
const WGPURequestDeviceStatus_Error = WGPURequestDeviceStatus(3)
const WGPURequestDeviceStatus_Unknown = WGPURequestDeviceStatus(4)

const WGPUSType = UInt32
const WGPUSType_ShaderSourceSPIRV = WGPUSType(1)
const WGPUSType_ShaderSourceWGSL = WGPUSType(2)
const WGPUSType_RenderPassMaxDrawCount = WGPUSType(3)
const WGPUSType_SurfaceSourceMetalLayer = WGPUSType(4)
const WGPUSType_SurfaceSourceWindowsHWND = WGPUSType(5)
const WGPUSType_SurfaceSourceXlibWindow = WGPUSType(6)
const WGPUSType_SurfaceSourceWaylandSurface = WGPUSType(7)
const WGPUSType_SurfaceSourceAndroidNativeWindow = WGPUSType(8)
const WGPUSType_SurfaceSourceXCBWindow = WGPUSType(9)

const WGPUSamplerBindingType = UInt32
const WGPUSamplerBindingType_BindingNotUsed = WGPUSamplerBindingType(0)
const WGPUSamplerBindingType_Undefined = WGPUSamplerBindingType(1)
const WGPUSamplerBindingType_Filtering = WGPUSamplerBindingType(2)
const WGPUSamplerBindingType_NonFiltering = WGPUSamplerBindingType(3)
const WGPUSamplerBindingType_Comparison = WGPUSamplerBindingType(4)

const WGPUStatus = UInt32
const WGPUStatus_Success = WGPUStatus(1)
const WGPUStatus_Error = WGPUStatus(2)

const WGPUStencilOperation = UInt32
const WGPUStencilOperation_Undefined = WGPUStencilOperation(0)
const WGPUStencilOperation_Keep = WGPUStencilOperation(1)
const WGPUStencilOperation_Zero = WGPUStencilOperation(2)
const WGPUStencilOperation_Replace = WGPUStencilOperation(3)
const WGPUStencilOperation_Invert = WGPUStencilOperation(4)
const WGPUStencilOperation_IncrementClamp = WGPUStencilOperation(5)
const WGPUStencilOperation_DecrementClamp = WGPUStencilOperation(6)
const WGPUStencilOperation_IncrementWrap = WGPUStencilOperation(7)
const WGPUStencilOperation_DecrementWrap = WGPUStencilOperation(8)

const WGPUStorageTextureAccess = UInt32
const WGPUStorageTextureAccess_BindingNotUsed = WGPUStorageTextureAccess(0)
const WGPUStorageTextureAccess_Undefined = WGPUStorageTextureAccess(1)
const WGPUStorageTextureAccess_WriteOnly = WGPUStorageTextureAccess(2)
const WGPUStorageTextureAccess_ReadOnly = WGPUStorageTextureAccess(3)
const WGPUStorageTextureAccess_ReadWrite = WGPUStorageTextureAccess(4)

const WGPUStoreOp = UInt32
const WGPUStoreOp_Undefined = WGPUStoreOp(0)
const WGPUStoreOp_Store = WGPUStoreOp(1)
const WGPUStoreOp_Discard = WGPUStoreOp(2)

const WGPUSurfaceGetCurrentTextureStatus = UInt32
const WGPUSurfaceGetCurrentTextureStatus_SuccessOptimal = WGPUSurfaceGetCurrentTextureStatus(1)
const WGPUSurfaceGetCurrentTextureStatus_SuccessSuboptimal = WGPUSurfaceGetCurrentTextureStatus(2)
const WGPUSurfaceGetCurrentTextureStatus_Timeout = WGPUSurfaceGetCurrentTextureStatus(3)
const WGPUSurfaceGetCurrentTextureStatus_Outdated = WGPUSurfaceGetCurrentTextureStatus(4)
const WGPUSurfaceGetCurrentTextureStatus_Lost = WGPUSurfaceGetCurrentTextureStatus(5)
const WGPUSurfaceGetCurrentTextureStatus_OutOfMemory = WGPUSurfaceGetCurrentTextureStatus(6)
const WGPUSurfaceGetCurrentTextureStatus_DeviceLost = WGPUSurfaceGetCurrentTextureStatus(7)
const WGPUSurfaceGetCurrentTextureStatus_Error = WGPUSurfaceGetCurrentTextureStatus(8)

const WGPUTextureAspect = UInt32
const WGPUTextureAspect_Undefined = WGPUTextureAspect(0)
const WGPUTextureAspect_All = WGPUTextureAspect(1)
const WGPUTextureAspect_StencilOnly = WGPUTextureAspect(2)
const WGPUTextureAspect_DepthOnly = WGPUTextureAspect(3)

const WGPUTextureDimension = UInt32
const WGPUTextureDimension_Undefined = WGPUTextureDimension(0)
const WGPUTextureDimension_1D = WGPUTextureDimension(1)
const WGPUTextureDimension_2D = WGPUTextureDimension(2)
const WGPUTextureDimension_3D = WGPUTextureDimension(3)

const WGPUTextureFormat = UInt32
const WGPUTextureFormat_Undefined = WGPUTextureFormat(0)
const WGPUTextureFormat_R8Unorm = WGPUTextureFormat(1)
const WGPUTextureFormat_R8Snorm = WGPUTextureFormat(2)
const WGPUTextureFormat_R8Uint = WGPUTextureFormat(3)
const WGPUTextureFormat_R8Sint = WGPUTextureFormat(4)
const WGPUTextureFormat_R16Uint = WGPUTextureFormat(5)
const WGPUTextureFormat_R16Sint = WGPUTextureFormat(6)
const WGPUTextureFormat_R16Float = WGPUTextureFormat(7)
const WGPUTextureFormat_RG8Unorm = WGPUTextureFormat(8)
const WGPUTextureFormat_RG8Snorm = WGPUTextureFormat(9)
const WGPUTextureFormat_RG8Uint = WGPUTextureFormat(10)
const WGPUTextureFormat_RG8Sint = WGPUTextureFormat(11)
const WGPUTextureFormat_R32Float = WGPUTextureFormat(12)
const WGPUTextureFormat_R32Uint = WGPUTextureFormat(13)
const WGPUTextureFormat_R32Sint = WGPUTextureFormat(14)
const WGPUTextureFormat_RG16Uint = WGPUTextureFormat(15)
const WGPUTextureFormat_RG16Sint = WGPUTextureFormat(16)
const WGPUTextureFormat_RG16Float = WGPUTextureFormat(17)
const WGPUTextureFormat_RGBA8Unorm = WGPUTextureFormat(18)
const WGPUTextureFormat_RGBA8UnormSrgb = WGPUTextureFormat(19)
const WGPUTextureFormat_RGBA8Snorm = WGPUTextureFormat(20)
const WGPUTextureFormat_RGBA8Uint = WGPUTextureFormat(21)
const WGPUTextureFormat_RGBA8Sint = WGPUTextureFormat(22)
const WGPUTextureFormat_BGRA8Unorm = WGPUTextureFormat(23)
const WGPUTextureFormat_BGRA8UnormSrgb = WGPUTextureFormat(24)
const WGPUTextureFormat_RGB10A2Uint = WGPUTextureFormat(25)
const WGPUTextureFormat_RGB10A2Unorm = WGPUTextureFormat(26)
const WGPUTextureFormat_RG11B10Ufloat = WGPUTextureFormat(27)
const WGPUTextureFormat_RGB9E5Ufloat = WGPUTextureFormat(28)
const WGPUTextureFormat_RG32Float = WGPUTextureFormat(29)
const WGPUTextureFormat_RG32Uint = WGPUTextureFormat(30)
const WGPUTextureFormat_RG32Sint = WGPUTextureFormat(31)
const WGPUTextureFormat_RGBA16Uint = WGPUTextureFormat(32)
const WGPUTextureFormat_RGBA16Sint = WGPUTextureFormat(33)
const WGPUTextureFormat_RGBA16Float = WGPUTextureFormat(34)
const WGPUTextureFormat_RGBA32Float = WGPUTextureFormat(35)
const WGPUTextureFormat_RGBA32Uint = WGPUTextureFormat(36)
const WGPUTextureFormat_RGBA32Sint = WGPUTextureFormat(37)
const WGPUTextureFormat_Stencil8 = WGPUTextureFormat(38)
const WGPUTextureFormat_Depth16Unorm = WGPUTextureFormat(39)
const WGPUTextureFormat_Depth24Plus = WGPUTextureFormat(40)
const WGPUTextureFormat_Depth24PlusStencil8 = WGPUTextureFormat(41)
const WGPUTextureFormat_Depth32Float = WGPUTextureFormat(42)
const WGPUTextureFormat_Depth32FloatStencil8 = WGPUTextureFormat(43)
const WGPUTextureFormat_BC1RGBAUnorm = WGPUTextureFormat(44)
const WGPUTextureFormat_BC1RGBAUnormSrgb = WGPUTextureFormat(45)
const WGPUTextureFormat_BC2RGBAUnorm = WGPUTextureFormat(46)
const WGPUTextureFormat_BC2RGBAUnormSrgb = WGPUTextureFormat(47)
const WGPUTextureFormat_BC3RGBAUnorm = WGPUTextureFormat(48)
const WGPUTextureFormat_BC3RGBAUnormSrgb = WGPUTextureFormat(49)
const WGPUTextureFormat_BC4RUnorm = WGPUTextureFormat(50)
const WGPUTextureFormat_BC4RSnorm = WGPUTextureFormat(51)
const WGPUTextureFormat_BC5RGUnorm = WGPUTextureFormat(52)
const WGPUTextureFormat_BC5RGSnorm = WGPUTextureFormat(53)
const WGPUTextureFormat_BC6HRGBUfloat = WGPUTextureFormat(54)
const WGPUTextureFormat_BC6HRGBFloat = WGPUTextureFormat(55)
const WGPUTextureFormat_BC7RGBAUnorm = WGPUTextureFormat(56)
const WGPUTextureFormat_BC7RGBAUnormSrgb = WGPUTextureFormat(57)
const WGPUTextureFormat_ETC2RGB8Unorm = WGPUTextureFormat(58)
const WGPUTextureFormat_ETC2RGB8UnormSrgb = WGPUTextureFormat(59)
const WGPUTextureFormat_ETC2RGB8A1Unorm = WGPUTextureFormat(60)
const WGPUTextureFormat_ETC2RGB8A1UnormSrgb = WGPUTextureFormat(61)
const WGPUTextureFormat_ETC2RGBA8Unorm = WGPUTextureFormat(62)
const WGPUTextureFormat_ETC2RGBA8UnormSrgb = WGPUTextureFormat(63)
const WGPUTextureFormat_EACR11Unorm = WGPUTextureFormat(64)
const WGPUTextureFormat_EACR11Snorm = WGPUTextureFormat(65)
const WGPUTextureFormat_EACRG11Unorm = WGPUTextureFormat(66)
const WGPUTextureFormat_EACRG11Snorm = WGPUTextureFormat(67)
const WGPUTextureFormat_ASTC4x4Unorm = WGPUTextureFormat(68)
const WGPUTextureFormat_ASTC4x4UnormSrgb = WGPUTextureFormat(69)
const WGPUTextureFormat_ASTC5x4Unorm = WGPUTextureFormat(70)
const WGPUTextureFormat_ASTC5x4UnormSrgb = WGPUTextureFormat(71)
const WGPUTextureFormat_ASTC5x5Unorm = WGPUTextureFormat(72)
const WGPUTextureFormat_ASTC5x5UnormSrgb = WGPUTextureFormat(73)
const WGPUTextureFormat_ASTC6x5Unorm = WGPUTextureFormat(74)
const WGPUTextureFormat_ASTC6x5UnormSrgb = WGPUTextureFormat(75)
const WGPUTextureFormat_ASTC6x6Unorm = WGPUTextureFormat(76)
const WGPUTextureFormat_ASTC6x6UnormSrgb = WGPUTextureFormat(77)
const WGPUTextureFormat_ASTC8x5Unorm = WGPUTextureFormat(78)
const WGPUTextureFormat_ASTC8x5UnormSrgb = WGPUTextureFormat(79)
const WGPUTextureFormat_ASTC8x6Unorm = WGPUTextureFormat(80)
const WGPUTextureFormat_ASTC8x6UnormSrgb = WGPUTextureFormat(81)
const WGPUTextureFormat_ASTC8x8Unorm = WGPUTextureFormat(82)
const WGPUTextureFormat_ASTC8x8UnormSrgb = WGPUTextureFormat(83)
const WGPUTextureFormat_ASTC10x5Unorm = WGPUTextureFormat(84)
const WGPUTextureFormat_ASTC10x5UnormSrgb = WGPUTextureFormat(85)
const WGPUTextureFormat_ASTC10x6Unorm = WGPUTextureFormat(86)
const WGPUTextureFormat_ASTC10x6UnormSrgb = WGPUTextureFormat(87)
const WGPUTextureFormat_ASTC10x8Unorm = WGPUTextureFormat(88)
const WGPUTextureFormat_ASTC10x8UnormSrgb = WGPUTextureFormat(89)
const WGPUTextureFormat_ASTC10x10Unorm = WGPUTextureFormat(90)
const WGPUTextureFormat_ASTC10x10UnormSrgb = WGPUTextureFormat(91)
const WGPUTextureFormat_ASTC12x10Unorm = WGPUTextureFormat(92)
const WGPUTextureFormat_ASTC12x10UnormSrgb = WGPUTextureFormat(93)
const WGPUTextureFormat_ASTC12x12Unorm = WGPUTextureFormat(94)
const WGPUTextureFormat_ASTC12x12UnormSrgb = WGPUTextureFormat(95)

const WGPUTextureSampleType = UInt32
const WGPUTextureSampleType_BindingNotUsed = WGPUTextureSampleType(0)
const WGPUTextureSampleType_Undefined = WGPUTextureSampleType(1)
const WGPUTextureSampleType_Float = WGPUTextureSampleType(2)
const WGPUTextureSampleType_UnfilterableFloat = WGPUTextureSampleType(3)
const WGPUTextureSampleType_Depth = WGPUTextureSampleType(4)
const WGPUTextureSampleType_Sint = WGPUTextureSampleType(5)
const WGPUTextureSampleType_Uint = WGPUTextureSampleType(6)

const WGPUTextureViewDimension = UInt32
const WGPUTextureViewDimension_Undefined = WGPUTextureViewDimension(0)
const WGPUTextureViewDimension_1D = WGPUTextureViewDimension(1)
const WGPUTextureViewDimension_2D = WGPUTextureViewDimension(2)
const WGPUTextureViewDimension_2DArray = WGPUTextureViewDimension(3)
const WGPUTextureViewDimension_Cube = WGPUTextureViewDimension(4)
const WGPUTextureViewDimension_CubeArray = WGPUTextureViewDimension(5)
const WGPUTextureViewDimension_3D = WGPUTextureViewDimension(6)

const WGPUVertexFormat = UInt32
const WGPUVertexFormat_Uint8 = WGPUVertexFormat(1)
const WGPUVertexFormat_Uint8x2 = WGPUVertexFormat(2)
const WGPUVertexFormat_Uint8x4 = WGPUVertexFormat(3)
const WGPUVertexFormat_Sint8 = WGPUVertexFormat(4)
const WGPUVertexFormat_Sint8x2 = WGPUVertexFormat(5)
const WGPUVertexFormat_Sint8x4 = WGPUVertexFormat(6)
const WGPUVertexFormat_Unorm8 = WGPUVertexFormat(7)
const WGPUVertexFormat_Unorm8x2 = WGPUVertexFormat(8)
const WGPUVertexFormat_Unorm8x4 = WGPUVertexFormat(9)
const WGPUVertexFormat_Snorm8 = WGPUVertexFormat(10)
const WGPUVertexFormat_Snorm8x2 = WGPUVertexFormat(11)
const WGPUVertexFormat_Snorm8x4 = WGPUVertexFormat(12)
const WGPUVertexFormat_Uint16 = WGPUVertexFormat(13)
const WGPUVertexFormat_Uint16x2 = WGPUVertexFormat(14)
const WGPUVertexFormat_Uint16x4 = WGPUVertexFormat(15)
const WGPUVertexFormat_Sint16 = WGPUVertexFormat(16)
const WGPUVertexFormat_Sint16x2 = WGPUVertexFormat(17)
const WGPUVertexFormat_Sint16x4 = WGPUVertexFormat(18)
const WGPUVertexFormat_Unorm16 = WGPUVertexFormat(19)
const WGPUVertexFormat_Unorm16x2 = WGPUVertexFormat(20)
const WGPUVertexFormat_Unorm16x4 = WGPUVertexFormat(21)
const WGPUVertexFormat_Snorm16 = WGPUVertexFormat(22)
const WGPUVertexFormat_Snorm16x2 = WGPUVertexFormat(23)
const WGPUVertexFormat_Snorm16x4 = WGPUVertexFormat(24)
const WGPUVertexFormat_Float16 = WGPUVertexFormat(25)
const WGPUVertexFormat_Float16x2 = WGPUVertexFormat(26)
const WGPUVertexFormat_Float16x4 = WGPUVertexFormat(27)
const WGPUVertexFormat_Float32 = WGPUVertexFormat(28)
const WGPUVertexFormat_Float32x2 = WGPUVertexFormat(29)
const WGPUVertexFormat_Float32x3 = WGPUVertexFormat(30)
const WGPUVertexFormat_Float32x4 = WGPUVertexFormat(31)
const WGPUVertexFormat_Uint32 = WGPUVertexFormat(32)
const WGPUVertexFormat_Uint32x2 = WGPUVertexFormat(33)
const WGPUVertexFormat_Uint32x3 = WGPUVertexFormat(34)
const WGPUVertexFormat_Uint32x4 = WGPUVertexFormat(35)
const WGPUVertexFormat_Sint32 = WGPUVertexFormat(36)
const WGPUVertexFormat_Sint32x2 = WGPUVertexFormat(37)
const WGPUVertexFormat_Sint32x3 = WGPUVertexFormat(38)
const WGPUVertexFormat_Sint32x4 = WGPUVertexFormat(39)
const WGPUVertexFormat_Unorm10_10_10_2 = WGPUVertexFormat(40)
const WGPUVertexFormat_Unorm8x4BGRA = WGPUVertexFormat(41)

const WGPUVertexStepMode = UInt32
const WGPUVertexStepMode_VertexBufferNotUsed = WGPUVertexStepMode(0)
const WGPUVertexStepMode_Undefined = WGPUVertexStepMode(1)
const WGPUVertexStepMode_Vertex = WGPUVertexStepMode(2)
const WGPUVertexStepMode_Instance = WGPUVertexStepMode(3)

# typedef void ( * WGPUBufferMapCallback ) ( WGPUMapAsyncStatus status , WGPUStringView message , WGPU_NULLABLE void * userdata1 , WGPU_NULLABLE void * userdata2 )
const WGPUBufferMapCallback = Ptr{Cvoid}

# typedef void ( * WGPUDeviceLostCallback ) ( WGPUDevice const * device , WGPUDeviceLostReason reason , WGPUStringView message , WGPU_NULLABLE void * userdata1 , WGPU_NULLABLE void * userdata2 )
const WGPUDeviceLostCallback = Ptr{Cvoid}

# typedef void ( * WGPUPopErrorScopeCallback ) ( WGPUPopErrorScopeStatus status , WGPUErrorType type , WGPUStringView message , WGPU_NULLABLE void * userdata1 , WGPU_NULLABLE void * userdata2 )
const WGPUPopErrorScopeCallback = Ptr{Cvoid}

# typedef void ( * WGPUQueueWorkDoneCallback ) ( WGPUQueueWorkDoneStatus status , WGPU_NULLABLE void * userdata1 , WGPU_NULLABLE void * userdata2 )
const WGPUQueueWorkDoneCallback = Ptr{Cvoid}

# typedef void ( * WGPURequestAdapterCallback ) ( WGPURequestAdapterStatus status , WGPUAdapter adapter , WGPUStringView message , WGPU_NULLABLE void * userdata1 , WGPU_NULLABLE void * userdata2 )
const WGPURequestAdapterCallback = Ptr{Cvoid}

# typedef void ( * WGPURequestDeviceCallback ) ( WGPURequestDeviceStatus status , WGPUDevice device , WGPUStringView message , WGPU_NULLABLE void * userdata1 , WGPU_NULLABLE void * userdata2 )
const WGPURequestDeviceCallback = Ptr{Cvoid}

# typedef void ( * WGPUUncapturedErrorCallback ) ( WGPUDevice const * device , WGPUErrorType type , WGPUStringView message , WGPU_NULLABLE void * userdata1 , WGPU_NULLABLE void * userdata2 )
const WGPUUncapturedErrorCallback = Ptr{Cvoid}

struct WGPUChainedStruct
    next::Ptr{WGPUChainedStruct}
    sType::WGPUSType
end

struct WGPUChainedStructOut
    next::Ptr{WGPUChainedStructOut}
    sType::WGPUSType
end

struct WGPUBufferMapCallbackInfo
    nextInChain::Ptr{WGPUChainedStruct}
    mode::WGPUCallbackMode
    callback::WGPUBufferMapCallback
    userdata1::Ptr{Cvoid}
    userdata2::Ptr{Cvoid}
end

struct WGPUDeviceLostCallbackInfo
    nextInChain::Ptr{WGPUChainedStruct}
    mode::WGPUCallbackMode
    callback::WGPUDeviceLostCallback
    userdata1::Ptr{Cvoid}
    userdata2::Ptr{Cvoid}
end

struct WGPUPopErrorScopeCallbackInfo
    nextInChain::Ptr{WGPUChainedStruct}
    mode::WGPUCallbackMode
    callback::WGPUPopErrorScopeCallback
    userdata1::Ptr{Cvoid}
    userdata2::Ptr{Cvoid}
end

struct WGPUQueueWorkDoneCallbackInfo
    nextInChain::Ptr{WGPUChainedStruct}
    mode::WGPUCallbackMode
    callback::WGPUQueueWorkDoneCallback
    userdata1::Ptr{Cvoid}
    userdata2::Ptr{Cvoid}
end

struct WGPURequestAdapterCallbackInfo
    nextInChain::Ptr{WGPUChainedStruct}
    mode::WGPUCallbackMode
    callback::WGPURequestAdapterCallback
    userdata1::Ptr{Cvoid}
    userdata2::Ptr{Cvoid}
end

struct WGPURequestDeviceCallbackInfo
    nextInChain::Ptr{WGPUChainedStruct}
    mode::WGPUCallbackMode
    callback::WGPURequestDeviceCallback
    userdata1::Ptr{Cvoid}
    userdata2::Ptr{Cvoid}
end

struct WGPUUncapturedErrorCallbackInfo
    nextInChain::Ptr{WGPUChainedStruct}
    callback::WGPUUncapturedErrorCallback
    userdata1::Ptr{Cvoid}
    userdata2::Ptr{Cvoid}
end

struct WGPUAdapterInfo
    nextInChain::Ptr{WGPUChainedStructOut}
    vendor::WGPUStringView
    architecture::WGPUStringView
    device::WGPUStringView
    description::WGPUStringView
    backendType::WGPUBackendType
    adapterType::WGPUAdapterType
    vendorID::UInt32
    deviceID::UInt32
end

struct WGPUBindGroupEntry
    nextInChain::Ptr{WGPUChainedStruct}
    binding::UInt32
    buffer::WGPUBuffer
    offset::UInt64
    size::UInt64
    sampler::WGPUSampler
    textureView::WGPUTextureView
end

struct WGPUBlendComponent
    operation::WGPUBlendOperation
    srcFactor::WGPUBlendFactor
    dstFactor::WGPUBlendFactor
end

struct WGPUBufferBindingLayout
    nextInChain::Ptr{WGPUChainedStruct}
    type::WGPUBufferBindingType
    hasDynamicOffset::WGPUBool
    minBindingSize::UInt64
end

struct WGPUBufferDescriptor
    nextInChain::Ptr{WGPUChainedStruct}
    label::WGPUStringView
    usage::WGPUBufferUsage
    size::UInt64
    mappedAtCreation::WGPUBool
end

struct WGPUColor
    r::Cdouble
    g::Cdouble
    b::Cdouble
    a::Cdouble
end

struct WGPUCommandBufferDescriptor
    nextInChain::Ptr{WGPUChainedStruct}
    label::WGPUStringView
end

struct WGPUCommandEncoderDescriptor
    nextInChain::Ptr{WGPUChainedStruct}
    label::WGPUStringView
end

struct WGPUConstantEntry
    nextInChain::Ptr{WGPUChainedStruct}
    key::WGPUStringView
    value::Cdouble
end

struct WGPUExtent3D
    width::UInt32
    height::UInt32
    depthOrArrayLayers::UInt32
end

struct WGPUFuture
    id::UInt64
end

struct WGPUInstanceCapabilities
    nextInChain::Ptr{WGPUChainedStructOut}
    timedWaitAnyEnable::WGPUBool
    timedWaitAnyMaxCount::Csize_t
end

struct WGPULimits
    nextInChain::Ptr{WGPUChainedStructOut}
    maxTextureDimension1D::UInt32
    maxTextureDimension2D::UInt32
    maxTextureDimension3D::UInt32
    maxTextureArrayLayers::UInt32
    maxBindGroups::UInt32
    maxBindGroupsPlusVertexBuffers::UInt32
    maxBindingsPerBindGroup::UInt32
    maxDynamicUniformBuffersPerPipelineLayout::UInt32
    maxDynamicStorageBuffersPerPipelineLayout::UInt32
    maxSampledTexturesPerShaderStage::UInt32
    maxSamplersPerShaderStage::UInt32
    maxStorageBuffersPerShaderStage::UInt32
    maxStorageTexturesPerShaderStage::UInt32
    maxUniformBuffersPerShaderStage::UInt32
    maxUniformBufferBindingSize::UInt64
    maxStorageBufferBindingSize::UInt64
    minUniformBufferOffsetAlignment::UInt32
    minStorageBufferOffsetAlignment::UInt32
    maxVertexBuffers::UInt32
    maxBufferSize::UInt64
    maxVertexAttributes::UInt32
    maxVertexBufferArrayStride::UInt32
    maxInterStageShaderVariables::UInt32
    maxColorAttachments::UInt32
    maxColorAttachmentBytesPerSample::UInt32
    maxComputeWorkgroupStorageSize::UInt32
    maxComputeInvocationsPerWorkgroup::UInt32
    maxComputeWorkgroupSizeX::UInt32
    maxComputeWorkgroupSizeY::UInt32
    maxComputeWorkgroupSizeZ::UInt32
    maxComputeWorkgroupsPerDimension::UInt32
end

struct WGPUMultisampleState
    nextInChain::Ptr{WGPUChainedStruct}
    count::UInt32
    mask::UInt32
    alphaToCoverageEnabled::WGPUBool
end

struct WGPUOrigin3D
    x::UInt32
    y::UInt32
    z::UInt32
end

struct WGPUPipelineLayoutDescriptor
    nextInChain::Ptr{WGPUChainedStruct}
    label::WGPUStringView
    bindGroupLayoutCount::Csize_t
    bindGroupLayouts::Ptr{WGPUBindGroupLayout}
end

struct WGPUPrimitiveState
    nextInChain::Ptr{WGPUChainedStruct}
    topology::WGPUPrimitiveTopology
    stripIndexFormat::WGPUIndexFormat
    frontFace::WGPUFrontFace
    cullMode::WGPUCullMode
    unclippedDepth::WGPUBool
end

struct WGPUQueueDescriptor
    nextInChain::Ptr{WGPUChainedStruct}
    label::WGPUStringView
end

struct WGPURenderPassDepthStencilAttachment
    view::WGPUTextureView
    depthLoadOp::WGPULoadOp
    depthStoreOp::WGPUStoreOp
    depthClearValue::Cfloat
    depthReadOnly::WGPUBool
    stencilLoadOp::WGPULoadOp
    stencilStoreOp::WGPUStoreOp
    stencilClearValue::UInt32
    stencilReadOnly::WGPUBool
end

struct WGPURenderPassTimestampWrites
    querySet::WGPUQuerySet
    beginningOfPassWriteIndex::UInt32
    endOfPassWriteIndex::UInt32
end

struct WGPURequestAdapterOptions
    nextInChain::Ptr{WGPUChainedStruct}
    featureLevel::WGPUFeatureLevel
    powerPreference::WGPUPowerPreference
    forceFallbackAdapter::WGPUBool
    backendType::WGPUBackendType
    compatibleSurface::WGPUSurface
end

struct WGPUSamplerBindingLayout
    nextInChain::Ptr{WGPUChainedStruct}
    type::WGPUSamplerBindingType
end

struct WGPUSamplerDescriptor
    nextInChain::Ptr{WGPUChainedStruct}
    label::WGPUStringView
    addressModeU::WGPUAddressMode
    addressModeV::WGPUAddressMode
    addressModeW::WGPUAddressMode
    magFilter::WGPUFilterMode
    minFilter::WGPUFilterMode
    mipmapFilter::WGPUMipmapFilterMode
    lodMinClamp::Cfloat
    lodMaxClamp::Cfloat
    compare::WGPUCompareFunction
    maxAnisotropy::UInt16
end

struct WGPUShaderModuleDescriptor
    nextInChain::Ptr{WGPUChainedStruct}
    label::WGPUStringView
end

struct WGPUShaderSourceWGSL
    chain::WGPUChainedStruct
    code::WGPUStringView
end

struct WGPUStencilFaceState
    compare::WGPUCompareFunction
    failOp::WGPUStencilOperation
    depthFailOp::WGPUStencilOperation
    passOp::WGPUStencilOperation
end

struct WGPUStorageTextureBindingLayout
    nextInChain::Ptr{WGPUChainedStruct}
    access::WGPUStorageTextureAccess
    format::WGPUTextureFormat
    viewDimension::WGPUTextureViewDimension
end

struct WGPUSupportedFeatures
    featureCount::Csize_t
    features::Ptr{WGPUFeatureName}
end

struct WGPUSurfaceCapabilities
    nextInChain::Ptr{WGPUChainedStructOut}
    usages::WGPUTextureUsage
    formatCount::Csize_t
    formats::Ptr{WGPUTextureFormat}
    presentModeCount::Csize_t
    presentModes::Ptr{WGPUPresentMode}
    alphaModeCount::Csize_t
    alphaModes::Ptr{WGPUCompositeAlphaMode}
end

struct WGPUSurfaceConfiguration
    nextInChain::Ptr{WGPUChainedStruct}
    device::WGPUDevice
    format::WGPUTextureFormat
    usage::WGPUTextureUsage
    width::UInt32
    height::UInt32
    viewFormatCount::Csize_t
    viewFormats::Ptr{WGPUTextureFormat}
    alphaMode::WGPUCompositeAlphaMode
    presentMode::WGPUPresentMode
end

struct WGPUSurfaceDescriptor
    nextInChain::Ptr{WGPUChainedStruct}
    label::WGPUStringView
end

struct WGPUSurfaceSourceWaylandSurface
    chain::WGPUChainedStruct
    display::Ptr{Cvoid}
    surface::Ptr{Cvoid}
end

struct WGPUSurfaceSourceXlibWindow
    chain::WGPUChainedStruct
    display::Ptr{Cvoid}
    window::UInt64
end

struct WGPUSurfaceSourceMetalLayer
    chain::WGPUChainedStruct
    layer::Ptr{Cvoid}
end

struct WGPUSurfaceSourceWindowsHWND
    chain::WGPUChainedStruct
    hinstance::Ptr{Cvoid}
    hwnd::Ptr{Cvoid}
end

struct WGPUSurfaceTexture
    nextInChain::Ptr{WGPUChainedStructOut}
    texture::WGPUTexture
    status::WGPUSurfaceGetCurrentTextureStatus
end

struct WGPUTexelCopyBufferLayout
    offset::UInt64
    bytesPerRow::UInt32
    rowsPerImage::UInt32
end

struct WGPUTextureBindingLayout
    nextInChain::Ptr{WGPUChainedStruct}
    sampleType::WGPUTextureSampleType
    viewDimension::WGPUTextureViewDimension
    multisampled::WGPUBool
end

struct WGPUTextureViewDescriptor
    nextInChain::Ptr{WGPUChainedStruct}
    label::WGPUStringView
    format::WGPUTextureFormat
    dimension::WGPUTextureViewDimension
    baseMipLevel::UInt32
    mipLevelCount::UInt32
    baseArrayLayer::UInt32
    arrayLayerCount::UInt32
    aspect::WGPUTextureAspect
    usage::WGPUTextureUsage
end

struct WGPUVertexAttribute
    format::WGPUVertexFormat
    offset::UInt64
    shaderLocation::UInt32
end

struct WGPUBindGroupDescriptor
    nextInChain::Ptr{WGPUChainedStruct}
    label::WGPUStringView
    layout::WGPUBindGroupLayout
    entryCount::Csize_t
    entries::Ptr{WGPUBindGroupEntry}
end

struct WGPUBindGroupLayoutEntry
    nextInChain::Ptr{WGPUChainedStruct}
    binding::UInt32
    visibility::WGPUShaderStage
    buffer::WGPUBufferBindingLayout
    sampler::WGPUSamplerBindingLayout
    texture::WGPUTextureBindingLayout
    storageTexture::WGPUStorageTextureBindingLayout
end

struct WGPUBlendState
    color::WGPUBlendComponent
    alpha::WGPUBlendComponent
end

struct WGPUDepthStencilState
    nextInChain::Ptr{WGPUChainedStruct}
    format::WGPUTextureFormat
    depthWriteEnabled::WGPUOptionalBool
    depthCompare::WGPUCompareFunction
    stencilFront::WGPUStencilFaceState
    stencilBack::WGPUStencilFaceState
    stencilReadMask::UInt32
    stencilWriteMask::UInt32
    depthBias::Int32
    depthBiasSlopeScale::Cfloat
    depthBiasClamp::Cfloat
end

struct WGPUDeviceDescriptor
    nextInChain::Ptr{WGPUChainedStruct}
    label::WGPUStringView
    requiredFeatureCount::Csize_t
    requiredFeatures::Ptr{WGPUFeatureName}
    requiredLimits::Ptr{WGPULimits}
    defaultQueue::WGPUQueueDescriptor
    deviceLostCallbackInfo::WGPUDeviceLostCallbackInfo
    uncapturedErrorCallbackInfo::WGPUUncapturedErrorCallbackInfo
end

struct WGPUInstanceDescriptor
    nextInChain::Ptr{WGPUChainedStruct}
    features::WGPUInstanceCapabilities
end

struct WGPURenderPassColorAttachment
    nextInChain::Ptr{WGPUChainedStruct}
    view::WGPUTextureView
    depthSlice::UInt32
    resolveTarget::WGPUTextureView
    loadOp::WGPULoadOp
    storeOp::WGPUStoreOp
    clearValue::WGPUColor
end

struct WGPUTexelCopyBufferInfo
    layout::WGPUTexelCopyBufferLayout
    buffer::WGPUBuffer
end

struct WGPUTexelCopyTextureInfo
    texture::WGPUTexture
    mipLevel::UInt32
    origin::WGPUOrigin3D
    aspect::WGPUTextureAspect
end

struct WGPUTextureDescriptor
    nextInChain::Ptr{WGPUChainedStruct}
    label::WGPUStringView
    usage::WGPUTextureUsage
    dimension::WGPUTextureDimension
    size::WGPUExtent3D
    format::WGPUTextureFormat
    mipLevelCount::UInt32
    sampleCount::UInt32
    viewFormatCount::Csize_t
    viewFormats::Ptr{WGPUTextureFormat}
end

struct WGPUVertexBufferLayout
    stepMode::WGPUVertexStepMode
    arrayStride::UInt64
    attributeCount::Csize_t
    attributes::Ptr{WGPUVertexAttribute}
end

struct WGPUBindGroupLayoutDescriptor
    nextInChain::Ptr{WGPUChainedStruct}
    label::WGPUStringView
    entryCount::Csize_t
    entries::Ptr{WGPUBindGroupLayoutEntry}
end

struct WGPUColorTargetState
    nextInChain::Ptr{WGPUChainedStruct}
    format::WGPUTextureFormat
    blend::Ptr{WGPUBlendState}
    writeMask::WGPUColorWriteMask
end

struct WGPURenderPassDescriptor
    nextInChain::Ptr{WGPUChainedStruct}
    label::WGPUStringView
    colorAttachmentCount::Csize_t
    colorAttachments::Ptr{WGPURenderPassColorAttachment}
    depthStencilAttachment::Ptr{WGPURenderPassDepthStencilAttachment}
    occlusionQuerySet::WGPUQuerySet
    timestampWrites::Ptr{WGPURenderPassTimestampWrites}
end

struct WGPUVertexState
    nextInChain::Ptr{WGPUChainedStruct}
    _module::WGPUShaderModule
    entryPoint::WGPUStringView
    constantCount::Csize_t
    constants::Ptr{WGPUConstantEntry}
    bufferCount::Csize_t
    buffers::Ptr{WGPUVertexBufferLayout}
end

struct WGPUFragmentState
    nextInChain::Ptr{WGPUChainedStruct}
    _module::WGPUShaderModule
    entryPoint::WGPUStringView
    constantCount::Csize_t
    constants::Ptr{WGPUConstantEntry}
    targetCount::Csize_t
    targets::Ptr{WGPUColorTargetState}
end

struct WGPURenderPipelineDescriptor
    nextInChain::Ptr{WGPUChainedStruct}
    label::WGPUStringView
    layout::WGPUPipelineLayout
    vertex::WGPUVertexState
    primitive::WGPUPrimitiveState
    depthStencil::Ptr{WGPUDepthStencilState}
    multisample::WGPUMultisampleState
    fragment::Ptr{WGPUFragmentState}
end

function wgpuCreateInstance(descriptor)
    @ccall libwgpu_native.wgpuCreateInstance(descriptor::Ptr{WGPUInstanceDescriptor})::WGPUInstance
end

function wgpuAdapterGetFeatures(adapter, features)
    @ccall libwgpu_native.wgpuAdapterGetFeatures(adapter::WGPUAdapter, features::Ptr{WGPUSupportedFeatures})::Cvoid
end

function wgpuAdapterGetInfo(adapter, info)
    @ccall libwgpu_native.wgpuAdapterGetInfo(adapter::WGPUAdapter, info::Ptr{WGPUAdapterInfo})::WGPUStatus
end

function wgpuAdapterGetLimits(adapter, limits)
    @ccall libwgpu_native.wgpuAdapterGetLimits(adapter::WGPUAdapter, limits::Ptr{WGPULimits})::WGPUStatus
end

function wgpuAdapterHasFeature(adapter, feature)
    @ccall libwgpu_native.wgpuAdapterHasFeature(adapter::WGPUAdapter, feature::WGPUFeatureName)::WGPUBool
end

function wgpuAdapterRequestDevice(adapter, descriptor, callbackInfo)
    @ccall libwgpu_native.wgpuAdapterRequestDevice(adapter::WGPUAdapter, descriptor::Ptr{WGPUDeviceDescriptor}, callbackInfo::WGPURequestDeviceCallbackInfo)::WGPUFuture
end

function wgpuAdapterRelease(adapter)
    @ccall libwgpu_native.wgpuAdapterRelease(adapter::WGPUAdapter)::Cvoid
end

function wgpuAdapterInfoFreeMembers(adapterInfo)
    @ccall libwgpu_native.wgpuAdapterInfoFreeMembers(adapterInfo::WGPUAdapterInfo)::Cvoid
end

function wgpuBindGroupRelease(bindGroup)
    @ccall libwgpu_native.wgpuBindGroupRelease(bindGroup::WGPUBindGroup)::Cvoid
end

function wgpuBindGroupLayoutRelease(bindGroupLayout)
    @ccall libwgpu_native.wgpuBindGroupLayoutRelease(bindGroupLayout::WGPUBindGroupLayout)::Cvoid
end

function wgpuBufferDestroy(buffer)
    @ccall libwgpu_native.wgpuBufferDestroy(buffer::WGPUBuffer)::Cvoid
end

function wgpuBufferGetConstMappedRange(buffer, offset, size)
    @ccall libwgpu_native.wgpuBufferGetConstMappedRange(buffer::WGPUBuffer, offset::Csize_t, size::Csize_t)::Ptr{Cvoid}
end

function wgpuBufferGetMappedRange(buffer, offset, size)
    @ccall libwgpu_native.wgpuBufferGetMappedRange(buffer::WGPUBuffer, offset::Csize_t, size::Csize_t)::Ptr{Cvoid}
end

function wgpuBufferGetSize(buffer)
    @ccall libwgpu_native.wgpuBufferGetSize(buffer::WGPUBuffer)::UInt64
end

function wgpuBufferMapAsync(buffer, mode, offset, size, callbackInfo)
    @ccall libwgpu_native.wgpuBufferMapAsync(buffer::WGPUBuffer, mode::WGPUMapMode, offset::Csize_t, size::Csize_t, callbackInfo::WGPUBufferMapCallbackInfo)::WGPUFuture
end

function wgpuBufferUnmap(buffer)
    @ccall libwgpu_native.wgpuBufferUnmap(buffer::WGPUBuffer)::Cvoid
end

function wgpuBufferRelease(buffer)
    @ccall libwgpu_native.wgpuBufferRelease(buffer::WGPUBuffer)::Cvoid
end

function wgpuCommandBufferRelease(commandBuffer)
    @ccall libwgpu_native.wgpuCommandBufferRelease(commandBuffer::WGPUCommandBuffer)::Cvoid
end

function wgpuCommandEncoderBeginRenderPass(commandEncoder, descriptor)
    @ccall libwgpu_native.wgpuCommandEncoderBeginRenderPass(commandEncoder::WGPUCommandEncoder, descriptor::Ptr{WGPURenderPassDescriptor})::WGPURenderPassEncoder
end

function wgpuCommandEncoderClearBuffer(commandEncoder, buffer, offset, size)
    @ccall libwgpu_native.wgpuCommandEncoderClearBuffer(commandEncoder::WGPUCommandEncoder, buffer::WGPUBuffer, offset::UInt64, size::UInt64)::Cvoid
end

function wgpuCommandEncoderCopyBufferToBuffer(commandEncoder, source, sourceOffset, destination, destinationOffset, size)
    @ccall libwgpu_native.wgpuCommandEncoderCopyBufferToBuffer(commandEncoder::WGPUCommandEncoder, source::WGPUBuffer, sourceOffset::UInt64, destination::WGPUBuffer, destinationOffset::UInt64, size::UInt64)::Cvoid
end

function wgpuCommandEncoderCopyBufferToTexture(commandEncoder, source, destination, copySize)
    @ccall libwgpu_native.wgpuCommandEncoderCopyBufferToTexture(commandEncoder::WGPUCommandEncoder, source::Ptr{WGPUTexelCopyBufferInfo}, destination::Ptr{WGPUTexelCopyTextureInfo}, copySize::Ptr{WGPUExtent3D})::Cvoid
end

function wgpuCommandEncoderCopyTextureToBuffer(commandEncoder, source, destination, copySize)
    @ccall libwgpu_native.wgpuCommandEncoderCopyTextureToBuffer(commandEncoder::WGPUCommandEncoder, source::Ptr{WGPUTexelCopyTextureInfo}, destination::Ptr{WGPUTexelCopyBufferInfo}, copySize::Ptr{WGPUExtent3D})::Cvoid
end

function wgpuCommandEncoderCopyTextureToTexture(commandEncoder, source, destination, copySize)
    @ccall libwgpu_native.wgpuCommandEncoderCopyTextureToTexture(commandEncoder::WGPUCommandEncoder, source::Ptr{WGPUTexelCopyTextureInfo}, destination::Ptr{WGPUTexelCopyTextureInfo}, copySize::Ptr{WGPUExtent3D})::Cvoid
end

function wgpuCommandEncoderFinish(commandEncoder, descriptor)
    @ccall libwgpu_native.wgpuCommandEncoderFinish(commandEncoder::WGPUCommandEncoder, descriptor::Ptr{WGPUCommandBufferDescriptor})::WGPUCommandBuffer
end

function wgpuCommandEncoderRelease(commandEncoder)
    @ccall libwgpu_native.wgpuCommandEncoderRelease(commandEncoder::WGPUCommandEncoder)::Cvoid
end

function wgpuDeviceCreateBindGroup(device, descriptor)
    @ccall libwgpu_native.wgpuDeviceCreateBindGroup(device::WGPUDevice, descriptor::Ptr{WGPUBindGroupDescriptor})::WGPUBindGroup
end

function wgpuDeviceCreateBindGroupLayout(device, descriptor)
    @ccall libwgpu_native.wgpuDeviceCreateBindGroupLayout(device::WGPUDevice, descriptor::Ptr{WGPUBindGroupLayoutDescriptor})::WGPUBindGroupLayout
end

function wgpuDeviceCreateBuffer(device, descriptor)
    @ccall libwgpu_native.wgpuDeviceCreateBuffer(device::WGPUDevice, descriptor::Ptr{WGPUBufferDescriptor})::WGPUBuffer
end

function wgpuDeviceCreateCommandEncoder(device, descriptor)
    @ccall libwgpu_native.wgpuDeviceCreateCommandEncoder(device::WGPUDevice, descriptor::Ptr{WGPUCommandEncoderDescriptor})::WGPUCommandEncoder
end

function wgpuDeviceCreatePipelineLayout(device, descriptor)
    @ccall libwgpu_native.wgpuDeviceCreatePipelineLayout(device::WGPUDevice, descriptor::Ptr{WGPUPipelineLayoutDescriptor})::WGPUPipelineLayout
end

function wgpuDeviceCreateRenderPipeline(device, descriptor)
    @ccall libwgpu_native.wgpuDeviceCreateRenderPipeline(device::WGPUDevice, descriptor::Ptr{WGPURenderPipelineDescriptor})::WGPURenderPipeline
end

function wgpuDeviceCreateSampler(device, descriptor)
    @ccall libwgpu_native.wgpuDeviceCreateSampler(device::WGPUDevice, descriptor::Ptr{WGPUSamplerDescriptor})::WGPUSampler
end

function wgpuDeviceCreateShaderModule(device, descriptor)
    @ccall libwgpu_native.wgpuDeviceCreateShaderModule(device::WGPUDevice, descriptor::Ptr{WGPUShaderModuleDescriptor})::WGPUShaderModule
end

function wgpuDeviceCreateTexture(device, descriptor)
    @ccall libwgpu_native.wgpuDeviceCreateTexture(device::WGPUDevice, descriptor::Ptr{WGPUTextureDescriptor})::WGPUTexture
end

function wgpuDeviceDestroy(device)
    @ccall libwgpu_native.wgpuDeviceDestroy(device::WGPUDevice)::Cvoid
end

function wgpuDeviceGetLimits(device, limits)
    @ccall libwgpu_native.wgpuDeviceGetLimits(device::WGPUDevice, limits::Ptr{WGPULimits})::WGPUStatus
end

function wgpuDeviceGetQueue(device)
    @ccall libwgpu_native.wgpuDeviceGetQueue(device::WGPUDevice)::WGPUQueue
end

function wgpuDeviceHasFeature(device, feature)
    @ccall libwgpu_native.wgpuDeviceHasFeature(device::WGPUDevice, feature::WGPUFeatureName)::WGPUBool
end

function wgpuDevicePopErrorScope(device, callbackInfo)
    @ccall libwgpu_native.wgpuDevicePopErrorScope(device::WGPUDevice, callbackInfo::WGPUPopErrorScopeCallbackInfo)::WGPUFuture
end

function wgpuDevicePushErrorScope(device, filter)
    @ccall libwgpu_native.wgpuDevicePushErrorScope(device::WGPUDevice, filter::WGPUErrorFilter)::Cvoid
end

function wgpuDeviceRelease(device)
    @ccall libwgpu_native.wgpuDeviceRelease(device::WGPUDevice)::Cvoid
end

function wgpuInstanceCreateSurface(instance, descriptor)
    @ccall libwgpu_native.wgpuInstanceCreateSurface(instance::WGPUInstance, descriptor::Ptr{WGPUSurfaceDescriptor})::WGPUSurface
end

function wgpuInstanceRequestAdapter(instance, options, callbackInfo)
    @ccall libwgpu_native.wgpuInstanceRequestAdapter(instance::WGPUInstance, options::Ptr{WGPURequestAdapterOptions}, callbackInfo::WGPURequestAdapterCallbackInfo)::WGPUFuture
end

function wgpuInstanceRelease(instance)
    @ccall libwgpu_native.wgpuInstanceRelease(instance::WGPUInstance)::Cvoid
end

function wgpuPipelineLayoutRelease(pipelineLayout)
    @ccall libwgpu_native.wgpuPipelineLayoutRelease(pipelineLayout::WGPUPipelineLayout)::Cvoid
end

function wgpuQueueOnSubmittedWorkDone(queue, callbackInfo)
    @ccall libwgpu_native.wgpuQueueOnSubmittedWorkDone(queue::WGPUQueue, callbackInfo::WGPUQueueWorkDoneCallbackInfo)::WGPUFuture
end

function wgpuQueueSubmit(queue, commandCount, commands)
    @ccall libwgpu_native.wgpuQueueSubmit(queue::WGPUQueue, commandCount::Csize_t, commands::Ptr{WGPUCommandBuffer})::Cvoid
end

function wgpuQueueWriteBuffer(queue, buffer, bufferOffset, data, size)
    @ccall libwgpu_native.wgpuQueueWriteBuffer(queue::WGPUQueue, buffer::WGPUBuffer, bufferOffset::UInt64, data::Ptr{Cvoid}, size::Csize_t)::Cvoid
end

function wgpuQueueWriteTexture(queue, destination, data, dataSize, dataLayout, writeSize)
    @ccall libwgpu_native.wgpuQueueWriteTexture(queue::WGPUQueue, destination::Ptr{WGPUTexelCopyTextureInfo}, data::Ptr{Cvoid}, dataSize::Csize_t, dataLayout::Ptr{WGPUTexelCopyBufferLayout}, writeSize::Ptr{WGPUExtent3D})::Cvoid
end

function wgpuQueueRelease(queue)
    @ccall libwgpu_native.wgpuQueueRelease(queue::WGPUQueue)::Cvoid
end

function wgpuRenderPassEncoderDraw(renderPassEncoder, vertexCount, instanceCount, firstVertex, firstInstance)
    @ccall libwgpu_native.wgpuRenderPassEncoderDraw(renderPassEncoder::WGPURenderPassEncoder, vertexCount::UInt32, instanceCount::UInt32, firstVertex::UInt32, firstInstance::UInt32)::Cvoid
end

function wgpuRenderPassEncoderDrawIndexed(renderPassEncoder, indexCount, instanceCount, firstIndex, baseVertex, firstInstance)
    @ccall libwgpu_native.wgpuRenderPassEncoderDrawIndexed(renderPassEncoder::WGPURenderPassEncoder, indexCount::UInt32, instanceCount::UInt32, firstIndex::UInt32, baseVertex::Int32, firstInstance::UInt32)::Cvoid
end

function wgpuRenderPassEncoderEnd(renderPassEncoder)
    @ccall libwgpu_native.wgpuRenderPassEncoderEnd(renderPassEncoder::WGPURenderPassEncoder)::Cvoid
end

function wgpuRenderPassEncoderSetBindGroup(renderPassEncoder, groupIndex, group, dynamicOffsetCount, dynamicOffsets)
    @ccall libwgpu_native.wgpuRenderPassEncoderSetBindGroup(renderPassEncoder::WGPURenderPassEncoder, groupIndex::UInt32, group::WGPUBindGroup, dynamicOffsetCount::Csize_t, dynamicOffsets::Ptr{UInt32})::Cvoid
end

function wgpuRenderPassEncoderSetBlendConstant(renderPassEncoder, color)
    @ccall libwgpu_native.wgpuRenderPassEncoderSetBlendConstant(renderPassEncoder::WGPURenderPassEncoder, color::Ptr{WGPUColor})::Cvoid
end

function wgpuRenderPassEncoderSetIndexBuffer(renderPassEncoder, buffer, format, offset, size)
    @ccall libwgpu_native.wgpuRenderPassEncoderSetIndexBuffer(renderPassEncoder::WGPURenderPassEncoder, buffer::WGPUBuffer, format::WGPUIndexFormat, offset::UInt64, size::UInt64)::Cvoid
end

function wgpuRenderPassEncoderSetPipeline(renderPassEncoder, pipeline)
    @ccall libwgpu_native.wgpuRenderPassEncoderSetPipeline(renderPassEncoder::WGPURenderPassEncoder, pipeline::WGPURenderPipeline)::Cvoid
end

function wgpuRenderPassEncoderSetScissorRect(renderPassEncoder, x, y, width, height)
    @ccall libwgpu_native.wgpuRenderPassEncoderSetScissorRect(renderPassEncoder::WGPURenderPassEncoder, x::UInt32, y::UInt32, width::UInt32, height::UInt32)::Cvoid
end

function wgpuRenderPassEncoderSetStencilReference(renderPassEncoder, reference)
    @ccall libwgpu_native.wgpuRenderPassEncoderSetStencilReference(renderPassEncoder::WGPURenderPassEncoder, reference::UInt32)::Cvoid
end

function wgpuRenderPassEncoderSetVertexBuffer(renderPassEncoder, slot, buffer, offset, size)
    @ccall libwgpu_native.wgpuRenderPassEncoderSetVertexBuffer(renderPassEncoder::WGPURenderPassEncoder, slot::UInt32, buffer::WGPUBuffer, offset::UInt64, size::UInt64)::Cvoid
end

function wgpuRenderPassEncoderSetViewport(renderPassEncoder, x, y, width, height, minDepth, maxDepth)
    @ccall libwgpu_native.wgpuRenderPassEncoderSetViewport(renderPassEncoder::WGPURenderPassEncoder, x::Cfloat, y::Cfloat, width::Cfloat, height::Cfloat, minDepth::Cfloat, maxDepth::Cfloat)::Cvoid
end

function wgpuRenderPassEncoderRelease(renderPassEncoder)
    @ccall libwgpu_native.wgpuRenderPassEncoderRelease(renderPassEncoder::WGPURenderPassEncoder)::Cvoid
end

function wgpuRenderPipelineGetBindGroupLayout(renderPipeline, groupIndex)
    @ccall libwgpu_native.wgpuRenderPipelineGetBindGroupLayout(renderPipeline::WGPURenderPipeline, groupIndex::UInt32)::WGPUBindGroupLayout
end

function wgpuRenderPipelineRelease(renderPipeline)
    @ccall libwgpu_native.wgpuRenderPipelineRelease(renderPipeline::WGPURenderPipeline)::Cvoid
end

function wgpuSamplerRelease(sampler)
    @ccall libwgpu_native.wgpuSamplerRelease(sampler::WGPUSampler)::Cvoid
end

function wgpuShaderModuleRelease(shaderModule)
    @ccall libwgpu_native.wgpuShaderModuleRelease(shaderModule::WGPUShaderModule)::Cvoid
end

function wgpuSupportedFeaturesFreeMembers(supportedFeatures)
    @ccall libwgpu_native.wgpuSupportedFeaturesFreeMembers(supportedFeatures::WGPUSupportedFeatures)::Cvoid
end

function wgpuSurfaceConfigure(surface, config)
    @ccall libwgpu_native.wgpuSurfaceConfigure(surface::WGPUSurface, config::Ptr{WGPUSurfaceConfiguration})::Cvoid
end

function wgpuSurfaceGetCapabilities(surface, adapter, capabilities)
    @ccall libwgpu_native.wgpuSurfaceGetCapabilities(surface::WGPUSurface, adapter::WGPUAdapter, capabilities::Ptr{WGPUSurfaceCapabilities})::WGPUStatus
end

function wgpuSurfaceGetCurrentTexture(surface, surfaceTexture)
    @ccall libwgpu_native.wgpuSurfaceGetCurrentTexture(surface::WGPUSurface, surfaceTexture::Ptr{WGPUSurfaceTexture})::Cvoid
end

function wgpuSurfacePresent(surface)
    @ccall libwgpu_native.wgpuSurfacePresent(surface::WGPUSurface)::WGPUStatus
end

function wgpuSurfaceUnconfigure(surface)
    @ccall libwgpu_native.wgpuSurfaceUnconfigure(surface::WGPUSurface)::Cvoid
end

function wgpuSurfaceRelease(surface)
    @ccall libwgpu_native.wgpuSurfaceRelease(surface::WGPUSurface)::Cvoid
end

function wgpuSurfaceCapabilitiesFreeMembers(surfaceCapabilities)
    @ccall libwgpu_native.wgpuSurfaceCapabilitiesFreeMembers(surfaceCapabilities::WGPUSurfaceCapabilities)::Cvoid
end

function wgpuTextureCreateView(texture, descriptor)
    @ccall libwgpu_native.wgpuTextureCreateView(texture::WGPUTexture, descriptor::Ptr{WGPUTextureViewDescriptor})::WGPUTextureView
end

function wgpuTextureDestroy(texture)
    @ccall libwgpu_native.wgpuTextureDestroy(texture::WGPUTexture)::Cvoid
end

function wgpuTextureGetFormat(texture)
    @ccall libwgpu_native.wgpuTextureGetFormat(texture::WGPUTexture)::WGPUTextureFormat
end

function wgpuTextureGetHeight(texture)
    @ccall libwgpu_native.wgpuTextureGetHeight(texture::WGPUTexture)::UInt32
end

function wgpuTextureGetWidth(texture)
    @ccall libwgpu_native.wgpuTextureGetWidth(texture::WGPUTexture)::UInt32
end

function wgpuTextureRelease(texture)
    @ccall libwgpu_native.wgpuTextureRelease(texture::WGPUTexture)::Cvoid
end

function wgpuTextureViewRelease(textureView)
    @ccall libwgpu_native.wgpuTextureViewRelease(textureView::WGPUTextureView)::Cvoid
end

const WGPUNativeSType = UInt32
const WGPUSType_DeviceExtras = WGPUNativeSType(196609)
const WGPUSType_NativeLimits = WGPUNativeSType(196610)
const WGPUSType_PipelineLayoutExtras = WGPUNativeSType(196611)
const WGPUSType_ShaderModuleGLSLDescriptor = WGPUNativeSType(196612)
const WGPUSType_InstanceExtras = WGPUNativeSType(196614)
const WGPUSType_BindGroupEntryExtras = WGPUNativeSType(196615)
const WGPUSType_BindGroupLayoutEntryExtras = WGPUNativeSType(196616)
const WGPUSType_QuerySetDescriptorExtras = WGPUNativeSType(196617)
const WGPUSType_SurfaceConfigurationExtras = WGPUNativeSType(196618)

const WGPUNativeFeature = UInt32
const WGPUNativeFeature_PushConstants = WGPUNativeFeature(196609)
const WGPUNativeFeature_TextureAdapterSpecificFormatFeatures = WGPUNativeFeature(196610)
const WGPUNativeFeature_MultiDrawIndirect = WGPUNativeFeature(196611)
const WGPUNativeFeature_MultiDrawIndirectCount = WGPUNativeFeature(196612)
const WGPUNativeFeature_VertexWritableStorage = WGPUNativeFeature(196613)
const WGPUNativeFeature_TextureBindingArray = WGPUNativeFeature(196614)
const WGPUNativeFeature_SampledTextureAndStorageBufferArrayNonUniformIndexing = WGPUNativeFeature(196615)
const WGPUNativeFeature_PipelineStatisticsQuery = WGPUNativeFeature(196616)
const WGPUNativeFeature_StorageResourceBindingArray = WGPUNativeFeature(196617)
const WGPUNativeFeature_PartiallyBoundBindingArray = WGPUNativeFeature(196618)
const WGPUNativeFeature_TextureFormat16bitNorm = WGPUNativeFeature(196619)
const WGPUNativeFeature_TextureCompressionAstcHdr = WGPUNativeFeature(196620)
const WGPUNativeFeature_MappablePrimaryBuffers = WGPUNativeFeature(196622)
const WGPUNativeFeature_BufferBindingArray = WGPUNativeFeature(196623)
const WGPUNativeFeature_UniformBufferAndStorageTextureArrayNonUniformIndexing = WGPUNativeFeature(196624)
const WGPUNativeFeature_SpirvShaderPassthrough = WGPUNativeFeature(196631)
const WGPUNativeFeature_VertexAttribute64bit = WGPUNativeFeature(196633)
const WGPUNativeFeature_TextureFormatNv12 = WGPUNativeFeature(196634)
const WGPUNativeFeature_RayTracingAccelerationStructure = WGPUNativeFeature(196635)
const WGPUNativeFeature_RayQuery = WGPUNativeFeature(196636)
const WGPUNativeFeature_ShaderF64 = WGPUNativeFeature(196637)
const WGPUNativeFeature_ShaderI16 = WGPUNativeFeature(196638)
const WGPUNativeFeature_ShaderPrimitiveIndex = WGPUNativeFeature(196639)
const WGPUNativeFeature_ShaderEarlyDepthTest = WGPUNativeFeature(196640)
const WGPUNativeFeature_Subgroup = WGPUNativeFeature(196641)
const WGPUNativeFeature_SubgroupVertex = WGPUNativeFeature(196642)
const WGPUNativeFeature_SubgroupBarrier = WGPUNativeFeature(196643)
const WGPUNativeFeature_TimestampQueryInsideEncoders = WGPUNativeFeature(196644)
const WGPUNativeFeature_TimestampQueryInsidePasses = WGPUNativeFeature(196645)

const WGPULogLevel = UInt32
const WGPULogLevel_Off = WGPULogLevel(0)
const WGPULogLevel_Error = WGPULogLevel(1)
const WGPULogLevel_Warn = WGPULogLevel(2)
const WGPULogLevel_Info = WGPULogLevel(3)
const WGPULogLevel_Debug = WGPULogLevel(4)
const WGPULogLevel_Trace = WGPULogLevel(5)

const WGPUInstanceBackend = WGPUFlags

const WGPUInstanceFlag = WGPUFlags

const WGPUDx12Compiler = UInt32
const WGPUDx12Compiler_Undefined = WGPUDx12Compiler(0)
const WGPUDx12Compiler_Fxc = WGPUDx12Compiler(1)
const WGPUDx12Compiler_Dxc = WGPUDx12Compiler(2)

const WGPUGles3MinorVersion = UInt32
const WGPUGles3MinorVersion_Automatic = WGPUGles3MinorVersion(0)
const WGPUGles3MinorVersion_Version0 = WGPUGles3MinorVersion(1)
const WGPUGles3MinorVersion_Version1 = WGPUGles3MinorVersion(2)
const WGPUGles3MinorVersion_Version2 = WGPUGles3MinorVersion(3)

struct WGPUInstanceExtras
    chain::WGPUChainedStruct
    backends::WGPUInstanceBackend
    flags::WGPUInstanceFlag
    dx12ShaderCompiler::WGPUDx12Compiler
    gles3MinorVersion::WGPUGles3MinorVersion
    dxilPath::WGPUStringView
    dxcPath::WGPUStringView
end

const WGPUSubmissionIndex = UInt64

struct WGPURegistryReport
    numAllocated::Csize_t
    numKeptFromUser::Csize_t
    numReleasedFromUser::Csize_t
    elementSize::Csize_t
end

struct WGPUHubReport
    adapters::WGPURegistryReport
    devices::WGPURegistryReport
    queues::WGPURegistryReport
    pipelineLayouts::WGPURegistryReport
    shaderModules::WGPURegistryReport
    bindGroupLayouts::WGPURegistryReport
    bindGroups::WGPURegistryReport
    commandBuffers::WGPURegistryReport
    renderBundles::WGPURegistryReport
    renderPipelines::WGPURegistryReport
    computePipelines::WGPURegistryReport
    pipelineCaches::WGPURegistryReport
    querySets::WGPURegistryReport
    buffers::WGPURegistryReport
    textures::WGPURegistryReport
    textureViews::WGPURegistryReport
    samplers::WGPURegistryReport
end

struct WGPUGlobalReport
    surfaces::WGPURegistryReport
    hub::WGPUHubReport
end

struct WGPUInstanceEnumerateAdapterOptions
    nextInChain::Ptr{WGPUChainedStruct}
    backends::WGPUInstanceBackend
end

# typedef void ( * WGPULogCallback ) ( WGPULogLevel level , WGPUStringView message , void * userdata )
const WGPULogCallback = Ptr{Cvoid}

function wgpuGenerateReport(instance, report)
    @ccall libwgpu_native.wgpuGenerateReport(instance::WGPUInstance, report::Ptr{WGPUGlobalReport})::Cvoid
end

function wgpuInstanceEnumerateAdapters(instance, options, adapters)
    @ccall libwgpu_native.wgpuInstanceEnumerateAdapters(instance::WGPUInstance, options::Ptr{WGPUInstanceEnumerateAdapterOptions}, adapters::Ptr{WGPUAdapter})::Csize_t
end

function wgpuQueueSubmitForIndex(queue, commandCount, commands)
    @ccall libwgpu_native.wgpuQueueSubmitForIndex(queue::WGPUQueue, commandCount::Csize_t, commands::Ptr{WGPUCommandBuffer})::WGPUSubmissionIndex
end

function wgpuDevicePoll(device, wait, wrappedSubmissionIndex)
    @ccall libwgpu_native.wgpuDevicePoll(device::WGPUDevice, wait::WGPUBool, wrappedSubmissionIndex::Ptr{WGPUSubmissionIndex})::WGPUBool
end

function wgpuSetLogCallback(callback, userdata)
    @ccall libwgpu_native.wgpuSetLogCallback(callback::WGPULogCallback, userdata::Ptr{Cvoid})::Cvoid
end

function wgpuSetLogLevel(level)
    @ccall libwgpu_native.wgpuSetLogLevel(level::WGPULogLevel)::Cvoid
end

function wgpuGetVersion()
    @ccall libwgpu_native.wgpuGetVersion()::UInt32
end

# `static const` in wgpu.h — Clang.jl does not emit those, so by hand.
const WGPUInstanceBackend_All = WGPUInstanceBackend(0)
const WGPUInstanceBackend_Vulkan = WGPUInstanceBackend(1 << 0)
const WGPUInstanceBackend_GL = WGPUInstanceBackend(1 << 1)
const WGPUInstanceBackend_Metal = WGPUInstanceBackend(1 << 2)
const WGPUInstanceBackend_DX12 = WGPUInstanceBackend(1 << 3)
const WGPUInstanceBackend_DX11 = WGPUInstanceBackend(1 << 4)
const WGPUInstanceBackend_BrowserWebGPU = WGPUInstanceBackend(1 << 5)
const WGPUInstanceBackend_Primary = WGPUInstanceBackend((1 << 0) | (1 << 2) | (1 << 3) | (1 << 5))
const WGPUInstanceBackend_Secondary = WGPUInstanceBackend((1 << 1) | (1 << 4))
const WGPUInstanceFlag_Default = WGPUInstanceFlag(0)
const WGPUInstanceFlag_Debug = WGPUInstanceFlag(1 << 0)
const WGPUInstanceFlag_Validation = WGPUInstanceFlag(1 << 1)
const WGPUInstanceFlag_DiscardHalLabels = WGPUInstanceFlag(1 << 2)
