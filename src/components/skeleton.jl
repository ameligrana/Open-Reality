# Skeletal animation: bone and skinned mesh components

"""
    BoneComponent <: Component

Represents a single bone in a skeletal hierarchy.
Each bone has an inverse bind matrix and an index into the bone array.
"""
struct BoneComponent <: Component
    inverse_bind_matrix::Mat4f
    bone_index::Int
    name::String

    BoneComponent(;
        inverse_bind_matrix::Mat4f = Mat4f(I),
        bone_index::Int = 0,
        name::String = ""
    ) = new(inverse_bind_matrix, bone_index, name)
end

"""
    SkinnedMeshComponent <: Component

Links a mesh entity to its skeleton.
`bone_entities` is an ordered list of entity IDs for each bone.
`bone_matrices` is the pre-computed final transform for each bone (updated per frame).
"""
mutable struct SkinnedMeshComponent <: Component
    bone_entities::Vector{EntityID}
    bone_matrices::Vector{Mat4f}

    SkinnedMeshComponent(;
        bone_entities::Vector{EntityID} = EntityID[],
        bone_matrices::Vector{Mat4f} = Mat4f[]
    ) = new(bone_entities, bone_matrices)
end
