# Terrain system: per-frame terrain update (initialization, LOD, culling)

# Default chunk LOD distances (meters from camera)
const DEFAULT_CHUNK_LOD_DISTANCES = Float32[50.0, 120.0, 250.0]

"""
    update_terrain!(cam_pos::Vec3f, frustum::Frustum)

Per-frame terrain update: initialize new terrains, update chunk LODs.
Called from the render loop before rendering.
"""
function update_terrain!(cam_pos::Vec3f, frustum::Frustum)
    iterate_components(TerrainComponent) do entity_id, comp
        # Initialize terrain if not yet cached
        if !haskey(_TERRAIN_CACHE, entity_id)
            @info "Initializing terrain" entity_id=entity_id
            initialize_terrain!(entity_id, comp)
        end

        td = _TERRAIN_CACHE[entity_id]

        # Build LOD distance thresholds
        lod_distances = if comp.num_lod_levels <= length(DEFAULT_CHUNK_LOD_DISTANCES)
            DEFAULT_CHUNK_LOD_DISTANCES[1:comp.num_lod_levels]
        else
            # Extrapolate for more LOD levels
            dists = Float32[]
            for i in 1:comp.num_lod_levels
                push!(dists, Float32(50.0 * (2.5 ^ (i - 1))))
            end
            dists
        end

        # Update chunk LODs based on camera distance
        update_terrain_lod!(td, cam_pos, lod_distances)
    end
end

"""
    get_terrain_data(entity_id::EntityID) -> Union{TerrainData, Nothing}

Retrieve cached terrain data for an entity.
"""
function get_terrain_data(entity_id::EntityID)
    return get(_TERRAIN_CACHE, entity_id, nothing)
end
