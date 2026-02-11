#include <metal_stdlib>
using namespace metal;

struct PerFrameUniforms {
    float4x4 view;
    float4x4 projection;
    float4x4 inv_view_proj;
    float4   camera_pos;
    float    time;
    float    _pad1;
    float    _pad2;
    float    _pad3;
};

struct PerObjectUniforms {
    float4x4 model;
    float4   normal_matrix_col0;
    float4   normal_matrix_col1;
    float4   normal_matrix_col2;
};

struct ShadowVertexOut {
    float4 position [[position]];
};

vertex ShadowVertexOut shadow_vertex(
    const device packed_float3* positions [[buffer(0)]],
    constant PerFrameUniforms&  frame     [[buffer(3)]],
    constant PerObjectUniforms& object    [[buffer(4)]],
    uint vid [[vertex_id]]
) {
    ShadowVertexOut out;
    float3 pos = positions[vid];
    out.position = frame.projection * frame.view * object.model * float4(pos, 1.0);
    return out;
}

fragment void shadow_fragment() {
    // Depth is written automatically by the rasterizer
}
