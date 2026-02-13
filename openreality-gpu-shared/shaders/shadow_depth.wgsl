// Shadow depth pass — renders depth only for cascaded shadow maps.

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
@group(1) @binding(0) var<uniform> object: PerObject;

@vertex
fn vs_main(@location(0) position: vec3<f32>) -> @builtin(position) vec4<f32> {
    return frame.projection * frame.view * object.model * vec4<f32>(position, 1.0);
}
