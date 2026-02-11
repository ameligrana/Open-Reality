# Metal IBL (Image-Based Lighting) implementation
# Handles equirect-to-cubemap, irradiance convolution, specular prefilter, and BRDF LUT.

# IBL uniform struct matching MSL layout
struct MetalIBLUniforms
    view::NTuple{16, Float32}        # float4x4
    projection::NTuple{16, Float32}  # float4x4
    roughness::Float32
    _pad1::Float32
    _pad2::Float32
    _pad3::Float32
end

# Cube vertex data (36 vertices, 3 floats each) for rendering cubemap faces
const _IBL_CUBE_VERTICES = Float32[
    -1, 1,-1,  -1,-1,-1,   1,-1,-1,   1,-1,-1,   1, 1,-1,  -1, 1,-1,  # -Z
    -1,-1, 1,  -1,-1,-1,  -1, 1,-1,  -1, 1,-1,  -1, 1, 1,  -1,-1, 1,  # -X
     1,-1,-1,   1,-1, 1,   1, 1, 1,   1, 1, 1,   1, 1,-1,   1,-1,-1,  # +X
    -1,-1, 1,  -1, 1, 1,   1, 1, 1,   1, 1, 1,   1,-1, 1,  -1,-1, 1,  # +Z
    -1, 1,-1,   1, 1,-1,   1, 1, 1,   1, 1, 1,  -1, 1, 1,  -1, 1,-1,  # +Y
    -1,-1,-1,  -1,-1, 1,   1,-1,-1,   1,-1,-1,  -1,-1, 1,   1,-1, 1   # -Y
]

# View matrices for each cubemap face (look_at from origin)
function _ibl_cube_view_matrices()
    return [
        look_at_matrix(Vec3f(0,0,0), Vec3f( 1, 0, 0), Vec3f(0,-1, 0)),  # +X
        look_at_matrix(Vec3f(0,0,0), Vec3f(-1, 0, 0), Vec3f(0,-1, 0)),  # -X
        look_at_matrix(Vec3f(0,0,0), Vec3f( 0, 1, 0), Vec3f(0, 0, 1)),  # +Y
        look_at_matrix(Vec3f(0,0,0), Vec3f( 0,-1, 0), Vec3f(0, 0,-1)),  # -Y
        look_at_matrix(Vec3f(0,0,0), Vec3f( 0, 0, 1), Vec3f(0,-1, 0)),  # +Z
        look_at_matrix(Vec3f(0,0,0), Vec3f( 0, 0,-1), Vec3f(0,-1, 0)),  # -Z
    ]
end

function _mat4f_to_ntuple(m::Mat4f)
    return ntuple(i -> Float32(m[i]), 16)
end

function _render_cube_faces!(cmd_buf_handle::UInt64, cube_texture::UInt64, face_size::Int32,
                              mip_level::Int32, pipeline::UInt64, cube_vb::UInt64,
                              uniforms_buf::UInt64, sampler::UInt64,
                              view_matrices, projection::Mat4f, roughness::Float32;
                              source_texture::UInt64 = UInt64(0))
    for face in 0:5
        # Pack IBL uniforms for this face
        u = MetalIBLUniforms(
            _mat4f_to_ntuple(view_matrices[face + 1]),
            _mat4f_to_ntuple(projection),
            roughness, 0.0f0, 0.0f0, 0.0f0
        )
        u_ref = Ref(u)
        GC.@preserve u_ref begin
            metal_update_buffer(uniforms_buf, Ptr{Cvoid}(pointer_from_objref(u_ref)), 0, sizeof(MetalIBLUniforms))
        end

        # Begin render pass targeting this cube face
        encoder = metal_begin_render_pass_cube_face(cmd_buf_handle, cube_texture,
                                                     Int32(face), mip_level, MTL_LOAD_CLEAR,
                                                     0.0f0, 0.0f0, 0.0f0, 1.0f0)

        mip_size = max(Int32(1), face_size >> mip_level)
        metal_set_viewport(encoder, 0.0, 0.0, Float64(mip_size), Float64(mip_size), 0.0, 1.0)
        metal_set_render_pipeline(encoder, pipeline)
        metal_set_cull_mode(encoder, MTL_CULL_NONE)

        # Bind cube vertex buffer at index 0
        metal_set_vertex_buffer(encoder, cube_vb, 0, Int32(0))
        # Bind uniforms at index 3 (vertex + fragment)
        metal_set_vertex_buffer(encoder, uniforms_buf, 0, Int32(3))
        metal_set_fragment_buffer(encoder, uniforms_buf, 0, Int32(3))

        # Bind source texture at index 0
        if source_texture != UInt64(0)
            metal_set_fragment_texture(encoder, source_texture, Int32(0))
            metal_set_fragment_sampler(encoder, sampler, Int32(0))
        end

        # Draw cube (36 vertices, non-indexed)
        metal_draw_primitives(encoder, MTL_PRIMITIVE_TRIANGLE, Int32(0), Int32(36))

        metal_end_render_pass(encoder)
    end
end

function metal_create_ibl_environment!(ibl::MetalIBLEnvironment, device_handle::UInt64,
                                        path::String, cmd_buf_handle::UInt64)
    # Load HDR image
    img = try
        FileIO.load(path)
    catch e
        @warn "Failed to load IBL environment map" path exception=e
        return ibl
    end

    h, w = size(img)

    # Convert to Float32 RGBA
    hdr_pixels = Vector{Float32}(undef, w * h * 4)
    for row in 1:h, col in 1:w
        c = img[row, col]
        idx = ((row - 1) * w + (col - 1)) * 4
        hdr_pixels[idx + 1] = Float32(c.r)
        hdr_pixels[idx + 2] = Float32(c.g)
        hdr_pixels[idx + 3] = Float32(c.b)
        hdr_pixels[idx + 4] = 1.0f0
    end

    # Upload equirectangular texture
    equirect_tex = metal_create_texture_2d(device_handle, Int32(w), Int32(h),
                                            MTL_PIXEL_FORMAT_RGBA16_FLOAT,
                                            Int32(0), MTL_USAGE_SHADER_READ, "ibl_equirect")
    hdr_bytes = reinterpret(UInt8, hdr_pixels)
    GC.@preserve hdr_bytes begin
        metal_upload_texture_2d(equirect_tex, pointer(hdr_bytes), Int32(w), Int32(h), Int32(16))
    end

    # Create cubemap textures
    cube_size = Int32(512)
    ibl.environment_map = metal_create_texture_cube(device_handle, cube_size,
                                                      MTL_PIXEL_FORMAT_RGBA16_FLOAT,
                                                      Int32(1), "ibl_env_cubemap")

    irr_size = Int32(32)
    ibl.irradiance_map = metal_create_texture_cube(device_handle, irr_size,
                                                     MTL_PIXEL_FORMAT_RGBA16_FLOAT,
                                                     Int32(0), "ibl_irradiance")

    pref_size = Int32(128)
    ibl.prefilter_map = metal_create_texture_cube(device_handle, pref_size,
                                                    MTL_PIXEL_FORMAT_RGBA16_FLOAT,
                                                    Int32(1), "ibl_prefilter")

    # BRDF LUT (2D)
    ibl.brdf_lut = metal_create_texture_2d(device_handle, Int32(512), Int32(512),
                                             MTL_PIXEL_FORMAT_RGBA16_FLOAT,
                                             Int32(0),
                                             MTL_USAGE_SHADER_READ | MTL_USAGE_RENDER_TARGET,
                                             "ibl_brdf_lut")

    # Create shared resources for IBL rendering
    cube_vb = metal_create_buffer(device_handle, Ptr{Cvoid}(pointer(_IBL_CUBE_VERTICES)),
                                   sizeof(_IBL_CUBE_VERTICES), "ibl_cube_vb")

    uniforms_buf = metal_create_buffer(device_handle, C_NULL, sizeof(MetalIBLUniforms), "ibl_uniforms")

    # Linear sampler for IBL texture reads
    sampler = metal_create_sampler(device_handle, Int32(1), Int32(1), Int32(1), Int32(0))

    # Projection matrix: 90° FOV for cubemap capture
    projection = perspective_matrix(90.0f0, 1.0f0, 0.1f0, 10.0f0)
    view_matrices = _ibl_cube_view_matrices()

    # IBL pipelines (all render to RGBA16F, no depth, no blend)
    ibl_color_fmts = UInt32[MTL_PIXEL_FORMAT_RGBA16_FLOAT]
    no_depth = UInt32(0xFF)  # sentinel for no depth attachment

    # --- 1. Equirect-to-cubemap ---
    equirect_msl = _load_msl_shader("ibl_equirect.metal")
    equirect_pipeline = metal_get_or_create_pipeline(equirect_msl,
        "ibl_cube_vertex", "equirect_to_cubemap_fragment";
        num_color_attachments=Int32(1), color_formats=ibl_color_fmts,
        depth_format=no_depth, blend_enabled=Int32(0))

    _render_cube_faces!(cmd_buf_handle, ibl.environment_map, cube_size, Int32(0),
                         equirect_pipeline, cube_vb, uniforms_buf, sampler,
                         view_matrices, projection, 0.0f0;
                         source_texture=equirect_tex)

    # Generate mipmaps for environment map (needed for prefilter sampling)
    metal_generate_mipmaps(cmd_buf_handle, ibl.environment_map)

    # --- 2. Irradiance convolution ---
    irradiance_msl = _load_msl_shader("ibl_irradiance.metal")
    irradiance_pipeline = metal_get_or_create_pipeline(irradiance_msl,
        "irradiance_vertex", "irradiance_fragment";
        num_color_attachments=Int32(1), color_formats=ibl_color_fmts,
        depth_format=no_depth, blend_enabled=Int32(0))

    _render_cube_faces!(cmd_buf_handle, ibl.irradiance_map, irr_size, Int32(0),
                         irradiance_pipeline, cube_vb, uniforms_buf, sampler,
                         view_matrices, projection, 0.0f0;
                         source_texture=ibl.environment_map)

    # --- 3. Specular prefilter (mip levels = roughness) ---
    prefilter_msl = _load_msl_shader("ibl_prefilter.metal")
    prefilter_pipeline = metal_get_or_create_pipeline(prefilter_msl,
        "prefilter_vertex", "prefilter_fragment";
        num_color_attachments=Int32(1), color_formats=ibl_color_fmts,
        depth_format=no_depth, blend_enabled=Int32(0))

    max_mip_levels = 5
    for mip in 0:(max_mip_levels - 1)
        roughness = Float32(mip) / Float32(max_mip_levels - 1)
        _render_cube_faces!(cmd_buf_handle, ibl.prefilter_map, pref_size, Int32(mip),
                             prefilter_pipeline, cube_vb, uniforms_buf, sampler,
                             view_matrices, projection, roughness;
                             source_texture=ibl.environment_map)
    end

    # --- 4. BRDF LUT ---
    brdf_msl = _load_msl_shader("ibl_brdf_lut.metal")
    # Quad vertex buffer for fullscreen pass (same as post-process quad format)
    quad_data = Float32[
        -1.0, 1.0, 0.0, 1.0,
        -1.0,-1.0, 0.0, 0.0,
         1.0,-1.0, 1.0, 0.0,
        -1.0, 1.0, 0.0, 1.0,
         1.0,-1.0, 1.0, 0.0,
         1.0, 1.0, 1.0, 1.0,
    ]
    quad_vb = metal_create_buffer(device_handle, Ptr{Cvoid}(pointer(quad_data)),
                                   sizeof(quad_data), "ibl_brdf_quad")

    brdf_pipeline = metal_get_or_create_pipeline(brdf_msl,
        "brdf_lut_vertex", "brdf_lut_fragment";
        num_color_attachments=Int32(1), color_formats=ibl_color_fmts,
        depth_format=no_depth, blend_enabled=Int32(0))

    encoder = metal_begin_render_pass_texture(cmd_buf_handle, ibl.brdf_lut, MTL_LOAD_CLEAR,
                                               0.0f0, 0.0f0, 0.0f0, 1.0f0)
    metal_set_viewport(encoder, 0.0, 0.0, 512.0, 512.0, 0.0, 1.0)
    metal_set_render_pipeline(encoder, brdf_pipeline)
    metal_set_vertex_buffer(encoder, quad_vb, 0, Int32(0))
    metal_draw_primitives(encoder, MTL_PRIMITIVE_TRIANGLE, Int32(0), Int32(6))
    metal_end_render_pass(encoder)

    # Clean up temporary resources
    metal_destroy_buffer(cube_vb)
    metal_destroy_buffer(uniforms_buf)
    metal_destroy_buffer(quad_vb)
    metal_destroy_texture(equirect_tex)

    @info "Metal IBL environment created" path cube_size irr_size pref_size
    return ibl
end

function metal_destroy_ibl_environment!(ibl::MetalIBLEnvironment)
    ibl.environment_map != UInt64(0) && metal_destroy_texture(ibl.environment_map)
    ibl.irradiance_map != UInt64(0) && metal_destroy_texture(ibl.irradiance_map)
    ibl.prefilter_map != UInt64(0) && metal_destroy_texture(ibl.prefilter_map)
    ibl.brdf_lut != UInt64(0) && metal_destroy_texture(ibl.brdf_lut)
    ibl.environment_map = UInt64(0)
    ibl.irradiance_map = UInt64(0)
    ibl.prefilter_map = UInt64(0)
    ibl.brdf_lut = UInt64(0)
    return nothing
end
