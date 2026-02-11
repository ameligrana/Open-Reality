# Metal PBR light uniform packing and material texture binding

function metal_bind_material_textures!(encoder_handle::UInt64, material::MaterialComponent,
                                        texture_cache::MetalTextureCache, device_handle::UInt64)
    # Texture binding indices for fragment shader:
    # 0 = albedo, 1 = normal, 2 = metallic-roughness, 3 = AO, 4 = emissive, 5 = height

    if material.albedo_map !== nothing
        tex = metal_load_texture(texture_cache, device_handle, material.albedo_map.path)
        metal_set_fragment_texture(encoder_handle, tex.handle, Int32(0))
    end

    if material.normal_map !== nothing
        tex = metal_load_texture(texture_cache, device_handle, material.normal_map.path)
        metal_set_fragment_texture(encoder_handle, tex.handle, Int32(1))
    end

    if material.metallic_roughness_map !== nothing
        tex = metal_load_texture(texture_cache, device_handle, material.metallic_roughness_map.path)
        metal_set_fragment_texture(encoder_handle, tex.handle, Int32(2))
    end

    if material.ao_map !== nothing
        tex = metal_load_texture(texture_cache, device_handle, material.ao_map.path)
        metal_set_fragment_texture(encoder_handle, tex.handle, Int32(3))
    end

    if material.emissive_map !== nothing
        tex = metal_load_texture(texture_cache, device_handle, material.emissive_map.path)
        metal_set_fragment_texture(encoder_handle, tex.handle, Int32(4))
    end

    if material.height_map !== nothing && material.parallax_height_scale > 0.0f0
        tex = metal_load_texture(texture_cache, device_handle, material.height_map.path)
        metal_set_fragment_texture(encoder_handle, tex.handle, Int32(5))
    end

    return nothing
end
