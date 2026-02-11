# Vulkan Screen-Space Reflections (SSR) pass

"""
    vk_create_ssr_pass(device, physical_device, width, height,
                        fullscreen_layout, descriptor_pool) -> VulkanSSRPass

Create a screen-space reflections pass.
"""
function vk_create_ssr_pass(device::Device, physical_device::PhysicalDevice,
                             width::Int, height::Int,
                             fullscreen_layout::DescriptorSetLayout,
                             descriptor_pool::DescriptorPool)
    ssr_target = vk_create_render_target(device, physical_device, width, height;
                                          color_format=FORMAT_R16G16B16A16_SFLOAT, has_depth=false)

    ssr_ds = vk_allocate_descriptor_set(device, descriptor_pool, fullscreen_layout)

    frag_src = """
    #version 450

    layout(set = 0, binding = 0) uniform SSRParams {
        mat4 projection;
        mat4 view;
        mat4 inv_projection;
        vec4 camera_pos;
        vec2 screen_size;
        int max_steps;
        float max_distance;
        float thickness;
        float _pad1, _pad2, _pad3;
    } params;

    layout(set = 0, binding = 1) uniform sampler2D gDepth;
    layout(set = 0, binding = 2) uniform sampler2D gNormalRoughness;
    layout(set = 0, binding = 3) uniform sampler2D lightingResult;

    layout(location = 0) in vec2 fragUV;
    layout(location = 0) out vec4 outReflection;

    void main() {
        float depth = texture(gDepth, fragUV).r;
        if (depth >= 1.0) { outReflection = vec4(0.0); return; }

        vec4 normalRoughness = texture(gNormalRoughness, fragUV);
        vec3 normal = normalize(normalRoughness.rgb * 2.0 - 1.0);
        float roughness = normalRoughness.a;

        if (roughness > 0.5) { outReflection = vec4(0.0); return; }

        // Reconstruct view-space position
        vec4 clipPos = vec4(fragUV * 2.0 - 1.0, depth, 1.0);
        vec4 viewPos = params.inv_projection * clipPos;
        viewPos /= viewPos.w;

        vec3 viewDir = normalize(viewPos.xyz);
        vec3 reflectDir = reflect(viewDir, (params.view * vec4(normal, 0.0)).xyz);

        // Ray march in screen space
        vec3 startPos = viewPos.xyz;
        float stepSize = params.max_distance / float(params.max_steps);

        for (int i = 1; i <= params.max_steps; i++) {
            vec3 samplePos = startPos + reflectDir * stepSize * float(i);
            vec4 sampleClip = params.projection * vec4(samplePos, 1.0);
            sampleClip.xy /= sampleClip.w;
            vec2 sampleUV = sampleClip.xy * 0.5 + 0.5;

            if (sampleUV.x < 0.0 || sampleUV.x > 1.0 || sampleUV.y < 0.0 || sampleUV.y > 1.0)
                break;

            float sampleDepth = texture(gDepth, sampleUV).r;
            vec4 sampleView = params.inv_projection * vec4(sampleUV * 2.0 - 1.0, sampleDepth, 1.0);
            sampleView /= sampleView.w;

            float depthDiff = samplePos.z - sampleView.z;
            if (depthDiff > 0.0 && depthDiff < params.thickness) {
                float confidence = 1.0 - float(i) / float(params.max_steps);
                confidence *= 1.0 - roughness * 2.0;
                vec3 hitColor = texture(lightingResult, sampleUV).rgb;
                outReflection = vec4(hitColor, clamp(confidence, 0.0, 1.0));
                return;
            }
        }

        outReflection = vec4(0.0);
    }
    """

    ssr_pipeline = vk_compile_and_create_pipeline(device, VK_FULLSCREEN_QUAD_VERT, frag_src,
        VulkanPipelineConfig(
            ssr_target.render_pass, UInt32(0),
            vk_fullscreen_vertex_bindings(), vk_fullscreen_vertex_attributes(),
            [fullscreen_layout], PushConstantRange[],
            false, false, false,
            CULL_MODE_NONE, FRONT_FACE_COUNTER_CLOCKWISE,
            1, width, height
        ))

    return VulkanSSRPass(ssr_target, ssr_pipeline, ssr_ds, width, height, 64, 50.0f0, 0.5f0)
end

function vk_destroy_ssr_pass!(device::Device, ssr::VulkanSSRPass)
    vk_destroy_render_target!(device, ssr.ssr_target)
    finalize(ssr.ssr_pipeline.pipeline)
    finalize(ssr.ssr_pipeline.pipeline_layout)
    return nothing
end
