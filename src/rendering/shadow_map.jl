# Shadow mapping: pure math / backend-agnostic utilities
# NOTE: OpenGL-specific types (ShadowMap struct, shaders) moved to backend/opengl/

# ---- Light-space matrix ----

"""
    compute_light_space_matrix(cam_pos::Vec3f, light_dir::Vec3f;
                               ortho_size::Float32=40.0f0,
                               near::Float32=-50.0f0,
                               far::Float32=50.0f0) -> Mat4f

Compute an orthographic light-space (view * projection) matrix for shadow mapping.
The view is centered on `cam_pos` looking along `light_dir`.
"""
function compute_light_space_matrix(cam_pos::Vec3f, light_dir::Vec3f;
                                    ortho_size::Float32=40.0f0,
                                    near::Float32=-50.0f0,
                                    far::Float32=50.0f0)
    # Normalise light direction
    d = normalize(Vec3f(light_dir[1], light_dir[2], light_dir[3]))

    # Light "eye" is at cam_pos offset opposite to light direction
    light_pos = cam_pos - d * 25.0f0

    # Light view matrix (look_at)
    up = abs(d[2]) > 0.99f0 ? Vec3f(0, 0, 1) : Vec3f(0, 1, 0)
    light_view = look_at_matrix(light_pos, light_pos + d, up)

    # Orthographic projection
    light_proj = _ortho_matrix(-ortho_size, ortho_size,
                               -ortho_size, ortho_size,
                               near, far)

    return light_proj * light_view
end

"""
Orthographic projection matrix (column-major, OpenGL convention).
"""
function _ortho_matrix(left::Float32, right::Float32,
                       bottom::Float32, top::Float32,
                       near::Float32, far::Float32)
    rl = right - left
    tb = top - bottom
    fn = far - near
    return Mat4f(
        2.0f0/rl,      0.0f0,         0.0f0,        0.0f0,
        0.0f0,         2.0f0/tb,      0.0f0,        0.0f0,
        0.0f0,         0.0f0,        -2.0f0/fn,     0.0f0,
        -(right+left)/rl, -(top+bottom)/tb, -(far+near)/fn, 1.0f0
    )
end

# look_at_matrix, normalize, cross, dot for Vec3f are defined in math/transforms.jl
