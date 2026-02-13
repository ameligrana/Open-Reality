// Final present pass — tone mapping + gamma correction.

struct PresentParams {
    bloom_threshold: f32,
    bloom_intensity: f32,
    gamma: f32,
    tone_mapping_mode: i32,
    horizontal: i32,
    _pad1: f32,
    _pad2: f32,
    _pad3: f32,
};

@group(0) @binding(0) var<uniform> params: PresentParams;
@group(0) @binding(1) var scene_texture: texture_2d<f32>;
@group(0) @binding(2) var tex_sampler: sampler;

struct FragmentInput {
    @location(0) uv: vec2<f32>,
};

fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@fragment
fn fs_main(in: FragmentInput) -> @location(0) vec4<f32> {
    let hdr = textureSample(scene_texture, tex_sampler, in.uv).rgb;
    // ACES tone mapping
    var mapped = aces(hdr);
    // Gamma correction
    mapped = pow(mapped, vec3<f32>(1.0 / params.gamma));
    return vec4<f32>(mapped, 1.0);
}
