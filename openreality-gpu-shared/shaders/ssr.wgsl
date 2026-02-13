// Screen-Space Reflections (SSR) — ray marching in screen space.

struct SSRParams {
    projection: mat4x4<f32>,
    view: mat4x4<f32>,
    inv_projection: mat4x4<f32>,
    camera_pos: vec4<f32>,
    screen_size: vec2<f32>,
    max_steps: i32,
    max_distance: f32,
    thickness: f32,
    _pad1: f32,
    _pad2: f32,
    _pad3: f32,
};

@group(0) @binding(0) var<uniform> params: SSRParams;
@group(0) @binding(1) var g_depth: texture_depth_2d;
@group(0) @binding(2) var g_normal_roughness: texture_2d<f32>;
@group(0) @binding(3) var lighting_result: texture_2d<f32>;
@group(0) @binding(4) var tex_sampler: sampler;
@group(0) @binding(5) var depth_sampler: sampler;

struct FragmentInput {
    @location(0) uv: vec2<f32>,
};

@fragment
fn fs_main(in: FragmentInput) -> @location(0) vec4<f32> {
    let depth = textureSample(g_depth, depth_sampler, in.uv);
    if depth >= 1.0 {
        return vec4<f32>(0.0);
    }

    let normal_roughness = textureSample(g_normal_roughness, tex_sampler, in.uv);
    let normal = normalize(normal_roughness.rgb * 2.0 - 1.0);
    let roughness = normal_roughness.a;

    // Skip rough surfaces — no visible reflections
    if roughness > 0.5 {
        return vec4<f32>(0.0);
    }

    // Reconstruct view-space position
    let clip_pos = vec4<f32>(in.uv * 2.0 - 1.0, depth, 1.0);
    var view_pos = params.inv_projection * clip_pos;
    view_pos /= view_pos.w;

    let view_dir = normalize(view_pos.xyz);
    let view_normal = (params.view * vec4<f32>(normal, 0.0)).xyz;
    let reflect_dir = reflect(view_dir, view_normal);

    // Ray march in view space
    let start_pos = view_pos.xyz;
    let step_size = params.max_distance / f32(params.max_steps);

    for (var i = 1; i <= params.max_steps; i++) {
        let sample_pos = start_pos + reflect_dir * step_size * f32(i);
        var sample_clip = params.projection * vec4<f32>(sample_pos, 1.0);
        sample_clip = vec4<f32>(sample_clip.xy / sample_clip.w, sample_clip.zw);
        let sample_uv = sample_clip.xy * 0.5 + 0.5;

        if sample_uv.x < 0.0 || sample_uv.x > 1.0 || sample_uv.y < 0.0 || sample_uv.y > 1.0 {
            break;
        }

        let sample_depth = textureSample(g_depth, depth_sampler, sample_uv);
        var sample_view = params.inv_projection * vec4<f32>(sample_uv * 2.0 - 1.0, sample_depth, 1.0);
        sample_view /= sample_view.w;

        let depth_diff = sample_pos.z - sample_view.z;
        if depth_diff > 0.0 && depth_diff < params.thickness {
            var confidence = 1.0 - f32(i) / f32(params.max_steps);
            confidence *= 1.0 - roughness * 2.0;
            let hit_color = textureSample(lighting_result, tex_sampler, sample_uv).rgb;
            return vec4<f32>(hit_color, clamp(confidence, 0.0, 1.0));
        }
    }

    return vec4<f32>(0.0);
}
