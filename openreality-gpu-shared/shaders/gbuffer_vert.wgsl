// G-Buffer geometry pass — vertex shader.

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

struct PerObject {
    model: mat4x4<f32>,
    normal_matrix_col0: vec4<f32>,
    normal_matrix_col1: vec4<f32>,
    normal_matrix_col2: vec4<f32>,
    _pad: vec4<f32>,
};

@group(0) @binding(0) var<uniform> frame: PerFrame;
@group(2) @binding(0) var<uniform> object: PerObject;

struct VertexInput {
    @location(0) position: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) uv: vec2<f32>,
};

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) world_pos: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) uv: vec2<f32>,
    @location(3) camera_pos: vec3<f32>,
};

@vertex
fn vs_main(in: VertexInput) -> VertexOutput {
    var out: VertexOutput;

    let world_pos = object.model * vec4<f32>(in.position, 1.0);
    out.world_pos = world_pos.xyz;

    let normal_matrix = mat3x3<f32>(
        object.normal_matrix_col0.xyz,
        object.normal_matrix_col1.xyz,
        object.normal_matrix_col2.xyz,
    );
    out.normal = normalize(normal_matrix * in.normal);
    out.uv = in.uv;
    out.camera_pos = frame.camera_pos.xyz;
    out.clip_position = frame.projection * frame.view * world_pos;

    return out;
}
