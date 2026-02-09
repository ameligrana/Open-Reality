# Light components

"""
    PointLightComponent <: Component

A point light that emits light in all directions.
"""
struct PointLightComponent <: Component
    color::RGB{Float32}
    intensity::Float32
    range::Float32

    PointLightComponent(;
        color::RGB{Float32} = RGB{Float32}(1.0, 1.0, 1.0),
        intensity::Float32 = 1.0f0,
        range::Float32 = 10.0f0
    ) = new(color, intensity, range)
end

"""
    DirectionalLightComponent <: Component

A directional light (like the sun).
"""
struct DirectionalLightComponent <: Component
    color::RGB{Float32}
    intensity::Float32
    direction::Vec3f

    DirectionalLightComponent(;
        color::RGB{Float32} = RGB{Float32}(1.0, 1.0, 1.0),
        intensity::Float32 = 1.0f0,
        direction::Vec3f = Vec3f(0, -1, 0)
    ) = new(color, intensity, direction)
end

"""
    IBLComponent <: Component

Image-Based Lighting component.
Provides environmental lighting and reflections from an HDR environment map.
Only one IBL component should be active in a scene at a time.
"""
struct IBLComponent <: Component
    environment_path::String  # Path to HDR environment map
    intensity::Float32        # Global intensity multiplier
    enabled::Bool            # Toggle IBL on/off

    IBLComponent(;
        environment_path::String = "",
        intensity::Float32 = 1.0f0,
        enabled::Bool = true
    ) = new(environment_path, intensity, enabled)
end
