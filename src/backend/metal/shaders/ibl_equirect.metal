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

vertex CubeVertexOut ibl_cube_vertex(
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

fragment float4 equirect_to_cubemap_fragment(
    CubeVertexOut in [[stage_in]],
    texture2d<float> equirectMap [[texture(0)]],
    sampler texSampler           [[sampler(0)]]
) {
    float3 v = normalize(in.localPos);

    // Equirectangular UV mapping
    float2 uv = float2(atan2(v.z, v.x), asin(v.y));
    uv *= float2(0.1591, 0.3183);  // 1/(2*PI), 1/PI
    uv += 0.5;

    float3 color = equirectMap.sample(texSampler, uv).rgb;
    return float4(color, 1.0);
}
