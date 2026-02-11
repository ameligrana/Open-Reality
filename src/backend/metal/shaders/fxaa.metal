#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut fxaa_vertex(
    const device float4* quad_data [[buffer(0)]],
    uint vid [[vertex_id]]
) {
    VertexOut out;
    float4 d = quad_data[vid];
    out.position = float4(d.xy, 0.0, 1.0);
    out.texCoord = d.zw;
    return out;
}

#define FXAA_EDGE_THRESHOLD_MIN 0.0625
#define FXAA_EDGE_THRESHOLD     0.125
#define FXAA_SUBPIX_QUALITY     0.75

static float fxaaLuma(float3 color) {
    return dot(color, float3(0.299, 0.587, 0.114));
}

fragment float4 fxaa_fragment(
    VertexOut in [[stage_in]],
    texture2d<float> inputTexture [[texture(0)]],
    sampler texSampler [[sampler(0)]]
) {
    float2 texelSize = 1.0 / float2(inputTexture.get_width(), inputTexture.get_height());

    float3 rgbM  = inputTexture.sample(texSampler, in.texCoord).rgb;
    float3 rgbNW = inputTexture.sample(texSampler, in.texCoord + float2(-1.0, -1.0) * texelSize).rgb;
    float3 rgbNE = inputTexture.sample(texSampler, in.texCoord + float2( 1.0, -1.0) * texelSize).rgb;
    float3 rgbSW = inputTexture.sample(texSampler, in.texCoord + float2(-1.0,  1.0) * texelSize).rgb;
    float3 rgbSE = inputTexture.sample(texSampler, in.texCoord + float2( 1.0,  1.0) * texelSize).rgb;

    float lumaM  = fxaaLuma(rgbM);
    float lumaNW = fxaaLuma(rgbNW);
    float lumaNE = fxaaLuma(rgbNE);
    float lumaSW = fxaaLuma(rgbSW);
    float lumaSE = fxaaLuma(rgbSE);

    float lumaMin = min(lumaM, min(min(lumaNW, lumaNE), min(lumaSW, lumaSE)));
    float lumaMax = max(lumaM, max(max(lumaNW, lumaNE), max(lumaSW, lumaSE)));
    float lumaRange = lumaMax - lumaMin;

    if (lumaRange < max(FXAA_EDGE_THRESHOLD_MIN, lumaMax * FXAA_EDGE_THRESHOLD)) {
        return float4(rgbM, 1.0);
    }

    float2 dir;
    dir.x = -((lumaNW + lumaNE) - (lumaSW + lumaSE));
    dir.y =  ((lumaNW + lumaSW) - (lumaNE + lumaSE));

    float dirReduce = max((lumaNW + lumaNE + lumaSW + lumaSE) * 0.25 * 0.25, 1.0 / 128.0);
    float rcpDirMin = 1.0 / (min(abs(dir.x), abs(dir.y)) + dirReduce);
    dir = clamp(dir * rcpDirMin, float2(-8.0), float2(8.0)) * texelSize;

    float3 rgbA = 0.5 * (
        inputTexture.sample(texSampler, in.texCoord + dir * (1.0/3.0 - 0.5)).rgb +
        inputTexture.sample(texSampler, in.texCoord + dir * (2.0/3.0 - 0.5)).rgb
    );

    float3 rgbB = rgbA * 0.5 + 0.25 * (
        inputTexture.sample(texSampler, in.texCoord + dir * -0.5).rgb +
        inputTexture.sample(texSampler, in.texCoord + dir *  0.5).rgb
    );

    float lumaB = fxaaLuma(rgbB);
    if (lumaB < lumaMin || lumaB > lumaMax) {
        return float4(rgbA, 1.0);
    }
    return float4(rgbB, 1.0);
}
