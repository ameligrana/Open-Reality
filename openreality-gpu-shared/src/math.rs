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

#[cfg(test)]
mod tests {
    use super::*;
    use std::f32::consts::PI;

    const EPSILON: f32 = 1e-5;

    fn approx_eq(a: f32, b: f32) -> bool {
        (a - b).abs() < EPSILON
    }

    // ── extract_frustum_planes ──

    #[test]
    fn test_frustum_planes_normalized() {
        let proj = Mat4::perspective_rh_gl(PI / 4.0, 16.0 / 9.0, 0.1, 100.0);
        let planes = extract_frustum_planes(&proj);
        for plane in &planes {
            let len = (plane[0] * plane[0] + plane[1] * plane[1] + plane[2] * plane[2]).sqrt();
            assert!(approx_eq(len, 1.0), "Plane normal not unit length: {len}");
        }
    }

    #[test]
    fn test_frustum_planes_identity() {
        let planes = extract_frustum_planes(&Mat4::IDENTITY);
        // Identity VP produces 6 planes; just verify we get 6 and they're valid
        assert_eq!(planes.len(), 6);
        for plane in &planes {
            let len = (plane[0] * plane[0] + plane[1] * plane[1] + plane[2] * plane[2]).sqrt();
            assert!(len > 0.0, "Degenerate plane normal");
        }
    }

    // ── sphere_in_frustum ──

    #[test]
    fn test_sphere_inside_frustum() {
        let proj = Mat4::perspective_rh_gl(PI / 4.0, 1.0, 0.1, 100.0);
        let view = Mat4::look_at_rh(Vec3::new(0.0, 0.0, 5.0), Vec3::ZERO, Vec3::Y);
        let vp = proj * view;
        let planes = extract_frustum_planes(&vp);
        // Origin is in front of the camera
        assert!(sphere_in_frustum(&planes, Vec3::ZERO, 0.5));
    }

    #[test]
    fn test_sphere_outside_frustum() {
        let proj = Mat4::perspective_rh_gl(PI / 4.0, 1.0, 0.1, 100.0);
        let view = Mat4::look_at_rh(Vec3::new(0.0, 0.0, 5.0), Vec3::ZERO, Vec3::Y);
        let vp = proj * view;
        let planes = extract_frustum_planes(&vp);
        // Far behind the camera
        assert!(!sphere_in_frustum(&planes, Vec3::new(0.0, 0.0, 200.0), 1.0));
    }

    #[test]
    fn test_sphere_straddling_plane() {
        let proj = Mat4::perspective_rh_gl(PI / 4.0, 1.0, 0.1, 100.0);
        let view = Mat4::look_at_rh(Vec3::new(0.0, 0.0, 5.0), Vec3::ZERO, Vec3::Y);
        let vp = proj * view;
        let planes = extract_frustum_planes(&vp);
        // Very far to the side but with a huge radius that reaches into the frustum
        assert!(sphere_in_frustum(&planes, Vec3::new(50.0, 0.0, 0.0), 100.0));
    }

    // ── compute_cascade_splits ──

    #[test]
    fn test_cascade_splits_boundaries() {
        let near = 0.1;
        let far = 100.0;
        let splits = compute_cascade_splits(near, far, 4, 0.5);
        assert_eq!(splits.len(), 5); // num_cascades + 1
        assert!(approx_eq(splits[0], near));
        assert!(approx_eq(splits[4], far));
    }

    #[test]
    fn test_cascade_splits_monotonic() {
        let splits = compute_cascade_splits(0.1, 500.0, 4, 0.75);
        for i in 1..splits.len() {
            assert!(splits[i] > splits[i - 1], "Splits not monotonically increasing");
        }
    }

    #[test]
    fn test_cascade_splits_lambda_zero_linear() {
        let near = 1.0;
        let far = 101.0;
        let splits = compute_cascade_splits(near, far, 4, 0.0);
        // lambda=0 → purely linear: near + (far-near) * i/n
        for i in 0..=4 {
            let expected = near + (far - near) * (i as f32 / 4.0);
            assert!(approx_eq(splits[i], expected), "splits[{i}]={} expected={expected}", splits[i]);
        }
    }

    #[test]
    fn test_cascade_splits_lambda_one_logarithmic() {
        let near = 1.0;
        let far = 100.0;
        let splits = compute_cascade_splits(near, far, 4, 1.0);
        // lambda=1 → purely logarithmic: near * (far/near)^(i/n)
        for i in 0..=4 {
            let expected = near * (far / near).powf(i as f32 / 4.0);
            assert!(approx_eq(splits[i], expected), "splits[{i}]={} expected={expected}", splits[i]);
        }
    }

    // ── distribution_ggx ──

    #[test]
    fn test_ggx_peak_at_aligned() {
        // When n_dot_h=1, denom = a2, so D = a2 / (PI * a2 * a2) = 1 / (PI * a2)
        let roughness = 0.5;
        let a = roughness * roughness;
        let a2 = a * a;
        let expected = 1.0 / (PI * a2);
        let result = distribution_ggx(1.0, roughness);
        assert!(approx_eq(result, expected), "D(1.0, 0.5)={result} expected={expected}");
    }

    #[test]
    fn test_ggx_non_negative() {
        for &roughness in &[0.1, 0.25, 0.5, 0.75, 1.0] {
            for &n_dot_h in &[0.0, 0.25, 0.5, 0.75, 1.0] {
                assert!(distribution_ggx(n_dot_h, roughness) >= 0.0);
            }
        }
    }

    // ── geometry_schlick_ggx ──

    #[test]
    fn test_schlick_ggx_aligned() {
        // When n_dot_v=1: result = 1 / (1*(1-k) + k) = 1/1 = 1.0
        let result = geometry_schlick_ggx(1.0, 0.5);
        assert!(approx_eq(result, 1.0), "G(1.0, 0.5)={result} expected=1.0");
    }

    #[test]
    fn test_schlick_ggx_grazing_approaches_zero() {
        // As n_dot_v → 0, G → 0/k = 0
        let result = geometry_schlick_ggx(0.001, 0.5);
        assert!(result < 0.01, "G at grazing angle should be near zero, got {result}");
    }

    #[test]
    fn test_schlick_ggx_range() {
        for &roughness in &[0.1, 0.5, 1.0] {
            for &n_dot_v in &[0.0, 0.25, 0.5, 0.75, 1.0] {
                let result = geometry_schlick_ggx(n_dot_v, roughness);
                assert!(result >= 0.0 && result <= 1.0, "G({n_dot_v}, {roughness})={result} out of [0,1]");
            }
        }
    }
}
