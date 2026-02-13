# LOD selection logic — backend-agnostic

# Per-entity previous LOD level cache (for hysteresis)
const _LOD_PREV_LEVELS = Dict{EntityID, Int}()

"""
    LODSelection

Result of LOD level selection for a single entity.
"""
struct LODSelection
    level_index::Int                            # 1-based index into LODComponent.levels
    mesh::MeshComponent                         # Primary mesh to render this frame
    crossfade_alpha::Float32                    # 1.0 = fully this level, <1.0 = transitioning
    next_mesh::Union{MeshComponent, Nothing}    # The other LOD during crossfade (nothing if alpha==1)
end

"""
    select_lod_level(lod::LODComponent, distance::Float32) -> LODSelection

Select the appropriate LOD level based on camera distance.
Uses hysteresis to prevent rapid LOD switching at boundary distances.
Computes crossfade alpha for smooth dithered transitions.
"""
function select_lod_level(lod::LODComponent, distance::Float32, entity_id::EntityID)
    nlevels = length(lod.levels)
    if nlevels == 0
        # No LOD levels defined — shouldn't happen if component is well-formed
        return LODSelection(1, MeshComponent(), 1.0f0, nothing)
    end
    if nlevels == 1
        return LODSelection(1, lod.levels[1].mesh, 1.0f0, nothing)
    end

    prev_level = get(_LOD_PREV_LEVELS, entity_id, 1)

    # Find the base level from distance thresholds
    base_level = nlevels  # Default to coarsest
    for i in 1:nlevels
        if distance <= lod.levels[i].max_distance
            base_level = i
            break
        end
    end

    # Apply hysteresis: resist switching back to finer LOD
    # If we were at a coarser level, require distance to be shorter by hysteresis factor
    if prev_level > base_level
        # Trying to go finer — check hysteresis
        threshold = lod.levels[base_level].max_distance / lod.hysteresis
        if distance > threshold
            base_level = prev_level  # Stay at coarser level
        end
    end

    # Clamp
    base_level = clamp(base_level, 1, nlevels)

    # Update previous level cache
    _LOD_PREV_LEVELS[entity_id] = base_level

    # Compute crossfade alpha for dither transitions
    if lod.transition_mode == LOD_TRANSITION_INSTANT || lod.transition_width <= 0.0f0
        return LODSelection(base_level, lod.levels[base_level].mesh, 1.0f0, nothing)
    end

    # Dither crossfade: compute blend within the transition band
    threshold = lod.levels[base_level].max_distance
    half_width = lod.transition_width * 0.5f0
    transition_start = threshold - half_width
    transition_end = threshold + half_width

    if distance < transition_start || base_level == nlevels
        # Fully within this level (or at coarsest — no further level to fade to)
        return LODSelection(base_level, lod.levels[base_level].mesh, 1.0f0, nothing)
    elseif distance > transition_end
        # Fully transitioned to next level
        next_level = min(base_level + 1, nlevels)
        _LOD_PREV_LEVELS[entity_id] = next_level
        return LODSelection(next_level, lod.levels[next_level].mesh, 1.0f0, nothing)
    else
        # In the transition band
        alpha = (transition_end - distance) / (transition_end - transition_start)
        alpha = clamp(alpha, 0.0f0, 1.0f0)
        next_level = min(base_level + 1, nlevels)
        next_mesh = lod.levels[next_level].mesh
        return LODSelection(base_level, lod.levels[base_level].mesh, alpha, next_mesh)
    end
end

"""
    reset_lod_cache!()

Clear the LOD level history cache. Call when resetting the scene.
"""
function reset_lod_cache!()
    empty!(_LOD_PREV_LEVELS)
    return nothing
end
