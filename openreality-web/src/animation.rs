use glam::{DVec3, DQuat};

use crate::scene::LoadedScene;
use openreality_gpu_shared::scene_format::{InterpolationMode, TargetProperty};

/// Update all animation playback states and apply interpolated values to transforms.
pub fn update_animations(scene: &mut LoadedScene, dt: f32) {
    for anim_state in &mut scene.animations {
        if !anim_state.playing {
            continue;
        }

        let clip_idx = anim_state.active_clip;
        if clip_idx < 0 || clip_idx as usize >= anim_state.clips.len() {
            continue;
        }

        // Advance time
        anim_state.current_time += dt * anim_state.speed;

        let duration = anim_state.clips[clip_idx as usize].duration;
        if anim_state.current_time > duration {
            if anim_state.looping {
                anim_state.current_time %= duration;
            } else {
                anim_state.current_time = duration;
                anim_state.playing = false;
            }
        }

        let time = anim_state.current_time;

        // Apply each channel
        let clip = &anim_state.clips[clip_idx as usize];
        for channel in &clip.channels {
            let target_idx = channel.target_entity_index;
            if target_idx >= scene.entities.len() {
                continue;
            }

            // Find bounding keyframes via binary search
            let key_idx = find_keyframe_index(&channel.times, time);
            if key_idx.is_none() {
                continue;
            }
            let (i0, i1, t) = key_idx.unwrap();

            match channel.target_property {
                TargetProperty::Position => {
                    let v0 = get_vec3(&channel.values, i0);
                    let v1 = get_vec3(&channel.values, i1);
                    let interpolated = match channel.interpolation {
                        InterpolationMode::Step => v0,
                        InterpolationMode::Linear | InterpolationMode::CubicSpline => {
                            lerp_vec3(v0, v1, t as f64)
                        }
                    };
                    scene.entities[target_idx].transform.position = interpolated;
                    scene.entities[target_idx].transform.dirty = true;
                }
                TargetProperty::Rotation => {
                    let q0 = get_quat(&channel.values, i0);
                    let q1 = get_quat(&channel.values, i1);
                    let interpolated = match channel.interpolation {
                        InterpolationMode::Step => q0,
                        InterpolationMode::Linear | InterpolationMode::CubicSpline => {
                            slerp_quat(q0, q1, t as f64)
                        }
                    };
                    scene.entities[target_idx].transform.rotation = interpolated;
                    scene.entities[target_idx].transform.dirty = true;
                }
                TargetProperty::Scale => {
                    let v0 = get_vec3(&channel.values, i0);
                    let v1 = get_vec3(&channel.values, i1);
                    let interpolated = match channel.interpolation {
                        InterpolationMode::Step => v0,
                        InterpolationMode::Linear | InterpolationMode::CubicSpline => {
                            lerp_vec3(v0, v1, t as f64)
                        }
                    };
                    scene.entities[target_idx].transform.scale = interpolated;
                    scene.entities[target_idx].transform.dirty = true;
                }
            }
        }
    }
}

/// Binary search for the keyframe interval containing `time`.
/// Returns (index0, index1, interpolation_factor) or None.
fn find_keyframe_index(times: &[f32], time: f32) -> Option<(usize, usize, f32)> {
    if times.is_empty() {
        return None;
    }
    if times.len() == 1 {
        return Some((0, 0, 0.0));
    }
    if time <= times[0] {
        return Some((0, 0, 0.0));
    }
    if time >= times[times.len() - 1] {
        let last = times.len() - 1;
        return Some((last, last, 0.0));
    }

    // Binary search
    let mut lo = 0;
    let mut hi = times.len() - 1;
    while lo < hi - 1 {
        let mid = (lo + hi) / 2;
        if times[mid] <= time {
            lo = mid;
        } else {
            hi = mid;
        }
    }

    let t0 = times[lo];
    let t1 = times[hi];
    let factor = if (t1 - t0).abs() < 1e-8 {
        0.0
    } else {
        (time - t0) / (t1 - t0)
    };

    Some((lo, hi, factor))
}

fn get_vec3(values: &[f64], index: usize) -> DVec3 {
    let i = index * 3;
    DVec3::new(values[i], values[i + 1], values[i + 2])
}

fn get_quat(values: &[f64], index: usize) -> DQuat {
    let i = index * 4;
    // ORSB stores w, x, y, z
    DQuat::from_xyzw(values[i + 1], values[i + 2], values[i + 3], values[i])
}

fn lerp_vec3(a: DVec3, b: DVec3, t: f64) -> DVec3 {
    a + (b - a) * t
}

fn slerp_quat(a: DQuat, b: DQuat, t: f64) -> DQuat {
    // glam's DQuat doesn't have slerp, so implement manually
    let mut dot = a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;

    // Ensure shortest path
    let b = if dot < 0.0 {
        dot = -dot;
        DQuat::from_xyzw(-b.x, -b.y, -b.z, -b.w)
    } else {
        b
    };

    if dot > 0.9995 {
        // Very close — use linear interpolation to avoid divide-by-zero
        let result = DQuat::from_xyzw(
            a.x + (b.x - a.x) * t,
            a.y + (b.y - a.y) * t,
            a.z + (b.z - a.z) * t,
            a.w + (b.w - a.w) * t,
        );
        return result.normalize();
    }

    let theta = dot.acos();
    let sin_theta = theta.sin();
    let w0 = ((1.0 - t) * theta).sin() / sin_theta;
    let w1 = (t * theta).sin() / sin_theta;

    DQuat::from_xyzw(
        a.x * w0 + b.x * w1,
        a.y * w0 + b.y * w1,
        a.z * w0 + b.z * w1,
        a.w * w0 + b.w * w1,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    const EPSILON: f64 = 1e-6;

    fn approx_eq(a: f64, b: f64) -> bool {
        (a - b).abs() < EPSILON
    }

    // ── find_keyframe_index ──

    #[test]
    fn test_empty_times() {
        assert_eq!(find_keyframe_index(&[], 1.0), None);
    }

    #[test]
    fn test_single_keyframe() {
        let result = find_keyframe_index(&[0.0], 0.5);
        assert_eq!(result, Some((0, 0, 0.0)));
    }

    #[test]
    fn test_before_first_keyframe() {
        let result = find_keyframe_index(&[1.0, 2.0, 3.0], 0.5);
        assert_eq!(result, Some((0, 0, 0.0)));
    }

    #[test]
    fn test_after_last_keyframe() {
        let result = find_keyframe_index(&[1.0, 2.0, 3.0], 5.0);
        assert_eq!(result, Some((2, 2, 0.0)));
    }

    #[test]
    fn test_exact_keyframe() {
        let result = find_keyframe_index(&[0.0, 1.0, 2.0], 1.0);
        let (i0, i1, _t) = result.unwrap();
        // At exact keyframe 1.0, should be in interval [1,2] with factor 0
        assert_eq!(i0, 1);
        assert_eq!(i1, 2);
        assert!((result.unwrap().2).abs() < 1e-5);
    }

    #[test]
    fn test_midpoint_interpolation() {
        let result = find_keyframe_index(&[0.0, 2.0], 1.0);
        let (i0, i1, t) = result.unwrap();
        assert_eq!(i0, 0);
        assert_eq!(i1, 1);
        assert!((t - 0.5).abs() < 1e-5, "Expected factor ~0.5, got {t}");
    }

    #[test]
    fn test_many_keyframes_binary_search() {
        let times: Vec<f32> = (0..20).map(|i| i as f32).collect();
        let result = find_keyframe_index(&times, 10.5);
        let (i0, i1, t) = result.unwrap();
        assert_eq!(i0, 10);
        assert_eq!(i1, 11);
        assert!((t - 0.5).abs() < 1e-5);
    }

    // ── lerp_vec3 ──

    #[test]
    fn test_lerp_vec3_zero() {
        let a = DVec3::new(1.0, 2.0, 3.0);
        let b = DVec3::new(4.0, 5.0, 6.0);
        let result = lerp_vec3(a, b, 0.0);
        assert!(approx_eq(result.x, 1.0));
        assert!(approx_eq(result.y, 2.0));
        assert!(approx_eq(result.z, 3.0));
    }

    #[test]
    fn test_lerp_vec3_one() {
        let a = DVec3::new(1.0, 2.0, 3.0);
        let b = DVec3::new(4.0, 5.0, 6.0);
        let result = lerp_vec3(a, b, 1.0);
        assert!(approx_eq(result.x, 4.0));
        assert!(approx_eq(result.y, 5.0));
        assert!(approx_eq(result.z, 6.0));
    }

    #[test]
    fn test_lerp_vec3_half() {
        let a = DVec3::new(0.0, 0.0, 0.0);
        let b = DVec3::new(10.0, 20.0, 30.0);
        let result = lerp_vec3(a, b, 0.5);
        assert!(approx_eq(result.x, 5.0));
        assert!(approx_eq(result.y, 10.0));
        assert!(approx_eq(result.z, 15.0));
    }

    // ── get_vec3 / get_quat ──

    #[test]
    fn test_get_vec3_index_zero() {
        let values = vec![1.0, 2.0, 3.0, 4.0, 5.0, 6.0];
        let v = get_vec3(&values, 0);
        assert_eq!(v, DVec3::new(1.0, 2.0, 3.0));
    }

    #[test]
    fn test_get_vec3_index_one() {
        let values = vec![1.0, 2.0, 3.0, 4.0, 5.0, 6.0];
        let v = get_vec3(&values, 1);
        assert_eq!(v, DVec3::new(4.0, 5.0, 6.0));
    }

    #[test]
    fn test_get_quat_identity() {
        // ORSB stores w, x, y, z → [1.0, 0.0, 0.0, 0.0]
        let values = vec![1.0, 0.0, 0.0, 0.0];
        let q = get_quat(&values, 0);
        // from_xyzw(x=0, y=0, z=0, w=1) → identity
        assert!(approx_eq(q.w, 1.0));
        assert!(approx_eq(q.x, 0.0));
        assert!(approx_eq(q.y, 0.0));
        assert!(approx_eq(q.z, 0.0));
    }

    #[test]
    fn test_get_quat_swizzle() {
        // ORSB format: [w, x, y, z]
        let values = vec![0.707, 0.0, 0.707, 0.0];
        let q = get_quat(&values, 0);
        // from_xyzw(values[1], values[2], values[3], values[0])
        assert!(approx_eq(q.x, 0.0));
        assert!(approx_eq(q.y, 0.707));
        assert!(approx_eq(q.z, 0.0));
        assert!(approx_eq(q.w, 0.707));
    }

    // ── slerp_quat ──

    #[test]
    fn test_slerp_zero() {
        let a = DQuat::IDENTITY;
        let b = DQuat::from_rotation_y(std::f64::consts::FRAC_PI_2);
        let result = slerp_quat(a, b, 0.0);
        assert!(approx_eq(result.w, a.w));
        assert!(approx_eq(result.x, a.x));
        assert!(approx_eq(result.y, a.y));
        assert!(approx_eq(result.z, a.z));
    }

    #[test]
    fn test_slerp_one() {
        let a = DQuat::IDENTITY;
        let b = DQuat::from_rotation_y(std::f64::consts::FRAC_PI_2);
        let result = slerp_quat(a, b, 1.0);
        assert!(approx_eq(result.w, b.w));
        assert!(approx_eq(result.x, b.x));
        assert!(approx_eq(result.y, b.y));
        assert!(approx_eq(result.z, b.z));
    }

    #[test]
    fn test_slerp_result_normalized() {
        let a = DQuat::IDENTITY;
        let b = DQuat::from_rotation_y(std::f64::consts::FRAC_PI_2);
        for i in 0..=10 {
            let t = i as f64 / 10.0;
            let result = slerp_quat(a, b, t);
            let len = (result.x * result.x + result.y * result.y
                + result.z * result.z + result.w * result.w).sqrt();
            assert!(approx_eq(len, 1.0), "Slerp result not normalized at t={t}: len={len}");
        }
    }

    #[test]
    fn test_slerp_nearly_identical() {
        // When quaternions are very close, uses linear interpolation fallback
        let a = DQuat::IDENTITY;
        let b = DQuat::from_rotation_y(0.0001);
        let result = slerp_quat(a, b, 0.5);
        let len = (result.x * result.x + result.y * result.y
            + result.z * result.z + result.w * result.w).sqrt();
        assert!(approx_eq(len, 1.0), "Near-identity slerp not normalized: len={len}");
    }

    #[test]
    fn test_slerp_shortest_path() {
        // If dot < 0, should negate b to take shortest path
        let a = DQuat::IDENTITY;
        // Negate identity → same rotation but opposite hemisphere
        let b = DQuat::from_xyzw(0.0, 0.0, 0.0, -1.0);
        let result = slerp_quat(a, b, 0.5);
        // Should interpolate along shortest path (staying near identity)
        let len = (result.x * result.x + result.y * result.y
            + result.z * result.z + result.w * result.w).sqrt();
        assert!(approx_eq(len, 1.0));
    }
}
