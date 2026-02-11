#include <metal_stdlib>
using namespace metal;

struct IBLUniforms {
    float4x4 view;
    float4x4 projection;
    float    roughness;
    float    _pad1, _pad2, _pad3;
};

struct CubeVertexOut {
    float4 position [[position]];
    float3 localPos;
};

vertex CubeVertexOut prefilter_vertex(
    const device packed_float3* positions [[buffer(0)]],
    constant IBLUniforms& uniforms       [[buffer(3)]],
    uint vid [[vertex_id]]
) {
    CubeVertexOut out;
    float3 pos = positions[vid];
    out.localPos = pos;
    out.position = uniforms.projection * uniforms.view * float4(pos, 1.0);
    return out;
}

// Hammersley low-discrepancy sequence
static float radicalInverse_VdC(uint bits) {
    bits = (bits << 16u) | (bits >> 16u);
    bits = ((bits & 0x55555555u) << 1u) | ((bits & 0xAAAAAAAAu) >> 1u);
    bits = ((bits & 0x33333333u) << 2u) | ((bits & 0xCCCCCCCCu) >> 2u);
    bits = ((bits & 0x0F0F0F0Fu) << 4u) | ((bits & 0xF0F0F0F0u) >> 4u);
    bits = ((bits & 0x00FF00FFu) << 8u) | ((bits & 0xFF00FF00u) >> 8u);
    return float(bits) * 2.3283064365386963e-10;
}

static float2 hammersley(uint i, uint N) {
    return float2(float(i) / float(N), radicalInverse_VdC(i));
}

static float distributionGGX(float3 N, float3 H, float roughness) {
    float a  = roughness * roughness;
    float a2 = a * a;
    float NdotH  = max(dot(N, H), 0.0);
    float NdotH2 = NdotH * NdotH;
    float denom = NdotH2 * (a2 - 1.0) + 1.0;
    denom = M_PI_F * denom * denom;
    return a2 / max(denom, 0.0000001);
}

static float3 importanceSampleGGX(float2 Xi, float3 N, float roughness) {
    float a = roughness * roughness;

    float phi = 2.0 * M_PI_F * Xi.x;
    float cosTheta = sqrt((1.0 - Xi.y) / (1.0 + (a * a - 1.0) * Xi.y));
    float sinTheta = sqrt(1.0 - cosTheta * cosTheta);

    // Spherical to cartesian
    float3 H = float3(cos(phi) * sinTheta, sin(phi) * sinTheta, cosTheta);

    // Tangent to world space
    float3 up      = abs(N.z) < 0.999 ? float3(0.0, 0.0, 1.0) : float3(1.0, 0.0, 0.0);
    float3 tangent = normalize(cross(up, N));
    float3 bitangent = cross(N, tangent);

    return normalize(tangent * H.x + bitangent * H.y + N * H.z);
}

fragment float4 prefilter_fragment(
    CubeVertexOut in [[stage_in]],
    constant IBLUniforms& uniforms [[buffer(3)]],
    texturecube<float> envMap      [[texture(0)]],
    sampler texSampler             [[sampler(0)]]
) {
    float3 N = normalize(in.localPos);
    float3 R = N;
    float3 V = R;

    const uint SAMPLE_COUNT = 1024u;
    float3 prefilteredColor = float3(0.0);
    float totalWeight = 0.0;

    for (uint i = 0u; i < SAMPLE_COUNT; ++i) {
        float2 Xi = hammersley(i, SAMPLE_COUNT);
        float3 H  = importanceSampleGGX(Xi, N, uniforms.roughness);
        float3 L  = normalize(2.0 * dot(V, H) * H - V);

        float NdotL = max(dot(N, L), 0.0);
        if (NdotL > 0.0) {
            prefilteredColor += envMap.sample(texSampler, L).rgb * NdotL;
            totalWeight += NdotL;
        }
    }

    prefilteredColor = prefilteredColor / totalWeight;
    return float4(prefilteredColor, 1.0);
}
