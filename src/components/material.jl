# Material component

using ColorTypes

"""
    MaterialComponent <: Component

Represents material properties for rendering.
"""
struct MaterialComponent <: Component
    color::RGB{Float32}
    metallic::Float32
    roughness::Float32

    MaterialComponent(;
        color::RGB{Float32} = RGB{Float32}(1.0, 1.0, 1.0),
        metallic::Float32 = 0.0f0,
        roughness::Float32 = 0.5f0
    ) = new(color, metallic, roughness)
end
