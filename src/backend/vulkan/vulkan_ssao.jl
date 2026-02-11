# Vulkan Screen-Space Ambient Occlusion (SSAO) pass

"""
    vk_create_ssao_pass(device, physical_device, cmd_pool, queue, width, height,
                         fullscreen_layout) -> VulkanSSAOPass

Create an SSAO pass with noise texture, sample kernel, and pipelines.
"""
function vk_create_ssao_pass(device::Device, physical_device::PhysicalDevice,
                              command_pool::CommandPool, queue::Queue,
                              width::Int, height::Int,
                              fullscreen_layout::DescriptorSetLayout,
                              descriptor_pool::DescriptorPool)
    # Create render targets
    ssao_target = vk_create_render_target(device, physical_device, width, height;
                                           color_format=FORMAT_R8_UNORM, has_depth=false)
    blur_target = vk_create_render_target(device, physical_device, width, height;
                                           color_format=FORMAT_R8_UNORM, has_depth=false)

    # Generate SSAO kernel
    kernel = generate_ssao_kernel(64)

    # Create noise texture (4x4 random rotations)
    noise_data = UInt8[]
    for _ in 1:16
        rx = rand(Float32) * 2.0f0 - 1.0f0
        ry = rand(Float32) * 2.0f0 - 1.0f0
        # Pack as R8G8 (normalized to 0-255)
        push!(noise_data, round(UInt8, clamp((rx * 0.5f0 + 0.5f0) * 255, 0, 255)))
        push!(noise_data, round(UInt8, clamp((ry * 0.5f0 + 0.5f0) * 255, 0, 255)))
        push!(noise_data, UInt8(0))
        push!(noise_data, UInt8(255))
    end
    noise_texture = vk_upload_texture(device, physical_device, command_pool, queue,
                                       noise_data, 4, 4, 4;
                                       format=FORMAT_R8G8B8A8_UNORM,
                                       generate_mipmaps=false)

    # Create kernel UBO
    kernel_uniforms = vk_pack_ssao_uniforms(kernel, Mat4f(I), 0.5f0, 0.025f0, 1.0f0, width, height)
    kernel_ubo, kernel_ubo_mem = vk_create_uniform_buffer(device, physical_device, kernel_uniforms)

    # Allocate descriptor sets
    ssao_ds = vk_allocate_descriptor_set(device, descriptor_pool, fullscreen_layout)
    blur_ds = vk_allocate_descriptor_set(device, descriptor_pool, fullscreen_layout)

    # Create SSAO pipeline
    ssao_frag = _vk_ssao_frag_source()
    ssao_pipeline = vk_compile_and_create_pipeline(device, VK_FULLSCREEN_QUAD_VERT, ssao_frag,
        VulkanPipelineConfig(
            ssao_target.render_pass, UInt32(0),
            vk_fullscreen_vertex_bindings(), vk_fullscreen_vertex_attributes(),
            [fullscreen_layout], PushConstantRange[],
            false, false, false,
            CULL_MODE_NONE, FRONT_FACE_COUNTER_CLOCKWISE,
            1, width, height
        ))

    # Blur pipeline
    blur_frag = _vk_ssao_blur_frag_source()
    blur_pipeline = vk_compile_and_create_pipeline(device, VK_FULLSCREEN_QUAD_VERT, blur_frag,
        VulkanPipelineConfig(
            blur_target.render_pass, UInt32(0),
            vk_fullscreen_vertex_bindings(), vk_fullscreen_vertex_attributes(),
            [fullscreen_layout], PushConstantRange[],
            false, false, false,
            CULL_MODE_NONE, FRONT_FACE_COUNTER_CLOCKWISE,
            1, width, height
        ))

    return VulkanSSAOPass(
        ssao_target, blur_target, noise_texture,
        ssao_pipeline, blur_pipeline,
        ssao_ds, blur_ds,
        kernel, kernel_ubo, kernel_ubo_mem,
        64, 0.5f0, 0.025f0, 1.0f0,
        width, height
    )
end

const VK_FULLSCREEN_QUAD_VERT = """
#version 450
layout(location = 0) in vec2 inPosition;
layout(location = 1) in vec2 inUV;
layout(location = 0) out vec2 fragUV;
void main() {
    fragUV = inUV;
    gl_Position = vec4(inPosition, 0.0, 1.0);
}
"""

function _vk_ssao_frag_source()
    return """
    #version 450

    layout(set = 0, binding = 0) uniform SSAOParams {
        vec4 samples[64];
        mat4 projection;
        int kernel_size;
        float radius;
        float bias;
        float power;
        float screen_width;
        float screen_height;
        float _pad1, _pad2;
    } params;

    layout(set = 0, binding = 1) uniform sampler2D gDepth;
    layout(set = 0, binding = 2) uniform sampler2D gNormalRoughness;
    layout(set = 0, binding = 3) uniform sampler2D noiseTexture;

    layout(location = 0) in vec2 fragUV;
    layout(location = 0) out float outOcclusion;

    void main() {
        float depth = texture(gDepth, fragUV).r;
        if (depth >= 1.0) { outOcclusion = 1.0; return; }

        vec3 normal = normalize(texture(gNormalRoughness, fragUV).rgb * 2.0 - 1.0);

        // Reconstruct view-space position from depth
        vec4 clipPos = vec4(fragUV * 2.0 - 1.0, depth, 1.0);
        vec4 viewPos = inverse(params.projection) * clipPos;
        viewPos /= viewPos.w;

        vec2 noiseScale = vec2(params.screen_width / 4.0, params.screen_height / 4.0);
        vec3 randomVec = vec3(texture(noiseTexture, fragUV * noiseScale).xy * 2.0 - 1.0, 0.0);

        vec3 tangent = normalize(randomVec - normal * dot(randomVec, normal));
        vec3 bitangent = cross(normal, tangent);
        mat3 TBN = mat3(tangent, bitangent, normal);

        float occlusion = 0.0;
        for (int i = 0; i < params.kernel_size; i++) {
            vec3 samplePos = viewPos.xyz + TBN * params.samples[i].xyz * params.radius;
            vec4 offset = params.projection * vec4(samplePos, 1.0);
            offset.xy /= offset.w;
            offset.xy = offset.xy * 0.5 + 0.5;

            float sampleDepth = texture(gDepth, offset.xy).r;
            vec4 sampleView = inverse(params.projection) * vec4(offset.xy * 2.0 - 1.0, sampleDepth, 1.0);
            sampleView /= sampleView.w;

            float rangeCheck = smoothstep(0.0, 1.0, params.radius / abs(viewPos.z - sampleView.z));
            occlusion += (sampleView.z >= samplePos.z + params.bias ? 1.0 : 0.0) * rangeCheck;
        }

        outOcclusion = pow(1.0 - (occlusion / float(params.kernel_size)), params.power);
    }
    """
end

function _vk_ssao_blur_frag_source()
    return """
    #version 450

    layout(set = 0, binding = 0) uniform BlurParams {
        vec4 _unused[64];
        mat4 _unused_proj;
        int _unused_ks;
        float _unused_r, _unused_b, _unused_p;
        float screen_width;
        float screen_height;
        float _pad1, _pad2;
    } params;

    layout(set = 0, binding = 1) uniform sampler2D inputTexture;

    layout(location = 0) in vec2 fragUV;
    layout(location = 0) out float outBlurred;

    void main() {
        vec2 texelSize = 1.0 / vec2(params.screen_width, params.screen_height);
        float result = 0.0;
        for (int x = -2; x <= 2; x++) {
            for (int y = -2; y <= 2; y++) {
                result += texture(inputTexture, fragUV + vec2(float(x), float(y)) * texelSize).r;
            }
        }
        outBlurred = result / 25.0;
    }
    """
end

function vk_destroy_ssao_pass!(device::Device, ssao::VulkanSSAOPass)
    vk_destroy_render_target!(device, ssao.ssao_target)
    vk_destroy_render_target!(device, ssao.blur_target)
    vk_destroy_texture!(device, ssao.noise_texture)
    finalize(ssao.ssao_pipeline.pipeline)
    finalize(ssao.ssao_pipeline.pipeline_layout)
    finalize(ssao.blur_pipeline.pipeline)
    finalize(ssao.blur_pipeline.pipeline_layout)
    finalize(ssao.kernel_ubo)
    finalize(ssao.kernel_ubo_memory)
    return nothing
end
