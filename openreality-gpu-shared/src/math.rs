use glam::{Mat4, Vec3, Vec4};

/// Extract 6 frustum planes from a view-projection matrix (Gribb-Hartmann method).
/// Each plane is [a, b, c, d] where ax + by + cz + d = 0 (Hessian normal form).
pub fn extract_frustum_planes(vp: &Mat4) -> [[f32; 4]; 6] {
    let row0 = Vec4::new(vp.col(0).x, vp.col(1).x, vp.col(2).x, vp.col(3).x);
    let row1 = Vec4::new(vp.col(0).y, vp.col(1).y, vp.col(2).y, vp.col(3).y);
    let row2 = Vec4::new(vp.col(0).z, vp.col(1).z, vp.col(2).z, vp.col(3).z);
    let row3 = Vec4::new(vp.col(0).w, vp.col(1).w, vp.col(2).w, vp.col(3).w);

    let mut planes = [
        (row3 + row0).to_array(), // left
        (row3 - row0).to_array(), // right
        (row3 + row1).to_array(), // bottom
        (row3 - row1).to_array(), // top
        (row3 + row2).to_array(), // near
        (row3 - row2).to_array(), // far
    ];

    // Normalize planes
    for plane in &mut planes {
        let len = (plane[0] * plane[0] + plane[1] * plane[1] + plane[2] * plane[2]).sqrt();
        if len > 1e-8 {
            plane[0] /= len;
            plane[1] /= len;
            plane[2] /= len;
            plane[3] /= len;
        }
    }

    planes
}

/// Test if a bounding sphere is inside or intersects the frustum.
pub fn sphere_in_frustum(planes: &[[f32; 4]; 6], center: Vec3, radius: f32) -> bool {
    for plane in planes {
        let dist = plane[0] * center.x + plane[1] * center.y + plane[2] * center.z + plane[3];
        if dist < -radius {
            return false;
        }
    }
    true
}

/// Compute cascade split distances using PSSM (Practical Split Scheme Method).
pub fn compute_cascade_splits(near: f32, far: f32, num_cascades: usize, lambda: f32) -> Vec<f32> {
    let mut splits = Vec::with_capacity(num_cascades + 1);
    splits.push(near);

    for i in 1..=num_cascades {
        let p = i as f32 / num_cascades as f32;
        let c_log = near * (far / near).powf(p);
        let c_linear = near + (far - near) * p;
        splits.push(lambda * c_log + (1.0 - lambda) * c_linear);
    }

    splits
}

/// Cook-Torrance GGX distribution function.
pub fn distribution_ggx(n_dot_h: f32, roughness: f32) -> f32 {
    let a = roughness * roughness;
    let a2 = a * a;
    let denom = n_dot_h * n_dot_h * (a2 - 1.0) + 1.0;
    a2 / (std::f32::consts::PI * denom * denom)
}

/// Schlick-GGX geometry function.
pub fn geometry_schlick_ggx(n_dot_v: f32, roughness: f32) -> f32 {
    let r = roughness + 1.0;
    let k = (r * r) / 8.0;
    n_dot_v / (n_dot_v * (1.0 - k) + k)
}
