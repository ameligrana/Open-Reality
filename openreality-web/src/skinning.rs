use glam::Mat4;

use crate::scene::LoadedScene;

const MAX_BONES: usize = 128;

/// Update bone matrices for all skinned meshes.
///
/// For each entity with skeleton data, computes final bone matrices:
///   bone_matrix[i] = inverse(mesh_world) * bone_world * inverse_bind_matrix
pub fn update_skinned_meshes(scene: &mut LoadedScene) {
    for skel_idx in 0..scene.skeletons.len() {
        let entity_idx = scene.skeletons[skel_idx].entity_index;
        if entity_idx >= scene.entities.len() {
            continue;
        }

        let mesh_world = scene.entities[entity_idx].world_transform;
        let inv_mesh_world = mesh_world.inverse();

        let bone_count = scene.skeletons[skel_idx].bone_entity_indices.len().min(MAX_BONES);
        scene.skeletons[skel_idx].bone_matrices.resize(bone_count, Mat4::IDENTITY);

        for i in 0..bone_count {
            let bone_entity_idx = scene.skeletons[skel_idx].bone_entity_indices[i];
            if bone_entity_idx >= scene.entities.len() {
                scene.skeletons[skel_idx].bone_matrices[i] = Mat4::IDENTITY;
                continue;
            }

            let bone_world = scene.entities[bone_entity_idx].world_transform;
            let inv_bind = scene.skeletons[skel_idx].inverse_bind_matrices[i];

            scene.skeletons[skel_idx].bone_matrices[i] = inv_mesh_world * bone_world * inv_bind;
        }
    }
}
