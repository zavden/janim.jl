# backend/wgpu/triangle.jl — "hello GPU" on WebGPU: three vertices, one
# primary colour each, over a flat background.
#
# WebGPU describes by hand what other APIs leave implicit: a vertex buffer
# layout, a colour target, a primitive state, a pipeline. This is the file
# where that shape is spelled out most plainly; every later shader follows it.
#
# The frame's SHA-256 from two child processes must agree, in both routes
# (RADV and lavapipe). The pixel values themselves are looked at (the
# centroid one third of each colour, the background the clear colour).

const TRIANGLE_WGSL = """
struct VertexOut {
    @builtin(position) position : vec4<f32>,
    @location(0) color : vec3<f32>,
};

@vertex
fn vs_main(@location(0) position : vec2<f32>, @location(1) color : vec3<f32>) -> VertexOut {
    var out : VertexOut;
    out.position = vec4<f32>(position, 0.0, 1.0);
    out.color = color;
    return out;
}

@fragment
fn fs_main(in : VertexOut) -> @location(0) vec4<f32> {
    return vec4<f32>(in.color, 1.0);
}
"""

# x, y, r, g, b — one vertex per primary colour
const TRIANGLE_F0 = Float32[
    -0.6, -0.5,  1.0, 0.0, 0.0,
     0.6, -0.5,  0.0, 1.0, 0.0,
     0.0,  0.6,  0.0, 0.0, 1.0,
]

const _VS_MAIN = "vs_main"
const _FS_MAIN = "fs_main"
const _TRIANGLE_LABEL = "triangle"

"""
    compile_wgsl(gpu, source; label) → WGPUShaderModule

A shader module from WGSL source, inside an error scope: a source naga
rejects throws `GPUValidationError` with naga's own diagnostic (line,
column, the offending token). The caller releases the module.
"""
function compile_wgsl(gpu::GPU, source::String; label::String = "wgsl")
    wgsl = Ref(WGPUShaderSourceWGSL(WGPUChainedStruct(C_NULL, WGPUSType_ShaderSourceWGSL),
                                    WGPUStringView(pointer(source), sizeof(source))))
    desc = Ref(WGPUShaderModuleDescriptor(
        Ptr{WGPUChainedStruct}(Base.unsafe_convert(Ptr{WGPUShaderSourceWGSL}, wgsl)),
        WGPUStringView(pointer(label), sizeof(label))))
    sm = GC.@preserve source label wgsl desc _error_scope(gpu) do
        wgpuDeviceCreateShaderModule(gpu.device, desc)
    end
    sm == C_NULL && throw(GPUValidationError("wgpuDeviceCreateShaderModule returned NULL for $label"))
    return sm
end

"""
A vertex buffer holding `data` (Vertex + CopyDst, written through the queue).
The caller releases it.
"""
function _vertex_buffer(gpu::GPU, data::Vector{Float32}, label::String)
    nbytes = sizeof(data)
    desc = Ref(WGPUBufferDescriptor(C_NULL, WGPUStringView(pointer(label), sizeof(label)),
                                    WGPUBufferUsage_Vertex | WGPUBufferUsage_CopyDst,
                                    UInt64(nbytes), 0))
    buf = GC.@preserve label desc wgpuDeviceCreateBuffer(gpu.device, desc)
    buf == C_NULL && throw(GPUValidationError("wgpuDeviceCreateBuffer returned NULL for $label"))
    GC.@preserve data wgpuQueueWriteBuffer(gpu.queue, buf, 0, pointer(data), nbytes)
    return buf
end

"The triangle pipeline: (x, y, r, g, b) per vertex, triangles, no blend, rgba8unorm."
function _triangle_pipeline(gpu::GPU, shader::WGPUShaderModule)
    attrs = [WGPUVertexAttribute(WGPUVertexFormat_Float32x2, 0, 0),
             WGPUVertexAttribute(WGPUVertexFormat_Float32x3, 2 * sizeof(Float32), 1)]
    layouts = [WGPUVertexBufferLayout(WGPUVertexStepMode_Vertex, 5 * sizeof(Float32),
                                      length(attrs), pointer(attrs))]
    targets = [WGPUColorTargetState(C_NULL, WGPUTextureFormat_RGBA8Unorm, C_NULL,
                                    WGPUColorWriteMask_All)]
    frag = Ref(WGPUFragmentState(C_NULL, shader, WGPUStringView(pointer(_FS_MAIN), sizeof(_FS_MAIN)),
                                 0, C_NULL, length(targets), pointer(targets)))
    desc = Ref(WGPURenderPipelineDescriptor(
        C_NULL, WGPUStringView(pointer(_TRIANGLE_LABEL), sizeof(_TRIANGLE_LABEL)),
        WGPUPipelineLayout(C_NULL),
        WGPUVertexState(C_NULL, shader, WGPUStringView(pointer(_VS_MAIN), sizeof(_VS_MAIN)),
                        0, C_NULL, length(layouts), pointer(layouts)),
        WGPUPrimitiveState(C_NULL, WGPUPrimitiveTopology_TriangleList, WGPUIndexFormat_Undefined,
                           WGPUFrontFace_CCW, WGPUCullMode_None, 0),
        C_NULL,
        WGPUMultisampleState(C_NULL, 1, 0xffffffff, 0),
        Base.unsafe_convert(Ptr{WGPUFragmentState}, frag)))
    pipe = GC.@preserve attrs layouts targets frag desc _error_scope(gpu) do
        wgpuDeviceCreateRenderPipeline(gpu.device, desc)
    end
    pipe == C_NULL && throw(GPUValidationError("wgpuDeviceCreateRenderPipeline returned NULL for the triangle"))
    return pipe
end

"""
One render pass over `target`: clear to `clear`, then `draw(pass)` records
whatever the caller wants. Submitted; returns the submission index.
"""
function _render_pass!(draw, gpu::GPU, t::GPUTarget, clear::NTuple{4, Float64})
    enc = wgpuDeviceCreateCommandEncoder(gpu.device, C_NULL)
    color = [WGPURenderPassColorAttachment(C_NULL, t.view, WGPU_DEPTH_SLICE_UNDEFINED,
                                           WGPUTextureView(C_NULL), WGPULoadOp_Clear,
                                           WGPUStoreOp_Store, WGPUColor(clear...))]
    desc = Ref(WGPURenderPassDescriptor(C_NULL, _EMPTY_SV, length(color), pointer(color),
                                        C_NULL, WGPUQuerySet(C_NULL), C_NULL))
    pass = GC.@preserve color desc wgpuCommandEncoderBeginRenderPass(enc, desc)
    draw(pass)
    wgpuRenderPassEncoderEnd(pass)
    wgpuRenderPassEncoderRelease(pass)
    cmd = wgpuCommandEncoderFinish(enc, C_NULL)
    wgpuCommandEncoderRelease(enc)
    return _submit!(gpu, cmd)
end

"""
    TriangleScene

The triangle set up once — shader, vertex buffer, pipeline — so that a
frame is one `draw_triangle!`. `shift` moves it along x, which is how the
readback tests get N DIFFERENT frames out of it.
"""
mutable struct TriangleScene
    gpu::GPU
    shader::WGPUShaderModule
    vbo::WGPUBuffer
    pipeline::WGPURenderPipeline
    verts::Vector{Float32}
    closed::Bool
end

const _TRIANGLE_VBO_LABEL = "triangle vertices"

function TriangleScene(gpu::GPU)
    shader = compile_wgsl(gpu, TRIANGLE_WGSL; label = _TRIANGLE_LABEL)
    verts = copy(TRIANGLE_F0)
    vbo = _vertex_buffer(gpu, verts, _TRIANGLE_VBO_LABEL)
    pipe = _triangle_pipeline(gpu, shader)
    s = TriangleScene(gpu, shader, vbo, pipe, verts, false)
    finalizer(close_triangle!, s)
    return s
end

function close_triangle!(s::TriangleScene)
    s.closed && return nothing
    s.closed = true
    wgpuRenderPipelineRelease(s.pipeline)
    wgpuBufferDestroy(s.vbo)
    wgpuBufferRelease(s.vbo)
    wgpuShaderModuleRelease(s.shader)
    return nothing
end

const _TRIANGLE_CLEAR = (0.10, 0.10, 0.12, 1.0)

"""
    draw_triangle!(s, target; shift = 0.0) → submission index

Clear + the triangle, moved `shift` along x (in NDC), into `target`.
"""
function draw_triangle!(s::TriangleScene, t::GPUTarget; shift::Real = 0.0)
    if shift != 0
        v = s.verts
        for k in 0:2
            v[5k + 1] = TRIANGLE_F0[5k + 1] + Float32(shift)
        end
        GC.@preserve v wgpuQueueWriteBuffer(s.gpu.queue, s.vbo, 0, pointer(v), sizeof(v))
    end
    return _render_pass!(s.gpu, t, _TRIANGLE_CLEAR) do pass
        wgpuRenderPassEncoderSetPipeline(pass, s.pipeline)
        wgpuRenderPassEncoderSetVertexBuffer(pass, 0, s.vbo, 0, UInt64(sizeof(s.verts)))
        wgpuRenderPassEncoderDraw(pass, 3, 1, 0, 0)
    end
end

"""
    demo_triangle_wgpu(; width = 640, height = 480, dump = nothing)

The triangle through the WebGPU backend: create the GPU, draw one frame,
read it back, close everything. Returns the driver identity, the centroid
pixel (≈ one third of each colour), a background pixel (the clear colour),
and the SHA-256 of the RGB frame — the number two processes must agree on.
`dump` writes the frame as a PNG.
"""
function demo_triangle_wgpu(; width::Int = 640, height::Int = 480, dump = nothing)
    gpu = create_gpu()
    try
        target = create_target(gpu, width, height)
        scene = TriangleScene(gpu)
        draw_triangle!(scene, target)
        img = read_rgb_topdown(gpu, target)
        _check_gpu_errors!(gpu)
        # centroid in NDC (0, (−0.5 − 0.5 + 0.6) / 3) = (0, −0.1333); rows run
        # top-down here, so y = (1 − (−0.1333)) / 2 of the height.
        cx = round(Int, width / 2)
        cy = round(Int, (1 + 0.1333) / 2 * height)
        center_pixel = Tuple(Int.(img[:, cx, cy]))
        background_pixel = Tuple(Int.(img[:, 5, 5]))
        dump === nothing || save_png(String(dump), img)
        close_triangle!(scene)
        close_target!(target)
        return (; gpu_info(gpu)..., center_pixel, background_pixel,
                sha = bytes2hex(sha256(vec(img))))
    finally
        close_gpu!(gpu)
    end
end

"""
    demo_triangle(; width = 640, height = 480, dump = nothing)

"Hello GPU": the RGB triangle drawn and read back on the process's backend.
This is [`demo_triangle_wgpu`](@ref) by another name.
"""
demo_triangle(; kw...) = demo_triangle_wgpu(; kw...)
