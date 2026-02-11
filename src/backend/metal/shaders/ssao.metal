#include <metal_stdlib>
using namespace metal;

struct SSAOUniforms {
    float4 samples[64];
    float4x4 projection;
    int   kernel_size;
    float radius;
    float bias;
    float power;
    float screen_width;
    float screen_height;
    float _pad1, _pad2;
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut ssao_vertex(
    const device float4* quad_data [[buffer(0)]],
    uint vid [[vertex_id]]
) {
    VertexOut out;
    float4 d = quad_data[vid];
    out.position = float4(d.xy, 0.0, 1.0);
    out.texCoord = d.zw;
    return out;
}

// ---- SSAO Fragment ----

fragment float4 ssao_fragment(
    VertexOut in [[stage_in]],
    constant SSAOUniforms& uniforms [[buffer(7)]],
    texture2d<float> gNormalRoughness [[texture(0)]],
    depth2d<float>   gDepth           [[texture(1)]],
    texture2d<float> noiseTexture     [[texture(2)]],
    sampler texSampler                [[sampler(0)]]
) {
    constexpr sampler nearestSampler(min_filter::nearest, mag_filter::nearest);

    float2 noiseScale = float2(uniforms.screen_width / 4.0, uniforms.screen_height / 4.0);

    float3 normal = normalize(gNormalRoughness.sample(nearestSampler, in.texCoord).rgb * 2.0 - 1.0);
    float depth = gDepth.sample(nearestSampler, in.texCoord);

    if (depth >= 1.0)
        return float4(1.0);

    // Reconstruct view-space position from depth
    float2 ndc = in.texCoord * 2.0 - 1.0;
    float4 clipPos = float4(ndc, depth * 2.0 - 1.0, 1.0);
    // Simplified: use projection inverse for view-space reconstruction
    float z = uniforms.projection[3][2] / (depth * 2.0 - 1.0 + uniforms.projection[2][2]);
    float3 fragPos = float3(ndc * float2(1.0 / uniforms.projection[0][0], 1.0 / uniforms.projection[1][1]) * (-z), z);

    float3 randomVec = normalize(noiseTexture.sample(nearestSampler, in.texCoord * noiseScale).xyz * 2.0 - 1.0);

    float3 tangent = normalize(randomVec - normal * dot(randomVec, normal));
    float3 bitangent = cross(normal, tangent);
    float3x3 TBN = float3x3(tangent, bitangent, normal);

    float occlusion = 0.0;
    for (int i = 0; i < uniforms.kernel_size; i++) {
        float3 samplePos = TBN * uniforms.samples[i].xyz;
        samplePos = fragPos + samplePos * uniforms.radius;

        float4 offset = uniforms.projection * float4(samplePos, 1.0);
        offset.xyz /= offset.w;
        float2 sampleUV = offset.xy * 0.5 + 0.5;
        sampleUV.y = 1.0 - sampleUV.y;

        float sampleDepth = gDepth.sample(nearestSampler, sampleUV);
        float sz = uniforms.projection[3][2] / (sampleDepth * 2.0 - 1.0 + uniforms.projection[2][2]);

        float rangeCheck = smoothstep(0.0, 1.0, uniforms.radius / abs(fragPos.z - sz));
        occlusion += (sz >= samplePos.z + uniforms.bias ? 1.0 : 0.0) * rangeCheck;
    }

    occlusion = 1.0 - (occlusion / float(uniforms.kernel_size));
    occlusion = pow(occlusion, uniforms.power);

    return float4(occlusion, occlusion, occlusion, 1.0);
}

// ---- SSAO Blur Fragment ----

fragment float4 ssao_blur_fragment(
    VertexOut in [[stage_in]],
    texture2d<float> ssaoTexture [[texture(0)]],
    sampler texSampler [[sampler(0)]]
) {
    constexpr sampler nearestSampler(min_filter::nearest, mag_filter::nearest);
    float2 texelSize = 1.0 / float2(ssaoTexture.get_width(), ssaoTexture.get_height());
    float result = 0.0;
    for (int x = -2; x <= 2; x++) {
        for (int y = -2; y <= 2; y++) {
            float2 offset = float2(float(x), float(y)) * texelSize;
            result += ssaoTexture.sample(nearestSampler, in.texCoord + offset).r;
        }
    }
    result /= 25.0;
    return float4(result, result, result, 1.0);
}
