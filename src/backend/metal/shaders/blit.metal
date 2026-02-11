#include <metal_stdlib>
using namespace metal;

struct BlitVertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// Fullscreen quad: positions + UVs interleaved as float4 (xy=pos, zw=uv)
vertex BlitVertexOut blit_vertex(
    const device float4* quad_data [[buffer(0)]],
    uint vid [[vertex_id]]
) {
    BlitVertexOut out;
    float4 d = quad_data[vid];
    out.position = float4(d.xy, 0.0, 1.0);
    out.texCoord = d.zw;
    return out;
}

fragment float4 blit_fragment(
    BlitVertexOut in [[stage_in]],
    texture2d<float> src [[texture(0)]],
    sampler samp [[sampler(0)]]
) {
    return src.sample(samp, in.texCoord);
}
