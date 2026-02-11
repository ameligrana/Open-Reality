#include <metal_stdlib>
using namespace metal;

struct PostProcessUniforms {
    float bloom_threshold;
    float bloom_intensity;
    float gamma;
    int   tone_mapping_mode;  // 0=Reinhard, 1=ACES, 2=Uncharted2
    int   horizontal;
    float _pad1, _pad2, _pad3;
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut composite_vertex(
    const device float4* quad_data [[buffer(0)]],
    uint vid [[vertex_id]]
) {
    VertexOut out;
    float4 d = quad_data[vid];
    out.position = float4(d.xy, 0.0, 1.0);
    out.texCoord = d.zw;
    return out;
}

// Tone mapping functions
static float3 toneMapReinhard(float3 color) {
    return color / (color + 1.0);
}

static float3 toneMapACES(float3 color) {
    float a = 2.51;
    float b = 0.03;
    float c = 2.43;
    float d = 0.59;
    float e = 0.14;
    return clamp((color * (a * color + b)) / (color * (c * color + d) + e), 0.0, 1.0);
}

static float3 uncharted2Helper(float3 x) {
    float A = 0.15, B = 0.50, C = 0.10, D = 0.20, E = 0.02, F = 0.30;
    return ((x * (A * x + C * B) + D * E) / (x * (A * x + B) + D * F)) - E / F;
}

static float3 toneMapUncharted2(float3 color) {
    float exposure = 2.0;
    float3 curr = uncharted2Helper(color * exposure);
    float3 whiteScale = 1.0 / uncharted2Helper(float3(11.2));
    return curr * whiteScale;
}

fragment float4 composite_fragment(
    VertexOut in [[stage_in]],
    constant PostProcessUniforms& uniforms [[buffer(7)]],
    texture2d<float> hdrTexture   [[texture(0)]],
    texture2d<float> bloomTexture [[texture(1)]],
    sampler texSampler [[sampler(0)]]
) {
    float3 hdrColor = hdrTexture.sample(texSampler, in.texCoord).rgb;
    float3 bloom = bloomTexture.sample(texSampler, in.texCoord).rgb;

    // Add bloom
    hdrColor += bloom * uniforms.bloom_intensity;

    // Tone mapping
    float3 mapped;
    if (uniforms.tone_mapping_mode == 0) {
        mapped = toneMapReinhard(hdrColor);
    } else if (uniforms.tone_mapping_mode == 1) {
        mapped = toneMapACES(hdrColor);
    } else {
        mapped = toneMapUncharted2(hdrColor);
    }

    // Gamma correction
    mapped = pow(mapped, float3(1.0 / uniforms.gamma));

    return float4(mapped, 1.0);
}
