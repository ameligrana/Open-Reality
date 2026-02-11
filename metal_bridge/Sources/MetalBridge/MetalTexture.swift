import Metal

// MARK: - Texture Creation (2D)

/// Create a 2D Metal texture and return its handle.
///
/// - Parameters:
///   - deviceHandle: Handle to a MetalDeviceWrapper (currently ignored; uses globalDevice).
///   - width: Texture width in pixels.
///   - height: Texture height in pixels.
///   - format: MetalPixelFormat raw value (UInt32).
///   - mipmapped: 0 = no mipmaps, 1 = auto-compute full mipmap chain.
///   - usage: Bitmask — bit 0 = shaderRead, bit 1 = shaderWrite, bit 2 = renderTarget.
///            If 0, defaults to shaderRead.
///   - label: Null-terminated C string used as the texture debug label.
/// - Returns: Handle (UInt64) for the new MetalTextureWrapper, or 0 on failure.
@_cdecl("metal_create_texture_2d")
public func metal_create_texture_2d(
    _ deviceHandle: UInt64,
    _ width: Int32,
    _ height: Int32,
    _ format: UInt32,
    _ mipmapped: Int32,
    _ usage: Int32,
    _ label: UnsafePointer<CChar>
) -> UInt64 {
    guard let deviceWrapper = globalDevice else {
        print("[MetalTexture] ERROR: globalDevice is nil")
        return 0
    }
    let device = deviceWrapper.device

    guard let bridgeFormat = MetalPixelFormat(rawValue: format) else {
        print("[MetalTexture] ERROR: unknown pixel format \(format)")
        return 0
    }
    let pixelFormat = toMTLPixelFormat(bridgeFormat)

    let w = Int(width)
    let h = Int(height)

    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: pixelFormat,
        width: w,
        height: h,
        mipmapped: false  // we manage mipmapLevelCount manually below
    )

    // Mipmap level count
    if mipmapped != 0 {
        let maxDim = max(w, h)
        let levels = Int(log2(Double(maxDim))) + 1
        descriptor.mipmapLevelCount = levels
    } else {
        descriptor.mipmapLevelCount = 1
    }

    // Usage flags
    var mtlUsage: MTLTextureUsage = []
    if usage == 0 {
        mtlUsage = .shaderRead
    } else {
        if (usage & 1) != 0 { mtlUsage.insert(.shaderRead) }
        if (usage & 2) != 0 { mtlUsage.insert(.shaderWrite) }
        if (usage & 4) != 0 { mtlUsage.insert(.renderTarget) }
    }
    descriptor.usage = mtlUsage

    // Storage mode: .private for render targets, .managed for uploadable textures (macOS)
    let isRenderTarget = (usage & 4) != 0
    if isRenderTarget {
        descriptor.storageMode = .private
    } else {
        #if os(macOS)
        descriptor.storageMode = .managed
        #else
        descriptor.storageMode = .shared
        #endif
    }

    guard let texture = device.makeTexture(descriptor: descriptor) else {
        print("[MetalTexture] ERROR: device.makeTexture returned nil")
        return 0
    }

    let labelString = String(cString: label)
    texture.label = labelString

    let wrapper = MetalTextureWrapper(
        texture: texture,
        width: w,
        height: h,
        pixelFormat: pixelFormat
    )

    return registry.insert(wrapper)
}

// MARK: - Texture Upload (2D)

/// Upload pixel data into a 2D texture (mip level 0).
/// If the texture has mipmaps, they are automatically generated via a blit encoder.
///
/// - Parameters:
///   - textureHandle: Handle to a MetalTextureWrapper.
///   - data: Pointer to raw pixel data (tightly packed rows).
///   - width: Width of the source data in pixels.
///   - height: Height of the source data in pixels.
///   - bytesPerPixel: Number of bytes per pixel (e.g. 4 for RGBA8, 8 for RGBA16F).
@_cdecl("metal_upload_texture_2d")
public func metal_upload_texture_2d(
    _ textureHandle: UInt64,
    _ data: UnsafeRawPointer,
    _ width: Int32,
    _ height: Int32,
    _ bytesPerPixel: Int32
) {
    guard let wrapper: MetalTextureWrapper = registry.get(textureHandle) else {
        print("[MetalTexture] ERROR: invalid texture handle \(textureHandle)")
        return
    }

    let w = Int(width)
    let h = Int(height)
    let bpp = Int(bytesPerPixel)
    let bytesPerRow = w * bpp

    let region = MTLRegionMake2D(0, 0, w, h)
    wrapper.texture.replace(
        region: region,
        mipmapLevel: 0,
        withBytes: data,
        bytesPerRow: bytesPerRow
    )

    // Generate mipmaps if the texture has more than one level
    if wrapper.texture.mipmapLevelCount > 1 {
        guard let deviceWrapper = globalDevice else {
            print("[MetalTexture] ERROR: globalDevice is nil, cannot generate mipmaps")
            return
        }
        guard let commandBuffer = deviceWrapper.commandQueue.makeCommandBuffer() else {
            print("[MetalTexture] ERROR: failed to create command buffer for mipmap generation")
            return
        }
        guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
            print("[MetalTexture] ERROR: failed to create blit encoder for mipmap generation")
            return
        }
        blitEncoder.generateMipmaps(for: wrapper.texture)
        blitEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
}

// MARK: - Texture Creation (Cube)

/// Create a cube map Metal texture and return its handle.
///
/// - Parameters:
///   - deviceHandle: Handle to a MetalDeviceWrapper (currently ignored; uses globalDevice).
///   - size: Width/height of each cube face in pixels.
///   - format: MetalPixelFormat raw value (UInt32).
///   - mipmapped: 0 = no mipmaps, 1 = auto-compute full mipmap chain.
///   - label: Null-terminated C string used as the texture debug label.
/// - Returns: Handle (UInt64) for the new MetalTextureWrapper, or 0 on failure.
@_cdecl("metal_create_texture_cube")
public func metal_create_texture_cube(
    _ deviceHandle: UInt64,
    _ size: Int32,
    _ format: UInt32,
    _ mipmapped: Int32,
    _ label: UnsafePointer<CChar>
) -> UInt64 {
    guard let deviceWrapper = globalDevice else {
        print("[MetalTexture] ERROR: globalDevice is nil")
        return 0
    }
    let device = deviceWrapper.device

    guard let bridgeFormat = MetalPixelFormat(rawValue: format) else {
        print("[MetalTexture] ERROR: unknown pixel format \(format)")
        return 0
    }
    let pixelFormat = toMTLPixelFormat(bridgeFormat)

    let s = Int(size)

    let descriptor = MTLTextureDescriptor()
    descriptor.textureType = .typeCube
    descriptor.pixelFormat = pixelFormat
    descriptor.width = s
    descriptor.height = s

    // Mipmap level count
    if mipmapped != 0 {
        let levels = Int(log2(Double(s))) + 1
        descriptor.mipmapLevelCount = levels
    } else {
        descriptor.mipmapLevelCount = 1
    }

    descriptor.usage = [.shaderRead]

    #if os(macOS)
    descriptor.storageMode = .managed
    #else
    descriptor.storageMode = .shared
    #endif

    guard let texture = device.makeTexture(descriptor: descriptor) else {
        print("[MetalTexture] ERROR: device.makeTexture returned nil for cube")
        return 0
    }

    let labelString = String(cString: label)
    texture.label = labelString

    let wrapper = MetalTextureWrapper(
        texture: texture,
        width: s,
        height: s,
        pixelFormat: pixelFormat
    )

    return registry.insert(wrapper)
}

// MARK: - Texture Upload (Cube Face)

/// Upload pixel data into a single face of a cube map texture.
///
/// - Parameters:
///   - textureHandle: Handle to a MetalTextureWrapper that wraps a cube texture.
///   - face: Cube face index (0..5: +X, -X, +Y, -Y, +Z, -Z).
///   - data: Pointer to raw pixel data for the face.
///   - size: Width/height of the face in pixels.
///   - bytesPerPixel: Number of bytes per pixel.
@_cdecl("metal_upload_texture_cube_face")
public func metal_upload_texture_cube_face(
    _ textureHandle: UInt64,
    _ face: Int32,
    _ data: UnsafeRawPointer,
    _ size: Int32,
    _ bytesPerPixel: Int32
) {
    guard let wrapper: MetalTextureWrapper = registry.get(textureHandle) else {
        print("[MetalTexture] ERROR: invalid texture handle \(textureHandle)")
        return
    }

    let s = Int(size)
    let bpp = Int(bytesPerPixel)
    let bytesPerRow = s * bpp

    let region = MTLRegionMake2D(0, 0, s, s)
    wrapper.texture.replace(
        region: region,
        mipmapLevel: 0,
        slice: Int(face),
        withBytes: data,
        bytesPerRow: bytesPerRow,
        bytesPerImage: bytesPerRow * s
    )
}

// MARK: - Texture Destruction

/// Destroy a texture by removing its wrapper from the handle registry.
/// The underlying MTLTexture is released when the wrapper is deallocated.
///
/// - Parameter handle: Handle to the MetalTextureWrapper to destroy.
@_cdecl("metal_destroy_texture")
public func metal_destroy_texture(_ handle: UInt64) {
    registry.remove(handle)
}
