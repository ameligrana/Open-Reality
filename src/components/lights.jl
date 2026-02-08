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
