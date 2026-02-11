# Metal TAA pass implementation

function metal_create_taa_pass!(taa::MetalTAAPass, device_handle::UInt64, width::Int, height::Int)
    taa.width = width
    taa.height = height

    color_formats = UInt32[MTL_PIXEL_FORMAT_RGBA16_FLOAT]

    taa.history_rt = metal_create_render_target(device_handle, Int32(width), Int32(height),
                                                 Int32(1), color_formats,
                                                 Int32(0), UInt32(0), "TAA_History")
    taa.history_texture = metal_get_rt_color_texture(taa.history_rt, Int32(0))

    taa.current_rt = metal_create_render_target(device_handle, Int32(width), Int32(height),
                                                 Int32(1), color_formats,
                                                 Int32(0), UInt32(0), "TAA_Current")
    taa.current_texture = metal_get_rt_color_texture(taa.current_rt, Int32(0))

    msl = _load_msl_shader("taa.metal")
    taa.taa_pipeline = metal_get_or_create_pipeline(msl, "taa_vertex", "taa_fragment";
        num_color_attachments=Int32(1), color_formats=color_formats,
        depth_format=UInt32(0), blend_enabled=Int32(0))

    taa.first_frame = true
    taa.jitter_index = 0
    taa.prev_view_proj = Mat4f(I)

    return taa
end

function metal_render_taa!(taa::MetalTAAPass, backend, input_texture::UInt64,
                            depth_texture::UInt64, view::Mat4f, proj::Mat4f,
                            cmd_buf_handle::UInt64)
    uniforms = MetalTAAUniforms(
        ntuple(i -> taa.prev_view_proj[i], 16),
        taa.feedback,
        taa.first_frame ? Int32(1) : Int32(0),
        Float32(taa.width),
        Float32(taa.height)
    )
    uniform_buf = _create_uniform_buffer(backend.device_handle, uniforms, "taa_uniforms")

    quad_buf = backend.deferred_pipeline.quad_vertex_buffer

    encoder = metal_begin_render_pass(cmd_buf_handle, taa.current_rt,
                                       MTL_LOAD_CLEAR, MTL_STORE_STORE,
                                       0.0f0, 0.0f0, 0.0f0, 0.0f0, 1.0)
    metal_set_render_pipeline(encoder, taa.taa_pipeline)
    metal_set_viewport(encoder, 0.0, 0.0, Float64(taa.width), Float64(taa.height), 0.0, 1.0)
    metal_set_vertex_buffer(encoder, quad_buf, 0, Int32(0))
    metal_set_fragment_buffer(encoder, uniform_buf, 0, Int32(7))
    metal_set_fragment_texture(encoder, input_texture, Int32(0))
    metal_set_fragment_texture(encoder, taa.history_texture, Int32(1))
    metal_set_fragment_texture(encoder, depth_texture, Int32(2))
    sampler_h = metal_create_sampler(backend.device_handle, Int32(1), Int32(1), Int32(0), Int32(0))
    metal_set_fragment_sampler(encoder, sampler_h, Int32(0))
    metal_draw_primitives(encoder, MTL_PRIMITIVE_TRIANGLE, Int32(0), Int32(6))
    metal_end_render_pass(encoder)

    # Copy current → history via blit
    metal_blit_texture(cmd_buf_handle, taa.current_texture, taa.history_texture)

    # Update state
    taa.prev_view_proj = proj * view
    taa.first_frame = false
    taa.jitter_index = (taa.jitter_index + 1) % 8

    metal_destroy_buffer(uniform_buf)
    return taa.current_texture
end

function metal_destroy_taa_pass!(taa::MetalTAAPass)
    taa.history_rt != UInt64(0) && metal_destroy_render_target(taa.history_rt)
    taa.current_rt != UInt64(0) && metal_destroy_render_target(taa.current_rt)
    taa.history_rt = UInt64(0)
    taa.current_rt = UInt64(0)
    taa.history_texture = UInt64(0)
    taa.current_texture = UInt64(0)
    taa.taa_pipeline = UInt64(0)
    return nothing
end
