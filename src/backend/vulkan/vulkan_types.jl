# Vulkan backend concrete types
# Each type wraps native Vulkan handles from Vulkan.jl.

using Vulkan

# ==================================================================
# Concrete GPU resource types
# ==================================================================

"""
    VulkanShaderProgram <: AbstractShaderProgram

Vulkan graphics pipeline with shader modules and descriptor set layouts.
"""
mutable struct VulkanShaderProgram <: AbstractShaderProgram
    pipeline::Pipeline
    pipeline_layout::PipelineLayout
    descriptor_set_layouts::Vector{DescriptorSetLayout}
    vert_module::Union{ShaderModule, Nothing}
    frag_module::Union{ShaderModule, Nothing}

    VulkanShaderProgram(pipeline, layout, set_layouts; vert=nothing, frag=nothing) =
        new(pipeline, layout, set_layouts, vert, frag)
end

"""
    VulkanGPUMesh <: AbstractGPUMesh

Vulkan GPU-resident mesh with separate vertex attribute buffers and an index buffer.
"""
mutable struct VulkanGPUMesh <: AbstractGPUMesh
    vertex_buffer::Buffer
    vertex_memory::DeviceMemory
    normal_buffer::Buffer
    normal_memory::DeviceMemory
    uv_buffer::Buffer
    uv_memory::DeviceMemory
    index_buffer::Buffer
    index_memory::DeviceMemory
    index_count::Int32
end

get_index_count(mesh::VulkanGPUMesh) = mesh.index_count

"""
    VulkanGPUTexture <: AbstractGPUTexture

Vulkan GPU texture with image, view, sampler, and layout tracking.
"""
mutable struct VulkanGPUTexture <: AbstractGPUTexture
    image::Image
    memory::DeviceMemory
    view::ImageView
    sampler::Sampler
    width::Int
    height::Int
    channels::Int
    format::Format
    current_layout::ImageLayout
end

"""
    VulkanFramebuffer <: AbstractFramebuffer

Vulkan render target — owns color image + depth image + framebuffer + render pass.
"""
mutable struct VulkanFramebuffer <: AbstractFramebuffer
    framebuffer::Framebuffer
    render_pass::RenderPass
    color_image::Image
    color_memory::DeviceMemory
    color_view::ImageView
    depth_image::Union{Image, Nothing}
    depth_memory::Union{DeviceMemory, Nothing}
    depth_view::Union{ImageView, Nothing}
    color_format::Format
    width::Int
    height::Int
end

get_width(fb::VulkanFramebuffer) = fb.width
get_height(fb::VulkanFramebuffer) = fb.height

"""
    VulkanGBuffer <: AbstractGBuffer

Vulkan G-Buffer with 4 color MRTs and a depth texture for deferred rendering.
MRT 0 (RGBA16F): albedo + metallic
MRT 1 (RGBA16F): normal + roughness
MRT 2 (RGBA16F): emissive + AO
MRT 3 (RGBA8):   clearcoat, SSS, reserved
Depth:           D32_SFLOAT
"""
mutable struct VulkanGBuffer <: AbstractGBuffer
    framebuffer::Framebuffer
    render_pass::RenderPass
    albedo_metallic::VulkanGPUTexture
    normal_roughness::VulkanGPUTexture
    emissive_ao::VulkanGPUTexture
    advanced_material::VulkanGPUTexture
    depth::VulkanGPUTexture
    width::Int
    height::Int
end

get_width(gb::VulkanGBuffer) = gb.width
get_height(gb::VulkanGBuffer) = gb.height

"""
    VulkanShadowMap <: AbstractShadowMap

Vulkan depth-only render target for shadow mapping.
"""
mutable struct VulkanShadowMap <: AbstractShadowMap
    framebuffer::Framebuffer
    render_pass::RenderPass
    depth_texture::VulkanGPUTexture
    width::Int
    height::Int
end

get_width(sm::VulkanShadowMap) = sm.width
get_height(sm::VulkanShadowMap) = sm.height

"""
    VulkanCascadedShadowMap <: AbstractCascadedShadowMap

Vulkan cascaded shadow maps with per-cascade framebuffers.
"""
mutable struct VulkanCascadedShadowMap <: AbstractCascadedShadowMap
    num_cascades::Int
    cascade_framebuffers::Vector{Framebuffer}
    cascade_render_passes::Vector{RenderPass}
    cascade_depth_textures::Vector{VulkanGPUTexture}
    cascade_matrices::Vector{Mat4f}
    split_distances::Vector{Float32}
    resolution::Int
    depth_pipeline::Union{VulkanShaderProgram, Nothing}
end

"""
    VulkanIBLEnvironment <: AbstractIBLEnvironment

Vulkan IBL textures: environment cubemap, irradiance, prefilter, BRDF LUT.
"""
mutable struct VulkanIBLEnvironment <: AbstractIBLEnvironment
    environment_map::VulkanGPUTexture
    irradiance_map::VulkanGPUTexture
    prefilter_map::VulkanGPUTexture
    brdf_lut::VulkanGPUTexture
    intensity::Float32
end

"""
    VulkanSSAOPass <: AbstractSSAOPass

Vulkan SSAO pass with output texture and blur.
"""
mutable struct VulkanSSAOPass <: AbstractSSAOPass
    ssao_target::VulkanFramebuffer
    blur_target::VulkanFramebuffer
    noise_texture::VulkanGPUTexture
    ssao_pipeline::VulkanShaderProgram
    blur_pipeline::VulkanShaderProgram
    ssao_descriptor_set::DescriptorSet
    blur_descriptor_set::DescriptorSet
    kernel::Vector{Vec3f}
    kernel_ubo::Buffer
    kernel_ubo_memory::DeviceMemory
    kernel_size::Int
    radius::Float32
    bias::Float32
    power::Float32
    width::Int
    height::Int
end

get_width(ssao::VulkanSSAOPass) = ssao.width
get_height(ssao::VulkanSSAOPass) = ssao.height

"""
    VulkanSSRPass <: AbstractSSRPass

Vulkan screen-space reflections pass.
"""
mutable struct VulkanSSRPass <: AbstractSSRPass
    ssr_target::VulkanFramebuffer
    ssr_pipeline::VulkanShaderProgram
    ssr_descriptor_set::DescriptorSet
    width::Int
    height::Int
    max_steps::Int
    max_distance::Float32
    thickness::Float32
end

get_width(ssr::VulkanSSRPass) = ssr.width
get_height(ssr::VulkanSSRPass) = ssr.height

"""
    VulkanTAAPass <: AbstractTAAPass

Vulkan temporal anti-aliasing pass.
"""
mutable struct VulkanTAAPass <: AbstractTAAPass
    history_target::VulkanFramebuffer
    current_target::VulkanFramebuffer
    taa_pipeline::VulkanShaderProgram
    taa_descriptor_set::DescriptorSet
    feedback::Float32
    jitter_index::Int
    prev_view_proj::Mat4f
    first_frame::Bool
    width::Int
    height::Int
end

get_width(taa::VulkanTAAPass) = taa.width
get_height(taa::VulkanTAAPass) = taa.height

"""
    VulkanPostProcessPipeline <: AbstractPostProcessPipeline

Vulkan post-processing pipeline (bloom, tone mapping, FXAA).
"""
mutable struct VulkanPostProcessPipeline <: AbstractPostProcessPipeline
    config::PostProcessConfig
    scene_target::VulkanFramebuffer
    bright_target::VulkanFramebuffer
    bloom_targets::Vector{VulkanFramebuffer}
    composite_pipeline::VulkanShaderProgram
    bright_extract_pipeline::VulkanShaderProgram
    blur_pipeline::VulkanShaderProgram
    fxaa_pipeline::Union{VulkanShaderProgram, Nothing}
    width::Int
    height::Int
end

"""
    VulkanDeferredPipeline <: AbstractDeferredPipeline

Vulkan deferred rendering pipeline orchestration.
"""
mutable struct VulkanDeferredPipeline <: AbstractDeferredPipeline
    gbuffer::Union{VulkanGBuffer, Nothing}
    lighting_target::Union{VulkanFramebuffer, Nothing}
    lighting_pipeline::Union{VulkanShaderProgram, Nothing}
    gbuffer_shader_library::Union{ShaderLibrary{VulkanShaderProgram}, Nothing}
    ssao_pass::Union{VulkanSSAOPass, Nothing}
    ssr_pass::Union{VulkanSSRPass, Nothing}
    taa_pass::Union{VulkanTAAPass, Nothing}
    ibl_env::Union{VulkanIBLEnvironment, Nothing}

    VulkanDeferredPipeline() =
        new(nothing, nothing, nothing, nothing, nothing, nothing, nothing, nothing)
end

"""
    VulkanGPUResourceCache <: AbstractGPUResourceCache

Maps EntityIDs to VulkanGPUMesh handles.
"""
mutable struct VulkanGPUResourceCache <: AbstractGPUResourceCache
    meshes::Dict{EntityID, VulkanGPUMesh}

    VulkanGPUResourceCache() = new(Dict{EntityID, VulkanGPUMesh}())
end

"""
    VulkanTextureCache <: AbstractTextureCache

Maps file paths to VulkanGPUTexture handles.
"""
mutable struct VulkanTextureCache <: AbstractTextureCache
    textures::Dict{String, VulkanGPUTexture}

    VulkanTextureCache() = new(Dict{String, VulkanGPUTexture}())
end
