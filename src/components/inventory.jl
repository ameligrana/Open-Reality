# =============================================================================
# Inventory Components — slots-based inventory and world pickups
# =============================================================================

"""
    ItemStack

A stack of items in an inventory slot.
"""
mutable struct ItemStack
    item_id::Symbol
    count::Int
end

"""
    InventoryComponent <: Component

Fixed-size inventory with item slots.
"""
mutable struct InventoryComponent <: Component
    slots::Vector{Union{ItemStack, Nothing}}
    max_slots::Int
    max_weight::Float32

    function InventoryComponent(; max_slots::Int=20, max_weight::Float32=100.0f0)
        new(fill(nothing, max_slots), max_slots, max_weight)
    end
end

"""
    PickupComponent <: Component

Makes an entity a world pickup that can be collected into an inventory.
"""
mutable struct PickupComponent <: Component
    item_id::Symbol
    count::Int
    auto_pickup_radius::Float32  # 0 = manual pickup only

    PickupComponent(item_id::Symbol;
                    count::Int = 1,
                    auto_pickup_radius::Float32 = 2.0f0
    ) = new(item_id, count, auto_pickup_radius)
end
