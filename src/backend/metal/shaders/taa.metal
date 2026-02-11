#include <metal_stdlib>
using namespace metal;

struct TAAUniforms {
    float4x4 prev_view_proj;
    float    feedback;
    int      first_frame;
    float    screen_width;
    float    screen_height;
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut taa_vertex(
    const device float4* quad_data [[buffer(0)]],
    uint vid [[vertex_id]]
) {
    VertexOut out;
    float4 d = quad_data[vid];
    out.position = float4(d.xy, 0.0, 1.0);
    out.texCoord = d.zw;
    return out;
}

fragment float4 taa_fragment(
    VertexOut in [[stage_in]],
    constant TAAUniforms&   uniforms       [[buffer(7)]],
    texture2d<float>        currentColor   [[texture(0)]],
    texture2d<float>        historyColor   [[texture(1)]],
    depth2d<float>          depthTexture   [[texture(2)]],
    sampler texSampler                     [[sampler(0)]]
) {
    constexpr sampler linearSampler(min_filter::linear, mag_filter::linear);
    constexpr sampler nearestSampler(min_filter::nearest, mag_filter::nearest);

    float3 current = currentColor.sample(nearestSampler, in.texCoord).rgb;

    if (uniforms.first_frame) {
        return float4(current, 1.0);
    }

    // Neighborhood clamping (3x3)
    float2 texelSize = 1.0 / float2(uniforms.screen_width, uniforms.screen_height);
    float3 minColor = current;
    float3 maxColor = current;

    for (int x = -1; x <= 1; x++) {
        for (int y = -1; y <= 1; y++) {
            if (x == 0 && y == 0) continue;
            float2 offset = float2(float(x), float(y)) * texelSize;
            float3 neighbor = currentColor.sample(nearestSampler, in.texCoord + offset).rgb;
            minColor = min(minColor, neighbor);
            maxColor = max(maxColor, neighbor);
        }
    }

    // Reproject using previous frame's view-projection
    float depth = depthTexture.sample(nearestSampler, in.texCoord);
    float2 ndc = in.texCoord * 2.0 - 1.0;
    // Reconstruct world pos (simplified)
    float4 clipPos = float4(ndc, depth * 2.0 - 1.0, 1.0);

    // Sample history at reprojected position (use current UV as approximation when motion vectors aren't available)
    float3 history = historyColor.sample(linearSampler, in.texCoord).rgb;

    // Clamp history to neighborhood
    history = clamp(history, minColor, maxColor);

    // Blend
    float3 result = mix(current, history, uniforms.feedback);

    return float4(result, 1.0);
}
