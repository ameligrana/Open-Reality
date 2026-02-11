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

vertex CubeVertexOut irradiance_vertex(
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

fragment float4 irradiance_fragment(
    CubeVertexOut in [[stage_in]],
    texturecube<float> envMap [[texture(0)]],
    sampler texSampler       [[sampler(0)]]
) {
    float3 N = normalize(in.localPos);

    float3 irradiance = float3(0.0);

    // Build tangent frame
    float3 up    = float3(0.0, 1.0, 0.0);
    float3 right = normalize(cross(up, N));
    up           = normalize(cross(N, right));

    float sampleDelta = 0.025;
    float nrSamples = 0.0;

    for (float phi = 0.0; phi < 2.0 * M_PI_F; phi += sampleDelta) {
        for (float theta = 0.0; theta < 0.5 * M_PI_F; theta += sampleDelta) {
            // Spherical to cartesian (tangent space)
            float3 tangentSample = float3(
                sin(theta) * cos(phi),
                sin(theta) * sin(phi),
                cos(theta)
            );
            // Tangent to world
            float3 sampleVec = tangentSample.x * right +
                               tangentSample.y * up +
                               tangentSample.z * N;

            irradiance += envMap.sample(texSampler, sampleVec).rgb * cos(theta) * sin(theta);
            nrSamples += 1.0;
        }
    }

    irradiance = M_PI_F * irradiance / nrSamples;
    return float4(irradiance, 1.0);
}
