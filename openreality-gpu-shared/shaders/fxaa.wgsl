// FXAA 3.11 (Fast Approximate Anti-Aliasing).

@group(0) @binding(0) var input_texture: texture_2d<f32>;
@group(0) @binding(1) var tex_sampler: sampler;

struct FragmentInput {
    @location(0) uv: vec2<f32>,
};

@fragment
fn fs_main(in: FragmentInput) -> @location(0) vec4<f32> {
    let tex_size = vec2<f32>(textureDimensions(input_texture, 0));
    let texel_size = 1.0 / tex_size;

    let rgb_NW = textureSample(input_texture, tex_sampler, in.uv + vec2<f32>(-1.0, -1.0) * texel_size).rgb;
    let rgb_NE = textureSample(input_texture, tex_sampler, in.uv + vec2<f32>(1.0, -1.0) * texel_size).rgb;
    let rgb_SW = textureSample(input_texture, tex_sampler, in.uv + vec2<f32>(-1.0, 1.0) * texel_size).rgb;
    let rgb_SE = textureSample(input_texture, tex_sampler, in.uv + vec2<f32>(1.0, 1.0) * texel_size).rgb;
    let rgb_M = textureSample(input_texture, tex_sampler, in.uv).rgb;

    let luma = vec3<f32>(0.299, 0.587, 0.114);
    let luma_NW = dot(rgb_NW, luma);
    let luma_NE = dot(rgb_NE, luma);
    let luma_SW = dot(rgb_SW, luma);
    let luma_SE = dot(rgb_SE, luma);
    let luma_M = dot(rgb_M, luma);

    let luma_min = min(luma_M, min(min(luma_NW, luma_NE), min(luma_SW, luma_SE)));
    let luma_max = max(luma_M, max(max(luma_NW, luma_NE), max(luma_SW, luma_SE)));

    let luma_range = luma_max - luma_min;
    if luma_range < max(0.0312, luma_max * 0.125) {
        return vec4<f32>(rgb_M, 1.0);
    }

    var dir: vec2<f32>;
    dir.x = -((luma_NW + luma_NE) - (luma_SW + luma_SE));
    dir.y = ((luma_NW + luma_SW) - (luma_NE + luma_SE));

    let dir_reduce = max((luma_NW + luma_NE + luma_SW + luma_SE) * 0.25 * 0.25, 1.0 / 128.0);
    let rcp_dir_min = 1.0 / (min(abs(dir.x), abs(dir.y)) + dir_reduce);
    dir = min(vec2<f32>(8.0), max(vec2<f32>(-8.0), dir * rcp_dir_min)) * texel_size;

    let rgb_A = 0.5 * (
        textureSample(input_texture, tex_sampler, in.uv + dir * (1.0 / 3.0 - 0.5)).rgb +
        textureSample(input_texture, tex_sampler, in.uv + dir * (2.0 / 3.0 - 0.5)).rgb
    );
    let rgb_B = rgb_A * 0.5 + 0.25 * (
        textureSample(input_texture, tex_sampler, in.uv + dir * -0.5).rgb +
        textureSample(input_texture, tex_sampler, in.uv + dir * 0.5).rgb
    );
    let luma_B = dot(rgb_B, luma);

    if luma_B < luma_min || luma_B > luma_max {
        return vec4<f32>(rgb_A, 1.0);
    } else {
        return vec4<f32>(rgb_B, 1.0);
    }
}
