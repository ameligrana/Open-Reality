// G-Buffer geometry pass — fragment shader.
// Uses override constants for shader variant features (replaces GLSL #define).

override HAS_ALBEDO_MAP: bool = false;
override HAS_NORMAL_MAP: bool = false;
override HAS_METALLIC_ROUGHNESS_MAP: bool = false;
override HAS_AO_MAP: bool = false;
override HAS_EMISSIVE_MAP: bool = false;
override HAS_ALPHA_CUTOFF: bool = false;
override HAS_CLEARCOAT: bool = false;
override HAS_PARALLAX_MAPPING: bool = false;
override HAS_SUBSURFACE: bool = false;

struct MaterialUBO {
    albedo: vec4<f32>,
    metallic: f32,
    roughness: f32,
    ao: f32,
    alpha_cutoff: f32,
    emissive_factor: vec4<f32>,
    clearcoat: f32,
    clearcoat_roughness: f32,
    subsurface: f32,
    parallax_scale: f32,
    has_albedo_map: i32,
    has_normal_map: i32,
    has_metallic_roughness_map: i32,
    has_ao_map: i32,
    has_emissive_map: i32,
    has_height_map: i32,
    _pad1: i32,
    _pad2: i32,
};

@group(1) @binding(0) var<uniform> material: MaterialUBO;
@group(1) @binding(1) var albedo_map: texture_2d<f32>;
@group(1) @binding(2) var normal_map: texture_2d<f32>;
@group(1) @binding(3) var metallic_roughness_map: texture_2d<f32>;
@group(1) @binding(4) var ao_map: texture_2d<f32>;
@group(1) @binding(5) var emissive_map: texture_2d<f32>;
@group(1) @binding(6) var height_map: texture_2d<f32>;
@group(1) @binding(7) var material_sampler: sampler;

struct FragmentInput {
    @location(0) world_pos: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) uv: vec2<f32>,
    @location(3) camera_pos: vec3<f32>,
};

struct GBufferOutput {
    @location(0) albedo_metallic: vec4<f32>,
    @location(1) normal_roughness: vec4<f32>,
    @location(2) emissive_ao: vec4<f32>,
    @location(3) advanced_material: vec4<f32>,
};

@fragment
fn fs_main(in: FragmentInput) -> GBufferOutput {
    var uv = in.uv;

    // Parallax mapping
    if HAS_PARALLAX_MAPPING && material.has_height_map != 0 && material.parallax_scale > 0.0 {
        let V = normalize(in.camera_pos - in.world_pos);
        let height = textureSample(height_map, material_sampler, uv).r;
        uv = uv + V.xy * (height * material.parallax_scale);
    }

    // Albedo
    var albedo = material.albedo.rgb;
    var opacity = material.albedo.a;
    if HAS_ALBEDO_MAP && material.has_albedo_map != 0 {
        let tex_color = textureSample(albedo_map, material_sampler, uv);
        albedo *= tex_color.rgb;
        opacity *= tex_color.a;
    }

    // Alpha cutoff
    if HAS_ALPHA_CUTOFF && material.alpha_cutoff > 0.0 && opacity < material.alpha_cutoff {
        discard;
    }

    // Metallic / roughness
    var metallic = material.metallic;
    var roughness = material.roughness;
    if HAS_METALLIC_ROUGHNESS_MAP && material.has_metallic_roughness_map != 0 {
        let mr = textureSample(metallic_roughness_map, material_sampler, uv).bg;
        metallic *= mr.x;
        roughness *= mr.y;
    }

    // Normal
    var N = normalize(in.normal);
    if HAS_NORMAL_MAP && material.has_normal_map != 0 {
        let tangent_normal = textureSample(normal_map, material_sampler, uv).xyz * 2.0 - 1.0;
        // TBN from screen-space derivatives
        let dPdx = dpdx(in.world_pos);
        let dPdy = dpdy(in.world_pos);
        let dUVdx = dpdx(uv);
        let dUVdy = dpdy(uv);
        let T = normalize(dPdx * dUVdy.y - dPdy * dUVdx.y);
        let B = normalize(cross(N, T));
        let TBN = mat3x3<f32>(T, B, N);
        N = normalize(TBN * tangent_normal);
    }

    // Emissive
    var emissive = material.emissive_factor.rgb;
    if HAS_EMISSIVE_MAP && material.has_emissive_map != 0 {
        emissive *= textureSample(emissive_map, material_sampler, uv).rgb;
    }

    // AO
    var ao = material.ao;
    if HAS_AO_MAP && material.has_ao_map != 0 {
        ao *= textureSample(ao_map, material_sampler, uv).r;
    }

    // Write G-Buffer MRTs
    var out: GBufferOutput;
    out.albedo_metallic = vec4<f32>(albedo, metallic);
    out.normal_roughness = vec4<f32>(N * 0.5 + 0.5, roughness);
    out.emissive_ao = vec4<f32>(emissive, ao);

    var clearcoat_val = 0.0;
    var sss_val = 0.0;
    if HAS_CLEARCOAT {
        clearcoat_val = material.clearcoat;
    }
    if HAS_SUBSURFACE {
        sss_val = material.subsurface;
    }
    out.advanced_material = vec4<f32>(clearcoat_val, sss_val, 0.0, 1.0);

    return out;
}
