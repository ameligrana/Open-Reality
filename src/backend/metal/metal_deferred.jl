# Metal deferred rendering pipeline orchestration

function metal_create_deferred_pipeline!(pipeline::MetalDeferredPipeline, device_handle::UInt64,
                                          width::Int, height::Int)
    # G-Buffer
    pipeline.gbuffer = MetalGBuffer(width=width, height=height)
    metal_create_gbuffer!(pipeline.gbuffer, device_handle, width, height)

    # Lighting accumulation render target (single RGBA16F)
    pipeline.lighting_rt = MetalRenderTarget(width=width, height=height)
    metal_create_render_target!(pipeline.lighting_rt, device_handle, width, height)

    # Lighting pass pipeline
    msl = _load_msl_shader("deferred_lighting.metal")
    pipeline.lighting_pipeline = metal_get_or_create_pipeline(
        msl, "deferred_lighting_vertex", "deferred_lighting_fragment";
        num_color_attachments=Int32(1),
        color_formats=UInt32[MTL_PIXEL_FORMAT_RGBA16_FLOAT],
        depth_format=MTL_PIXEL_FORMAT_DEPTH32_FLOAT,
        blend_enabled=Int32(0)
    )

    # G-Buffer shader library for material variants
    gbuffer_msl = _load_msl_shader("gbuffer.metal")
    gbuffer_color_formats = UInt32[
        MTL_PIXEL_FORMAT_RGBA16_FLOAT,
        MTL_PIXEL_FORMAT_RGBA16_FLOAT,
        MTL_PIXEL_FORMAT_RGBA16_FLOAT,
        MTL_PIXEL_FORMAT_RGBA8_UNORM
    ]
    pipeline.gbuffer_shader_library = ShaderLibrary{MetalShaderProgram}(
        "", gbuffer_msl,
        (vert, frag, key) -> metal_compile_shader_variant(
            vert, frag, key;
            num_color_attachments=Int32(4),
            color_formats=gbuffer_color_formats,
            depth_format=MTL_PIXEL_FORMAT_DEPTH32_FLOAT,
            blend_enabled=Int32(0),
            vertex_func="gbuffer_vertex",
            fragment_func="gbuffer_fragment"
        )
    )

    # Fullscreen quad vertex buffer (6 vertices: xy=position, zw=uv)
    quad_data = Float32[
        -1.0f0, -1.0f0, 0.0f0, 0.0f0,   # bottom-left
         1.0f0, -1.0f0, 1.0f0, 0.0f0,   # bottom-right
         1.0f0,  1.0f0, 1.0f0, 1.0f0,   # top-right
        -1.0f0, -1.0f0, 0.0f0, 0.0f0,   # bottom-left
         1.0f0,  1.0f0, 1.0f0, 1.0f0,   # top-right
        -1.0f0,  1.0f0, 0.0f0, 1.0f0    # top-left
    ]
    GC.@preserve quad_data begin
        pipeline.quad_vertex_buffer = metal_create_buffer(device_handle, pointer(quad_data),
                                                           sizeof(quad_data), "quad_vertices")
    end

    @info "Metal deferred pipeline created" width height
    return pipeline
end

function metal_destroy_deferred_pipeline!(pipeline::MetalDeferredPipeline)
    if pipeline.gbuffer !== nothing
        metal_destroy_gbuffer!(pipeline.gbuffer)
        pipeline.gbuffer = nothing
    end
    if pipeline.lighting_rt !== nothing
        metal_destroy_render_target!(pipeline.lighting_rt)
        pipeline.lighting_rt = nothing
    end
    if pipeline.gbuffer_shader_library !== nothing
        destroy_shader_library!(pipeline.gbuffer_shader_library)
        pipeline.gbuffer_shader_library = nothing
    end
    if pipeline.ssao_pass !== nothing
        metal_destroy_ssao_pass!(pipeline.ssao_pass)
        pipeline.ssao_pass = nothing
    end
    if pipeline.ssr_pass !== nothing
        metal_destroy_ssr_pass!(pipeline.ssr_pass)
        pipeline.ssr_pass = nothing
    end
    if pipeline.taa_pass !== nothing
        metal_destroy_taa_pass!(pipeline.taa_pass)
        pipeline.taa_pass = nothing
    end
    if pipeline.ibl_env !== nothing
        metal_destroy_ibl_environment!(pipeline.ibl_env)
        pipeline.ibl_env = nothing
    end
    if pipeline.quad_vertex_buffer != UInt64(0)
        metal_destroy_buffer(pipeline.quad_vertex_buffer)
        pipeline.quad_vertex_buffer = UInt64(0)
    end
    pipeline.lighting_pipeline = UInt64(0)
    return nothing
end

function metal_resize_deferred_pipeline!(pipeline::MetalDeferredPipeline, device_handle::UInt64,
                                          width::Int, height::Int)
    if pipeline.gbuffer !== nothing
        metal_resize_gbuffer!(pipeline.gbuffer, device_handle, width, height)
    end
    if pipeline.lighting_rt !== nothing
        metal_resize_render_target_!(pipeline.lighting_rt, width, height)
    end
    return nothing
end

function metal_render_gbuffer_pass!(backend, pipeline::MetalDeferredPipeline,
                                     opaque_entities, view::Mat4f, proj::Mat4f,
                                     cam_pos::Vec3f, cmd_buf_handle::UInt64)
    gb = pipeline.gbuffer
    if gb === nothing return nothing end

    # Begin G-Buffer render pass
    encoder = metal_begin_render_pass(cmd_buf_handle, gb.rt_handle,
                                       MTL_LOAD_CLEAR, MTL_STORE_STORE,
                                       0.0f0, 0.0f0, 0.0f0, 0.0f0, 1.0)

    # Depth stencil state
    ds_state = metal_create_depth_stencil_state(backend.device_handle, MTL_COMPARE_LESS, Int32(1))
    metal_set_depth_stencil_state(encoder, ds_state)
    metal_set_cull_mode(encoder, MTL_CULL_BACK)
    metal_set_viewport(encoder, 0.0, 0.0, Float64(gb.width), Float64(gb.height), 0.0, 1.0)

    # Per-frame uniforms
    frame_uniforms = pack_per_frame(view, proj, cam_pos, Float32(time()))
    frame_buf = _create_uniform_buffer(backend.device_handle, frame_uniforms, "gbuf_frame")

    # Default sampler
    default_sampler = metal_create_sampler(backend.device_handle, Int32(1), Int32(1), Int32(1), Int32(0))

    for (entity_id, mesh, model, normal_matrix) in opaque_entities
        material = get_component(entity_id, MaterialComponent)
        if material === nothing continue end

        # Select shader variant
        variant_key = determine_shader_variant(material)
        sp = get_or_compile_variant!(pipeline.gbuffer_shader_library, variant_key)

        metal_set_render_pipeline(encoder, sp.pipeline_handle)

        # Vertex buffers
        metal_set_vertex_buffer(encoder, frame_buf, 0, Int32(3))

        # Per-object uniforms
        obj_uniforms = pack_per_object(model, normal_matrix)
        obj_buf = _create_uniform_buffer(backend.device_handle, obj_uniforms, "gbuf_obj")
        metal_set_vertex_buffer(encoder, obj_buf, 0, Int32(4))

        # Material uniforms
        mat_uniforms = pack_material(material)
        mat_buf = _create_uniform_buffer(backend.device_handle, mat_uniforms, "gbuf_mat")
        metal_set_fragment_buffer(encoder, frame_buf, 0, Int32(3))
        metal_set_fragment_buffer(encoder, mat_buf, 0, Int32(5))

        # Bind textures
        metal_bind_material_textures!(encoder, material, backend.texture_cache, backend.device_handle)
        metal_set_fragment_sampler(encoder, default_sampler, Int32(0))

        # Draw mesh
        gpu_mesh = metal_get_or_upload_mesh!(backend.gpu_cache, backend.device_handle, entity_id, mesh)
        metal_draw_mesh!(encoder, gpu_mesh)

        metal_destroy_buffer(obj_buf)
        metal_destroy_buffer(mat_buf)
    end

    metal_end_render_pass(encoder)
    metal_destroy_buffer(frame_buf)

    return nothing
end

function metal_render_deferred_lighting_pass!(backend, pipeline::MetalDeferredPipeline,
                                               cam_pos::Vec3f, view::Mat4f, proj::Mat4f,
                                               light_data::FrameLightData,
                                               cmd_buf_handle::UInt64)
    rt = pipeline.lighting_rt
    if rt === nothing return nothing end

    encoder = metal_begin_render_pass(cmd_buf_handle, rt.handle,
                                       MTL_LOAD_CLEAR, MTL_STORE_STORE,
                                       0.0f0, 0.0f0, 0.0f0, 0.0f0, 1.0)

    metal_set_render_pipeline(encoder, pipeline.lighting_pipeline)

    # No depth test for fullscreen quad
    ds_state = metal_create_depth_stencil_state(backend.device_handle, MTL_COMPARE_ALWAYS, Int32(0))
    metal_set_depth_stencil_state(encoder, ds_state)
    metal_set_cull_mode(encoder, MTL_CULL_NONE)
    metal_set_viewport(encoder, 0.0, 0.0, Float64(rt.width), Float64(rt.height), 0.0, 1.0)

    # Bind quad vertex buffer
    metal_set_vertex_buffer(encoder, pipeline.quad_vertex_buffer, 0, Int32(0))

    # Per-frame uniforms
    frame_uniforms = pack_per_frame(view, proj, cam_pos, Float32(time()))
    frame_buf = _create_uniform_buffer(backend.device_handle, frame_uniforms, "light_frame")
    metal_set_fragment_buffer(encoder, frame_buf, 0, Int32(3))

    # Light uniforms
    light_uniforms = pack_lights(light_data)
    light_buf = _create_uniform_buffer(backend.device_handle, light_uniforms, "lights")
    metal_set_fragment_buffer(encoder, light_buf, 0, Int32(6))

    # Shadow uniforms
    has_shadows = backend.csm !== nothing && !isempty(backend.csm.cascade_matrices)
    shadow_uniforms = if has_shadows
        pack_shadow_uniforms(backend.csm, true)
    else
        MetalShadowUniforms(
            ntuple(_ -> ntuple(_ -> 0.0f0, 16), 4),
            ntuple(_ -> 0.0f0, 5),
            Int32(0), Int32(0), 0.0f0
        )
    end
    shadow_buf = _create_uniform_buffer(backend.device_handle, shadow_uniforms, "shadows")
    metal_set_fragment_buffer(encoder, shadow_buf, 0, Int32(7))

    # Bind G-Buffer textures
    gb = pipeline.gbuffer
    metal_set_fragment_texture(encoder, gb.albedo_metallic, Int32(0))
    metal_set_fragment_texture(encoder, gb.normal_roughness, Int32(1))
    metal_set_fragment_texture(encoder, gb.emissive_ao, Int32(2))
    metal_set_fragment_texture(encoder, gb.depth, Int32(3))
    metal_set_fragment_texture(encoder, gb.advanced_material, Int32(4))

    # Bind CSM shadow map textures
    if has_shadows
        for i in 1:backend.csm.num_cascades
            metal_set_fragment_texture(encoder, backend.csm.cascade_depth_textures[i], Int32(4 + i))
        end
    end

    # Bind IBL textures if available
    if pipeline.ibl_env !== nothing && pipeline.ibl_env.irradiance_map != UInt64(0)
        metal_set_fragment_texture(encoder, pipeline.ibl_env.irradiance_map, Int32(9))
        metal_set_fragment_texture(encoder, pipeline.ibl_env.prefilter_map, Int32(10))
        metal_set_fragment_texture(encoder, pipeline.ibl_env.brdf_lut, Int32(11))
    end

    # Samplers
    gbuf_sampler = metal_create_sampler(backend.device_handle, Int32(0), Int32(0), Int32(0), Int32(0))  # nearest
    shadow_sampler = metal_create_sampler(backend.device_handle, Int32(1), Int32(1), Int32(0), Int32(0))  # linear
    metal_set_fragment_sampler(encoder, gbuf_sampler, Int32(0))
    metal_set_fragment_sampler(encoder, shadow_sampler, Int32(1))

    # Draw fullscreen quad
    metal_draw_primitives(encoder, MTL_PRIMITIVE_TRIANGLE, Int32(0), Int32(6))

    metal_end_render_pass(encoder)

    metal_destroy_buffer(frame_buf)
    metal_destroy_buffer(light_buf)
    metal_destroy_buffer(shadow_buf)

    return nothing
end
