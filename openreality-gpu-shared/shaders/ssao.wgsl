// Screen-Space Ambient Occlusion (SSAO) generation pass.

struct SSAOParams {
    samples: array<vec4<f32>, 64>,
    projection: mat4x4<f32>,
    kernel_size: i32,
    radius: f32,
    bias: f32,
    power: f32,
    screen_width: f32,
    screen_height: f32,
    _pad1: f32,
    _pad2: f32,
};

@group(0) @binding(0) var<uniform> params: SSAOParams;
@group(0) @binding(1) var g_depth: texture_depth_2d;
@group(0) @binding(2) var g_normal_roughness: texture_2d<f32>;
@group(0) @binding(3) var noise_texture: texture_2d<f32>;
@group(0) @binding(4) var tex_sampler: sampler;
@group(0) @binding(5) var depth_sampler: sampler;

struct FragmentInput {
    @location(0) uv: vec2<f32>,
};

@fragment
fn fs_main(in: FragmentInput) -> @location(0) f32 {
    let depth = textureSample(g_depth, depth_sampler, in.uv);
    if depth >= 1.0 {
        return 1.0;
    }

    let normal = normalize(textureSample(g_normal_roughness, tex_sampler, in.uv).rgb * 2.0 - 1.0);

    // Reconstruct view-space position from depth
    let clip_pos = vec4<f32>(in.uv * 2.0 - 1.0, depth, 1.0);
    let inv_proj = inverse_mat4(params.projection);
    var view_pos = inv_proj * clip_pos;
    view_pos /= view_pos.w;

    let noise_scale = vec2<f32>(params.screen_width / 4.0, params.screen_height / 4.0);
    let random_vec = vec3<f32>(textureSample(noise_texture, tex_sampler, in.uv * noise_scale).xy * 2.0 - 1.0, 0.0);

    let tangent = normalize(random_vec - normal * dot(random_vec, normal));
    let bitangent = cross(normal, tangent);
    let TBN = mat3x3<f32>(tangent, bitangent, normal);

    var occlusion = 0.0;
    for (var i = 0; i < params.kernel_size; i++) {
        let sample_pos = view_pos.xyz + TBN * params.samples[i].xyz * params.radius;
        var offset = params.projection * vec4<f32>(sample_pos, 1.0);
        offset = vec4<f32>(offset.xy / offset.w, offset.zw);
        let sample_uv = offset.xy * 0.5 + 0.5;

        let sample_depth = textureSample(g_depth, depth_sampler, sample_uv);
        var sample_view = inv_proj * vec4<f32>(sample_uv * 2.0 - 1.0, sample_depth, 1.0);
        sample_view /= sample_view.w;

        let range_check = smoothstep(0.0, 1.0, params.radius / abs(view_pos.z - sample_view.z));
        if sample_view.z >= sample_pos.z + params.bias {
            occlusion += range_check;
        }
    }

    return pow(1.0 - (occlusion / f32(params.kernel_size)), params.power);
}

// WGSL doesn't have a built-in inverse for mat4x4, so we provide a helper.
// In practice, the inverse projection should be passed as a uniform.
// This is a placeholder that will be replaced by a uniform in production.
fn inverse_mat4(m: mat4x4<f32>) -> mat4x4<f32> {
    // For the SSAO pass, we pass inv_projection as a separate uniform in production.
    // This function exists as a fallback.
    // TODO: Replace with inv_projection uniform
    return m; // placeholder
}
