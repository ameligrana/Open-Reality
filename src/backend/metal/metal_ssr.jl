# Metal SSR pass implementation

function metal_create_ssr_pass!(ssr::MetalSSRPass, device_handle::UInt64, width::Int, height::Int)
    ssr.width = width
    ssr.height = height

    color_formats = UInt32[MTL_PIXEL_FORMAT_RGBA16_FLOAT]
    ssr.ssr_rt = metal_create_render_target(device_handle, Int32(width), Int32(height),
                                             Int32(1), color_formats,
                                             Int32(0), UInt32(0), "SSR")
    ssr.ssr_texture = metal_get_rt_color_texture(ssr.ssr_rt, Int32(0))

    msl = _load_msl_shader("ssr.metal")
    ssr.ssr_pipeline = metal_get_or_create_pipeline(msl, "ssr_vertex", "ssr_fragment";
        num_color_attachments=Int32(1), color_formats=color_formats,
        depth_format=UInt32(0), blend_enabled=Int32(0))

    return ssr
end

function metal_render_ssr!(ssr::MetalSSRPass, backend, gbuffer::MetalGBuffer,
                            lighting_texture::UInt64, view::Mat4f, proj::Mat4f,
                            cam_pos::Vec3f, cmd_buf_handle::UInt64)
    inv_proj = Mat4f(inv(proj))
    uniforms = MetalSSRUniforms(
        ntuple(i -> proj[i], 16),
        ntuple(i -> view[i], 16),
        ntuple(i -> inv_proj[i], 16),
        (cam_pos[1], cam_pos[2], cam_pos[3], 0.0f0),
        (Float32(ssr.width), Float32(ssr.height)),
        Int32(ssr.max_steps),
        ssr.max_distance,
        ssr.thickness,
        0.0f0, 0.0f0, 0.0f0
    )
    uniform_buf = _create_uniform_buffer(backend.device_handle, uniforms, "ssr_uniforms")

    quad_buf = backend.deferred_pipeline.quad_vertex_buffer

    encoder = metal_begin_render_pass(cmd_buf_handle, ssr.ssr_rt,
                                       MTL_LOAD_CLEAR, MTL_STORE_STORE,
                                       0.0f0, 0.0f0, 0.0f0, 0.0f0, 1.0)
    metal_set_render_pipeline(encoder, ssr.ssr_pipeline)
    metal_set_viewport(encoder, 0.0, 0.0, Float64(ssr.width), Float64(ssr.height), 0.0, 1.0)
    metal_set_vertex_buffer(encoder, quad_buf, 0, Int32(0))
    metal_set_fragment_buffer(encoder, uniform_buf, 0, Int32(7))
    metal_set_fragment_texture(encoder, gbuffer.normal_roughness, Int32(0))
    metal_set_fragment_texture(encoder, gbuffer.depth, Int32(1))
    metal_set_fragment_texture(encoder, lighting_texture, Int32(2))
    sampler_h = metal_create_sampler(backend.device_handle, Int32(1), Int32(1), Int32(0), Int32(0))
    metal_set_fragment_sampler(encoder, sampler_h, Int32(0))
    metal_draw_primitives(encoder, MTL_PRIMITIVE_TRIANGLE, Int32(0), Int32(6))
    metal_end_render_pass(encoder)

    metal_destroy_buffer(uniform_buf)
    return ssr.ssr_texture
end

function metal_destroy_ssr_pass!(ssr::MetalSSRPass)
    ssr.ssr_rt != UInt64(0) && metal_destroy_render_target(ssr.ssr_rt)
    ssr.ssr_rt = UInt64(0)
    ssr.ssr_texture = UInt64(0)
    ssr.ssr_pipeline = UInt64(0)
    return nothing
end
