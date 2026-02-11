# Metal shadow map and cascaded shadow map implementation

function metal_create_shadow_map_rt!(sm::MetalShadowMap, device_handle::UInt64)
    # Depth-only render target (no color attachments)
    color_formats = UInt32[]
    sm.rt_handle = metal_create_render_target(device_handle, Int32(sm.width), Int32(sm.height),
                                               Int32(0), color_formats,
                                               Int32(1), MTL_PIXEL_FORMAT_DEPTH32_FLOAT,
                                               "ShadowMap")
    sm.depth_texture = metal_get_rt_depth_texture(sm.rt_handle)
    return sm
end

function metal_create_csm_rt!(csm::MetalCascadedShadowMap, device_handle::UInt64,
                               near::Float32, far::Float32)
    csm.split_distances = compute_cascade_splits(near, far, csm.num_cascades)

    for i in 1:csm.num_cascades
        color_formats = UInt32[]
        rt_handle = metal_create_render_target(device_handle, Int32(csm.resolution), Int32(csm.resolution),
                                                Int32(0), color_formats,
                                                Int32(1), MTL_PIXEL_FORMAT_DEPTH32_FLOAT,
                                                "CSM_Cascade_$i")
        push!(csm.cascade_rt_handles, rt_handle)
        push!(csm.cascade_depth_textures, metal_get_rt_depth_texture(rt_handle))
        push!(csm.cascade_matrices, Mat4f(I))
    end

    # Create depth-only pipeline
    msl = _load_msl_shader("shadow_depth.metal")
    csm.depth_pipeline = metal_get_or_create_pipeline(msl, "shadow_vertex", "shadow_fragment";
                                                        num_color_attachments=Int32(0),
                                                        color_formats=UInt32[],
                                                        depth_format=MTL_PIXEL_FORMAT_DEPTH32_FLOAT,
                                                        blend_enabled=Int32(0))
    return csm
end

function metal_render_csm_passes!(backend, csm::MetalCascadedShadowMap, view::Mat4f, proj::Mat4f,
                                   light_dir::Vec3f, cmd_buf_handle::UInt64)
    for cascade_idx in 1:csm.num_cascades
        near = csm.split_distances[cascade_idx]
        far = csm.split_distances[cascade_idx + 1]

        # Compute light space matrix for this cascade
        light_matrix = compute_cascade_light_matrix(view, proj, near, far, light_dir)
        csm.cascade_matrices[cascade_idx] = light_matrix

        # Begin depth-only render pass
        encoder = metal_begin_render_pass(cmd_buf_handle, csm.cascade_rt_handles[cascade_idx],
                                           MTL_LOAD_CLEAR, MTL_STORE_STORE,
                                           0.0f0, 0.0f0, 0.0f0, 0.0f0, 1.0)

        metal_set_render_pipeline(encoder, csm.depth_pipeline)

        # Create depth stencil state (less, write enabled)
        ds_state = metal_create_depth_stencil_state(backend.device_handle, MTL_COMPARE_LESS, Int32(1))
        metal_set_depth_stencil_state(encoder, ds_state)

        # Cull front faces (reduces peter-panning)
        metal_set_cull_mode(encoder, MTL_CULL_FRONT)
        metal_set_viewport(encoder, 0.0, 0.0, Float64(csm.resolution), Float64(csm.resolution), 0.0, 1.0)

        # Pack per-frame uniforms with light matrix
        frame_uniforms = pack_per_frame(light_matrix, Mat4f(I), Vec3f(0,0,0), 0.0f0)
        # Override: for shadow pass, view=light_matrix, proj=I (already baked into light_matrix)
        frame_uniforms = MetalPerFrameUniforms(
            ntuple(i -> light_matrix[i], 16),  # view = light_matrix
            ntuple(_ -> 0.0f0, 16),             # proj = identity (baked into light_matrix)
            ntuple(_ -> 0.0f0, 16),
            (0.0f0, 0.0f0, 0.0f0, 0.0f0),
            0.0f0, 0.0f0, 0.0f0, 0.0f0
        )
        # Actually, the shadow_depth.metal uses proj * view * model.
        # For CSM, light_matrix = proj_ortho * view_light, so set view=I, proj=light_matrix
        frame_uniforms = MetalPerFrameUniforms(
            ntuple(i -> Mat4f(I)[i], 16),       # view = I
            ntuple(i -> light_matrix[i], 16),    # proj = light_matrix
            ntuple(_ -> 0.0f0, 16),
            (0.0f0, 0.0f0, 0.0f0, 0.0f0),
            0.0f0, 0.0f0, 0.0f0, 0.0f0
        )
        frame_buf = _create_uniform_buffer(backend.device_handle, frame_uniforms, "shadow_frame")
        metal_set_vertex_buffer(encoder, frame_buf, 0, Int32(3))

        # Render all mesh entities
        iterate_components(MeshComponent) do entity_id, mesh
            isempty(mesh.indices) && return

            world_transform = get_world_transform(entity_id)
            model = Mat4f(world_transform)
            normal_matrix = SMatrix{3,3,Float32,9}(I)  # not needed for shadows

            obj_uniforms = pack_per_object(model, normal_matrix)
            obj_buf = _create_uniform_buffer(backend.device_handle, obj_uniforms, "shadow_obj")
            metal_set_vertex_buffer(encoder, obj_buf, 0, Int32(4))

            gpu_mesh = metal_get_or_upload_mesh!(backend.gpu_cache, backend.device_handle, entity_id, mesh)
            metal_draw_mesh!(encoder, gpu_mesh)

            metal_destroy_buffer(obj_buf)
        end

        metal_end_render_pass(encoder)
        metal_destroy_buffer(frame_buf)
    end

    return nothing
end

function metal_destroy_shadow_map!(sm::MetalShadowMap)
    if sm.rt_handle != UInt64(0)
        metal_destroy_render_target(sm.rt_handle)
        sm.rt_handle = UInt64(0)
        sm.depth_texture = UInt64(0)
    end
    return nothing
end

function metal_destroy_csm!(csm::MetalCascadedShadowMap)
    for rt in csm.cascade_rt_handles
        metal_destroy_render_target(rt)
    end
    empty!(csm.cascade_rt_handles)
    empty!(csm.cascade_depth_textures)
    empty!(csm.cascade_matrices)
    empty!(csm.split_distances)
    csm.depth_pipeline = UInt64(0)
    return nothing
end
