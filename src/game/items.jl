# =============================================================================
# Item System — item definitions and global registry
# =============================================================================

@enum ItemType begin
    ITEM_CONSUMABLE
    ITEM_EQUIPMENT
    ITEM_MATERIAL
    ITEM_KEY
    ITEM_QUEST
end

"""
    ItemDef

Definition of an item type. Registered once in the global `ItemRegistry`.
"""
struct ItemDef
    id::Symbol
    name::String
    description::String
    icon_path::String
    stackable::Bool
    max_stack::Int
    weight::Float32
    item_type::ItemType
    on_use::Union{Function, Nothing}   # (user_entity, item_def) -> Bool (consumed?)
    metadata::Dict{Symbol, Any}        # Custom data (damage, defense, heal amount, etc.)

    function ItemDef(id::Symbol, name::String;
                     description::String = "",
                     icon_path::String = "",
                     stackable::Bool = true,
                     max_stack::Int = 99,
                     weight::Float32 = 0.0f0,
                     item_type::ItemType = ITEM_MATERIAL,
                     on_use::Union{Function, Nothing} = nothing,
                     metadata::Dict{Symbol, Any} = Dict{Symbol, Any}())
        new(id, name, description, icon_path, stackable, max_stack,
            weight, item_type, on_use, metadata)
    end
end

"""
    ItemRegistry

Global registry of item definitions.
"""
mutable struct ItemRegistry
    items::Dict{Symbol, ItemDef}
    ItemRegistry() = new(Dict{Symbol, ItemDef}())
end

# ---------------------------------------------------------------------------
# Global singleton
# ---------------------------------------------------------------------------

const _ITEM_REGISTRY = Ref{Union{ItemRegistry, Nothing}}(nothing)

function get_item_registry()::ItemRegistry
    if _ITEM_REGISTRY[] === nothing
        _ITEM_REGISTRY[] = ItemRegistry()
    end
    return _ITEM_REGISTRY[]
end

function reset_item_registry!()
    _ITEM_REGISTRY[] = nothing
    return nothing
end

"""
    register_item!(def::ItemDef)

Register an item definition in the global registry.
"""
function register_item!(def::ItemDef)
    registry = get_item_registry()
    registry.items[def.id] = def
    return nothing
end

"""
    get_item_def(id::Symbol) -> Union{ItemDef, Nothing}

Look up an item definition by ID.
"""
function get_item_def(id::Symbol)::Union{ItemDef, Nothing}
    registry = get_item_registry()
    return get(registry.items, id, nothing)
end

# ---------------------------------------------------------------------------
# Events
# ---------------------------------------------------------------------------

struct ItemPickedUpEvent <: GameEvent
    entity::EntityID
    item_id::Symbol
    count::Int
end

struct ItemUsedEvent <: GameEvent
    entity::EntityID
    item_id::Symbol
end

struct ItemDroppedEvent <: GameEvent
    entity::EntityID
    item_id::Symbol
    count::Int
    position::Vec3d
end
