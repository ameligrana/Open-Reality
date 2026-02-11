# Vulkan PBR material texture binding and descriptor set updates

"""
    vk_bind_material_textures!(device, descriptor_set, material, texture_cache,
                                physical_device, cmd_pool, queue, default_texture)

Update a per-material descriptor set (set 1) with material UBO and texture bindings.
Bindings: 0=material UBO, 1=albedo, 2=normal, 3=MR, 4=AO, 5=emissive, 6=height
"""
function vk_bind_material_textures!(device::Device, descriptor_set::DescriptorSet,
                                     material::MaterialComponent,
                                     texture_cache::VulkanTextureCache,
                                     physical_device::PhysicalDevice,
                                     command_pool::CommandPool, queue::Queue,
                                     default_texture::VulkanGPUTexture)
    texture_slots = [
        (1, material.albedo_map),
        (2, material.normal_map),
        (3, material.metallic_roughness_map),
        (4, material.ao_map),
        (5, material.emissive_map),
        (6, material.height_map),
    ]

    for (binding, tex_ref) in texture_slots
        if tex_ref !== nothing
            tex = vk_load_texture(texture_cache, device, physical_device,
                                   command_pool, queue, tex_ref.path)
            vk_update_texture_descriptor!(device, descriptor_set, binding, tex)
        else
            vk_update_texture_descriptor!(device, descriptor_set, binding, default_texture)
        end
    end

    return nothing
end

# ==================================================================
# PBR Shader Sources (Vulkan GLSL #version 450)
# ==================================================================

const VK_PBR_FORWARD_VERT = """
#version 450

layout(set = 0, binding = 0) uniform PerFrame {
    mat4 view;
    mat4 projection;
    mat4 inv_view_proj;
    vec4 camera_pos;
    float time;
    float _pad1, _pad2, _pad3;
} frame;

layout(push_constant) uniform PerObject {
    mat4 model;
    vec4 normal_matrix_col0;
    vec4 normal_matrix_col1;
    vec4 normal_matrix_col2;
} obj;

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec3 inNormal;
layout(location = 2) in vec2 inUV;

layout(location = 0) out vec3 fragWorldPos;
layout(location = 1) out vec3 fragNormal;
layout(location = 2) out vec2 fragUV;

void main() {
    vec4 worldPos = obj.model * vec4(inPosition, 1.0);
    fragWorldPos = worldPos.xyz;

    mat3 normalMatrix = mat3(
        obj.normal_matrix_col0.xyz,
        obj.normal_matrix_col1.xyz,
        obj.normal_matrix_col2.xyz
    );
    fragNormal = normalize(normalMatrix * inNormal);
    fragUV = inUV;

    gl_Position = frame.projection * frame.view * worldPos;
}
"""

const VK_PBR_FORWARD_FRAG = """
#version 450

layout(set = 0, binding = 0) uniform PerFrame {
    mat4 view;
    mat4 projection;
    mat4 inv_view_proj;
    vec4 camera_pos;
    float time;
    float _pad1, _pad2, _pad3;
} frame;

layout(set = 1, binding = 0) uniform MaterialUBO {
    vec4 albedo;  // rgb + opacity
    float metallic;
    float roughness;
    float ao;
    float alpha_cutoff;
    vec4 emissive_factor;
    float clearcoat;
    float clearcoat_roughness;
    float subsurface;
    float parallax_scale;
    int has_albedo_map;
    int has_normal_map;
    int has_metallic_roughness_map;
    int has_ao_map;
    int has_emissive_map;
    int has_height_map;
    int _pad1, _pad2;
} material;

layout(set = 1, binding = 1) uniform sampler2D albedoMap;
layout(set = 1, binding = 2) uniform sampler2D normalMap;
layout(set = 1, binding = 3) uniform sampler2D metallicRoughnessMap;
layout(set = 1, binding = 4) uniform sampler2D aoMap;
layout(set = 1, binding = 5) uniform sampler2D emissiveMap;
layout(set = 1, binding = 6) uniform sampler2D heightMap;

struct PointLight {
    vec4 position;
    vec4 color;
    float intensity;
    float range;
    float _pad1, _pad2;
};

struct DirLight {
    vec4 direction;
    vec4 color;
    float intensity;
    float _pad1, _pad2, _pad3;
};

layout(set = 2, binding = 0) uniform LightUBO {
    PointLight point_lights[16];
    DirLight dir_lights[4];
    int num_point_lights;
    int num_dir_lights;
    int has_ibl;
    float ibl_intensity;
} lights;

layout(set = 2, binding = 1) uniform ShadowUBO {
    mat4 cascade_matrices[4];
    float cascade_splits[5];
    int num_cascades;
    int has_shadows;
    float _pad1;
} shadows;

layout(set = 2, binding = 2) uniform sampler2DShadow cascadeShadow0;
layout(set = 2, binding = 3) uniform sampler2DShadow cascadeShadow1;
layout(set = 2, binding = 4) uniform sampler2DShadow cascadeShadow2;
layout(set = 2, binding = 5) uniform sampler2DShadow cascadeShadow3;

layout(location = 0) in vec3 fragWorldPos;
layout(location = 1) in vec3 fragNormal;
layout(location = 2) in vec2 fragUV;

layout(location = 0) out vec4 outColor;

const float PI = 3.14159265359;

// Cook-Torrance BRDF functions
float DistributionGGX(vec3 N, vec3 H, float roughness) {
    float a = roughness * roughness;
    float a2 = a * a;
    float NdotH = max(dot(N, H), 0.0);
    float denom = NdotH * NdotH * (a2 - 1.0) + 1.0;
    return a2 / (PI * denom * denom);
}

float GeometrySchlickGGX(float NdotV, float roughness) {
    float r = roughness + 1.0;
    float k = (r * r) / 8.0;
    return NdotV / (NdotV * (1.0 - k) + k);
}

float GeometrySmith(vec3 N, vec3 V, vec3 L, float roughness) {
    return GeometrySchlickGGX(max(dot(N, V), 0.0), roughness) *
           GeometrySchlickGGX(max(dot(N, L), 0.0), roughness);
}

vec3 FresnelSchlick(float cosTheta, vec3 F0) {
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

float shadowFactor(vec3 worldPos) {
    if (shadows.has_shadows == 0 || shadows.num_cascades == 0) return 1.0;

    float viewDepth = -(frame.view * vec4(worldPos, 1.0)).z;

    // Find cascade
    int cascade = shadows.num_cascades - 1;
    for (int i = 0; i < shadows.num_cascades; i++) {
        if (viewDepth < shadows.cascade_splits[i + 1]) {
            cascade = i;
            break;
        }
    }

    vec4 lightSpacePos = shadows.cascade_matrices[cascade] * vec4(worldPos, 1.0);
    vec3 projCoords = lightSpacePos.xyz / lightSpacePos.w;
    projCoords.xy = projCoords.xy * 0.5 + 0.5;

    if (projCoords.x < 0.0 || projCoords.x > 1.0 ||
        projCoords.y < 0.0 || projCoords.y > 1.0 ||
        projCoords.z > 1.0) return 1.0;

    // PCF 3x3
    float shadow = 0.0;
    vec2 texelSize = vec2(1.0 / 2048.0);
    for (int x = -1; x <= 1; x++) {
        for (int y = -1; y <= 1; y++) {
            vec3 sampleCoord = vec3(projCoords.xy + vec2(x, y) * texelSize, projCoords.z);
            float s;
            if (cascade == 0) s = texture(cascadeShadow0, sampleCoord);
            else if (cascade == 1) s = texture(cascadeShadow1, sampleCoord);
            else if (cascade == 2) s = texture(cascadeShadow2, sampleCoord);
            else s = texture(cascadeShadow3, sampleCoord);
            shadow += s;
        }
    }
    return shadow / 9.0;
}

void main() {
    // Material properties
    vec3 albedo = material.albedo.rgb;
    float opacity = material.albedo.a;
    float metallic = material.metallic;
    float roughness = material.roughness;
    vec3 emissive = material.emissive_factor.rgb;

    if (material.has_albedo_map != 0)
        albedo *= texture(albedoMap, fragUV).rgb;
    if (material.has_metallic_roughness_map != 0) {
        vec2 mr = texture(metallicRoughnessMap, fragUV).bg;
        metallic *= mr.x;
        roughness *= mr.y;
    }
    if (material.has_emissive_map != 0)
        emissive *= texture(emissiveMap, fragUV).rgb;

    // Alpha cutoff
    if (material.alpha_cutoff > 0.0 && opacity < material.alpha_cutoff)
        discard;

    vec3 N = normalize(fragNormal);
    vec3 V = normalize(frame.camera_pos.xyz - fragWorldPos);

    vec3 F0 = mix(vec3(0.04), albedo, metallic);

    // Lighting
    vec3 Lo = vec3(0.0);

    // Point lights
    for (int i = 0; i < lights.num_point_lights; i++) {
        vec3 L = normalize(lights.point_lights[i].position.xyz - fragWorldPos);
        vec3 H = normalize(V + L);
        float dist = length(lights.point_lights[i].position.xyz - fragWorldPos);
        float attenuation = lights.point_lights[i].intensity / (dist * dist);
        vec3 radiance = lights.point_lights[i].color.rgb * attenuation;

        float NDF = DistributionGGX(N, H, roughness);
        float G = GeometrySmith(N, V, L, roughness);
        vec3 F = FresnelSchlick(max(dot(H, V), 0.0), F0);

        vec3 numerator = NDF * G * F;
        float denominator = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.0001;
        vec3 specular = numerator / denominator;

        vec3 kD = (1.0 - F) * (1.0 - metallic);
        float NdotL = max(dot(N, L), 0.0);
        Lo += (kD * albedo / PI + specular) * radiance * NdotL;
    }

    // Directional lights
    for (int i = 0; i < lights.num_dir_lights; i++) {
        vec3 L = normalize(-lights.dir_lights[i].direction.xyz);
        vec3 H = normalize(V + L);
        vec3 radiance = lights.dir_lights[i].color.rgb * lights.dir_lights[i].intensity;

        float NDF = DistributionGGX(N, H, roughness);
        float G = GeometrySmith(N, V, L, roughness);
        vec3 F = FresnelSchlick(max(dot(H, V), 0.0), F0);

        vec3 numerator = NDF * G * F;
        float denominator = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.0001;
        vec3 specular = numerator / denominator;

        vec3 kD = (1.0 - F) * (1.0 - metallic);
        float NdotL = max(dot(N, L), 0.0);
        float shadow = shadowFactor(fragWorldPos);
        Lo += (kD * albedo / PI + specular) * radiance * NdotL * shadow;
    }

    vec3 ambient = vec3(0.03) * albedo;
    vec3 color = ambient + Lo + emissive;

    outColor = vec4(color, opacity);
}
"""
