#include <metal_stdlib>
using namespace metal;

struct PostProcessUniforms {
    float bloom_threshold;
    float bloom_intensity;
    float gamma;
    int   tone_mapping_mode;
    int   horizontal;
    float _pad1, _pad2, _pad3;
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut blur_vertex(
    const device float4* quad_data [[buffer(0)]],
    uint vid [[vertex_id]]
) {
    VertexOut out;
    float4 d = quad_data[vid];
    out.position = float4(d.xy, 0.0, 1.0);
    out.texCoord = d.zw;
    return out;
}

fragment float4 blur_fragment(
    VertexOut in [[stage_in]],
    constant PostProcessUniforms& uniforms [[buffer(7)]],
    texture2d<float> image [[texture(0)]],
    sampler texSampler [[sampler(0)]]
) {
    constexpr float weights[5] = {0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216};

    float2 texelSize = 1.0 / float2(image.get_width(), image.get_height());
    float3 result = image.sample(texSampler, in.texCoord).rgb * weights[0];

    if (uniforms.horizontal) {
        for (int i = 1; i < 5; i++) {
            result += image.sample(texSampler, in.texCoord + float2(texelSize.x * float(i), 0.0)).rgb * weights[i];
            result += image.sample(texSampler, in.texCoord - float2(texelSize.x * float(i), 0.0)).rgb * weights[i];
        }
    } else {
        for (int i = 1; i < 5; i++) {
            result += image.sample(texSampler, in.texCoord + float2(0.0, texelSize.y * float(i))).rgb * weights[i];
            result += image.sample(texSampler, in.texCoord - float2(0.0, texelSize.y * float(i))).rgb * weights[i];
        }
    }

    return float4(result, 1.0);
}
