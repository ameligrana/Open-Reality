#include <metal_stdlib>
using namespace metal;

// ---- Shared Uniform Structs ----

struct PerFrameUniforms {
    float4x4 view;
    float4x4 projection;
    float4x4 inv_view_proj;
    float4   camera_pos;
    float    time;
    float    _pad1;
    float    _pad2;
    float    _pad3;
};

struct PerObjectUniforms {
    float4x4 model;
    float4   normal_matrix_col0;
    float4   normal_matrix_col1;
    float4   normal_matrix_col2;
};

struct MaterialUniforms {
    float4 albedo;                // rgb + opacity
    float  metallic;
    float  roughness;
    float  ao;
    float  alpha_cutoff;
    float4 emissive_factor;       // rgb + pad
    float  clearcoat;
    float  clearcoat_roughness;
    float  subsurface;
    float  parallax_scale;
    int    has_albedo_map;
    int    has_normal_map;
    int    has_metallic_roughness_map;
    int    has_ao_map;
    int    has_emissive_map;
    int    has_height_map;
    int    _pad1;
    int    _pad2;
};

struct PointLight {
    float4 position;
    float4 color;
    float  intensity;
    float  range;
    float  _pad1;
    float  _pad2;
};

struct DirLight {
    float4 direction;
    float4 color;
    float  intensity;
    float  _pad1;
    float  _pad2;
    float  _pad3;
};

struct LightUniforms {
    PointLight point_lights[16];
    DirLight   dir_lights[4];
    int        num_point_lights;
    int        num_dir_lights;
    int        has_ibl;
    float      ibl_intensity;
};

struct ShadowUniforms {
    float4x4 cascade_matrices[4];
    float    cascade_splits[5];
    int      num_cascades;
    int      has_shadows;
    float    _pad1;
};

// ---- Vertex I/O ----

struct PBRVertexOut {
    float4 position    [[position]];
    float3 world_pos;
    float3 normal;
    float2 texCoord;
};

// ---- BRDF Functions ----

static float3 fresnelSchlick(float cosTheta, float3 F0) {
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

static float distributionGGX(float3 N, float3 H, float roughness) {
    float a  = roughness * roughness;
    float a2 = a * a;
    float NdotH  = max(dot(N, H), 0.0);
    float NdotH2 = NdotH * NdotH;
    float denom = NdotH2 * (a2 - 1.0) + 1.0;
    denom = M_PI_F * denom * denom;
    return a2 / max(denom, 0.0001);
}

static float geometrySchlickGGX(float NdotV, float roughness) {
    float r = roughness + 1.0;
    float k = (r * r) / 8.0;
    return NdotV / (NdotV * (1.0 - k) + k);
}

static float geometrySmith(float3 N, float3 V, float3 L, float roughness) {
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    return geometrySchlickGGX(NdotV, roughness) * geometrySchlickGGX(NdotL, roughness);
}

static float3 computeRadiance(float3 N, float3 V, float3 L, float3 radiance,
                               float3 albedo, float metallic, float roughness, float3 F0) {
    float3 H = normalize(V + L);
    float NDF = distributionGGX(N, H, roughness);
    float G   = geometrySmith(N, V, L, roughness);
    float3 F  = fresnelSchlick(max(dot(H, V), 0.0), F0);

    float3 numerator    = NDF * G * F;
    float  denominator  = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.0001;
    float3 specular     = numerator / denominator;

    float3 kS = F;
    float3 kD = (1.0 - kS) * (1.0 - metallic);

    float NdotL = max(dot(N, L), 0.0);
    return (kD * albedo / M_PI_F + specular) * radiance * NdotL;
}

// ---- Shadow Sampling ----

static float sampleShadow(float4 fragPosLightSpace, depth2d<float> shadowMap, sampler shadowSampler) {
    float3 projCoords = fragPosLightSpace.xyz / fragPosLightSpace.w;
    // Metal depth range is [0, 1]
    float2 shadowUV = projCoords.xy * 0.5 + 0.5;
    shadowUV.y = 1.0 - shadowUV.y;  // flip Y

    if (shadowUV.x < 0.0 || shadowUV.x > 1.0 || shadowUV.y < 0.0 || shadowUV.y > 1.0)
        return 1.0;

    float currentDepth = projCoords.z;
    if (currentDepth > 1.0)
        return 1.0;

    float bias = 0.005;
    float shadow = 0.0;
    // Simple PCF
    float texelSize = 1.0 / 2048.0;
    for (int x = -1; x <= 1; x++) {
        for (int y = -1; y <= 1; y++) {
            float2 offset = float2(float(x), float(y)) * texelSize;
            float depth = shadowMap.sample(shadowSampler, shadowUV + offset);
            shadow += (currentDepth - bias > depth) ? 0.0 : 1.0;
        }
    }
    return shadow / 9.0;
}

// ---- Vertex Shader ----

vertex PBRVertexOut pbr_vertex(
    const device packed_float3* positions [[buffer(0)]],
    const device packed_float3* normals   [[buffer(1)]],
    const device packed_float2* uvs       [[buffer(2)]],
    constant PerFrameUniforms&  frame     [[buffer(3)]],
    constant PerObjectUniforms& object    [[buffer(4)]],
    uint vid [[vertex_id]]
) {
    PBRVertexOut out;
    float3 pos = positions[vid];
    float4 worldPos = object.model * float4(pos, 1.0);
    out.position  = frame.projection * frame.view * worldPos;
    out.world_pos = worldPos.xyz;

    float3 n = normals[vid];
    float3x3 normalMatrix = float3x3(
        object.normal_matrix_col0.xyz,
        object.normal_matrix_col1.xyz,
        object.normal_matrix_col2.xyz
    );
    out.normal = normalize(normalMatrix * n);
    out.texCoord = uvs[vid];
    return out;
}

// ---- Fragment Shader ----

fragment float4 pbr_fragment(
    PBRVertexOut in [[stage_in]],
    constant PerFrameUniforms&  frame     [[buffer(3)]],
    constant MaterialUniforms&  material  [[buffer(5)]],
    constant LightUniforms&     lights    [[buffer(6)]],
    constant ShadowUniforms&    shadows   [[buffer(7)]],
    texture2d<float> albedoMap         [[texture(0)]],
    texture2d<float> normalMap         [[texture(1)]],
    texture2d<float> metallicRoughMap  [[texture(2)]],
    texture2d<float> aoMap             [[texture(3)]],
    texture2d<float> emissiveMap       [[texture(4)]],
    depth2d<float>   shadowMap0        [[texture(10)]],
    depth2d<float>   shadowMap1        [[texture(11)]],
    depth2d<float>   shadowMap2        [[texture(12)]],
    depth2d<float>   shadowMap3        [[texture(13)]],
    sampler texSampler                 [[sampler(0)]],
    sampler shadowSampler              [[sampler(1)]]
) {
    // Base material properties
    float3 albedo = material.albedo.rgb;
    float metallic = material.metallic;
    float roughness = material.roughness;
    float ao = material.ao;
    float opacity = material.albedo.a;

    // Sample textures if available
    if (material.has_albedo_map) {
        float4 texColor = albedoMap.sample(texSampler, in.texCoord);
        albedo = texColor.rgb;
        opacity *= texColor.a;
    }

    if (material.has_metallic_roughness_map) {
        float4 mr = metallicRoughMap.sample(texSampler, in.texCoord);
        metallic = mr.b;
        roughness = mr.g;
    }

    if (material.has_ao_map) {
        ao = aoMap.sample(texSampler, in.texCoord).r;
    }

    // Normal
    float3 N = normalize(in.normal);
    if (material.has_normal_map) {
        float3 tangentNormal = normalMap.sample(texSampler, in.texCoord).rgb * 2.0 - 1.0;
        // Compute TBN from screen-space derivatives
        float3 dp1 = dfdx(in.world_pos);
        float3 dp2 = dfdy(in.world_pos);
        float2 duv1 = dfdx(in.texCoord);
        float2 duv2 = dfdy(in.texCoord);
        float3 T = normalize(dp1 * duv2.y - dp2 * duv1.y);
        float3 B = normalize(dp2 * duv1.x - dp1 * duv2.x);
        float3x3 TBN = float3x3(T, B, N);
        N = normalize(TBN * tangentNormal);
    }

    float3 V = normalize(frame.camera_pos.xyz - in.world_pos);
    float3 F0 = mix(float3(0.04), albedo, metallic);

    // Accumulate lighting
    float3 Lo = float3(0.0);

    // Point lights
    for (int i = 0; i < lights.num_point_lights; i++) {
        float3 lightPos = lights.point_lights[i].position.xyz;
        float3 L = normalize(lightPos - in.world_pos);
        float dist = length(lightPos - in.world_pos);
        float range = lights.point_lights[i].range;
        if (dist > range) continue;
        float attenuation = lights.point_lights[i].intensity / (dist * dist + 1.0);
        float3 radiance = lights.point_lights[i].color.rgb * attenuation;
        Lo += computeRadiance(N, V, L, radiance, albedo, metallic, roughness, F0);
    }

    // Directional lights
    for (int i = 0; i < lights.num_dir_lights; i++) {
        float3 L = normalize(-lights.dir_lights[i].direction.xyz);
        float3 radiance = lights.dir_lights[i].color.rgb * lights.dir_lights[i].intensity;

        // Shadow
        float shadow = 1.0;
        if (shadows.has_shadows && i == 0) {
            // Determine cascade
            float viewDepth = (frame.view * float4(in.world_pos, 1.0)).z;
            viewDepth = -viewDepth;  // negate (camera looks down -Z)

            int cascadeIdx = shadows.num_cascades - 1;
            for (int c = 0; c < shadows.num_cascades; c++) {
                if (viewDepth < shadows.cascade_splits[c + 1]) {
                    cascadeIdx = c;
                    break;
                }
            }

            float4 fragPosLightSpace = shadows.cascade_matrices[cascadeIdx] * float4(in.world_pos, 1.0);

            if (cascadeIdx == 0) shadow = sampleShadow(fragPosLightSpace, shadowMap0, shadowSampler);
            else if (cascadeIdx == 1) shadow = sampleShadow(fragPosLightSpace, shadowMap1, shadowSampler);
            else if (cascadeIdx == 2) shadow = sampleShadow(fragPosLightSpace, shadowMap2, shadowSampler);
            else shadow = sampleShadow(fragPosLightSpace, shadowMap3, shadowSampler);
        }

        Lo += computeRadiance(N, V, L, radiance, albedo, metallic, roughness, F0) * shadow;
    }

    // Emissive
    float3 emissive = material.emissive_factor.rgb;
    if (material.has_emissive_map) {
        emissive *= emissiveMap.sample(texSampler, in.texCoord).rgb;
    }

    // Ambient (fallback when no IBL)
    float3 ambient = float3(0.03) * albedo * ao;

    float3 color = ambient + Lo + emissive;

    // Alpha cutoff
    if (material.has_albedo_map && opacity < material.alpha_cutoff)
        discard_fragment();

    return float4(color, opacity);
}
