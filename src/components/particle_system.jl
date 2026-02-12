# Particle system component

"""
    ParticleSystemComponent <: Component

Configures a particle emitter. Attach to an entity with a TransformComponent
to emit particles from that entity's world position.
"""
mutable struct ParticleSystemComponent <: Component
    # Emission
    max_particles::Int
    emission_rate::Float32          # particles/sec (0 = burst only)
    burst_count::Int                # one-shot burst count (set >0, consumed on first frame)

    # Lifetime
    lifetime_min::Float32
    lifetime_max::Float32

    # Velocity (randomized per-component in this range, local space)
    velocity_min::Vec3f
    velocity_max::Vec3f

    # Physics
    gravity_modifier::Float32       # multiplier on (0, -9.81, 0)
    damping::Float32                # velocity *= (1 - damping * dt)

    # Size over lifetime
    start_size_min::Float32
    start_size_max::Float32
    end_size::Float32

    # Color over lifetime
    start_color::RGB{Float32}
    end_color::RGB{Float32}
    start_alpha::Float32
    end_alpha::Float32

    # Blending
    additive::Bool                  # additive vs alpha blend

    # Internal state
    _emit_accumulator::Float32
    _active::Bool

    function ParticleSystemComponent(;
        max_particles::Int = 256,
        emission_rate::Float32 = 20.0f0,
        burst_count::Int = 0,
        lifetime_min::Float32 = 1.0f0,
        lifetime_max::Float32 = 2.0f0,
        velocity_min::Vec3f = Vec3f(-0.5f0, 1.0f0, -0.5f0),
        velocity_max::Vec3f = Vec3f(0.5f0, 3.0f0, 0.5f0),
        gravity_modifier::Float32 = 1.0f0,
        damping::Float32 = 0.0f0,
        start_size_min::Float32 = 0.1f0,
        start_size_max::Float32 = 0.3f0,
        end_size::Float32 = 0.0f0,
        start_color::RGB{Float32} = RGB{Float32}(1.0f0, 1.0f0, 1.0f0),
        end_color::RGB{Float32} = RGB{Float32}(1.0f0, 1.0f0, 1.0f0),
        start_alpha::Float32 = 1.0f0,
        end_alpha::Float32 = 0.0f0,
        additive::Bool = false,
        _emit_accumulator::Float32 = 0.0f0,
        _active::Bool = true
    )
        new(max_particles, emission_rate, burst_count,
            lifetime_min, lifetime_max,
            velocity_min, velocity_max,
            gravity_modifier, damping,
            start_size_min, start_size_max, end_size,
            start_color, end_color, start_alpha, end_alpha,
            additive,
            _emit_accumulator, _active)
    end
end
