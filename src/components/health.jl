# =============================================================================
# Health Component — HP, armor, resistances, and damage type definitions
# =============================================================================

@enum DamageType begin
    DAMAGE_PHYSICAL
    DAMAGE_FIRE
    DAMAGE_ICE
    DAMAGE_ELECTRIC
    DAMAGE_MAGIC
    DAMAGE_TRUE     # Ignores armor and resistances
end

"""
    HealthComponent <: Component

Tracks entity health, armor, and damage resistances.
"""
mutable struct HealthComponent <: Component
    current_hp::Float32
    max_hp::Float32
    invincible::Bool
    armor::Float32                              # Flat damage reduction for PHYSICAL
    resistances::Dict{DamageType, Float32}      # Multiplier per type (0.0=immune, 1.0=normal, 2.0=weak)
    on_damage::Union{Function, Nothing}         # (entity_id, DamageEvent) -> nothing
    on_death::Union{Function, Nothing}          # (entity_id, DeathEvent) -> nothing
    auto_despawn::Bool                          # Despawn entity on death?
    _dead::Bool

    function HealthComponent(;
        max_hp::Real = 100.0f0,
        current_hp::Union{Real, Nothing} = nothing,
        armor::Real = 0.0f0,
        invincible::Bool = false,
        resistances::Dict{DamageType, Float32} = Dict{DamageType, Float32}(),
        on_damage::Union{Function, Nothing} = nothing,
        on_death::Union{Function, Nothing} = nothing,
        auto_despawn::Bool = false
    )
        hp = current_hp !== nothing ? Float32(current_hp) : Float32(max_hp)
        new(hp, Float32(max_hp), invincible, Float32(armor), resistances,
            on_damage, on_death, auto_despawn, false)
    end
end

# ---------------------------------------------------------------------------
# Event types
# ---------------------------------------------------------------------------

struct DamageEvent <: GameEvent
    source::Union{EntityID, Nothing}
    target::EntityID
    amount::Float32           # Raw damage before reduction
    final_amount::Float32     # After armor/resistance
    damage_type::DamageType
    knockback_force::Vec3d
end

struct HealEvent <: GameEvent
    source::Union{EntityID, Nothing}
    target::EntityID
    amount::Float32
end

struct DeathEvent <: GameEvent
    entity::EntityID
    killer::Union{EntityID, Nothing}
    damage_type::DamageType
end
