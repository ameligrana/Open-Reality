# Instanced rendering — backend-agnostic batching logic

"""
    InstanceBatchKey

Key for grouping entities that share the same mesh + material signature.
Entities with the same key can be drawn in a single instanced call.
"""
struct InstanceBatchKey
    mesh_id::UInt64                     # objectid of the MeshComponent (reference identity)
    material_variant::ShaderVariantKey  # Shader variant determines compatible draw state
    has_skinning::Bool                  # Skinned meshes cannot be instanced
end

Base.hash(k::InstanceBatchKey, h::UInt) = hash(k.mesh_id, hash(k.material_variant, hash(k.has_skinning, h)))
Base.:(==)(a::InstanceBatchKey, b::InstanceBatchKey) =
    a.mesh_id == b.mesh_id && a.material_variant == b.material_variant && a.has_skinning == b.has_skinning

"""
    InstanceBatch

A group of entities that can be rendered with a single instanced draw call.
All entities share the same mesh geometry and material shader variant.
"""
struct InstanceBatch
    key::InstanceBatchKey
    representative::EntityRenderData           # First entity — used for mesh/material lookup
    model_matrices::Vector{Mat4f}
    normal_matrices::Vector{SMatrix{3, 3, Float32, 9}}
    entity_ids::Vector{EntityID}               # For per-entity material overrides if needed
end

"""
    group_into_batches(entities::Vector{EntityRenderData}) -> (Vector{InstanceBatch}, Vector{EntityRenderData})

Group opaque entities into instanced batches based on shared mesh + material.
Returns:
- `batches`: groups with ≥2 entities sharing mesh+material (benefit from instancing)
- `singles`: entities that don't share mesh+material with others (render normally)

Only non-skinned, non-LOD-crossfading entities are eligible for instancing.
"""
function group_into_batches(entities::Vector{EntityRenderData})
    batches = InstanceBatch[]
    singles = EntityRenderData[]

    # Group by batch key
    groups = Dict{InstanceBatchKey, Vector{EntityRenderData}}()

    for erd in entities
        # Skip entities that are LOD crossfading (need special 2-pass rendering)
        if erd.lod_crossfade < 1.0f0 && erd.lod_next_mesh !== nothing
            push!(singles, erd)
            continue
        end

        # Skip skinned meshes (bone matrices differ per entity)
        has_skinning = !isempty(erd.mesh.bone_weights) && !isempty(erd.mesh.bone_indices)
        if has_skinning
            push!(singles, erd)
            continue
        end

        # Determine material variant for this entity
        material = get_component(erd.entity_id, MaterialComponent)
        if material === nothing
            push!(singles, erd)
            continue
        end
        variant_key = determine_shader_variant(material)

        # Use objectid of the mesh as identity (works when meshes are shared by reference)
        mesh_id = objectid(erd.mesh)
        batch_key = InstanceBatchKey(mesh_id, variant_key, false)

        if !haskey(groups, batch_key)
            groups[batch_key] = EntityRenderData[]
        end
        push!(groups[batch_key], erd)
    end

    # Convert groups to batches
    for (key, group) in groups
        if length(group) >= 2
            models = Mat4f[erd.model for erd in group]
            normals = SMatrix{3, 3, Float32, 9}[erd.normal_matrix for erd in group]
            eids = EntityID[erd.entity_id for erd in group]
            push!(batches, InstanceBatch(key, group[1], models, normals, eids))
        else
            push!(singles, group[1])
        end
    end

    return (batches, singles)
end
