# =============================================================================
# Health System — damage application, healing, and death handling
# =============================================================================

"""
    apply_damage!(target, amount; damage_type, source, knockback)

Apply damage to an entity with `HealthComponent`. Calculates final damage
after armor and resistances, emits events, and handles death.
"""
function apply_damage!(target::EntityID, amount::Real;
                       damage_type::DamageType = DAMAGE_PHYSICAL,
                       source::Union{EntityID, Nothing} = nothing,
                       knockback::Vec3d = Vec3d(0, 0, 0))
    health = get_component(target, HealthComponent)
    health === nothing && return nothing
    health._dead && return nothing
    health.invincible && return nothing

    raw = Float32(amount)
    final_amount = raw

    if damage_type != DAMAGE_TRUE
        # Apply armor for physical damage
        if damage_type == DAMAGE_PHYSICAL
            final_amount = max(0.0f0, final_amount - health.armor)
        end
        # Apply resistance multiplier
        resistance = get(health.resistances, damage_type, 1.0f0)
        final_amount *= resistance
    end

    health.current_hp = max(0.0f0, health.current_hp - final_amount)

    event = DamageEvent(source, target, raw, final_amount, damage_type, knockback)
    emit!(event)

    # Fire per-entity callback
    if health.on_damage !== nothing
        try
            health.on_damage(target, event)
        catch e
            @warn "on_damage callback error" entity=target exception=e
        end
    end

    # Apply knockback to rigidbody
    if knockback != Vec3d(0, 0, 0)
        rb = get_component(target, RigidBodyComponent)
        if rb !== nothing && rb.body_type == BODY_DYNAMIC
            rb.velocity = rb.velocity + knockback
        end
    end

    # Death check
    if health.current_hp <= 0.0f0 && !health._dead
        health._dead = true
        death_event = DeathEvent(target, source, damage_type)
        emit!(death_event)
        if health.on_death !== nothing
            try
                health.on_death(target, death_event)
            catch e
                @warn "on_death callback error" entity=target exception=e
            end
        end
    end

    return nothing
end

"""
    heal!(target, amount; source=nothing)

Heal an entity. Clamps at max_hp. Emits `HealEvent`.
"""
function heal!(target::EntityID, amount::Real;
               source::Union{EntityID, Nothing} = nothing)
    health = get_component(target, HealthComponent)
    health === nothing && return nothing
    health._dead && return nothing

    old_hp = health.current_hp
    health.current_hp = min(health.max_hp, health.current_hp + Float32(amount))
    actual = health.current_hp - old_hp

    if actual > 0.0f0
        emit!(HealEvent(source, target, actual))
    end

    return nothing
end

"""
    is_dead(entity) -> Bool

Check if an entity's HealthComponent has reached 0 HP.
"""
function is_dead(entity::EntityID)::Bool
    health = get_component(entity, HealthComponent)
    return health !== nothing && health._dead
end

"""
    get_hp(entity) -> Union{Float32, Nothing}

Get the current HP of an entity, or `nothing` if it has no HealthComponent.
"""
function get_hp(entity::EntityID)::Union{Float32, Nothing}
    health = get_component(entity, HealthComponent)
    return health !== nothing ? health.current_hp : nothing
end

"""
    get_hp_fraction(entity) -> Union{Float32, Nothing}

Get the current HP as a fraction of max HP (0.0 to 1.0).
"""
function get_hp_fraction(entity::EntityID)::Union{Float32, Nothing}
    health = get_component(entity, HealthComponent)
    health === nothing && return nothing
    health.max_hp <= 0.0f0 && return 0.0f0
    return health.current_hp / health.max_hp
end

"""
    update_health_system!(ctx::GameContext)

Process auto-despawn for dead entities. Called once per frame.
"""
function update_health_system!(ctx::GameContext)
    iterate_components(HealthComponent) do eid, health
        if health._dead && health.auto_despawn
            health.auto_despawn = false  # Prevent double-despawn
            despawn!(ctx, eid)
        end
    end
    return nothing
end
