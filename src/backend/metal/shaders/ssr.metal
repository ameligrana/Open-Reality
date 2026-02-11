#include <metal_stdlib>
using namespace metal;

struct SSRUniforms {
    float4x4 projection;
    float4x4 view;
    float4x4 inv_projection;
    float4   camera_pos;
    float2   screen_size;
    int      max_steps;
    float    max_distance;
    float    thickness;
    float    _pad1, _pad2, _pad3;
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut ssr_vertex(
    const device float4* quad_data [[buffer(0)]],
    uint vid [[vertex_id]]
) {
    VertexOut out;
    float4 d = quad_data[vid];
    out.position = float4(d.xy, 0.0, 1.0);
    out.texCoord = d.zw;
    return out;
}

fragment float4 ssr_fragment(
    VertexOut in [[stage_in]],
    constant SSRUniforms& uniforms  [[buffer(7)]],
    texture2d<float> gNormalRoughness [[texture(0)]],
    depth2d<float>   gDepth           [[texture(1)]],
    texture2d<float> colorBuffer      [[texture(2)]],
    sampler texSampler                [[sampler(0)]]
) {
    constexpr sampler nearestSampler(min_filter::nearest, mag_filter::nearest);

    float4 normalRoughness = gNormalRoughness.sample(nearestSampler, in.texCoord);
    float3 normal = normalize(normalRoughness.rgb * 2.0 - 1.0);
    float roughness = normalRoughness.a;

    float depth = gDepth.sample(nearestSampler, in.texCoord);
    if (depth >= 1.0 || roughness > 0.7)
        return float4(0.0);

    // Reconstruct view-space position
    float2 ndc = in.texCoord * 2.0 - 1.0;
    float z = uniforms.projection[3][2] / (depth * 2.0 - 1.0 + uniforms.projection[2][2]);
    float3 fragPos = float3(ndc * float2(1.0 / uniforms.projection[0][0], 1.0 / uniforms.projection[1][1]) * (-z), z);

    // View-space normal (approximate - assume normal is already in world/view space)
    float3 viewDir = normalize(fragPos);
    float3 reflectDir = reflect(viewDir, normal);

    // Ray march in screen space
    float3 startPos = fragPos;
    float stepSize = uniforms.max_distance / float(uniforms.max_steps);

    for (int i = 1; i <= uniforms.max_steps; i++) {
        float3 rayPos = startPos + reflectDir * (stepSize * float(i));

        // Project to screen
        float4 projected = uniforms.projection * float4(rayPos, 1.0);
        projected.xyz /= projected.w;
        float2 sampleUV = projected.xy * 0.5 + 0.5;
        sampleUV.y = 1.0 - sampleUV.y;

        if (sampleUV.x < 0.0 || sampleUV.x > 1.0 || sampleUV.y < 0.0 || sampleUV.y > 1.0)
            break;

        float sampledDepth = gDepth.sample(nearestSampler, sampleUV);
        float sampledZ = uniforms.projection[3][2] / (sampledDepth * 2.0 - 1.0 + uniforms.projection[2][2]);

        float depthDiff = rayPos.z - sampledZ;
        if (depthDiff > 0.0 && depthDiff < uniforms.thickness) {
            float3 hitColor = colorBuffer.sample(texSampler, sampleUV).rgb;

            // Fade at edges
            float2 edgeFade = smoothstep(float2(0.0), float2(0.1), sampleUV) *
                              (1.0 - smoothstep(float2(0.9), float2(1.0), sampleUV));
            float fade = edgeFade.x * edgeFade.y;

            // Roughness fade
            float roughnessFade = 1.0 - smoothstep(0.3, 0.7, roughness);

            return float4(hitColor * fade * roughnessFade, fade * roughnessFade);
        }
    }

    return float4(0.0);
}
