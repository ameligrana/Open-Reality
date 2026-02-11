# Metal SSAO pass implementation

function metal_create_ssao_pass!(ssao::MetalSSAOPass, device_handle::UInt64, width::Int, height::Int)
    ssao.width = width
    ssao.height = height

    # SSAO output (R16F single-channel)
    color_formats_r16 = UInt32[MTL_PIXEL_FORMAT_R16_FLOAT]
    ssao.ssao_rt = metal_create_render_target(device_handle, Int32(width), Int32(height),
                                               Int32(1), color_formats_r16,
                                               Int32(0), UInt32(0), "SSAO")
    ssao.ssao_texture = metal_get_rt_color_texture(ssao.ssao_rt, Int32(0))

    # Blur output
    ssao.blur_rt = metal_create_render_target(device_handle, Int32(width), Int32(height),
                                               Int32(1), color_formats_r16,
                                               Int32(0), UInt32(0), "SSAO_Blur")
    ssao.blur_texture = metal_get_rt_color_texture(ssao.blur_rt, Int32(0))

    # Generate SSAO kernel
    ssao.kernel = generate_ssao_kernel(ssao.kernel_size)

    # Generate noise texture (4x4 random rotation vectors)
    noise_data = Float32[]
    for _ in 1:16
        push!(noise_data, rand(Float32) * 2.0f0 - 1.0f0)
        push!(noise_data, rand(Float32) * 2.0f0 - 1.0f0)
        push!(noise_data, 0.0f0)
        push!(noise_data, 0.0f0)
    end
    noise_pixels = reinterpret(UInt8, noise_data)
    ssao.noise_texture = metal_create_texture_2d(device_handle, Int32(4), Int32(4),
                                                   MTL_PIXEL_FORMAT_RGBA16_FLOAT,
                                                   Int32(0), MTL_USAGE_SHADER_READ, "ssao_noise")
    GC.@preserve noise_pixels begin
        metal_upload_texture_2d(ssao.noise_texture, pointer(noise_pixels), Int32(4), Int32(4), Int32(16))
    end

    # Pipelines
    msl = _load_msl_shader("ssao.metal")
    ssao.ssao_pipeline = metal_get_or_create_pipeline(msl, "ssao_vertex", "ssao_fragment";
        num_color_attachments=Int32(1), color_formats=color_formats_r16,
        depth_format=UInt32(0), blend_enabled=Int32(0))
    ssao.blur_pipeline = metal_get_or_create_pipeline(msl, "ssao_vertex", "ssao_blur_fragment";
        num_color_attachments=Int32(1), color_formats=color_formats_r16,
        depth_format=UInt32(0), blend_enabled=Int32(0))

    return ssao
end

function metal_render_ssao!(ssao::MetalSSAOPass, backend, gbuffer::MetalGBuffer,
                             proj::Mat4f, cmd_buf_handle::UInt64)
    # Pack SSAO uniforms
    uniforms = pack_ssao_uniforms(ssao.kernel, proj, ssao.radius, ssao.bias, ssao.power,
                                   ssao.width, ssao.height)
    uniform_buf = _create_uniform_buffer(backend.device_handle, uniforms, "ssao_uniforms")

    quad_buf = backend.deferred_pipeline.quad_vertex_buffer

    # SSAO pass
    encoder = metal_begin_render_pass(cmd_buf_handle, ssao.ssao_rt,
                                       MTL_LOAD_CLEAR, MTL_STORE_STORE,
                                       1.0f0, 1.0f0, 1.0f0, 1.0f0, 1.0)
    metal_set_render_pipeline(encoder, ssao.ssao_pipeline)
    metal_set_viewport(encoder, 0.0, 0.0, Float64(ssao.width), Float64(ssao.height), 0.0, 1.0)
    metal_set_vertex_buffer(encoder, quad_buf, 0, Int32(0))
    metal_set_fragment_buffer(encoder, uniform_buf, 0, Int32(7))
    metal_set_fragment_texture(encoder, gbuffer.normal_roughness, Int32(0))
    metal_set_fragment_texture(encoder, gbuffer.depth, Int32(1))
    metal_set_fragment_texture(encoder, ssao.noise_texture, Int32(2))
    sampler_h = metal_create_sampler(backend.device_handle, Int32(0), Int32(0), Int32(0), Int32(0))
    metal_set_fragment_sampler(encoder, sampler_h, Int32(0))
    metal_draw_primitives(encoder, MTL_PRIMITIVE_TRIANGLE, Int32(0), Int32(6))
    metal_end_render_pass(encoder)

    # Blur pass
    encoder = metal_begin_render_pass(cmd_buf_handle, ssao.blur_rt,
                                       MTL_LOAD_CLEAR, MTL_STORE_STORE,
                                       1.0f0, 1.0f0, 1.0f0, 1.0f0, 1.0)
    metal_set_render_pipeline(encoder, ssao.blur_pipeline)
    metal_set_viewport(encoder, 0.0, 0.0, Float64(ssao.width), Float64(ssao.height), 0.0, 1.0)
    metal_set_vertex_buffer(encoder, quad_buf, 0, Int32(0))
    metal_set_fragment_texture(encoder, ssao.ssao_texture, Int32(0))
    metal_set_fragment_sampler(encoder, sampler_h, Int32(0))
    metal_draw_primitives(encoder, MTL_PRIMITIVE_TRIANGLE, Int32(0), Int32(6))
    metal_end_render_pass(encoder)

    metal_destroy_buffer(uniform_buf)

    return ssao.blur_texture
end

function metal_destroy_ssao_pass!(ssao::MetalSSAOPass)
    ssao.ssao_rt != UInt64(0) && metal_destroy_render_target(ssao.ssao_rt)
    ssao.blur_rt != UInt64(0) && metal_destroy_render_target(ssao.blur_rt)
    ssao.noise_texture != UInt64(0) && metal_destroy_texture(ssao.noise_texture)
    ssao.ssao_rt = UInt64(0)
    ssao.blur_rt = UInt64(0)
    ssao.ssao_texture = UInt64(0)
    ssao.blur_texture = UInt64(0)
    ssao.noise_texture = UInt64(0)
    ssao.ssao_pipeline = UInt64(0)
    ssao.blur_pipeline = UInt64(0)
    return nothing
end
