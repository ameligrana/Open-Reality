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
