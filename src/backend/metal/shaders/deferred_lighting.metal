#include <metal_stdlib>
using namespace metal;

#define MAX_POINT_LIGHTS 16
#define MAX_DIR_LIGHTS 4
#define MAX_CASCADES 4

struct PerFrameUniforms {
    float4x4 view;
    float4x4 projection;
    float4x4 inv_view_proj;
    float4   camera_pos;
    float    time;
    float    _pad1, _pad2, _pad3;
};

struct PointLight {
    float4 position;
    float4 color;
    float  intensity;
    float  range;
    float  _pad1, _pad2;
};

struct DirLight {
    float4 direction;
    float4 color;
    float  intensity;
    float  _pad1, _pad2, _pad3;
};

struct LightUniforms {
    PointLight point_lights[MAX_POINT_LIGHTS];
    DirLight   dir_lights[MAX_DIR_LIGHTS];
    int        num_point_lights;
    int        num_dir_lights;
    int        has_ibl;
    float      ibl_intensity;
};

struct ShadowUniforms {
    float4x4 cascade_matrices[MAX_CASCADES];
    float    cascade_splits[5];
    int      num_cascades;
    int      has_shadows;
    float    _pad1;
};

struct LightingVertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// ---- Fullscreen quad vertex ----

vertex LightingVertexOut deferred_lighting_vertex(
    const device float4* quad_data [[buffer(0)]],
    uint vid [[vertex_id]]
) {
    LightingVertexOut out;
    float4 d = quad_data[vid];
    out.position = float4(d.xy, 0.0, 1.0);
    out.texCoord = d.zw;
    return out;
}

// ---- PBR BRDF functions ----

static float distributionGGX(float3 N, float3 H, float roughness) {
    float a  = roughness * roughness;
    float a2 = a * a;
    float NdotH  = max(dot(N, H), 0.0);
    float NdotH2 = NdotH * NdotH;
    float denom = NdotH2 * (a2 - 1.0) + 1.0;
    denom = M_PI_F * denom * denom;
    return a2 / max(denom, 0.0000001);
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

static float3 fresnelSchlick(float cosTheta, float3 F0) {
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

static float3 fresnelSchlickRoughness(float cosTheta, float3 F0, float roughness) {
    return F0 + (max(float3(1.0 - roughness), F0) - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
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

// ---- Shadow sampling ----

static float sampleCascadeShadow(float3 worldPos, float3 N, float3 L, int cascadeIdx,
                                  float4x4 cascadeMatrix, depth2d<float> shadowMap,
                                  sampler shadowSampler) {
    float4 fragPosLS = cascadeMatrix * float4(worldPos, 1.0);
    float3 projCoords = fragPosLS.xyz / fragPosLS.w;
    float2 shadowUV = projCoords.xy * 0.5 + 0.5;
    shadowUV.y = 1.0 - shadowUV.y;

    if (projCoords.z > 1.0 || shadowUV.x < 0.0 || shadowUV.x > 1.0 ||
        shadowUV.y < 0.0 || shadowUV.y > 1.0)
        return 0.0;

    float bias = max(0.005 * (1.0 - dot(N, L)), 0.001);
    bias *= 1.0 / (float(cascadeIdx + 1) * 0.5 + 1.0);

    float shadow = 0.0;
    float texelSize = 1.0 / 2048.0;
    for (int x = -1; x <= 1; x++) {
        for (int y = -1; y <= 1; y++) {
            float2 offset = float2(float(x), float(y)) * texelSize;
            float depth = shadowMap.sample(shadowSampler, shadowUV + offset);
            shadow += (projCoords.z - bias > depth) ? 1.0 : 0.0;
        }
    }
    return shadow / 9.0;
}

// ---- World position reconstruction from depth ----

static float3 reconstructWorldPos(float2 texCoord, float depth, float4x4 inv_view_proj) {
    float4 clipPos = float4(texCoord * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    float4 worldPos = inv_view_proj * clipPos;
    return worldPos.xyz / worldPos.w;
}

// ---- Fragment Shader ----

fragment float4 deferred_lighting_fragment(
    LightingVertexOut in [[stage_in]],
    constant PerFrameUniforms& frame   [[buffer(3)]],
    constant LightUniforms&    lights  [[buffer(6)]],
    constant ShadowUniforms&   shadows [[buffer(7)]],
    // G-Buffer textures
    texture2d<float> gAlbedoMetallic     [[texture(0)]],
    texture2d<float> gNormalRoughness    [[texture(1)]],
    texture2d<float> gEmissiveAO         [[texture(2)]],
    depth2d<float>   gDepth              [[texture(3)]],
    texture2d<float> gAdvancedMaterial   [[texture(4)]],
    // CSM shadow maps
    depth2d<float>   shadowMap0          [[texture(5)]],
    depth2d<float>   shadowMap1          [[texture(6)]],
    depth2d<float>   shadowMap2          [[texture(7)]],
    depth2d<float>   shadowMap3          [[texture(8)]],
    // IBL textures
    texturecube<float> irradianceMap     [[texture(9)]],
    texturecube<float> prefilterMap      [[texture(10)]],
    texture2d<float>   brdfLUT           [[texture(11)]],
    // Samplers
    sampler texSampler                   [[sampler(0)]],
    sampler shadowSampler                [[sampler(1)]]
) {
    constexpr sampler gbufSampler(min_filter::nearest, mag_filter::nearest);

    // Sample G-Buffer
    float4 albedoMetallic = gAlbedoMetallic.sample(gbufSampler, in.texCoord);
    float4 normalRoughness = gNormalRoughness.sample(gbufSampler, in.texCoord);
    float4 emissiveAO = gEmissiveAO.sample(gbufSampler, in.texCoord);
    float depth = gDepth.sample(gbufSampler, in.texCoord);

    // Background
    if (depth >= 1.0) {
        return float4(0.1, 0.1, 0.1, 1.0);
    }

    float3 albedo = albedoMetallic.rgb;
    float metallic = albedoMetallic.a;
    float3 normal = normalize(normalRoughness.rgb * 2.0 - 1.0);
    float roughness = normalRoughness.a;
    float3 emissive = emissiveAO.rgb;
    float ao = emissiveAO.a;

    float4 advMat = gAdvancedMaterial.sample(gbufSampler, in.texCoord);
    float clearcoat = advMat.r;
    float clearcoatRoughness = advMat.g;
    float subsurface_val = advMat.b;

    float3 worldPos = reconstructWorldPos(in.texCoord, depth, frame.inv_view_proj);
    float3 V = normalize(frame.camera_pos.xyz - worldPos);

    float3 F0 = mix(float3(0.04), albedo, metallic);

    float3 Lo = float3(0.0);
    float3 ccLo = float3(0.0);
    float3 sssLo = float3(0.0);

    float3 subsurfaceColor = float3(1.0, 0.2, 0.1);

    // Point lights
    for (int i = 0; i < lights.num_point_lights; i++) {
        float3 lightPos = lights.point_lights[i].position.xyz;
        float3 L = lightPos - worldPos;
        float dist = length(L);
        L = normalize(L);

        float attenuation = 1.0 / (dist * dist);
        float rangeFactor = clamp(1.0 - pow(dist / lights.point_lights[i].range, 4.0), 0.0, 1.0);
        attenuation *= rangeFactor * rangeFactor;

        float3 radiance = lights.point_lights[i].color.rgb * lights.point_lights[i].intensity * attenuation;
        Lo += computeRadiance(normal, V, L, radiance, albedo, metallic, roughness, F0);

        if (clearcoat > 0.0) {
            ccLo += computeRadiance(normal, V, L, radiance, float3(1.0), 0.0, clearcoatRoughness, float3(0.04));
        }

        if (subsurface_val > 0.0) {
            float wrap = 0.5;
            float NdotL_wrap = max(0.0, (dot(normal, L) + wrap) / (1.0 + wrap));
            float3 H_back = normalize(L + normal * 0.3);
            float VdotH_back = pow(clamp(dot(V, -H_back), 0.0, 1.0), 4.0);
            float thickness = 1.0 - max(dot(normal, V), 0.0);
            sssLo += subsurfaceColor * albedo * (NdotL_wrap + VdotH_back * thickness) * radiance;
        }
    }

    // View depth for cascade selection
    float viewDepth = length(frame.camera_pos.xyz - worldPos);

    // Directional lights
    for (int i = 0; i < lights.num_dir_lights; i++) {
        float3 L = normalize(-lights.dir_lights[i].direction.xyz);
        float3 radiance = lights.dir_lights[i].color.rgb * lights.dir_lights[i].intensity;

        float shadowFactor = 1.0;
        if (shadows.has_shadows && i == 0 && shadows.num_cascades > 0) {
            int cascadeIdx = shadows.num_cascades - 1;
            for (int c = 0; c < shadows.num_cascades; c++) {
                if (viewDepth < shadows.cascade_splits[c + 1]) {
                    cascadeIdx = c;
                    break;
                }
            }

            float shadow = 0.0;
            if (cascadeIdx == 0) shadow = sampleCascadeShadow(worldPos, normal, L, 0, shadows.cascade_matrices[0], shadowMap0, shadowSampler);
            else if (cascadeIdx == 1) shadow = sampleCascadeShadow(worldPos, normal, L, 1, shadows.cascade_matrices[1], shadowMap1, shadowSampler);
            else if (cascadeIdx == 2) shadow = sampleCascadeShadow(worldPos, normal, L, 2, shadows.cascade_matrices[2], shadowMap2, shadowSampler);
            else shadow = sampleCascadeShadow(worldPos, normal, L, 3, shadows.cascade_matrices[3], shadowMap3, shadowSampler);

            shadowFactor = 1.0 - shadow;
        }

        Lo += computeRadiance(normal, V, L, radiance, albedo, metallic, roughness, F0) * shadowFactor;

        if (clearcoat > 0.0) {
            ccLo += computeRadiance(normal, V, L, radiance, float3(1.0), 0.0, clearcoatRoughness, float3(0.04)) * shadowFactor;
        }

        if (subsurface_val > 0.0) {
            float wrap = 0.5;
            float NdotL_wrap = max(0.0, (dot(normal, L) + wrap) / (1.0 + wrap));
            float3 H_back = normalize(L + normal * 0.3);
            float VdotH_back = pow(clamp(dot(V, -H_back), 0.0, 1.0), 4.0);
            float thickness = 1.0 - max(dot(normal, V), 0.0);
            sssLo += subsurfaceColor * albedo * (NdotL_wrap + VdotH_back * thickness) * radiance * shadowFactor;
        }
    }

    // Clearcoat
    if (clearcoat > 0.0) {
        float3 ccFresnel = fresnelSchlick(max(dot(normal, V), 0.0), float3(0.04));
        Lo = Lo * (1.0 - clearcoat * ccFresnel) + clearcoat * ccLo;
    }

    // Subsurface
    if (subsurface_val > 0.0) {
        Lo += subsurface_val * sssLo;
    }

    // Ambient / IBL
    float3 ambient = float3(0.0);

    if (lights.has_ibl) {
        float3 F = fresnelSchlickRoughness(max(dot(normal, V), 0.0), F0, roughness);
        float3 kD = (1.0 - F) * (1.0 - metallic);

        constexpr sampler iblSampler(min_filter::linear, mag_filter::linear, mip_filter::linear);

        float3 irradiance = irradianceMap.sample(iblSampler, normal).rgb;
        float3 diffuse = irradiance * albedo;

        float3 R = reflect(-V, normal);
        const float MAX_REFLECTION_LOD = 4.0;
        float3 prefilteredColor = prefilterMap.sample(iblSampler, R, level(roughness * MAX_REFLECTION_LOD)).rgb;

        float2 brdf = brdfLUT.sample(iblSampler, float2(max(dot(normal, V), 0.0), roughness)).rg;
        float3 specular = prefilteredColor * (F * brdf.x + brdf.y);

        ambient = (kD * diffuse + specular) * lights.ibl_intensity * ao;

        if (clearcoat > 0.0) {
            float3 ccR = reflect(-V, normal);
            float3 ccPrefilteredColor = prefilterMap.sample(iblSampler, ccR, level(clearcoatRoughness * MAX_REFLECTION_LOD)).rgb;
            float3 ccF = fresnelSchlick(max(dot(normal, V), 0.0), float3(0.04));
            float2 ccBrdf = brdfLUT.sample(iblSampler, float2(max(dot(normal, V), 0.0), clearcoatRoughness)).rg;
            float3 ccSpecular = ccPrefilteredColor * (ccF * ccBrdf.x + ccBrdf.y);
            ambient += clearcoat * ccSpecular * lights.ibl_intensity;
        }
    } else {
        ambient = float3(0.03) * albedo * ao;
    }

    float3 color = ambient + Lo + emissive;
    return float4(color, 1.0);
}
