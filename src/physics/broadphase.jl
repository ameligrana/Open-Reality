# Spatial hash grid broadphase for O(n) collision pair generation

"""
    SpatialHashGrid

Uniform grid broadphase using spatial hashing.
Objects are inserted into grid cells based on their AABB; overlapping cells
generate candidate collision pairs.
"""
mutable struct SpatialHashGrid
    cell_size::Float64
    inv_cell_size::Float64
    cells::Dict{Tuple{Int,Int,Int}, Vector{EntityID}}
    entity_aabbs::Dict{EntityID, AABB3D}
    entity_layers::Dict{EntityID, Tuple{UInt32, UInt32}}  # (layer, mask) per entity
end

function SpatialHashGrid(; cell_size::Float64 = 2.0)
    SpatialHashGrid(cell_size, 1.0 / cell_size,
                    Dict{Tuple{Int,Int,Int}, Vector{EntityID}}(),
                    Dict{EntityID, AABB3D}(),
                    Dict{EntityID, Tuple{UInt32, UInt32}}())
end

"""
    clear!(grid::SpatialHashGrid)

Remove all entities from the grid.
"""
function clear!(grid::SpatialHashGrid)
    empty!(grid.cells)
    empty!(grid.entity_aabbs)
    empty!(grid.entity_layers)
end

"""
    _cell_coord(grid::SpatialHashGrid, x::Float64) -> Int

Convert a world coordinate to a grid cell coordinate.
"""
@inline function _cell_coord(grid::SpatialHashGrid, x::Float64)
    return floor(Int, x * grid.inv_cell_size)
end

"""
    insert!(grid::SpatialHashGrid, entity_id::EntityID, aabb::AABB3D)

Insert an entity into all grid cells that its AABB overlaps.
"""
function Base.insert!(grid::SpatialHashGrid, entity_id::EntityID, aabb::AABB3D;
                      layer::UInt32 = LAYER_DEFAULT, mask::UInt32 = LAYER_ALL)
    grid.entity_aabbs[entity_id] = aabb
    grid.entity_layers[entity_id] = (layer, mask)

    min_x = _cell_coord(grid, aabb.min_pt[1])
    min_y = _cell_coord(grid, aabb.min_pt[2])
    min_z = _cell_coord(grid, aabb.min_pt[3])
    max_x = _cell_coord(grid, aabb.max_pt[1])
    max_y = _cell_coord(grid, aabb.max_pt[2])
    max_z = _cell_coord(grid, aabb.max_pt[3])

    for x in min_x:max_x
        for y in min_y:max_y
            for z in min_z:max_z
                key = (x, y, z)
                if haskey(grid.cells, key)
                    push!(grid.cells[key], entity_id)
                else
                    grid.cells[key] = [entity_id]
                end
            end
        end
    end
end

"""
    query_pairs(grid::SpatialHashGrid) -> Vector{CollisionPair}

Generate unique collision pairs from entities sharing grid cells.
Each pair is returned exactly once (entity_a < entity_b).
"""
function query_pairs(grid::SpatialHashGrid)
    seen = Set{Tuple{EntityID, EntityID}}()
    pairs = CollisionPair[]

    for (_, entities) in grid.cells
        n = length(entities)
        for i in 1:n
            for j in (i+1):n
                a = entities[i]
                b = entities[j]
                # Canonical ordering
                key = a < b ? (a, b) : (b, a)
                if !(key in seen)
                    push!(seen, key)

                    # Check collision layer compatibility
                    la, ma = get(grid.entity_layers, key[1], (LAYER_DEFAULT, LAYER_ALL))
                    lb, mb = get(grid.entity_layers, key[2], (LAYER_DEFAULT, LAYER_ALL))
                    if !layers_interact(la, ma, lb, mb)
                        continue
                    end

                    # Verify AABB overlap (cells can be coarse)
                    aabb_a = grid.entity_aabbs[key[1]]
                    aabb_b = grid.entity_aabbs[key[2]]
                    if aabb_overlap(aabb_a, aabb_b)
                        push!(pairs, CollisionPair(key[1], key[2]))
                    end
                end
            end
        end
    end

    return pairs
end
