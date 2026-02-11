# Metal texture upload and cache operations

function metal_upload_texture_to_gpu(device_handle::UInt64, pixels::Vector{UInt8},
                                      width::Int, height::Int, channels::Int)
    tex = MetalGPUTexture()
    tex.width = width
    tex.height = height
    tex.channels = channels

    # Determine format
    format = if channels == 4
        MTL_PIXEL_FORMAT_RGBA8_UNORM
    elseif channels == 3
        # Metal doesn't support RGB8; expand to RGBA8
        MTL_PIXEL_FORMAT_RGBA8_UNORM
    elseif channels == 1
        MTL_PIXEL_FORMAT_R8_UNORM
    else
        MTL_PIXEL_FORMAT_RGBA8_UNORM
    end

    # Expand RGB → RGBA if needed
    upload_pixels = if channels == 3
        rgba = Vector{UInt8}(undef, width * height * 4)
        for i in 1:(width * height)
            src = (i - 1) * 3
            dst = (i - 1) * 4
            rgba[dst + 1] = pixels[src + 1]
            rgba[dst + 2] = pixels[src + 2]
            rgba[dst + 3] = pixels[src + 3]
            rgba[dst + 4] = 0xFF  # full alpha
        end
        rgba
    else
        pixels
    end

    bpp = (format == MTL_PIXEL_FORMAT_R8_UNORM) ? Int32(1) : Int32(4)
    usage = MTL_USAGE_SHADER_READ

    tex.handle = metal_create_texture_2d(device_handle, Int32(width), Int32(height),
                                          format, Int32(1), usage, "texture")

    GC.@preserve upload_pixels begin
        metal_upload_texture_2d(tex.handle, pointer(upload_pixels), Int32(width), Int32(height), bpp)
    end

    return tex
end

function metal_load_texture(cache::MetalTextureCache, device_handle::UInt64, path::String)
    existing = get(cache.textures, path, nothing)
    if existing !== nothing
        return existing
    end

    # Load image from file
    img = FileIO.load(path)
    h, w = size(img)

    # Convert to raw bytes
    pixels = UInt8[]
    channels = 4  # default RGBA
    if eltype(img) <: ColorTypes.RGBA
        pixels = Vector{UInt8}(undef, w * h * 4)
        for row in 1:h, col in 1:w
            c = img[row, col]
            idx = ((row - 1) * w + (col - 1)) * 4
            pixels[idx + 1] = round(UInt8, clamp(Float64(c.r), 0.0, 1.0) * 255)
            pixels[idx + 2] = round(UInt8, clamp(Float64(c.g), 0.0, 1.0) * 255)
            pixels[idx + 3] = round(UInt8, clamp(Float64(c.b), 0.0, 1.0) * 255)
            pixels[idx + 4] = round(UInt8, clamp(Float64(c.alpha), 0.0, 1.0) * 255)
        end
    elseif eltype(img) <: ColorTypes.RGB
        pixels = Vector{UInt8}(undef, w * h * 4)
        channels = 4
        for row in 1:h, col in 1:w
            c = img[row, col]
            idx = ((row - 1) * w + (col - 1)) * 4
            pixels[idx + 1] = round(UInt8, clamp(Float64(c.r), 0.0, 1.0) * 255)
            pixels[idx + 2] = round(UInt8, clamp(Float64(c.g), 0.0, 1.0) * 255)
            pixels[idx + 3] = round(UInt8, clamp(Float64(c.b), 0.0, 1.0) * 255)
            pixels[idx + 4] = 0xFF
        end
    elseif eltype(img) <: ColorTypes.Gray
        channels = 1
        pixels = Vector{UInt8}(undef, w * h)
        for row in 1:h, col in 1:w
            idx = (row - 1) * w + col
            pixels[idx] = round(UInt8, clamp(Float64(img[row, col].val), 0.0, 1.0) * 255)
        end
    else
        # Fallback: try RGBA conversion
        pixels = Vector{UInt8}(undef, w * h * 4)
        for row in 1:h, col in 1:w
            c = convert(ColorTypes.RGBA{Float64}, img[row, col])
            idx = ((row - 1) * w + (col - 1)) * 4
            pixels[idx + 1] = round(UInt8, clamp(c.r, 0.0, 1.0) * 255)
            pixels[idx + 2] = round(UInt8, clamp(c.g, 0.0, 1.0) * 255)
            pixels[idx + 3] = round(UInt8, clamp(c.b, 0.0, 1.0) * 255)
            pixels[idx + 4] = round(UInt8, clamp(c.alpha, 0.0, 1.0) * 255)
        end
    end

    # Note: Metal texture origin is top-left (same as image storage), so no Y-flip needed
    tex = metal_upload_texture_to_gpu(device_handle, pixels, w, h, channels)
    cache.textures[path] = tex
    return tex
end

function metal_destroy_texture!(tex::MetalGPUTexture)
    if tex.handle != UInt64(0)
        metal_destroy_texture(tex.handle)
        tex.handle = UInt64(0)
    end
    return nothing
end

function metal_destroy_all_textures!(cache::MetalTextureCache)
    for (_, tex) in cache.textures
        metal_destroy_texture!(tex)
    end
    empty!(cache.textures)
    return nothing
end
