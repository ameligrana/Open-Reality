# Metal post-processing pipeline (bloom, tone mapping, FXAA)

function metal_create_post_process_pipeline!(pp::MetalPostProcessPipeline, device_handle::UInt64,
                                              width::Int, height::Int)
    color_formats = UInt32[MTL_PIXEL_FORMAT_RGBA16_FLOAT]
    color_formats_ldr = UInt32[MTL_PIXEL_FORMAT_BGRA8_UNORM]

    # Scene render target (if not rendering into deferred pipeline's output)
    pp.scene_rt = metal_create_render_target(device_handle, Int32(width), Int32(height),
                                              Int32(1), color_formats,
                                              Int32(1), MTL_PIXEL_FORMAT_DEPTH32_FLOAT, "PP_Scene")

    # Bright extraction target
    pp.bright_rt = metal_create_render_target(device_handle, Int32(width ÷ 2), Int32(height ÷ 2),
                                               Int32(1), color_formats,
                                               Int32(0), UInt32(0), "PP_Bright")

    # Bloom blur targets (ping-pong)
    for i in 1:2
        rt = metal_create_render_target(device_handle, Int32(width ÷ 2), Int32(height ÷ 2),
                                         Int32(1), color_formats,
                                         Int32(0), UInt32(0), "PP_Bloom_$i")
        push!(pp.bloom_rts, rt)
    end

    # Fullscreen quad
    quad_data = Float32[
        -1.0f0, -1.0f0, 0.0f0, 0.0f0,
         1.0f0, -1.0f0, 1.0f0, 0.0f0,
         1.0f0,  1.0f0, 1.0f0, 1.0f0,
        -1.0f0, -1.0f0, 0.0f0, 0.0f0,
         1.0f0,  1.0f0, 1.0f0, 1.0f0,
        -1.0f0,  1.0f0, 0.0f0, 1.0f0
    ]
    GC.@preserve quad_data begin
        pp.quad_vertex_buffer = metal_create_buffer(device_handle, pointer(quad_data),
                                                     sizeof(quad_data), "pp_quad")
    end

    # Pipelines
    bloom_extract_msl = _load_msl_shader("bloom_extract.metal")
    pp.bright_extract_pipeline = metal_get_or_create_pipeline(
        bloom_extract_msl, "bloom_vertex", "bloom_extract_fragment";
        num_color_attachments=Int32(1), color_formats=color_formats,
        depth_format=UInt32(0), blend_enabled=Int32(0))

    bloom_blur_msl = _load_msl_shader("bloom_blur.metal")
    pp.blur_pipeline = metal_get_or_create_pipeline(
        bloom_blur_msl, "blur_vertex", "blur_fragment";
        num_color_attachments=Int32(1), color_formats=color_formats,
        depth_format=UInt32(0), blend_enabled=Int32(0))

    composite_msl = _load_msl_shader("composite.metal")
    pp.composite_pipeline = metal_get_or_create_pipeline(
        composite_msl, "composite_vertex", "composite_fragment";
        num_color_attachments=Int32(1), color_formats=color_formats_ldr,
        depth_format=UInt32(0), blend_enabled=Int32(0))

    fxaa_msl = _load_msl_shader("fxaa.metal")
    pp.fxaa_pipeline = metal_get_or_create_pipeline(
        fxaa_msl, "fxaa_vertex", "fxaa_fragment";
        num_color_attachments=Int32(1), color_formats=color_formats_ldr,
        depth_format=UInt32(0), blend_enabled=Int32(0))

    return pp
end

function metal_run_post_process!(pp::MetalPostProcessPipeline, backend,
                                  input_texture::UInt64, cmd_buf_handle::UInt64,
                                  width::Int, height::Int)
    config = pp.config
    quad_buf = pp.quad_vertex_buffer
    sampler_h = metal_create_sampler(backend.device_handle, Int32(1), Int32(1), Int32(0), Int32(1))

    # Get tone mapping mode int
    tm_mode = if config.tone_mapping == TONEMAP_REINHARD
        Int32(0)
    elseif config.tone_mapping == TONEMAP_ACES
        Int32(1)
    else  # TONEMAP_UNCHARTED2
        Int32(2)
    end

    final_texture = input_texture

    # ---- Bloom ----
    if config.bloom_enabled
        # 1. Extract bright pixels
        encoder = metal_begin_render_pass(cmd_buf_handle, pp.bright_rt,
                                           MTL_LOAD_CLEAR, MTL_STORE_STORE,
                                           0.0f0, 0.0f0, 0.0f0, 0.0f0, 1.0)
        metal_set_render_pipeline(encoder, pp.bright_extract_pipeline)
        metal_set_viewport(encoder, 0.0, 0.0, Float64(width ÷ 2), Float64(height ÷ 2), 0.0, 1.0)
        metal_set_vertex_buffer(encoder, quad_buf, 0, Int32(0))

        bloom_uniforms = MetalPostProcessUniforms(config.bloom_threshold, config.bloom_intensity,
                                                    config.gamma, tm_mode, Int32(0), 0.0f0, 0.0f0, 0.0f0)
        ubuf = _create_uniform_buffer(backend.device_handle, bloom_uniforms, "bloom_extract")
        metal_set_fragment_buffer(encoder, ubuf, 0, Int32(7))
        metal_set_fragment_texture(encoder, input_texture, Int32(0))
        metal_set_fragment_sampler(encoder, sampler_h, Int32(0))
        metal_draw_primitives(encoder, MTL_PRIMITIVE_TRIANGLE, Int32(0), Int32(6))
        metal_end_render_pass(encoder)
        metal_destroy_buffer(ubuf)

        bright_texture = metal_get_rt_color_texture(pp.bright_rt, Int32(0))

        # 2. Gaussian blur (ping-pong, 5 iterations)
        blur_input = bright_texture
        for iter in 1:5
            for pass in 0:1  # 0=horizontal, 1=vertical
                target_rt = pp.bloom_rts[pass + 1]
                encoder = metal_begin_render_pass(cmd_buf_handle, target_rt,
                                                   MTL_LOAD_CLEAR, MTL_STORE_STORE,
                                                   0.0f0, 0.0f0, 0.0f0, 0.0f0, 1.0)
                metal_set_render_pipeline(encoder, pp.blur_pipeline)
                metal_set_viewport(encoder, 0.0, 0.0, Float64(width ÷ 2), Float64(height ÷ 2), 0.0, 1.0)
                metal_set_vertex_buffer(encoder, quad_buf, 0, Int32(0))

                blur_uniforms = MetalPostProcessUniforms(config.bloom_threshold, config.bloom_intensity,
                                                          config.gamma, tm_mode, Int32(1 - pass),
                                                          0.0f0, 0.0f0, 0.0f0)
                ubuf = _create_uniform_buffer(backend.device_handle, blur_uniforms, "bloom_blur")
                metal_set_fragment_buffer(encoder, ubuf, 0, Int32(7))
                metal_set_fragment_texture(encoder, blur_input, Int32(0))
                metal_set_fragment_sampler(encoder, sampler_h, Int32(0))
                metal_draw_primitives(encoder, MTL_PRIMITIVE_TRIANGLE, Int32(0), Int32(6))
                metal_end_render_pass(encoder)
                metal_destroy_buffer(ubuf)

                blur_input = metal_get_rt_color_texture(target_rt, Int32(0))
            end
        end

        final_texture = input_texture  # composite will combine HDR + bloom
    end

    # ---- Final composite (tone mapping + bloom combine + gamma) → drawable ----
    # Render to drawable
    encoder = metal_begin_render_pass_drawable(cmd_buf_handle, MTL_LOAD_CLEAR,
                                                0.0f0, 0.0f0, 0.0f0, 1.0f0)
    metal_set_render_pipeline(encoder, pp.composite_pipeline)
    metal_set_viewport(encoder, 0.0, 0.0, Float64(width), Float64(height), 0.0, 1.0)
    metal_set_vertex_buffer(encoder, quad_buf, 0, Int32(0))

    composite_uniforms = MetalPostProcessUniforms(config.bloom_threshold, config.bloom_intensity,
                                                    config.gamma, tm_mode, Int32(0),
                                                    0.0f0, 0.0f0, 0.0f0)
    ubuf = _create_uniform_buffer(backend.device_handle, composite_uniforms, "composite")
    metal_set_fragment_buffer(encoder, ubuf, 0, Int32(7))
    metal_set_fragment_texture(encoder, final_texture, Int32(0))

    # Bloom texture (last blur output or black)
    if config.bloom_enabled && !isempty(pp.bloom_rts)
        bloom_tex = metal_get_rt_color_texture(pp.bloom_rts[end], Int32(0))
        metal_set_fragment_texture(encoder, bloom_tex, Int32(1))
    end
    metal_set_fragment_sampler(encoder, sampler_h, Int32(0))
    metal_draw_primitives(encoder, MTL_PRIMITIVE_TRIANGLE, Int32(0), Int32(6))
    metal_end_render_pass(encoder)
    metal_destroy_buffer(ubuf)

    return nothing
end

function metal_destroy_post_process_pipeline!(pp::MetalPostProcessPipeline)
    pp.scene_rt != UInt64(0) && metal_destroy_render_target(pp.scene_rt)
    pp.bright_rt != UInt64(0) && metal_destroy_render_target(pp.bright_rt)
    for rt in pp.bloom_rts
        metal_destroy_render_target(rt)
    end
    pp.quad_vertex_buffer != UInt64(0) && metal_destroy_buffer(pp.quad_vertex_buffer)
    pp.scene_rt = UInt64(0)
    pp.bright_rt = UInt64(0)
    empty!(pp.bloom_rts)
    pp.quad_vertex_buffer = UInt64(0)
    pp.composite_pipeline = UInt64(0)
    pp.bright_extract_pipeline = UInt64(0)
    pp.blur_pipeline = UInt64(0)
    pp.fxaa_pipeline = UInt64(0)
    return nothing
end
