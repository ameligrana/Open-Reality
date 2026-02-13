// Bloom Gaussian blur pass (separable, 5-tap).

struct PostProcessParams {
    bloom_threshold: f32,
    bloom_intensity: f32,
    gamma: f32,
    tone_mapping_mode: i32,
    horizontal: i32,
    _pad1: f32,
    _pad2: f32,
    _pad3: f32,
};

@group(0) @binding(0) var<uniform> params: PostProcessParams;
@group(0) @binding(1) var input_texture: texture_2d<f32>;
@group(0) @binding(2) var tex_sampler: sampler;

struct FragmentInput {
    @location(0) uv: vec2<f32>,
};

@fragment
fn fs_main(in: FragmentInput) -> @location(0) vec4<f32> {
    let tex_size = vec2<f32>(textureDimensions(input_texture, 0));
    let texel_size = 1.0 / tex_size;

    // Gaussian weights (5-tap)
    let weights = array<f32, 5>(0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216);

    var result = textureSample(input_texture, tex_sampler, in.uv).rgb * weights[0];

    if params.horizontal != 0 {
        for (var i = 1; i < 5; i++) {
            let offset = vec2<f32>(texel_size.x * f32(i), 0.0);
            result += textureSample(input_texture, tex_sampler, in.uv + offset).rgb * weights[i];
            result += textureSample(input_texture, tex_sampler, in.uv - offset).rgb * weights[i];
        }
    } else {
        for (var i = 1; i < 5; i++) {
            let offset = vec2<f32>(0.0, texel_size.y * f32(i));
            result += textureSample(input_texture, tex_sampler, in.uv + offset).rgb * weights[i];
            result += textureSample(input_texture, tex_sampler, in.uv - offset).rgb * weights[i];
        }
    }

    return vec4<f32>(result, 1.0);
}
