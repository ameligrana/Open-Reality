# Metal mesh upload and draw operations

function metal_upload_mesh!(cache::MetalGPUResourceCache, device_handle::UInt64,
                            entity_id::EntityID, mesh::MeshComponent)
    gpu = MetalGPUMesh()

    # Positions (Vec3f = 3 x Float32 per vertex)
    pos_data = reinterpret(UInt8, mesh.vertices)
    GC.@preserve pos_data begin
        gpu.vertex_buffer = metal_create_buffer(device_handle, pointer(pos_data), length(pos_data), "positions")
    end

    # Normals
    if !isempty(mesh.normals)
        norm_data = reinterpret(UInt8, mesh.normals)
        GC.@preserve norm_data begin
            gpu.normal_buffer = metal_create_buffer(device_handle, pointer(norm_data), length(norm_data), "normals")
        end
    end

    # UVs (Vec2f = 2 x Float32 per vertex)
    if !isempty(mesh.uvs)
        uv_data = reinterpret(UInt8, mesh.uvs)
        GC.@preserve uv_data begin
            gpu.uv_buffer = metal_create_buffer(device_handle, pointer(uv_data), length(uv_data), "uvs")
        end
    end

    # Indices (UInt32)
    idx_data = reinterpret(UInt8, mesh.indices)
    GC.@preserve idx_data begin
        gpu.index_buffer = metal_create_buffer(device_handle, pointer(idx_data), length(idx_data), "indices")
    end
    gpu.index_count = Int32(length(mesh.indices))

    cache.meshes[entity_id] = gpu
    return gpu
end

function metal_get_or_upload_mesh!(cache::MetalGPUResourceCache, device_handle::UInt64,
                                    entity_id::EntityID, mesh::MeshComponent)
    existing = get(cache.meshes, entity_id, nothing)
    if existing !== nothing
        return existing
    end
    return metal_upload_mesh!(cache, device_handle, entity_id, mesh)
end

function metal_draw_mesh!(encoder_handle::UInt64, gpu_mesh::MetalGPUMesh)
    # Bind vertex buffers: positions=0, normals=1, uvs=2
    metal_set_vertex_buffer(encoder_handle, gpu_mesh.vertex_buffer, 0, Int32(0))
    if gpu_mesh.normal_buffer != UInt64(0)
        metal_set_vertex_buffer(encoder_handle, gpu_mesh.normal_buffer, 0, Int32(1))
    end
    if gpu_mesh.uv_buffer != UInt64(0)
        metal_set_vertex_buffer(encoder_handle, gpu_mesh.uv_buffer, 0, Int32(2))
    end

    # Draw indexed triangles
    metal_draw_indexed(encoder_handle, MTL_PRIMITIVE_TRIANGLE, gpu_mesh.index_count,
                       gpu_mesh.index_buffer, 0)
end

function metal_destroy_mesh!(gpu_mesh::MetalGPUMesh)
    gpu_mesh.vertex_buffer != UInt64(0) && metal_destroy_buffer(gpu_mesh.vertex_buffer)
    gpu_mesh.normal_buffer != UInt64(0) && metal_destroy_buffer(gpu_mesh.normal_buffer)
    gpu_mesh.uv_buffer != UInt64(0) && metal_destroy_buffer(gpu_mesh.uv_buffer)
    gpu_mesh.index_buffer != UInt64(0) && metal_destroy_buffer(gpu_mesh.index_buffer)
    gpu_mesh.vertex_buffer = UInt64(0)
    gpu_mesh.normal_buffer = UInt64(0)
    gpu_mesh.uv_buffer = UInt64(0)
    gpu_mesh.index_buffer = UInt64(0)
    gpu_mesh.index_count = Int32(0)
    return nothing
end

function metal_destroy_all_meshes!(cache::MetalGPUResourceCache)
    for (_, gpu_mesh) in cache.meshes
        metal_destroy_mesh!(gpu_mesh)
    end
    empty!(cache.meshes)
    return nothing
end
