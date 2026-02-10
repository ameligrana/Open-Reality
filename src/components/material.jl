# Material component

using ColorTypes

"""
    TextureRef

Reference to a texture by file path. The rendering system resolves
these to GPU textures at render time via the TextureCache.
"""
struct TextureRef
    path::String
end

"""
    MaterialComponent <: Component

PBR material with optional texture maps and advanced material features.
When a texture is set, it overrides the corresponding uniform value.

Advanced features:
- Clear coat: Secondary specular lobe for lacquered/coated surfaces (car paint, varnish)
- Parallax occlusion mapping: Height-based UV displacement for surface depth illusion
- Subsurface scattering: Light transmission through thin translucent surfaces (skin, wax, leaves)
"""
struct MaterialComponent <: Component
    color::RGB{Float32}
    metallic::Float32
    roughness::Float32
    albedo_map::Union{TextureRef, Nothing}
    normal_map::Union{TextureRef, Nothing}
    metallic_roughness_map::Union{TextureRef, Nothing}
    ao_map::Union{TextureRef, Nothing}
    emissive_map::Union{TextureRef, Nothing}
    emissive_factor::Vec3f
    opacity::Float32
    alpha_cutoff::Float32
    # Clear coat
    clearcoat::Float32
    clearcoat_roughness::Float32
    clearcoat_map::Union{TextureRef, Nothing}
    # Parallax occlusion mapping
    height_map::Union{TextureRef, Nothing}
    parallax_height_scale::Float32
    # Subsurface scattering
    subsurface::Float32
    subsurface_color::Vec3f

    MaterialComponent(;
        color::RGB{Float32} = RGB{Float32}(1.0, 1.0, 1.0),
        metallic::Float32 = 0.0f0,
        roughness::Float32 = 0.5f0,
        albedo_map::Union{TextureRef, Nothing} = nothing,
        normal_map::Union{TextureRef, Nothing} = nothing,
        metallic_roughness_map::Union{TextureRef, Nothing} = nothing,
        ao_map::Union{TextureRef, Nothing} = nothing,
        emissive_map::Union{TextureRef, Nothing} = nothing,
        emissive_factor::Vec3f = Vec3f(0, 0, 0),
        opacity::Float32 = 1.0f0,
        alpha_cutoff::Float32 = 0.0f0,
        clearcoat::Float32 = 0.0f0,
        clearcoat_roughness::Float32 = 0.0f0,
        clearcoat_map::Union{TextureRef, Nothing} = nothing,
        height_map::Union{TextureRef, Nothing} = nothing,
        parallax_height_scale::Float32 = 0.0f0,
        subsurface::Float32 = 0.0f0,
        subsurface_color::Vec3f = Vec3f(1.0f0, 1.0f0, 1.0f0)
    ) = new(color, metallic, roughness, albedo_map, normal_map,
            metallic_roughness_map, ao_map, emissive_map, emissive_factor,
            opacity, alpha_cutoff,
            clearcoat, clearcoat_roughness, clearcoat_map,
            height_map, parallax_height_scale,
            subsurface, subsurface_color)
end
