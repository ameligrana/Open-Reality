# Metal uniform buffer structs
# These must match MSL struct layouts exactly (std140-like alignment).
# Metal requires float4 alignment for float4x4, and float4 padding for float3.

# ---- Per-Frame Uniforms ----
# Bound to vertex [[buffer(3)]] and fragment [[buffer(3)]]

struct MetalPerFrameUniforms
    view::NTuple{16, Float32}         # float4x4
    projection::NTuple{16, Float32}   # float4x4
    inv_view_proj::NTuple{16, Float32} # float4x4
    camera_pos::NTuple{4, Float32}    # float4 (xyz + padding)
    time::Float32
    _pad1::Float32
    _pad2::Float32
    _pad3::Float32
end

function pack_per_frame(view::Mat4f, proj::Mat4f, cam_pos::Vec3f, t::Float32)
    vp = proj * view
    ivp = Mat4f(inv(vp))
    MetalPerFrameUniforms(
        ntuple(i -> view[i], 16),
        ntuple(i -> proj[i], 16),
        ntuple(i -> ivp[i], 16),
        (cam_pos[1], cam_pos[2], cam_pos[3], 0.0f0),
        t, 0.0f0, 0.0f0, 0.0f0
    )
end

# ---- Per-Object Uniforms ----
# Bound to vertex [[buffer(4)]] and fragment [[buffer(4)]]

struct MetalPerObjectUniforms
    model::NTuple{16, Float32}        # float4x4
    normal_matrix_col0::NTuple{4, Float32}  # float4 (first col of 3x3 + pad)
    normal_matrix_col1::NTuple{4, Float32}  # float4
    normal_matrix_col2::NTuple{4, Float32}  # float4
end

function pack_per_object(model::Mat4f, normal_matrix::SMatrix{3,3,Float32,9})
    MetalPerObjectUniforms(
        ntuple(i -> model[i], 16),
        (normal_matrix[1,1], normal_matrix[2,1], normal_matrix[3,1], 0.0f0),
        (normal_matrix[1,2], normal_matrix[2,2], normal_matrix[3,2], 0.0f0),
        (normal_matrix[1,3], normal_matrix[2,3], normal_matrix[3,3], 0.0f0)
    )
end

# ---- Material Uniforms ----
# Bound to fragment [[buffer(5)]]

struct MetalMaterialUniforms
    albedo::NTuple{4, Float32}        # float4 (rgb + opacity)
    metallic::Float32
    roughness::Float32
    ao::Float32
    alpha_cutoff::Float32
    emissive_factor::NTuple{4, Float32}  # float4 (rgb + pad)
    clearcoat::Float32
    clearcoat_roughness::Float32
    subsurface::Float32
    parallax_scale::Float32
    has_albedo_map::Int32
    has_normal_map::Int32
    has_metallic_roughness_map::Int32
    has_ao_map::Int32
    has_emissive_map::Int32
    has_height_map::Int32
    _pad1::Int32
    _pad2::Int32
end

function pack_material(mat::MaterialComponent)
    MetalMaterialUniforms(
        (mat.color[1], mat.color[2], mat.color[3], mat.opacity),
        mat.metallic,
        mat.roughness,
        1.0f0,  # default AO
        mat.alpha_cutoff,
        (mat.emissive_factor[1], mat.emissive_factor[2], mat.emissive_factor[3], 0.0f0),
        mat.clearcoat,
        mat.clearcoat_roughness,
        mat.subsurface,
        mat.parallax_height_scale,
        mat.albedo_map !== nothing ? Int32(1) : Int32(0),
        mat.normal_map !== nothing ? Int32(1) : Int32(0),
        mat.metallic_roughness_map !== nothing ? Int32(1) : Int32(0),
        mat.ao_map !== nothing ? Int32(1) : Int32(0),
        mat.emissive_map !== nothing ? Int32(1) : Int32(0),
        (mat.height_map !== nothing && mat.parallax_height_scale > 0.0f0) ? Int32(1) : Int32(0),
        Int32(0), Int32(0)
    )
end

# ---- Light Uniforms ----
# Bound to fragment [[buffer(6)]]

const METAL_MAX_POINT_LIGHTS = 16
const METAL_MAX_DIR_LIGHTS = 4

struct MetalPointLightData
    position::NTuple{4, Float32}   # float4 (xyz + pad)
    color::NTuple{4, Float32}      # float4 (rgb + pad)
    intensity::Float32
    range::Float32
    _pad1::Float32
    _pad2::Float32
end

struct MetalDirLightData
    direction::NTuple{4, Float32}  # float4 (xyz + pad)
    color::NTuple{4, Float32}      # float4 (rgb + pad)
    intensity::Float32
    _pad1::Float32
    _pad2::Float32
    _pad3::Float32
end

struct MetalLightUniforms
    point_lights::NTuple{16, MetalPointLightData}
    dir_lights::NTuple{4, MetalDirLightData}
    num_point_lights::Int32
    num_dir_lights::Int32
    has_ibl::Int32
    ibl_intensity::Float32
end

function _empty_point_light()
    MetalPointLightData(
        (0.0f0, 0.0f0, 0.0f0, 0.0f0),
        (0.0f0, 0.0f0, 0.0f0, 0.0f0),
        0.0f0, 0.0f0, 0.0f0, 0.0f0
    )
end

function _empty_dir_light()
    MetalDirLightData(
        (0.0f0, 0.0f0, 0.0f0, 0.0f0),
        (0.0f0, 0.0f0, 0.0f0, 0.0f0),
        0.0f0, 0.0f0, 0.0f0, 0.0f0
    )
end

function pack_lights(light_data::FrameLightData)
    point_lights = ntuple(METAL_MAX_POINT_LIGHTS) do i
        if i <= length(light_data.point_positions)
            pos = light_data.point_positions[i]
            col = light_data.point_colors[i]
            MetalPointLightData(
                (pos[1], pos[2], pos[3], 0.0f0),
                (col[1], col[2], col[3], 0.0f0),
                light_data.point_intensities[i],
                light_data.point_ranges[i],
                0.0f0, 0.0f0
            )
        else
            _empty_point_light()
        end
    end

    dir_lights = ntuple(METAL_MAX_DIR_LIGHTS) do i
        if i <= length(light_data.dir_directions)
            dir = light_data.dir_directions[i]
            col = light_data.dir_colors[i]
            MetalDirLightData(
                (dir[1], dir[2], dir[3], 0.0f0),
                (col[1], col[2], col[3], 0.0f0),
                light_data.dir_intensities[i],
                0.0f0, 0.0f0, 0.0f0
            )
        else
            _empty_dir_light()
        end
    end

    MetalLightUniforms(
        point_lights,
        dir_lights,
        Int32(length(light_data.point_positions)),
        Int32(length(light_data.dir_directions)),
        light_data.ibl_enabled ? Int32(1) : Int32(0),
        light_data.ibl_intensity
    )
end

# ---- Shadow Uniforms ----
# Bound to fragment [[buffer(7)]]

const METAL_MAX_CASCADES = 4

struct MetalShadowUniforms
    cascade_matrices::NTuple{4, NTuple{16, Float32}}  # 4 x float4x4
    cascade_splits::NTuple{5, Float32}                  # num_cascades + 1
    num_cascades::Int32
    has_shadows::Int32
    _pad1::Float32
end

function pack_shadow_uniforms(csm::MetalCascadedShadowMap, has_shadows::Bool)
    mats = ntuple(METAL_MAX_CASCADES) do i
        if i <= length(csm.cascade_matrices)
            m = csm.cascade_matrices[i]
            ntuple(j -> m[j], 16)
        else
            ntuple(_ -> 0.0f0, 16)
        end
    end

    splits = ntuple(5) do i
        if i <= length(csm.split_distances)
            csm.split_distances[i]
        else
            0.0f0
        end
    end

    MetalShadowUniforms(
        mats, splits,
        Int32(csm.num_cascades),
        has_shadows ? Int32(1) : Int32(0),
        0.0f0
    )
end

# ---- SSAO Uniforms ----
# Bound to fragment [[buffer(7)]] during SSAO pass

struct MetalSSAOUniforms
    samples::NTuple{64, NTuple{4, Float32}}  # 64 x float4 (xyz + pad)
    projection::NTuple{16, Float32}           # float4x4
    kernel_size::Int32
    radius::Float32
    bias::Float32
    power::Float32
    screen_width::Float32
    screen_height::Float32
    _pad1::Float32
    _pad2::Float32
end

function pack_ssao_uniforms(kernel::Vector{Vec3f}, proj::Mat4f, radius::Float32,
                            bias::Float32, power::Float32, width::Int, height::Int)
    samples = ntuple(64) do i
        if i <= length(kernel)
            k = kernel[i]
            (k[1], k[2], k[3], 0.0f0)
        else
            (0.0f0, 0.0f0, 0.0f0, 0.0f0)
        end
    end

    MetalSSAOUniforms(
        samples,
        ntuple(i -> proj[i], 16),
        Int32(length(kernel)),
        radius, bias, power,
        Float32(width), Float32(height),
        0.0f0, 0.0f0
    )
end

# ---- SSR Uniforms ----

struct MetalSSRUniforms
    projection::NTuple{16, Float32}
    view::NTuple{16, Float32}
    inv_projection::NTuple{16, Float32}
    camera_pos::NTuple{4, Float32}
    screen_size::NTuple{2, Float32}
    max_steps::Int32
    max_distance::Float32
    thickness::Float32
    _pad1::Float32
    _pad2::Float32
    _pad3::Float32
end

# ---- TAA Uniforms ----

struct MetalTAAUniforms
    prev_view_proj::NTuple{16, Float32}
    feedback::Float32
    first_frame::Int32
    screen_width::Float32
    screen_height::Float32
end

# ---- Post-Process Uniforms ----

struct MetalPostProcessUniforms
    bloom_threshold::Float32
    bloom_intensity::Float32
    gamma::Float32
    tone_mapping_mode::Int32  # 0=Reinhard, 1=ACES, 2=Uncharted2
    horizontal::Int32         # for blur pass direction
    _pad1::Float32
    _pad2::Float32
    _pad3::Float32
end

# ---- Helper: upload a struct to a Metal buffer ----

function _upload_uniform!(buffer_handle::UInt64, uniform_struct)
    data = Ref(uniform_struct)
    GC.@preserve data begin
        ptr = Base.unsafe_convert(Ptr{Cvoid}, Base.unsafe_convert(Ptr{typeof(uniform_struct)}, data))
        metal_update_buffer(buffer_handle, ptr, 0, sizeof(typeof(uniform_struct)))
    end
end

function _create_uniform_buffer(device_handle::UInt64, uniform_struct, label::String)
    data = Ref(uniform_struct)
    GC.@preserve data begin
        ptr = Base.unsafe_convert(Ptr{Cvoid}, Base.unsafe_convert(Ptr{typeof(uniform_struct)}, data))
        return metal_create_buffer(device_handle, ptr, sizeof(typeof(uniform_struct)), label)
    end
end
