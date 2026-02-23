# Collider component for collision detection

"""
    ColliderShape

Abstract base type for collider shapes.
"""
abstract type ColliderShape end

"""
    AABBShape <: ColliderShape

Axis-Aligned Bounding Box collider defined by half-extents from center.
"""
struct AABBShape <: ColliderShape
    half_extents::Vec3f
end

"""
    SphereShape <: ColliderShape

Sphere collider defined by a radius.
"""
struct SphereShape <: ColliderShape
    radius::Float32
end

# ---------------------------------------------------------------------------
# Collision layer constants
# ---------------------------------------------------------------------------

const LAYER_DEFAULT    = UInt32(1)
const LAYER_PLAYER     = UInt32(1 << 1)
const LAYER_ENEMY      = UInt32(1 << 2)
const LAYER_TERRAIN    = UInt32(1 << 3)
const LAYER_PROJECTILE = UInt32(1 << 4)
const LAYER_PICKUP     = UInt32(1 << 5)
const LAYER_TRIGGER    = UInt32(1 << 6)
const LAYER_ALL        = UInt32(0xFFFFFFFF)

# User-extensible named layer registry
const _LAYER_NAMES = Dict{String, UInt32}(
    "default"    => LAYER_DEFAULT,
    "player"     => LAYER_PLAYER,
    "enemy"      => LAYER_ENEMY,
    "terrain"    => LAYER_TERRAIN,
    "projectile" => LAYER_PROJECTILE,
    "pickup"     => LAYER_PICKUP,
    "trigger"    => LAYER_TRIGGER,
)

"""
    register_layer!(name::String, bit::UInt32)

Register a named collision layer.
"""
function register_layer!(name::String, bit::UInt32)
    _LAYER_NAMES[name] = bit
    return nothing
end

"""
    get_layer(name::String) -> UInt32

Get the bitmask for a named collision layer.
"""
function get_layer(name::String)::UInt32
    return get(_LAYER_NAMES, name, LAYER_DEFAULT)
end

"""
    layers_interact(layer_a::UInt32, mask_a::UInt32, layer_b::UInt32, mask_b::UInt32) -> Bool

Check if two colliders should interact based on their layer/mask configuration.
Both directions must match: a's layer must be in b's mask AND b's layer must be in a's mask.
"""
@inline function layers_interact(layer_a::UInt32, mask_a::UInt32, layer_b::UInt32, mask_b::UInt32)::Bool
    return (layer_a & mask_b) != 0 && (layer_b & mask_a) != 0
end

"""
    ColliderComponent <: Component

Attaches a collision shape to an entity. The shape is defined in local space;
the physics system uses the entity's world transform to position it.

`offset` shifts the collider relative to the entity's origin.
`is_trigger` if true, generates trigger events instead of contact forces.
`layer` bitmask of which layer this collider belongs to.
`mask` bitmask of which layers this collider checks against.
"""
mutable struct ColliderComponent <: Component
    shape::ColliderShape
    offset::Vec3f
    is_trigger::Bool
    layer::UInt32
    mask::UInt32

    ColliderComponent(;
        shape::ColliderShape = AABBShape(Vec3f(0.5, 0.5, 0.5)),
        offset::Vec3f = Vec3f(0, 0, 0),
        is_trigger::Bool = false,
        layer::UInt32 = LAYER_DEFAULT,
        mask::UInt32 = LAYER_ALL
    ) = new(shape, offset, is_trigger, layer, mask)
end

"""
    set_collision_layer!(entity::EntityID, layer::UInt32)

Set the collision layer for an entity's collider.
"""
function set_collision_layer!(entity::EntityID, layer::UInt32)
    collider = get_component(entity, ColliderComponent)
    collider !== nothing && (collider.layer = layer)
    return nothing
end

"""
    set_collision_mask!(entity::EntityID, mask::UInt32)

Set the collision mask for an entity's collider.
"""
function set_collision_mask!(entity::EntityID, mask::UInt32)
    collider = get_component(entity, ColliderComponent)
    collider !== nothing && (collider.mask = mask)
    return nothing
end

"""
    collider_from_mesh(mesh::MeshComponent) -> ColliderComponent

Auto-generate an AABB collider from mesh vertex bounds.
"""
function collider_from_mesh(mesh::MeshComponent)
    if isempty(mesh.vertices)
        return ColliderComponent()
    end

    min_pt = Vec3f(Inf32, Inf32, Inf32)
    max_pt = Vec3f(-Inf32, -Inf32, -Inf32)

    for v in mesh.vertices
        min_pt = Vec3f(min(min_pt[1], v[1]), min(min_pt[2], v[2]), min(min_pt[3], v[3]))
        max_pt = Vec3f(max(max_pt[1], v[1]), max(max_pt[2], v[2]), max(max_pt[3], v[3]))
    end

    center = (min_pt + max_pt) * 0.5f0
    half_ext = (max_pt - min_pt) * 0.5f0

    return ColliderComponent(shape=AABBShape(half_ext), offset=center)
end

"""
    sphere_collider_from_mesh(mesh::MeshComponent) -> ColliderComponent

Auto-generate a sphere collider that bounds all mesh vertices.
"""
function sphere_collider_from_mesh(mesh::MeshComponent)
    if isempty(mesh.vertices)
        return ColliderComponent(shape=SphereShape(0.5f0))
    end

    center = Vec3f(0, 0, 0)
    for v in mesh.vertices
        center = center + Vec3f(v[1], v[2], v[3])
    end
    center = center / Float32(length(mesh.vertices))

    max_dist_sq = 0.0f0
    for v in mesh.vertices
        d = Vec3f(v[1], v[2], v[3]) - center
        dist_sq = d[1]^2 + d[2]^2 + d[3]^2
        max_dist_sq = max(max_dist_sq, dist_sq)
    end

    return ColliderComponent(shape=SphereShape(sqrt(max_dist_sq)), offset=center)
end

"""
    HeightmapShape <: ColliderShape

Collision shape backed by a terrain heightmap. Used for terrain physics.
Stores a reference to the entity ID whose TerrainData/TerrainComponent
provides the heightmap data.
"""
struct HeightmapShape <: ColliderShape
    terrain_entity_id::EntityID
    terrain_size::Vec2f       # World-space X, Z dimensions
    max_height::Float32
end
