# Vulkan descriptor set layout, pool, and management
# Organizes bindings by update frequency:
#   Set 0: Per-frame (view, proj, camera, time)
#   Set 1: Per-material (material UBO + texture samplers)
#   Set 2: Lighting + shadows (light UBO, shadow UBO, CSM textures, IBL cubemaps)
# Per-object data uses push constants (model matrix + normal matrix = 112 bytes).

const VK_MAX_MATERIAL_TEXTURES = 6  # albedo, normal, MR, AO, emissive, height
const VK_MAX_CSM_CASCADES = 4
const VK_MAX_IBL_TEXTURES = 3  # irradiance, prefilter, BRDF LUT

# ==================================================================
# Descriptor Set Layout Creation
# ==================================================================

"""
    vk_create_per_frame_layout(device) -> DescriptorSetLayout

Set 0: per-frame UBO at binding 0.
"""
function vk_create_per_frame_layout(device::Device)
    bindings = [
        DescriptorSetLayoutBinding(
            UInt32(0), DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            SHADER_STAGE_VERTEX_BIT | SHADER_STAGE_FRAGMENT_BIT;
            descriptor_count=1
        )
    ]
    info = DescriptorSetLayoutCreateInfo(bindings)
    return unwrap(create_descriptor_set_layout(device, info))
end

"""
    vk_create_per_material_layout(device) -> DescriptorSetLayout

Set 1: material UBO at binding 0, combined image samplers at bindings 1-6.
"""
function vk_create_per_material_layout(device::Device)
    bindings = [
        # Material UBO
        DescriptorSetLayoutBinding(
            UInt32(0), DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            SHADER_STAGE_FRAGMENT_BIT;
            descriptor_count=1
        )
    ]
    # Material textures (6 combined image samplers)
    for i in 1:VK_MAX_MATERIAL_TEXTURES
        push!(bindings, DescriptorSetLayoutBinding(
            UInt32(i), DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            SHADER_STAGE_FRAGMENT_BIT;
            descriptor_count=1
        ))
    end
    info = DescriptorSetLayoutCreateInfo(bindings)
    return unwrap(create_descriptor_set_layout(device, info))
end

"""
    vk_create_lighting_layout(device) -> DescriptorSetLayout

Set 2: light UBO (binding 0), shadow UBO (binding 1), CSM textures (bindings 2-5),
       IBL textures (bindings 6-8).
"""
function vk_create_lighting_layout(device::Device)
    bindings = [
        # Light UBO
        DescriptorSetLayoutBinding(
            UInt32(0), DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            SHADER_STAGE_FRAGMENT_BIT;
            descriptor_count=1
        ),
        # Shadow UBO
        DescriptorSetLayoutBinding(
            UInt32(1), DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            SHADER_STAGE_FRAGMENT_BIT;
            descriptor_count=1
        ),
    ]
    # CSM depth textures (4 cascades)
    for i in 0:(VK_MAX_CSM_CASCADES - 1)
        push!(bindings, DescriptorSetLayoutBinding(
            UInt32(2 + i), DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            SHADER_STAGE_FRAGMENT_BIT;
            descriptor_count=1
        ))
    end
    # IBL textures (irradiance, prefilter, BRDF LUT)
    for i in 0:(VK_MAX_IBL_TEXTURES - 1)
        push!(bindings, DescriptorSetLayoutBinding(
            UInt32(6 + i), DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            SHADER_STAGE_FRAGMENT_BIT;
            descriptor_count=1
        ))
    end
    info = DescriptorSetLayoutCreateInfo(bindings)
    return unwrap(create_descriptor_set_layout(device, info))
end

"""
    vk_create_fullscreen_pass_layout(device) -> DescriptorSetLayout

Layout for fullscreen passes (deferred lighting, SSAO, SSR, TAA, post-process).
Binding 0: UBO (pass-specific uniforms)
Bindings 1-8: input textures (combined image samplers)
"""
function vk_create_fullscreen_pass_layout(device::Device; num_textures::Int=8)
    bindings = [
        DescriptorSetLayoutBinding(
            UInt32(0), DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            SHADER_STAGE_FRAGMENT_BIT;
            descriptor_count=1
        )
    ]
    for i in 1:num_textures
        push!(bindings, DescriptorSetLayoutBinding(
            UInt32(i), DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            SHADER_STAGE_FRAGMENT_BIT;
            descriptor_count=1
        ))
    end
    info = DescriptorSetLayoutCreateInfo(bindings)
    return unwrap(create_descriptor_set_layout(device, info))
end

# ==================================================================
# Push Constant Range
# ==================================================================

"""
    vk_per_object_push_constant_range() -> PushConstantRange

Push constant range for per-object data:
- model matrix (64 bytes) + normal matrix columns (48 bytes) = 112 bytes
"""
function vk_per_object_push_constant_range()
    return PushConstantRange(
        SHADER_STAGE_VERTEX_BIT | SHADER_STAGE_FRAGMENT_BIT,
        UInt32(0),
        UInt32(112)  # 16 floats (model) + 12 floats (3 columns of normal matrix)
    )
end

# ==================================================================
# Descriptor Pool
# ==================================================================

"""
    vk_create_descriptor_pool(device; max_sets=256) -> DescriptorPool

Create a descriptor pool large enough for typical rendering needs.
"""
function vk_create_descriptor_pool(device::Device; max_sets::Int=256)
    pool_sizes = [
        DescriptorPoolSize(DESCRIPTOR_TYPE_UNIFORM_BUFFER, UInt32(max_sets * 4)),
        DescriptorPoolSize(DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, UInt32(max_sets * 12)),
    ]
    pool_info = DescriptorPoolCreateInfo(
        UInt32(max_sets), pool_sizes;
        flags=DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT
    )
    return unwrap(create_descriptor_pool(device, pool_info))
end

# ==================================================================
# Descriptor Set Allocation and Updates
# ==================================================================

"""
    vk_allocate_descriptor_set(device, pool, layout) -> DescriptorSet
"""
function vk_allocate_descriptor_set(device::Device, pool::DescriptorPool,
                                     layout::DescriptorSetLayout)
    alloc_info = DescriptorSetAllocateInfo(pool, [layout])
    sets = unwrap(allocate_descriptor_sets(device, alloc_info))
    return sets[1]
end

"""
    vk_update_ubo_descriptor!(device, descriptor_set, binding, buffer, size)

Write a UBO binding to a descriptor set.
"""
function vk_update_ubo_descriptor!(device::Device, descriptor_set::DescriptorSet,
                                    binding::Integer, buffer::Buffer, size::Integer)
    buffer_info = DescriptorBufferInfo(buffer, UInt64(0), UInt64(size))
    write = WriteDescriptorSet(
        descriptor_set,
        UInt32(binding),
        UInt32(0),  # array element
        DESCRIPTOR_TYPE_UNIFORM_BUFFER,
        [],  # image infos
        [buffer_info],
        []   # texel buffer views
    )
    update_descriptor_sets(device, [write], [])
    return nothing
end

"""
    vk_update_texture_descriptor!(device, descriptor_set, binding, texture)

Write a combined image sampler binding to a descriptor set.
"""
function vk_update_texture_descriptor!(device::Device, descriptor_set::DescriptorSet,
                                        binding::Integer, texture::VulkanGPUTexture)
    image_info = DescriptorImageInfo(
        texture.sampler, texture.view,
        IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL
    )
    write = WriteDescriptorSet(
        descriptor_set,
        UInt32(binding),
        UInt32(0),
        DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        [image_info],
        [],
        []
    )
    update_descriptor_sets(device, [write], [])
    return nothing
end

"""
    vk_update_image_sampler_descriptor!(device, descriptor_set, binding, view, sampler, layout)

Write an image view + sampler binding to a descriptor set (for non-VulkanGPUTexture images).
"""
function vk_update_image_sampler_descriptor!(device::Device, descriptor_set::DescriptorSet,
                                              binding::Integer, view::ImageView,
                                              sampler::Sampler,
                                              layout::ImageLayout=IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL)
    image_info = DescriptorImageInfo(sampler, view, layout)
    write = WriteDescriptorSet(
        descriptor_set,
        UInt32(binding),
        UInt32(0),
        DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        [image_info],
        [],
        []
    )
    update_descriptor_sets(device, [write], [])
    return nothing
end
