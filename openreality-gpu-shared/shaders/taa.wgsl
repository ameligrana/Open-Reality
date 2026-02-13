// Temporal Anti-Aliasing (TAA) resolve pass.

struct TAAParams {
    prev_view_proj: mat4x4<f32>,
    feedback: f32,
    first_frame: i32,
    screen_width: f32,
    screen_height: f32,
};

@group(0) @binding(0) var<uniform> params: TAAParams;
@group(0) @binding(1) var current_frame: texture_2d<f32>;
@group(0) @binding(2) var history_frame: texture_2d<f32>;
@group(0) @binding(3) var depth_texture: texture_depth_2d;
@group(0) @binding(4) var tex_sampler: sampler;
@group(0) @binding(5) var depth_sampler: sampler;

struct FragmentInput {
    @location(0) uv: vec2<f32>,
};

@fragment
fn fs_main(in: FragmentInput) -> @location(0) vec4<f32> {
    let current_color = textureSample(current_frame, tex_sampler, in.uv);

    if params.first_frame != 0 {
        return current_color;
    }

    // Simplified reprojection (no motion vectors)
    let history_uv = in.uv;
    let history_color = textureSample(history_frame, tex_sampler, history_uv);

    // Neighborhood clamping (3x3 AABB)
    let texel_size = vec2<f32>(1.0 / params.screen_width, 1.0 / params.screen_height);
    var min_color = current_color.rgb;
    var max_color = current_color.rgb;

    for (var x = -1; x <= 1; x++) {
        for (var y = -1; y <= 1; y++) {
            let offset = vec2<f32>(f32(x), f32(y)) * texel_size;
            let neighbor = textureSample(current_frame, tex_sampler, in.uv + offset).rgb;
            min_color = min(min_color, neighbor);
            max_color = max(max_color, neighbor);
        }
    }

    let clamped_history = clamp(history_color.rgb, min_color, max_color);
    let result = mix(current_color.rgb, clamped_history, params.feedback);

    return vec4<f32>(result, 1.0);
}
