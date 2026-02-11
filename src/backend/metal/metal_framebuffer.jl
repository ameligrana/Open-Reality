# Metal framebuffer (render target) and G-Buffer creation

function metal_create_render_target!(rt::MetalRenderTarget, device_handle::UInt64,
                                      width::Int, height::Int;
                                      color_format::UInt32 = MTL_PIXEL_FORMAT_RGBA16_FLOAT)
    color_formats = UInt32[color_format]
    rt.handle = metal_create_render_target(device_handle, Int32(width), Int32(height),
                                            Int32(1), color_formats,
                                            Int32(1), MTL_PIXEL_FORMAT_DEPTH32_FLOAT,
                                            "RenderTarget")
    rt.color_texture_handles = [metal_get_rt_color_texture(rt.handle, Int32(0))]
    rt.depth_texture_handle = metal_get_rt_depth_texture(rt.handle)
    rt.width = width
    rt.height = height
    return rt
end

function metal_create_gbuffer!(gb::MetalGBuffer, device_handle::UInt64, width::Int, height::Int)
    color_formats = UInt32[
        MTL_PIXEL_FORMAT_RGBA16_FLOAT,   # 0: albedo.rgb + metallic
        MTL_PIXEL_FORMAT_RGBA16_FLOAT,   # 1: normal.rgb + roughness
        MTL_PIXEL_FORMAT_RGBA16_FLOAT,   # 2: emissive.rgb + ao
        MTL_PIXEL_FORMAT_RGBA8_UNORM     # 3: clearcoat, clearcoat_roughness, subsurface, reserved
    ]

    gb.rt_handle = metal_create_render_target(device_handle, Int32(width), Int32(height),
                                               Int32(4), color_formats,
                                               Int32(1), MTL_PIXEL_FORMAT_DEPTH32_FLOAT,
                                               "GBuffer")
    gb.albedo_metallic = metal_get_rt_color_texture(gb.rt_handle, Int32(0))
    gb.normal_roughness = metal_get_rt_color_texture(gb.rt_handle, Int32(1))
    gb.emissive_ao = metal_get_rt_color_texture(gb.rt_handle, Int32(2))
    gb.advanced_material = metal_get_rt_color_texture(gb.rt_handle, Int32(3))
    gb.depth = metal_get_rt_depth_texture(gb.rt_handle)
    gb.width = width
    gb.height = height
    return gb
end

function metal_destroy_render_target!(rt::MetalRenderTarget)
    if rt.handle != UInt64(0)
        metal_destroy_render_target(rt.handle)
        rt.handle = UInt64(0)
        empty!(rt.color_texture_handles)
        rt.depth_texture_handle = UInt64(0)
    end
    return nothing
end

function metal_destroy_gbuffer!(gb::MetalGBuffer)
    if gb.rt_handle != UInt64(0)
        metal_destroy_render_target(gb.rt_handle)
        gb.rt_handle = UInt64(0)
        gb.albedo_metallic = UInt64(0)
        gb.normal_roughness = UInt64(0)
        gb.emissive_ao = UInt64(0)
        gb.advanced_material = UInt64(0)
        gb.depth = UInt64(0)
    end
    return nothing
end

function metal_resize_gbuffer!(gb::MetalGBuffer, device_handle::UInt64, width::Int, height::Int)
    metal_destroy_gbuffer!(gb)
    metal_create_gbuffer!(gb, device_handle, width, height)
    return nothing
end

function metal_resize_render_target_!(rt::MetalRenderTarget, width::Int, height::Int)
    if rt.handle != UInt64(0)
        metal_resize_render_target(rt.handle, Int32(width), Int32(height))
        rt.width = width
        rt.height = height
        # Re-fetch texture handles after resize
        if !isempty(rt.color_texture_handles)
            for i in eachindex(rt.color_texture_handles)
                rt.color_texture_handles[i] = metal_get_rt_color_texture(rt.handle, Int32(i - 1))
            end
        end
        rt.depth_texture_handle = metal_get_rt_depth_texture(rt.handle)
    end
    return nothing
end
