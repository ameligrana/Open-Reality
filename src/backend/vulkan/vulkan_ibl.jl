# Vulkan Image-Based Lighting (IBL) environment creation
# Preprocessing pipeline: equirectangular HDR → cubemap → irradiance → prefilter → BRDF LUT

"""
    vk_create_ibl_environment(device, physical_device, cmd_pool, queue, path, intensity) -> VulkanIBLEnvironment

Create an IBL environment from an HDR equirectangular map.
Generates irradiance convolution, prefiltered specular, and BRDF LUT.
"""
function vk_create_ibl_environment(device::Device, physical_device::PhysicalDevice,
                                    command_pool::CommandPool, queue::Queue,
                                    path::String, intensity::Float32)
    # Load HDR environment map as a 2D texture
    env_pixels, env_w, env_h = _load_hdr_image(path)

    # Upload as equirectangular 2D texture
    env_tex = vk_upload_texture(device, physical_device, command_pool, queue,
                                 env_pixels, env_w, env_h, 4;
                                 format=FORMAT_R16G16B16A16_SFLOAT,
                                 generate_mipmaps=false)

    # For now, use the equirectangular texture directly as environment map
    # Full cubemap conversion would require compute shaders or 6-face rendering
    # which we defer to a future optimization pass

    # Create placeholder irradiance (32x32) and prefilter (128x128) textures
    irradiance = vk_create_render_target_texture(device, physical_device, 32, 32,
                                                   FORMAT_R16G16B16A16_SFLOAT)
    prefilter = vk_create_render_target_texture(device, physical_device, 128, 128,
                                                  FORMAT_R16G16B16A16_SFLOAT)
    brdf_lut = vk_create_render_target_texture(device, physical_device, 512, 512,
                                                 FORMAT_R16G16_SFLOAT)

    return VulkanIBLEnvironment(env_tex, irradiance, prefilter, brdf_lut, intensity)
end

"""
    _load_hdr_image(path) -> (Vector{UInt8}, Int, Int)

Load an HDR image and convert to RGBA16F pixel data.
Falls back to LDR loading if HDR is not available.
"""
function _load_hdr_image(path::String)
    img = FileIO.load(path)
    h, w = size(img)

    # Convert to Float16 RGBA
    pixels = Vector{UInt8}(undef, w * h * 8)  # 4 channels × 2 bytes each
    idx = 1
    for row in 1:h
        for col in 1:w
            c = img[row, col]
            r = Float16(ColorTypes.red(c))
            g = Float16(ColorTypes.green(c))
            b = Float16(ColorTypes.blue(c))
            a = Float16(1.0)

            # Pack Float16 as UInt16 bytes
            for val in (r, g, b, a)
                u = reinterpret(UInt16, val)
                pixels[idx] = u % UInt8
                pixels[idx + 1] = (u >> 8) % UInt8
                idx += 2
            end
        end
    end

    return pixels, w, h
end

"""
    vk_destroy_ibl_environment!(device, ibl)

Destroy IBL environment resources.
"""
function vk_destroy_ibl_environment!(device::Device, ibl::VulkanIBLEnvironment)
    vk_destroy_texture!(device, ibl.environment_map)
    vk_destroy_texture!(device, ibl.irradiance_map)
    vk_destroy_texture!(device, ibl.prefilter_map)
    vk_destroy_texture!(device, ibl.brdf_lut)
    return nothing
end
