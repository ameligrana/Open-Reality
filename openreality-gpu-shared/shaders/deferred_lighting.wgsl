// Deferred lighting pass — fullscreen PBR lighting with Cook-Torrance BRDF.

const PI: f32 = 3.14159265359;

struct PerFrame {
    view: mat4x4<f32>,
    projection: mat4x4<f32>,
    inv_view_proj: mat4x4<f32>,
    camera_pos: vec4<f32>,
    time: f32,
    _pad1: f32,
    _pad2: f32,
    _pad3: f32,
};

struct PointLight {
    position: vec4<f32>,
    color: vec4<f32>,
    intensity: f32,
    range: f32,
    _pad1: f32,
    _pad2: f32,
};

struct DirLight {
    direction: vec4<f32>,
    color: vec4<f32>,
    intensity: f32,
    _pad1: f32,
    _pad2: f32,
    _pad3: f32,
};

struct LightData {
    point_lights: array<PointLight, 16>,
    dir_lights: array<DirLight, 4>,
    num_point_lights: i32,
    num_dir_lights: i32,
    has_ibl: i32,
    ibl_intensity: f32,
};

// Bind group 0: per-frame + G-Buffer textures
@group(0) @binding(0) var<uniform> frame: PerFrame;
@group(0) @binding(1) var g_albedo_metallic: texture_2d<f32>;
@group(0) @binding(2) var g_normal_roughness: texture_2d<f32>;
@group(0) @binding(3) var g_emissive_ao: texture_2d<f32>;
@group(0) @binding(4) var g_advanced_material: texture_2d<f32>;
@group(0) @binding(5) var g_depth: texture_depth_2d;
@group(0) @binding(6) var ssao_texture: texture_2d<f32>;
@group(0) @binding(7) var ssr_texture: texture_2d<f32>;
@group(0) @binding(8) var gbuffer_sampler: sampler;
@group(0) @binding(9) var depth_sampler: sampler;

// Bind group 1: light data
@group(1) @binding(0) var<uniform> lights: LightData;

struct FragmentInput {
    @location(0) uv: vec2<f32>,
};

fn reconstruct_world_pos(uv: vec2<f32>, depth: f32) -> vec3<f32> {
    let clip_pos = vec4<f32>(uv * 2.0 - 1.0, depth, 1.0);
    let world_pos = frame.inv_view_proj * clip_pos;
    return world_pos.xyz / world_pos.w;
}

fn distribution_ggx(N: vec3<f32>, H: vec3<f32>, roughness: f32) -> f32 {
    let a = roughness * roughness;
    let a2 = a * a;
    let NdotH = max(dot(N, H), 0.0);
    let denom = NdotH * NdotH * (a2 - 1.0) + 1.0;
    return a2 / (PI * denom * denom);
}

fn geometry_schlick_ggx(NdotV: f32, roughness: f32) -> f32 {
    let r = roughness + 1.0;
    let k = (r * r) / 8.0;
    return NdotV / (NdotV * (1.0 - k) + k);
}

fn geometry_smith(N: vec3<f32>, V: vec3<f32>, L: vec3<f32>, roughness: f32) -> f32 {
    return geometry_schlick_ggx(max(dot(N, V), 0.0), roughness) *
           geometry_schlick_ggx(max(dot(N, L), 0.0), roughness);
}

fn fresnel_schlick(cos_theta: f32, F0: vec3<f32>) -> vec3<f32> {
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cos_theta, 0.0, 1.0), 5.0);
}

@fragment
fn fs_main(in: FragmentInput) -> @location(0) vec4<f32> {
    let albedo_metallic = textureSample(g_albedo_metallic, gbuffer_sampler, in.uv);
    let normal_roughness = textureSample(g_normal_roughness, gbuffer_sampler, in.uv);
    let emissive_ao = textureSample(g_emissive_ao, gbuffer_sampler, in.uv);
    let depth = textureSample(g_depth, depth_sampler, in.uv);

    // Skip background pixels
    if depth >= 1.0 {
        return vec4<f32>(0.1, 0.1, 0.1, 1.0);
    }

    let albedo = albedo_metallic.rgb;
    let metallic = albedo_metallic.a;
    let N = normalize(normal_roughness.rgb * 2.0 - 1.0);
    let roughness = normal_roughness.a;
    let emissive = emissive_ao.rgb;
    let ao = emissive_ao.a;

    let world_pos = reconstruct_world_pos(in.uv, depth);
    let V = normalize(frame.camera_pos.xyz - world_pos);
    let F0 = mix(vec3<f32>(0.04), albedo, metallic);

    // Ambient (modulated by SSAO)
    let ssao = textureSample(ssao_texture, gbuffer_sampler, in.uv).r;
    let ambient = vec3<f32>(0.03) * albedo * ao * ssao;
    var Lo = ambient;

    // Directional lights
    for (var i = 0; i < lights.num_dir_lights; i++) {
        let L = normalize(-lights.dir_lights[i].direction.xyz);
        let H = normalize(V + L);
        let NdotL = max(dot(N, L), 0.0);

        let D = distribution_ggx(N, H, roughness);
        let G = geometry_smith(N, V, L, roughness);
        let F = fresnel_schlick(max(dot(H, V), 0.0), F0);

        let specular = (D * G * F) / (4.0 * max(dot(N, V), 0.0) * NdotL + 0.0001);
        let kD = (vec3<f32>(1.0) - F) * (1.0 - metallic);
        let radiance = lights.dir_lights[i].color.rgb * lights.dir_lights[i].intensity;
        Lo += (kD * albedo / PI + specular) * radiance * NdotL;
    }

    // Point lights
    for (var i = 0; i < lights.num_point_lights; i++) {
        let light_pos = lights.point_lights[i].position.xyz;
        let L = normalize(light_pos - world_pos);
        let H = normalize(V + L);
        let NdotL = max(dot(N, L), 0.0);

        let dist = length(light_pos - world_pos);
        var attenuation = 1.0 / (dist * dist + 0.0001);
        let range_factor = clamp(1.0 - pow(dist / max(lights.point_lights[i].range, 0.001), 4.0), 0.0, 1.0);
        attenuation *= range_factor * range_factor;

        let D = distribution_ggx(N, H, roughness);
        let G = geometry_smith(N, V, L, roughness);
        let F = fresnel_schlick(max(dot(H, V), 0.0), F0);

        let specular = (D * G * F) / (4.0 * max(dot(N, V), 0.0) * NdotL + 0.0001);
        let kD = (vec3<f32>(1.0) - F) * (1.0 - metallic);
        let radiance = lights.point_lights[i].color.rgb * lights.point_lights[i].intensity * attenuation;
        Lo += (kD * albedo / PI + specular) * radiance * NdotL;
    }

    // Emissive
    Lo += emissive;

    // SSR contribution
    let ssr = textureSample(ssr_texture, gbuffer_sampler, in.uv);
    if ssr.a > 0.0 {
        let F = fresnel_schlick(max(dot(N, V), 0.0), F0);
        Lo += ssr.rgb * F * ssr.a * (1.0 - roughness);
    }

    return vec4<f32>(Lo, 1.0);
}
