# =============================================================================
# Inventory System — item operations and pickup processing
# =============================================================================

"""
    add_item!(entity, item_id, count=1) -> Int

Add items to an entity's inventory. Returns the number actually added
(may be less if inventory is full or weight exceeded).
"""
function add_item!(entity::EntityID, item_id::Symbol, count::Int=1)::Int
    inv = get_component(entity, InventoryComponent)
    inv === nothing && return 0
    def = get_item_def(item_id)
    def === nothing && return 0

    remaining = count

    # First pass: stack onto existing slots with same item
    if def.stackable
        for slot in inv.slots
            remaining <= 0 && break
            slot === nothing && continue
            slot.item_id != item_id && continue
            space = def.max_stack - slot.count
            added = min(remaining, space)
            if added > 0
                slot.count += added
                remaining -= added
            end
        end
    end

    # Second pass: fill empty slots
    while remaining > 0
        idx = findfirst(isnothing, inv.slots)
        idx === nothing && break
        add_count = def.stackable ? min(remaining, def.max_stack) : 1
        inv.slots[idx] = ItemStack(item_id, add_count)
        remaining -= add_count
    end

    return count - remaining
end

"""
    remove_item!(entity, item_id, count=1) -> Int

Remove items from an entity's inventory. Returns the number actually removed.
"""
function remove_item!(entity::EntityID, item_id::Symbol, count::Int=1)::Int
    inv = get_component(entity, InventoryComponent)
    inv === nothing && return 0

    remaining = count

    for i in eachindex(inv.slots)
        remaining <= 0 && break
        slot = inv.slots[i]
        slot === nothing && continue
        slot.item_id != item_id && continue

        removed = min(remaining, slot.count)
        slot.count -= removed
        remaining -= removed

        if slot.count <= 0
            inv.slots[i] = nothing
        end
    end

    return count - remaining
end

"""
    has_item(entity, item_id; count=1) -> Bool

Check if an entity's inventory contains at least `count` of the given item.
"""
function has_item(entity::EntityID, item_id::Symbol; count::Int=1)::Bool
    return get_item_count(entity, item_id) >= count
end

"""
    get_item_count(entity, item_id) -> Int

Get the total count of an item across all inventory slots.
"""
function get_item_count(entity::EntityID, item_id::Symbol)::Int
    inv = get_component(entity, InventoryComponent)
    inv === nothing && return 0
    total = 0
    for slot in inv.slots
        slot === nothing && continue
        slot.item_id == item_id && (total += slot.count)
    end
    return total
end

"""
    use_item!(entity, slot_index) -> Bool

Use the item at the given slot index (1-based). Calls the item's `on_use` callback.
Returns `true` if the item was consumed.
"""
function use_item!(entity::EntityID, slot_index::Int)::Bool
    inv = get_component(entity, InventoryComponent)
    inv === nothing && return false
    slot_index < 1 || slot_index > length(inv.slots) && return false

    slot = inv.slots[slot_index]
    slot === nothing && return false

    def = get_item_def(slot.item_id)
    def === nothing && return false

    consumed = false
    if def.on_use !== nothing
        try
            consumed = def.on_use(entity, def)::Bool
        catch e
            @warn "Item on_use error" item=slot.item_id exception=e
            return false
        end
    end

    if consumed
        emit!(ItemUsedEvent(entity, slot.item_id))
        slot.count -= 1
        if slot.count <= 0
            inv.slots[slot_index] = nothing
        end
    end

    return consumed
end

"""
    get_inventory_slots(entity) -> Union{Vector{Union{ItemStack, Nothing}}, Nothing}

Get the raw slots array for rendering inventory UI.
"""
function get_inventory_slots(entity::EntityID)
    inv = get_component(entity, InventoryComponent)
    return inv !== nothing ? inv.slots : nothing
end

"""
    update_pickups!(dt::Float64, ctx::GameContext)

Check proximity between PickupComponents and InventoryComponents.
Auto-collect items within pickup radius.
"""
function update_pickups!(dt::Float64, ctx::GameContext)
    # Collect all entities with inventories and their positions
    inventory_entities = Tuple{EntityID, Vec3d}[]
    iterate_components(InventoryComponent) do eid, _inv
        tc = get_component(eid, TransformComponent)
        tc === nothing && return
        push!(inventory_entities, (eid, tc.position[]))
    end

    isempty(inventory_entities) && return nothing

    # Check each pickup against inventory entities
    iterate_components(PickupComponent) do pickup_eid, pickup
        pickup.auto_pickup_radius <= 0 && return

        tc = get_component(pickup_eid, TransformComponent)
        tc === nothing && return
        pickup_pos = tc.position[]

        radius_sq = Float64(pickup.auto_pickup_radius)^2

        for (inv_eid, inv_pos) in inventory_entities
            dx = pickup_pos[1] - inv_pos[1]
            dy = pickup_pos[2] - inv_pos[2]
            dz = pickup_pos[3] - inv_pos[3]
            dist_sq = dx * dx + dy * dy + dz * dz

            if dist_sq <= radius_sq
                added = add_item!(inv_eid, pickup.item_id, pickup.count)
                if added > 0
                    emit!(ItemPickedUpEvent(inv_eid, pickup.item_id, added))
                    despawn!(ctx, pickup_eid)
                    return  # This pickup is consumed
                end
            end
        end
    end

    return nothing
end
