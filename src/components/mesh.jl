# Mesh component

"""
    MeshComponent <: Component

Represents a 3D mesh with vertices and indices.
"""
struct MeshComponent <: Component
    vertices::Vector{Point3f}
    indices::Vector{UInt32}
    normals::Vector{Vec3f}

    MeshComponent(;
        vertices::Vector{Point3f} = Point3f[],
        indices::Vector{UInt32} = UInt32[],
        normals::Vector{Vec3f} = Vec3f[]
    ) = new(vertices, indices, normals)
end
