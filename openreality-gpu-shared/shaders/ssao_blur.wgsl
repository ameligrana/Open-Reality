// SSAO bilateral blur pass (5x5 box filter).

struct BlurParams {
    screen_width: f32,
    screen_height: f32,
    _pad1: f32,
    _pad2: f32,
};

@group(0) @binding(0) var<uniform> params: BlurParams;
@group(0) @binding(1) var input_texture: texture_2d<f32>;
@group(0) @binding(2) var tex_sampler: sampler;

struct FragmentInput {
    @location(0) uv: vec2<f32>,
};

@fragment
fn fs_main(in: FragmentInput) -> @location(0) f32 {
    let texel_size = vec2<f32>(1.0 / params.screen_width, 1.0 / params.screen_height);
    var result = 0.0;

    for (var x = -2; x <= 2; x++) {
        for (var y = -2; y <= 2; y++) {
            let offset = vec2<f32>(f32(x), f32(y)) * texel_size;
            result += textureSample(input_texture, tex_sampler, in.uv + offset).r;
        }
    }

    return result / 25.0;
}
