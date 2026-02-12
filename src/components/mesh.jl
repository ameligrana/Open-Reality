# Mesh component

# Type alias for bone indices (4 bone indices per vertex)
const BoneIndices4 = NTuple{4, UInt16}

"""
    MeshComponent <: Component

Represents a 3D mesh with vertices, indices, normals, UV coordinates,
and optional skeletal animation data (bone weights and indices).
"""
struct MeshComponent <: Component
    vertices::Vector{Point3f}
    indices::Vector{UInt32}
    normals::Vector{Vec3f}
    uvs::Vector{Vec2f}
    bone_weights::Vector{Vec4f}
    bone_indices::Vector{BoneIndices4}

    MeshComponent(;
        vertices::Vector{Point3f} = Point3f[],
        indices::Vector{UInt32} = UInt32[],
        normals::Vector{Vec3f} = Vec3f[],
        uvs::Vector{Vec2f} = Vec2f[],
        bone_weights::Vector{Vec4f} = Vec4f[],
        bone_indices::Vector{BoneIndices4} = BoneIndices4[]
    ) = new(vertices, indices, normals, uvs, bone_weights, bone_indices)
end
