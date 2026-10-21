# core/model.jl — ThreeDModel (surface.py:435), a Wavefront OBJ
# as a Group of meshes.
#
# GL loads the file through trimesh + pywavefront and wraps each geometry in
# a TexturedGeometry. Here the OBJ and its MTL are read by a short parser of
# our own (no MeshIO dependency), and every material
# becomes ONE mesh — a TexturedSurface when the material's `map_Kd` image is
# beside the file, a plain Surface otherwise — both indexed triangle lists
# the renderer already draws. Nothing here touches the backend.
#
# Two deliberate divergences from ManimGL (checked on a textured cube):
#   · GL's single-mesh branch ignores the MTL and textures every model with
#     the `texture.png` beside the file (or a white default; its
#     multi-material path is unimplemented in the source). This reader honours
#     `map_Kd` per material, and `Kd` when there is no image.
#   · GL's TexturedGeometry sets d_normal_point = point — no normal at all,
#     so no lighting. This reader keeps the file's `vn` and, when a corner
#     has none, averages the area-weighted normals of its faces, so a model
#     is lit like any Surface.
# What GL does and we do too: `height = 3` by default, centred, depth-tested.

struct _ObjMaterial
    name::String
    kd::Union{Nothing,NTuple{3,Float64}}
    map_kd::Union{Nothing,String}      # resolved beside the MTL, or nothing
end

"The materials of an MTL file: `newmtl`, `Kd` and `map_Kd` (its last token is the file)."
function _read_mtl(path::AbstractString)
    materials = Dict{String,_ObjMaterial}()
    isfile(path) || return materials
    dir = dirname(path)
    name = ""
    kd = nothing
    map_kd = nothing
    for raw in eachline(path)
        line = strip(raw)
        (isempty(line) || startswith(line, "#")) && continue
        parts = split(line)
        key = parts[1]
        if key == "newmtl"
            isempty(name) || (materials[name] = _ObjMaterial(name, kd, map_kd))
            name = join(parts[2:end], " ")
            kd = nothing
            map_kd = nothing
        elseif key == "Kd" && length(parts) >= 4
            kd = (parse(Float64, parts[2]), parse(Float64, parts[3]), parse(Float64, parts[4]))
        elseif key == "map_Kd" && length(parts) >= 2
            file = String(parts[end])
            map_kd = isabspath(file) ? file : joinpath(dir, file)
        end
    end
    isempty(name) || (materials[name] = _ObjMaterial(name, kd, map_kd))
    return materials
end

"One `v/vt/vn` token → 1-based indices (0 = absent); negative indices count from the end."
function _obj_corner(token::AbstractString, nv::Int, nt::Int, nn::Int)
    fields = split(token, '/')
    at(i, n) = i <= length(fields) && !isempty(fields[i]) ?
               (k = parse(Int, fields[i]); k < 0 ? n + k + 1 : k) : 0
    return (at(1, nv), at(2, nt), at(3, nn))
end

"""
The OBJ's vertices, texture coordinates, normals and faces grouped by
material (in order of first use; "" is the material-less group), plus the
MTL's materials.
"""
function _read_obj(path::AbstractString)
    vertices = SVector{3,Float64}[]
    texcoords = SVector{2,Float64}[]
    normals = SVector{3,Float64}[]
    faces = Dict{String,Vector{Vector{NTuple{3,Int}}}}()
    order = String[]
    materials = Dict{String,_ObjMaterial}()
    current = ""
    for raw in eachline(path)
        line = strip(raw)
        (isempty(line) || startswith(line, "#")) && continue
        parts = split(line)
        key = parts[1]
        if key == "v" && length(parts) >= 4
            push!(vertices, SVector(parse(Float64, parts[2]), parse(Float64, parts[3]),
                                    parse(Float64, parts[4])))
        elseif key == "vt" && length(parts) >= 2
            push!(texcoords, SVector(parse(Float64, parts[2]),
                                     length(parts) >= 3 ? parse(Float64, parts[3]) : 0.0))
        elseif key == "vn" && length(parts) >= 4
            push!(normals, SVector(parse(Float64, parts[2]), parse(Float64, parts[3]),
                                   parse(Float64, parts[4])))
        elseif key == "mtllib" && length(parts) >= 2
            merge!(materials, _read_mtl(joinpath(dirname(path), join(parts[2:end], " "))))
        elseif key == "usemtl"
            current = join(parts[2:end], " ")
        elseif key == "f" && length(parts) >= 4
            corners = [_obj_corner(token, length(vertices), length(texcoords), length(normals))
                       for token in parts[2:end]]
            if !haskey(faces, current)
                push!(order, current)
                faces[current] = Vector{NTuple{3,Int}}[]
            end
            push!(faces[current], corners)
        end
    end
    return vertices, texcoords, normals, faces, order, materials
end

"""
Unique (v, vt, vn) corners → vertex arrays and 0-based triangle indices
(polygons fanned from their first corner). A corner without a normal gets
the area-weighted average of its faces' normals.
"""
function _obj_mesh(vertices, texcoords, normals, faces)
    index_of = Dict{NTuple{3,Int},Int32}()
    points = SVector{3,Float64}[]
    uvs = SVector{2,Float64}[]
    corner_normals = SVector{3,Float64}[]
    indices = Int32[]
    zero3 = SVector(0.0, 0.0, 0.0)
    for face in faces
        ids = Int32[]
        for corner in face
            (1 <= corner[1] <= length(vertices)) || throw(ArgumentError(
                "OBJ face refers to vertex $(corner[1]) of $(length(vertices))"))
            id = get!(index_of, corner) do
                push!(points, vertices[corner[1]])
                push!(uvs, corner[2] == 0 ? SVector(0.0, 0.0) : texcoords[corner[2]])
                push!(corner_normals, corner[3] == 0 ? zero3 : normals[corner[3]])
                Int32(length(points) - 1)
            end
            push!(ids, id)
        end
        for k in 2:length(ids)-1
            push!(indices, ids[1], ids[k], ids[k + 1])
        end
    end
    if any(==(zero3), corner_normals)
        accumulated = [zero3 for _ in points]
        for t in 1:3:length(indices)
            a = points[indices[t] + 1]
            b = points[indices[t + 1] + 1]
            c = points[indices[t + 2] + 1]
            face_normal = cross(b - a, c - a)          # length = twice the area
            for j in 0:2
                accumulated[indices[t + j] + 1] += face_normal
            end
        end
        for i in eachindex(corner_normals)
            corner_normals[i] == zero3 || continue
            n = accumulated[i]
            nn = norm(n)
            corner_normals[i] = nn > 0 ? n / nn : SVector(0.0, 0.0, 1.0)
        end
    end
    return points, uvs, corner_normals, indices
end

const _MODEL_SHADING = (0.3f0, 0.2f0, 0.4f0)        # Surface's default
const _MODEL_NORMAL_NUDGE = 1e-3                     # Surface's default

function _obj_surface(points, corner_normals, indices, color, opacity)
    pts = [Point3f(p) for p in points]
    dnp = [Point3f(p + _MODEL_NORMAL_NUDGE * n) for (p, n) in zip(points, corner_normals)]
    rgba = _rgba(color isa NTuple{3,Float64} ? RGB(color...) : color, opacity)
    return Surface(pts, dnp, fill(rgba, length(pts)), (length(pts), 1), indices,
                   _MODEL_SHADING, true, false, Mobject[], Mobject[], Updater[], false, 0.0)
end

function _obj_textured(points, uvs, corner_normals, indices, pixels, opacity)
    pts = [Point3f(p) for p in points]
    dnp = [Point3f(p + _MODEL_NORMAL_NUDGE * n) for (p, n) in zip(points, corner_normals)]
    uv = [(Float32(t[1]), Float32(1 - t[2])) for t in uvs]   # image rows run top-down (GL flips too)
    return TexturedSurface(pts, dnp, uv, (length(pts), 1), indices, pixels, Float64(opacity),
                           _MODEL_SHADING, true, false, Mobject[], Mobject[], Updater[], false, 0.0)
end

"""
    ThreeDModel(path; height=3.0, color=WHITE, opacity=1.0)

A Wavefront OBJ as a `Group` of meshes, one per material (surface.py:435):
textured through the MTL's `map_Kd` when the image is beside the file,
coloured by its `Kd` otherwise, and `color` when there is neither — GL's
white. Normals come from the file's `vn`, or are averaged from the faces.
Depth-tested, scaled to `height` and centred, like GL's.

```julia
model = ThreeDModel("teapot.obj"; height = 4)
apply_depth_test!(model)      # already on; a reminder that it lives in 3D
```
"""
function ThreeDModel(path::AbstractString; height::Real = 3.0, color = WHITE,
                     opacity::Real = 1.0)
    isfile(path) || throw(ArgumentError("model not found: «$path»"))
    vertices, texcoords, normals, faces, order, materials = _read_obj(String(path))
    isempty(vertices) && throw(ArgumentError("«$path» has no vertices — is it a Wavefront OBJ?"))
    parts = Mobject[]
    for name in order
        points, uvs, corner_normals, indices = _obj_mesh(vertices, texcoords, normals, faces[name])
        isempty(indices) && continue
        material = get(materials, name, nothing)
        image = material === nothing ? nothing : material.map_kd
        if image !== nothing && isfile(image)
            push!(parts, _obj_textured(points, uvs, corner_normals, indices,
                                       _load_pixels(image), opacity))
        else
            kd = material === nothing || material.kd === nothing ? color : material.kd
            push!(parts, _obj_surface(points, corner_normals, indices, kd, opacity))
        end
    end
    isempty(parts) && throw(ArgumentError("«$path» has no faces"))
    model = Group(parts...)
    set_height!(model, height)
    center!(model)
    return model
end
