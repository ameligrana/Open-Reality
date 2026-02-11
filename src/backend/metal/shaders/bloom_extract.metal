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

vertex VertexOut bloom_vertex(
    const device float4* quad_data [[buffer(0)]],
    uint vid [[vertex_id]]
) {
    VertexOut out;
    float4 d = quad_data[vid];
    out.position = float4(d.xy, 0.0, 1.0);
    out.texCoord = d.zw;
    return out;
}

fragment float4 bloom_extract_fragment(
    VertexOut in [[stage_in]],
    constant PostProcessUniforms& uniforms [[buffer(7)]],
    texture2d<float> hdrTexture [[texture(0)]],
    sampler texSampler [[sampler(0)]]
) {
    float3 color = hdrTexture.sample(texSampler, in.texCoord).rgb;
    float brightness = dot(color, float3(0.2126, 0.7152, 0.0722));
    if (brightness > uniforms.bloom_threshold) {
        return float4(color, 1.0);
    }
    return float4(0.0, 0.0, 0.0, 1.0);
}
