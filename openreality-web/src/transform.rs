use glam::{DVec3, DQuat, Mat4, Vec3, Quat};

use crate::scene::LoadedScene;

/// Compute world transform matrices for all entities in the scene.
/// Traverses from root entities down, composing parent * local transforms.
pub fn compute_world_transforms(scene: &mut LoadedScene) {
    let n = scene.entities.len();

    // Process entities in order (parents before children since ORSB is DFS-ordered)
    for i in 0..n {
        let local = compose_local_transform(
            &scene.entities[i].transform.position,
            &scene.entities[i].transform.rotation,
            &scene.entities[i].transform.scale,
        );

        let world = if let Some(parent_idx) = scene.entities[i].parent_index {
            if parent_idx < n {
                scene.entities[parent_idx].world_transform * local
            } else {
                local
            }
        } else {
            local
        };

        scene.entities[i].world_transform = world;
        scene.entities[i].transform.dirty = false;
    }
}

/// Compose a local transform matrix from position, rotation, and scale.
fn compose_local_transform(position: &DVec3, rotation: &DQuat, scale: &DVec3) -> Mat4 {
    let pos = Vec3::new(position.x as f32, position.y as f32, position.z as f32);
    let rot = Quat::from_xyzw(
        rotation.x as f32,
        rotation.y as f32,
        rotation.z as f32,
        rotation.w as f32,
    );
    let scl = Vec3::new(scale.x as f32, scale.y as f32, scale.z as f32);

    Mat4::from_scale_rotation_translation(scl, rot, pos)
}
