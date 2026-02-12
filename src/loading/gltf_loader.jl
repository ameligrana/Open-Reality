# glTF 2.0 model loader

# Helper struct for deferred skin resolution during glTF loading
struct _DeferredSkin
    joint_node_indices::Vector{Int}
end

# Helper struct for deferred component addition (after scene construction)
struct _DeferredComponent
    target_entity::EntityID
    component::Component
end

"""
    load_gltf(path::String; base_dir::String = dirname(path)) -> Vector{EntityDef}

Load a glTF 2.0 file (.gltf or .glb) and return a vector of EntityDefs.
Traverses the glTF node hierarchy to preserve transforms and parent-child relationships.
Each node becomes an entity with TransformComponent; mesh primitives become child entities.
"""
function load_gltf(path::String; base_dir::String = dirname(abspath(path)))
    gltf = GLTFLib.load(path)

    # Load buffer data
    buffers_data = _load_gltf_buffers(gltf, base_dir)

    entities_out = EntityDef[]
    node_to_entity = Dict{Int, EntityID}()

    # No nodes: fall back to mesh-based loading for compatibility
    if gltf.nodes === nothing || isempty(gltf.nodes)
        gltf.meshes === nothing && return entities_out
        for mesh in gltf.meshes
            for prim in mesh.primitives
                mesh_comp = _extract_gltf_mesh(gltf, prim, buffers_data)
                mat_comp = _extract_gltf_material(gltf, prim, base_dir, buffers_data)
                push!(entities_out, entity([mesh_comp, mat_comp, transform()]))
            end
        end
        return entities_out
    end

    # Pre-extract mesh primitives as (MeshComponent, MaterialComponent) tuples
    mesh_primitives = Dict{Int, Vector{Tuple{MeshComponent, MaterialComponent}}}()
    if gltf.meshes !== nothing
        for (mi, mesh) in enumerate(gltf.meshes)
            prims = Tuple{MeshComponent, MaterialComponent}[]
            for prim in mesh.primitives
                mesh_comp = _extract_gltf_mesh(gltf, prim, buffers_data)
                mat_comp = _extract_gltf_material(gltf, prim, base_dir, buffers_data)
                push!(prims, (mesh_comp, mat_comp))
            end
            mesh_primitives[mi - 1] = prims  # 0-based mesh index
        end
    end

    # Find root nodes from the default scene, or by exclusion
    root_node_indices = _find_gltf_root_nodes(gltf)

    # Pre-compute skin data: which nodes are joints, their inverse bind matrices
    joint_bone_data = Dict{Int, Tuple{Mat4f, Int, String}}()  # joint_node_idx → (ibm, bone_index, name)
    skin_joint_lists = Dict{Int, Vector{Int}}()  # skin_idx → [joint_node_indices]
    node_skin_map = Dict{Int, Int}()  # node_idx → skin_idx (for nodes that reference a skin)

    if gltf.skins !== nothing && !isempty(gltf.skins)
        for (si, skin) in enumerate(gltf.skins)
            skin_idx = si - 1
            joints = skin.joints
            joints === nothing && continue
            isempty(joints) && continue

            # Read inverse bind matrices
            ibms = Mat4f[]
            if skin.inverseBindMatrices !== nothing
                ibm_data = _read_accessor_data(gltf, skin.inverseBindMatrices, buffers_data)
                for i in 1:16:length(ibm_data)
                    i + 15 > length(ibm_data) && break
                    m = Mat4f(
                        ibm_data[i],    ibm_data[i+1],  ibm_data[i+2],  ibm_data[i+3],
                        ibm_data[i+4],  ibm_data[i+5],  ibm_data[i+6],  ibm_data[i+7],
                        ibm_data[i+8],  ibm_data[i+9],  ibm_data[i+10], ibm_data[i+11],
                        ibm_data[i+12], ibm_data[i+13], ibm_data[i+14], ibm_data[i+15]
                    )
                    push!(ibms, m)
                end
            end

            joint_indices = Int[]
            for (idx, jni) in enumerate(joints)
                joint_node_idx = Int(jni)
                push!(joint_indices, joint_node_idx)
                ibm = idx <= length(ibms) ? ibms[idx] : Mat4f(I)
                node = gltf.nodes[joint_node_idx]
                bone_name = (hasproperty(node, :name) && node.name !== nothing) ? node.name : "bone_$idx"
                joint_bone_data[joint_node_idx] = (ibm, idx - 1, bone_name)
            end
            skin_joint_lists[skin_idx] = joint_indices
        end

        # Map nodes to their skin reference
        if gltf.nodes !== nothing
            for (ni, node) in enumerate(gltf.nodes)
                if hasproperty(node, :skin) && node.skin !== nothing
                    node_skin_map[ni - 1] = Int(node.skin)
                end
            end
        end
    end

    # Build node EntityDefs with DFS position tracking for animation remapping.
    # The DFS counter tracks the 1-based position each entity will occupy when
    # scene() flattens the hierarchy via add_entity_from_def.
    dfs_counter = Ref(0)

    # Deferred skin components: added after scene construction via add_component!
    deferred_skin_components = Tuple{EntityID, Component}[]

    function _build_node_entity(node_idx::Int)::EntityDef
        node = gltf.nodes[node_idx]  # ZVector is already 0-indexed

        # Track this node's DFS position for animation targeting
        dfs_counter[] += 1
        node_to_entity[node_idx] = EntityID(dfs_counter[])

        tc = _extract_node_transform(node)
        node_components = Any[tc]
        children = Any[]

        # If this node is a joint, add BoneComponent
        if haskey(joint_bone_data, node_idx)
            ibm, bone_idx, bone_name = joint_bone_data[node_idx]
            push!(node_components, BoneComponent(
                inverse_bind_matrix=ibm,
                bone_index=bone_idx,
                name=bone_name
            ))
        end

        # Mesh primitives become child entities under this node's transform
        if node.mesh !== nothing && haskey(mesh_primitives, node.mesh)
            # Check if this node references a skin
            has_skin = haskey(node_skin_map, node_idx)
            skin_idx = has_skin ? node_skin_map[node_idx] : -1

            for (mc, matc) in mesh_primitives[node.mesh]
                dfs_counter[] += 1
                mesh_eid = EntityID(dfs_counter[])

                # If skin is present, create SkinnedMeshComponent for deferred addition
                if has_skin && haskey(skin_joint_lists, skin_idx)
                    joint_node_indices = skin_joint_lists[skin_idx]
                    # bone_entities will be resolved after all nodes are built
                    push!(deferred_skin_components, (mesh_eid, _DeferredSkin(joint_node_indices)))
                end

                push!(children, entity([mc, matc, transform()]))
            end
        end

        # Recurse into child nodes
        if node.children !== nothing
            for child_idx in node.children
                push!(children, _build_node_entity(Int(child_idx)))
            end
        end

        return entity(node_components; children=children)
    end

    for root_idx in root_node_indices
        push!(entities_out, _build_node_entity(root_idx))
    end

    # Resolve deferred skin components (now that node_to_entity is fully populated)
    if !isempty(deferred_skin_components) && !isempty(entities_out)
        for (mesh_eid, deferred) in deferred_skin_components
            bone_entities = EntityID[]
            for jni in deferred.joint_node_indices
                if haskey(node_to_entity, jni)
                    push!(bone_entities, node_to_entity[jni])
                end
            end
            if !isempty(bone_entities)
                skin_comp = SkinnedMeshComponent(
                    bone_entities=bone_entities,
                    bone_matrices=fill(Mat4f(I), length(bone_entities))
                )
                # Store as a deferred add_component! call (entity_id, component)
                push!(entities_out[1].components, _DeferredComponent(mesh_eid, skin_comp))
            end
        end
    end

    # Extract animations if present
    anim_clips = _extract_gltf_animations(gltf, buffers_data, node_to_entity)
    if !isempty(anim_clips)
        anim_comp = AnimationComponent(
            clips=anim_clips,
            active_clip=1,
            playing=true,
            looping=true
        )
        if !isempty(entities_out)
            push!(entities_out[1].components, anim_comp)
        end
    end

    return entities_out
end

# ---- Node hierarchy helpers ----

"""Find root node indices for the glTF file."""
function _find_gltf_root_nodes(gltf::GLTFLib.Object)
    root_indices = Int[]

    # Try the default scene
    if gltf.scene !== nothing && gltf.scenes !== nothing
        scene_obj = gltf.scenes[gltf.scene]
        if scene_obj.nodes !== nothing && !isempty(scene_obj.nodes)
            return [Int(n) for n in scene_obj.nodes]
        end
    end

    # Fallback: nodes not referenced as children of any other node
    child_set = Set{Int}()
    for (_, node) in enumerate(gltf.nodes)
        if node.children !== nothing
            for c in node.children
                push!(child_set, Int(c))
            end
        end
    end
    for (i, _) in enumerate(gltf.nodes)
        node_idx = i - 1  # enumerate on ZVector gives 1-based counter
        if !(node_idx in child_set)
            push!(root_indices, node_idx)
        end
    end

    return root_indices
end

"""Extract a TransformComponent from a glTF node's TRS or matrix."""
function _extract_node_transform(node)
    if getfield(node, :matrix) !== nothing
        m = node.matrix  # Cfloat[16], 1-based Julia Vector, column-major
        # Translation from column 3
        pos = Vec3d(Float64(m[13]), Float64(m[14]), Float64(m[15]))
        # Scale as column magnitudes
        sx = sqrt(Float64(m[1])^2 + Float64(m[2])^2 + Float64(m[3])^2)
        sy = sqrt(Float64(m[5])^2 + Float64(m[6])^2 + Float64(m[7])^2)
        sz = sqrt(Float64(m[9])^2 + Float64(m[10])^2 + Float64(m[11])^2)
        scl = Vec3d(sx, sy, sz)
        # Normalized rotation matrix
        inv_sx = sx > 0.0 ? 1.0 / sx : 0.0
        inv_sy = sy > 0.0 ? 1.0 / sy : 0.0
        inv_sz = sz > 0.0 ? 1.0 / sz : 0.0
        r11 = Float64(m[1]) * inv_sx;  r21 = Float64(m[2]) * inv_sx;  r31 = Float64(m[3]) * inv_sx
        r12 = Float64(m[5]) * inv_sy;  r22 = Float64(m[6]) * inv_sy;  r32 = Float64(m[7]) * inv_sy
        r13 = Float64(m[9]) * inv_sz;  r23 = Float64(m[10]) * inv_sz; r33 = Float64(m[11]) * inv_sz
        rot = _rotation_matrix_to_quaternion(r11, r12, r13, r21, r22, r23, r31, r32, r33)
        return transform(position=pos, rotation=rot, scale=scl)
    else
        # TRS (getproperty defaults provide identity if not explicitly set)
        t = node.translation  # [x, y, z]
        r = node.rotation     # [x, y, z, w]
        s = node.scale        # [sx, sy, sz]
        pos = Vec3d(Float64(t[1]), Float64(t[2]), Float64(t[3]))
        rot = Quaterniond(Float64(r[4]), Float64(r[1]), Float64(r[2]), Float64(r[3]))
        scl = Vec3d(Float64(s[1]), Float64(s[2]), Float64(s[3]))
        return transform(position=pos, rotation=rot, scale=scl)
    end
end

"""Convert a 3x3 rotation matrix to a quaternion (Shepperd's method)."""
function _rotation_matrix_to_quaternion(r11, r12, r13, r21, r22, r23, r31, r32, r33)
    trace = r11 + r22 + r33
    if trace > 0.0
        s = 0.5 / sqrt(trace + 1.0)
        w = 0.25 / s
        x = (r32 - r23) * s
        y = (r13 - r31) * s
        z = (r21 - r12) * s
    elseif r11 > r22 && r11 > r33
        s = 2.0 * sqrt(1.0 + r11 - r22 - r33)
        w = (r32 - r23) / s
        x = 0.25 * s
        y = (r12 + r21) / s
        z = (r13 + r31) / s
    elseif r22 > r33
        s = 2.0 * sqrt(1.0 + r22 - r11 - r33)
        w = (r13 - r31) / s
        x = (r12 + r21) / s
        y = 0.25 * s
        z = (r23 + r32) / s
    else
        s = 2.0 * sqrt(1.0 + r33 - r11 - r22)
        w = (r21 - r12) / s
        x = (r13 + r31) / s
        y = (r23 + r32) / s
        z = 0.25 * s
    end
    return Quaterniond(w, x, y, z)
end

# ---- Buffer loading ----

function _load_gltf_buffers(gltf::GLTFLib.Object, base_dir::String)
    buffers_data = Vector{UInt8}[]
    gltf.buffers === nothing && return buffers_data

    for buf in gltf.buffers
        if buf.uri !== nothing
            if startswith(buf.uri, "data:")
                # Data URI (base64 embedded)
                data_start = findfirst(',', buf.uri)
                if data_start !== nothing
                    encoded = buf.uri[data_start+1:end]
                    push!(buffers_data, base64decode(encoded))
                else
                    push!(buffers_data, UInt8[])
                end
            else
                # External file
                filepath = joinpath(base_dir, buf.uri)
                push!(buffers_data, read(filepath))
            end
        else
            push!(buffers_data, UInt8[])
        end
    end

    return buffers_data
end

# ---- Accessor data extraction ----

const GLTF_COMPONENT_SIZES = Dict(
    5120 => 1,  # BYTE
    5121 => 1,  # UNSIGNED_BYTE
    5122 => 2,  # SHORT
    5123 => 2,  # UNSIGNED_SHORT
    5125 => 4,  # UNSIGNED_INT
    5126 => 4,  # FLOAT
)

const GLTF_TYPE_COUNTS = Dict(
    "SCALAR" => 1,
    "VEC2" => 2,
    "VEC3" => 3,
    "VEC4" => 4,
    "MAT2" => 4,
    "MAT3" => 9,
    "MAT4" => 16,
)

function _read_accessor_data(gltf::GLTFLib.Object, accessor_idx::Int, buffers_data::Vector{Vector{UInt8}})
    accessor = gltf.accessors[accessor_idx]
    if accessor.bufferView === nothing
        @warn "glTF accessor $accessor_idx has no bufferView, returning empty data"
        return Float32[]
    end

    bv = gltf.bufferViews[accessor.bufferView]
    buf_data = buffers_data[bv.buffer + 1]  # buffers are 0-indexed in glTF, 1-indexed in our array

    bv_offset = something(bv.byteOffset, 0)
    acc_offset = something(accessor.byteOffset, 0)
    byte_offset = bv_offset + acc_offset
    component_size = get(GLTF_COMPONENT_SIZES, accessor.componentType, 4)
    type_count = get(GLTF_TYPE_COUNTS, accessor.type, 1)
    stride = bv.byteStride !== nothing ? bv.byteStride : component_size * type_count

    n = accessor.count
    result = Float32[]

    for i in 0:(n-1)
        offset = byte_offset + i * stride
        for j in 0:(type_count-1)
            elem_offset = offset + j * component_size + 1  # +1 for Julia 1-based

            if accessor.componentType == 5126  # FLOAT
                val = reinterpret(Float32, buf_data[elem_offset:elem_offset+3])[1]
                push!(result, val)
            elseif accessor.componentType == 5125  # UNSIGNED_INT
                val = reinterpret(UInt32, buf_data[elem_offset:elem_offset+3])[1]
                push!(result, Float32(val))
            elseif accessor.componentType == 5123  # UNSIGNED_SHORT
                val = reinterpret(UInt16, buf_data[elem_offset:elem_offset+1])[1]
                push!(result, Float32(val))
            elseif accessor.componentType == 5121  # UNSIGNED_BYTE
                push!(result, Float32(buf_data[elem_offset]))
            end
        end
    end

    return result
end

function _read_index_data(gltf::GLTFLib.Object, accessor_idx::Int, buffers_data::Vector{Vector{UInt8}})
    accessor = gltf.accessors[accessor_idx]
    if accessor.bufferView === nothing
        @warn "glTF index accessor $accessor_idx has no bufferView, returning empty data"
        return UInt32[]
    end

    bv = gltf.bufferViews[accessor.bufferView]
    buf_data = buffers_data[bv.buffer + 1]

    bv_offset = something(bv.byteOffset, 0)
    acc_offset = something(accessor.byteOffset, 0)
    byte_offset = bv_offset + acc_offset
    component_size = get(GLTF_COMPONENT_SIZES, accessor.componentType, 4)
    stride = bv.byteStride !== nothing ? bv.byteStride : component_size

    n = accessor.count
    result = UInt32[]

    for i in 0:(n-1)
        offset = byte_offset + i * stride + 1  # +1 for Julia 1-based

        if accessor.componentType == 5125  # UNSIGNED_INT
            val = reinterpret(UInt32, buf_data[offset:offset+3])[1]
            push!(result, val)
        elseif accessor.componentType == 5123  # UNSIGNED_SHORT
            val = reinterpret(UInt16, buf_data[offset:offset+1])[1]
            push!(result, UInt32(val))
        elseif accessor.componentType == 5121  # UNSIGNED_BYTE
            push!(result, UInt32(buf_data[offset]))
        end
    end

    return result
end

# ---- Mesh extraction ----

"""Generate sequential triangle indices for non-indexed primitives."""
function _generate_fallback_indices(num_vertices::Int, mode::Int)
    if mode == 5  # TRIANGLE_STRIP
        indices = UInt32[]
        for i in 0:(num_vertices - 3)
            if i % 2 == 0
                push!(indices, UInt32(i), UInt32(i + 1), UInt32(i + 2))
            else
                push!(indices, UInt32(i + 1), UInt32(i), UInt32(i + 2))
            end
        end
        return indices
    elseif mode == 6  # TRIANGLE_FAN
        indices = UInt32[]
        for i in 1:(num_vertices - 2)
            push!(indices, UInt32(0), UInt32(i), UInt32(i + 1))
        end
        return indices
    else  # TRIANGLES (mode 4) and default
        return UInt32.(0:(num_vertices - 1))
    end
end

function _extract_gltf_mesh(gltf::GLTFLib.Object, prim::GLTFLib.Primitive, buffers_data::Vector{Vector{UInt8}})
    positions = Point3f[]
    normals = Vec3f[]
    uvs = Vec2f[]
    indices = UInt32[]

    # Positions
    if haskey(prim.attributes, "POSITION")
        pos_data = _read_accessor_data(gltf, prim.attributes["POSITION"], buffers_data)
        for i in 1:3:length(pos_data)
            push!(positions, Point3f(pos_data[i], pos_data[i+1], pos_data[i+2]))
        end
    end

    # Normals
    if haskey(prim.attributes, "NORMAL")
        norm_data = _read_accessor_data(gltf, prim.attributes["NORMAL"], buffers_data)
        for i in 1:3:length(norm_data)
            push!(normals, Vec3f(norm_data[i], norm_data[i+1], norm_data[i+2]))
        end
    end

    # UVs (TEXCOORD_0)
    if haskey(prim.attributes, "TEXCOORD_0")
        uv_data = _read_accessor_data(gltf, prim.attributes["TEXCOORD_0"], buffers_data)
        for i in 1:2:length(uv_data)
            push!(uvs, Vec2f(uv_data[i], uv_data[i+1]))
        end
    end

    # Indices
    if prim.indices !== nothing
        indices = _read_index_data(gltf, prim.indices, buffers_data)
    elseif !isempty(positions)
        # Fallback: generate sequential indices for non-indexed primitives
        prim_mode = prim.mode !== nothing ? Int(prim.mode) : 4
        indices = _generate_fallback_indices(length(positions), prim_mode)
    end

    # Bone weights (WEIGHTS_0) — vec4 per vertex
    bone_weights = Vec4f[]
    if haskey(prim.attributes, "WEIGHTS_0")
        w_data = _read_accessor_data(gltf, prim.attributes["WEIGHTS_0"], buffers_data)
        for i in 1:4:length(w_data)
            i + 3 > length(w_data) && break
            push!(bone_weights, Vec4f(w_data[i], w_data[i+1], w_data[i+2], w_data[i+3]))
        end
    end

    # Bone indices (JOINTS_0) — 4 joint indices per vertex
    bone_indices = BoneIndices4[]
    if haskey(prim.attributes, "JOINTS_0")
        j_data = _read_accessor_data(gltf, prim.attributes["JOINTS_0"], buffers_data)
        for i in 1:4:length(j_data)
            i + 3 > length(j_data) && break
            push!(bone_indices, (UInt16(j_data[i]), UInt16(j_data[i+1]),
                                 UInt16(j_data[i+2]), UInt16(j_data[i+3])))
        end
    end

    # Compute normals if not provided
    if isempty(normals) && !isempty(positions) && !isempty(indices)
        normals = _compute_averaged_normals(positions, indices)
    end

    return MeshComponent(vertices=positions, indices=indices, normals=normals, uvs=uvs,
                         bone_weights=bone_weights, bone_indices=bone_indices)
end

# ---- Material extraction ----

function _extract_gltf_material(gltf::GLTFLib.Object, prim::GLTFLib.Primitive, base_dir::String, buffers_data::Vector{Vector{UInt8}})
    if prim.material === nothing || gltf.materials === nothing
        return MaterialComponent()
    end

    mat = gltf.materials[prim.material]
    pbr = mat.pbrMetallicRoughness

    # Base color
    bc = pbr.baseColorFactor
    color = RGB{Float32}(Float32(bc[1]), Float32(bc[2]), Float32(bc[3]))
    metallic = Float32(pbr.metallicFactor)
    roughness = Float32(pbr.roughnessFactor)

    # Texture references
    albedo_map = _resolve_gltf_texture(gltf, pbr.baseColorTexture, base_dir, buffers_data)
    normal_map = _resolve_gltf_texture(gltf, mat.normalTexture, base_dir, buffers_data)
    mr_map = _resolve_gltf_texture(gltf, pbr.metallicRoughnessTexture, base_dir, buffers_data)
    ao_map = _resolve_gltf_texture(gltf, mat.occlusionTexture, base_dir, buffers_data)
    emissive_map = _resolve_gltf_texture(gltf, mat.emissiveTexture, base_dir, buffers_data)

    emissive_factor = Vec3f(0, 0, 0)
    if mat.emissiveFactor !== nothing
        ef = mat.emissiveFactor
        emissive_factor = Vec3f(Float32(ef[1]), Float32(ef[2]), Float32(ef[3]))
    end

    # Alpha mode
    opacity = Float32(1.0)
    alpha_cutoff = Float32(0.0)
    if hasproperty(mat, :alphaMode) && mat.alphaMode !== nothing
        if mat.alphaMode == "BLEND"
            opacity = length(bc) >= 4 ? Float32(bc[4]) : Float32(1.0)
        elseif mat.alphaMode == "MASK"
            alpha_cutoff = hasproperty(mat, :alphaCutoff) && mat.alphaCutoff !== nothing ?
                Float32(mat.alphaCutoff) : Float32(0.5)
        end
    end

    # Clear coat extension (KHR_materials_clearcoat)
    clearcoat = Float32(0.0)
    clearcoat_roughness = Float32(0.0)
    if hasproperty(mat, :extensions) && mat.extensions !== nothing
        exts = mat.extensions
        if exts isa Dict && haskey(exts, "KHR_materials_clearcoat")
            cc_ext = exts["KHR_materials_clearcoat"]
            if cc_ext isa Dict
                clearcoat = Float32(get(cc_ext, "clearcoatFactor", 0.0))
                clearcoat_roughness = Float32(get(cc_ext, "clearcoatRoughnessFactor", 0.0))
            end
        end
    end

    return MaterialComponent(
        color=color, metallic=metallic, roughness=roughness,
        albedo_map=albedo_map, normal_map=normal_map,
        metallic_roughness_map=mr_map, ao_map=ao_map,
        emissive_map=emissive_map, emissive_factor=emissive_factor,
        opacity=opacity, alpha_cutoff=alpha_cutoff,
        clearcoat=clearcoat, clearcoat_roughness=clearcoat_roughness
    )
end

function _resolve_gltf_texture(gltf::GLTFLib.Object, tex_info, base_dir::String, buffers_data::Vector{Vector{UInt8}})
    tex_info === nothing && return nothing
    gltf.textures === nothing && return nothing

    texture = gltf.textures[tex_info.index]
    texture.source === nothing && return nothing

    gltf.images === nothing && return nothing
    image = gltf.images[texture.source]

    # Case 1: External file URI
    if image.uri !== nothing && !startswith(image.uri, "data:")
        return TextureRef(joinpath(base_dir, image.uri))
    end

    # Case 2: Data URI (base64 embedded)
    if image.uri !== nothing && startswith(image.uri, "data:")
        return _resolve_data_uri_texture(image.uri)
    end

    # Case 3: BufferView (glb embedded)
    if image.uri === nothing && image.bufferView !== nothing
        return _resolve_bufferview_texture(gltf, image, buffers_data)
    end

    return nothing
end

"""Decode a data-URI image and return a TextureRef pointing to a temp file."""
function _resolve_data_uri_texture(uri::String)
    # Parse MIME type from data:[<MIME>][;base64],<data>
    mime_match = match(r"^data:([^;,]+)", uri)
    mime_type = mime_match !== nothing ? mime_match.captures[1] : "image/png"

    data_start = findfirst(',', uri)
    data_start === nothing && return nothing
    encoded = uri[data_start+1:end]
    decoded = base64decode(encoded)

    ext = _mime_to_ext(mime_type)
    tmp_path = tempname() * ext
    write(tmp_path, decoded)

    return TextureRef(tmp_path)
end

"""Extract an image from a glTF bufferView and return a TextureRef pointing to a temp file."""
function _resolve_bufferview_texture(gltf::GLTFLib.Object, image, buffers_data::Vector{Vector{UInt8}})
    bv = gltf.bufferViews[image.bufferView]
    buf_data = buffers_data[bv.buffer + 1]  # 0-based to 1-based

    offset = something(bv.byteOffset, 0)
    len = bv.byteLength
    image_data = buf_data[offset+1:offset+len]  # +1 for Julia 1-based

    mime_type = image.mimeType !== nothing ? image.mimeType : "image/png"
    ext = _mime_to_ext(mime_type)
    tmp_path = tempname() * ext
    write(tmp_path, image_data)

    return TextureRef(tmp_path)
end

"""Map MIME type to file extension."""
function _mime_to_ext(mime::String)
    if contains(mime, "png")
        return ".png"
    elseif contains(mime, "jpeg") || contains(mime, "jpg")
        return ".jpg"
    elseif contains(mime, "webp")
        return ".webp"
    else
        return ".png"
    end
end

# ---- Animation extraction ----

const GLTF_PATH_MAP = Dict(
    "translation" => :position,
    "rotation" => :rotation,
    "scale" => :scale,
)

const GLTF_INTERP_MAP = Dict(
    "STEP" => INTERP_STEP,
    "LINEAR" => INTERP_LINEAR,
    "CUBICSPLINE" => INTERP_CUBICSPLINE,
)

function _extract_gltf_animations(gltf::GLTFLib.Object, buffers_data::Vector{Vector{UInt8}},
                                  node_to_entity::Dict{Int, EntityID})
    clips = AnimationClip[]
    (gltf.animations === nothing || isempty(gltf.animations)) && return clips

    for anim in gltf.animations
        channels_out = AnimationChannel[]
        name = hasproperty(anim, :name) && anim.name !== nothing ? anim.name : "clip"

        for ch in anim.channels
            ch.target === nothing && continue
            ch.target.node === nothing && continue

            node_idx = ch.target.node
            !haskey(node_to_entity, node_idx) && continue

            target_eid = node_to_entity[node_idx]
            path_str = ch.target.path
            !haskey(GLTF_PATH_MAP, path_str) && continue
            target_prop = GLTF_PATH_MAP[path_str]

            sampler = anim.samplers[ch.sampler + 1]  # 0-indexed in glTF

            # Read keyframe times
            times_raw = _read_accessor_data(gltf, sampler.input, buffers_data)
            times = Float32.(times_raw)

            # Read keyframe values
            values_raw = _read_accessor_data(gltf, sampler.output, buffers_data)

            interp = get(GLTF_INTERP_MAP,
                        hasproperty(sampler, :interpolation) && sampler.interpolation !== nothing ?
                            sampler.interpolation : "LINEAR",
                        INTERP_LINEAR)

            # Parse values based on target property
            values = Any[]
            if target_prop == :position || target_prop == :scale
                for i in 1:3:length(values_raw)
                    i + 2 > length(values_raw) && break
                    push!(values, Vec3d(Float64(values_raw[i]), Float64(values_raw[i+1]), Float64(values_raw[i+2])))
                end
            elseif target_prop == :rotation
                for i in 1:4:length(values_raw)
                    i + 3 > length(values_raw) && break
                    # glTF quaternions are (x, y, z, w), Quaternions.jl is (w, x, y, z)
                    push!(values, Quaterniond(
                        Float64(values_raw[i+3]),  # w
                        Float64(values_raw[i]),    # x
                        Float64(values_raw[i+1]),  # y
                        Float64(values_raw[i+2])   # z
                    ))
                end
            end

            isempty(values) && continue

            push!(channels_out, AnimationChannel(target_eid, target_prop, times, values, interp))
        end

        duration = 0.0f0
        for ch in channels_out
            if !isempty(ch.times)
                duration = max(duration, ch.times[end])
            end
        end

        !isempty(channels_out) && push!(clips, AnimationClip(name, channels_out, duration))
    end

    return clips
end
