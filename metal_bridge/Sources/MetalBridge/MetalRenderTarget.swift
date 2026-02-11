import Metal

// MARK: - Create Render Target

/// Create a Metal render target (the equivalent of an OpenGL framebuffer).
///
/// Allocates one or more color textures and an optional depth texture at the
/// requested dimensions, wraps them in a `MetalRenderTargetWrapper`, and
/// stores the wrapper in the global handle registry.
///
/// - Parameters:
///   - deviceHandle: Unused directly; the function reads `globalDevice` instead.
///   - width: Texture width in pixels.
///   - height: Texture height in pixels.
///   - numColorAttachments: Number of color textures to create.
///   - colorFormats: Pointer to an array of `UInt32` bridge pixel format values.
///   - hasDepth: Non-zero to create a depth attachment.
///   - depthFormat: Bridge pixel format value for the depth texture.
///   - label: A null-terminated C string used as a debug label.
/// - Returns: A handle to the new `MetalRenderTargetWrapper`.
@_cdecl("metal_create_render_target")
public func metal_create_render_target(
    _ deviceHandle: UInt64,
    _ width: Int32,
    _ height: Int32,
    _ numColorAttachments: Int32,
    _ colorFormats: UnsafePointer<UInt32>,
    _ hasDepth: Int32,
    _ depthFormat: UInt32,
    _ label: UnsafePointer<CChar>
) -> UInt64 {
    guard let wrapper = globalDevice else {
        fatalError("metal_create_render_target: No global Metal device available.")
    }
    let device = wrapper.device
    let labelStr = String(cString: label)

    // --- Color attachments ---
    var colorTextures: [MTLTexture] = []
    for i in 0..<Int(numColorAttachments) {
        guard let bridgeFormat = MetalPixelFormat(rawValue: colorFormats[i]) else {
            fatalError("metal_create_render_target: Unknown color pixel format \(colorFormats[i]) at index \(i).")
        }
        let mtlFormat = toMTLPixelFormat(bridgeFormat)

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: mtlFormat,
            width: Int(width),
            height: Int(height),
            mipmapped: false
        )
        desc.usage = [.shaderRead, .renderTarget]
        desc.storageMode = .private

        guard let texture = device.makeTexture(descriptor: desc) else {
            fatalError("metal_create_render_target: Failed to create color texture \(i).")
        }
        texture.label = "\(labelStr)_color\(i)"
        colorTextures.append(texture)
    }

    // --- Depth attachment ---
    var depthTexture: MTLTexture? = nil
    if hasDepth != 0 {
        guard let bridgeFormat = MetalPixelFormat(rawValue: depthFormat) else {
            fatalError("metal_create_render_target: Unknown depth pixel format \(depthFormat).")
        }
        let mtlFormat = toMTLPixelFormat(bridgeFormat)

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: mtlFormat,
            width: Int(width),
            height: Int(height),
            mipmapped: false
        )
        desc.usage = [.shaderRead, .renderTarget]
        desc.storageMode = .private

        guard let texture = device.makeTexture(descriptor: desc) else {
            fatalError("metal_create_render_target: Failed to create depth texture.")
        }
        texture.label = "\(labelStr)_depth"
        depthTexture = texture
    }

    let rt = MetalRenderTargetWrapper(
        colorTextures: colorTextures,
        depthTexture: depthTexture,
        width: Int(width),
        height: Int(height),
        label: labelStr
    )
    return registry.insert(rt)
}

// MARK: - Accessors

/// Retrieve a color texture from a render target by index.
///
/// The returned texture is wrapped in a new `MetalTextureWrapper` and inserted
/// into the registry so Julia can reference it independently.
///
/// - Parameters:
///   - rtHandle: Handle to a `MetalRenderTargetWrapper`.
///   - index: Zero-based color attachment index.
/// - Returns: A handle to the `MetalTextureWrapper`, or 0 if the index is out of bounds.
@_cdecl("metal_get_rt_color_texture")
public func metal_get_rt_color_texture(_ rtHandle: UInt64, _ index: Int32) -> UInt64 {
    guard let rt: MetalRenderTargetWrapper = registry.get(rtHandle) else {
        return 0
    }

    let idx = Int(index)
    guard idx >= 0 && idx < rt.colorTextures.count else {
        return 0
    }

    let tex = rt.colorTextures[idx]
    let texWrapper = MetalTextureWrapper(
        texture: tex,
        width: tex.width,
        height: tex.height,
        pixelFormat: tex.pixelFormat
    )
    return registry.insert(texWrapper)
}

/// Retrieve the depth texture from a render target.
///
/// - Parameter rtHandle: Handle to a `MetalRenderTargetWrapper`.
/// - Returns: A handle to the `MetalTextureWrapper`, or 0 if no depth texture exists.
@_cdecl("metal_get_rt_depth_texture")
public func metal_get_rt_depth_texture(_ rtHandle: UInt64) -> UInt64 {
    guard let rt: MetalRenderTargetWrapper = registry.get(rtHandle) else {
        return 0
    }

    guard let depthTex = rt.depthTexture else {
        return 0
    }

    let texWrapper = MetalTextureWrapper(
        texture: depthTex,
        width: depthTex.width,
        height: depthTex.height,
        pixelFormat: depthTex.pixelFormat
    )
    return registry.insert(texWrapper)
}

// MARK: - Resize

/// Recreate all textures in a render target at a new resolution.
///
/// The pixel formats of the existing color and depth textures are preserved;
/// only the dimensions change.
///
/// - Parameters:
///   - rtHandle: Handle to a `MetalRenderTargetWrapper`.
///   - width: New width in pixels.
///   - height: New height in pixels.
@_cdecl("metal_resize_render_target")
public func metal_resize_render_target(_ rtHandle: UInt64, _ width: Int32, _ height: Int32) {
    guard let rt: MetalRenderTargetWrapper = registry.get(rtHandle) else {
        return
    }
    guard let wrapper = globalDevice else {
        return
    }
    let device = wrapper.device
    let w = Int(width)
    let h = Int(height)

    // Recreate color textures with the same formats.
    var newColorTextures: [MTLTexture] = []
    for (i, oldTex) in rt.colorTextures.enumerated() {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: oldTex.pixelFormat,
            width: w,
            height: h,
            mipmapped: false
        )
        desc.usage = [.shaderRead, .renderTarget]
        desc.storageMode = .private

        guard let newTex = device.makeTexture(descriptor: desc) else {
            fatalError("metal_resize_render_target: Failed to recreate color texture \(i).")
        }
        newTex.label = "\(rt.label)_color\(i)"
        newColorTextures.append(newTex)
    }
    rt.colorTextures = newColorTextures

    // Recreate depth texture if one exists.
    if let oldDepth = rt.depthTexture {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: oldDepth.pixelFormat,
            width: w,
            height: h,
            mipmapped: false
        )
        desc.usage = [.shaderRead, .renderTarget]
        desc.storageMode = .private

        guard let newDepth = device.makeTexture(descriptor: desc) else {
            fatalError("metal_resize_render_target: Failed to recreate depth texture.")
        }
        newDepth.label = "\(rt.label)_depth"
        rt.depthTexture = newDepth
    }

    rt.width = w
    rt.height = h
}

// MARK: - Destroy

/// Remove a render target from the registry, releasing its textures.
///
/// - Parameter handle: Handle to a `MetalRenderTargetWrapper`.
@_cdecl("metal_destroy_render_target")
public func metal_destroy_render_target(_ handle: UInt64) {
    registry.remove(handle)
}
