# =============================================================================
# Entity ID System
# =============================================================================

"""
    EntityID

Unique identifier for entities in the ECS.
"""
const EntityID = Ark.Entity

# just for current tests TODO: remove this after adjusting tests
####
EntityID(x::Int) = Ark._new_entity(UInt32(x), UInt32(0))
EntityID(x::Int, y::Int) = Ark._new_entity(UInt32(x), UInt32(y))
Base.isless(a::EntityID, b::EntityID) = a._id < b._id
####

function initialize_world(custom_components=[])
    component_types = [
        # Custom
        custom_components...,
        # Animation
        AnimationComponent,
        # Animation Blend Tree
        AnimationBlendTreeComponent,
        # Audio
        AudioListenerComponent,
        AudioSourceComponent,
        # Camera
        CameraComponent,
        # Camera Controller
        ThirdPersonCamera,
        OrbitCamera,
        CinematicCamera,
        # Collider
        ColliderComponent,
        # Lights
        PointLightComponent,
        DirectionalLightComponent,
        IBLComponent,
        # Lod
        LODComponent,
        # Material
        MaterialComponent,
        # Mesh
        MeshComponent,
        # Particle System
        ParticleSystemComponent,
        # Player
        PlayerComponent,
        # Rigid Body
        RigidBodyComponent,
        # Script
        ScriptComponent,
        # Skeleton
        BoneComponent,
        SkinnedMeshComponent,
        # Terrain
        TerrainComponent,
        # Transform
        TransformComponent,
        # Constraint
        JointComponent,
        # Trigger
        TriggerComponent,
        # Collision
        CollisionCallbackComponent,
    ]

    return Ark.World(component_types..., allow_mutable=true)
end

"""
    World

Container for all entities and their components.
"""
World() = _WORLD

"""
    create_entity!(world::World) -> EntityID
"""
function create_entity!(world)
    ark_entity = Ark.new_entity!(world, ())
    return ark_entity
end

# =============================================================================
# Component Base Type
# =============================================================================

"""
    Component

Abstract base type for all components in the ECS.
"""
abstract type Component end

# =============================================================================
# Component Storage (Compatibility Layer)
# =============================================================================

struct ComponentStore{T <: Component}
end

const COMPONENT_STORES = Dict{DataType, ComponentStore{<:Component}}()

"""
    reset_component_stores!()
"""
function reset_component_stores!()
    world = World()
    Ark.reset!(world)
    empty!(_GPU_CLEANUP_QUEUE)
    for hook in _RESET_HOOKS
        hook()
    end
end

const _RESET_HOOKS = Function[]

const _GPU_CLEANUP_QUEUE = EntityID[]

function queue_gpu_cleanup!(entity_ids)
    append!(_GPU_CLEANUP_QUEUE, entity_ids)
    return nothing
end

function drain_gpu_cleanup_queue!()::Vector{EntityID}
    if isempty(_GPU_CLEANUP_QUEUE)
        return EntityID[]
    end
    result = copy(_GPU_CLEANUP_QUEUE)
    empty!(_GPU_CLEANUP_QUEUE)
    return result
end

function get_component_store(::Type{T}) where T <: Component
    return ComponentStore{T}()
end

# =============================================================================
# Component Operations
# =============================================================================

"""
    add_component!(entity_id::EntityID, component::T) where T <: Component
"""
function add_component!(ark_entity::EntityID, component::T) where T <: Component
    world = World()
    if ark_entity === nothing
        ark_entity = Ark.new_entity!(world, ())
    end
    if Ark.has_components(world, ark_entity, (T,))
        Ark.set_components!(world, ark_entity, (component,))
    else
        Ark.add_components!(world, ark_entity, (component,))
    end
    return nothing
end

"""
    get_component(entity_id::EntityID, ::Type{T}) where T <: Component
"""
function get_component(ark_entity::EntityID, ::Type{T})::Union{T, Nothing} where T <: Component
    world = World()
    ark_entity === nothing && return nothing
    if !Ark.has_components(world, ark_entity, (T,))
        return nothing
    end
    return Ark.get_components(world, ark_entity, (T,))[1]
end

function has_component(ark_entity::EntityID, ::Type{T})::Bool where T <: Component
    world = World()
    ark_entity === nothing && return false
    return Ark.has_components(world, ark_entity, (T,))
end

function remove_component!(ark_entity::EntityID, ::Type{T})::Bool where T <: Component
    world = World()
    ark_entity === nothing && return false
    if !Ark.has_components(world, ark_entity, (T,))
        return false
    end
    Ark.remove_components!(world, ark_entity, (T,))
    return true
end

# =============================================================================
# Component Iteration
# =============================================================================

"""
    collect_components(::Type{T}) where T <: Component
"""
function collect_components(::Type{T})::Vector{T} where T <: Component
    world = World()
    items = T[]
    for (entities, col) in Ark.Query(world, (T,))
        append!(items, col)
    end
    return items
end

"""
    entities_with_component(::Type{T}) where T <: Component
"""
function entities_with_component(::Type{T})::Vector{EntityID} where T <: Component
    world = World()
    ids = Ark.Entity[]
    q = Ark.Query(world, (T,))
    for (entities, _) in q
        append!(ids, entities)
    end
    return ids
end

"""
    first_entity_with_component(::Type{T}) where T <: Component
"""
function first_entity_with_component(::Type{T})::Union{EntityID, Nothing} where T <: Component
    world = World()
    q = Ark.Query(world, (T,))
    for (entities, _) in q
        Ark.close!(q)
        return entities[1]
    end
    return nothing
end

"""
    component_count(::Type{T}) where T <: Component
"""
function component_count(::Type{T})::Int where T <: Component
    world = World()
    q = Ark.Query(world, (T,))
    count = Ark.count_entities(q)
    Ark.close!(q)
    return count
end

"""
    iterate_components(f::Function, ::Type{T}) where T <: Component
"""
function iterate_components(f::Function, ::Type{T}) where T <: Component
    world = World()
    for (entities, cols...) in Ark.Query(world, (T,))
        col = cols[1]
        for i in eachindex(entities)
            ark_ent = entities[i]
            f(ark_ent, col[i])
        end
    end
    return nothing
end

"""
    reset_engine_state!()
"""
function reset_engine_state!()
    reset_component_stores!()
    reset_physics_world!()
    reset_trigger_state!()
    reset_particle_pools!()
    reset_terrain_cache!()
    reset_lod_cache!()
    clear_world_transform_cache!()
    reset_asset_manager!()
    reset_async_loader!()
    reset_event_bus!()
    return nothing
end
