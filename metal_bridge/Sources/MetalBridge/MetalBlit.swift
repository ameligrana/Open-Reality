import Metal

// MARK: - Blit (Copy) Texture

/// Copy the full contents of one texture to another using a blit command encoder.
///
/// - Parameters:
///   - cmdBufHandle: Handle to the MetalCommandBufferWrapper.
///   - srcTextureHandle: Handle to the source MetalTextureWrapper.
///   - dstTextureHandle: Handle to the destination MetalTextureWrapper.
@_cdecl("metal_blit_texture")
public func metal_blit_texture(_ cmdBufHandle: UInt64, _ srcTextureHandle: UInt64, _ dstTextureHandle: UInt64) {
    guard let cmdBufWrapper: MetalCommandBufferWrapper = registry.get(cmdBufHandle) else {
        print("[MetalBlit] ERROR: Invalid command buffer handle \(cmdBufHandle)")
        return
    }

    guard let srcWrapper: MetalTextureWrapper = registry.get(srcTextureHandle) else {
        print("[MetalBlit] ERROR: Invalid source texture handle \(srcTextureHandle)")
        return
    }

    guard let dstWrapper: MetalTextureWrapper = registry.get(dstTextureHandle) else {
        print("[MetalBlit] ERROR: Invalid destination texture handle \(dstTextureHandle)")
        return
    }

    guard let blitEncoder = cmdBufWrapper.commandBuffer.makeBlitCommandEncoder() else {
        print("[MetalBlit] ERROR: Failed to create blit command encoder")
        return
    }

    let srcTexture = srcWrapper.texture
    let dstTexture = dstWrapper.texture

    let origin = MTLOrigin(x: 0, y: 0, z: 0)
    let size = MTLSize(width: srcTexture.width, height: srcTexture.height, depth: srcTexture.depth)

    blitEncoder.copy(
        from: srcTexture,
        sourceSlice: 0,
        sourceLevel: 0,
        sourceOrigin: origin,
        sourceSize: size,
        to: dstTexture,
        destinationSlice: 0,
        destinationLevel: 0,
        destinationOrigin: origin
    )

    blitEncoder.endEncoding()
}

// MARK: - Generate Mipmaps

/// Generate mipmaps for a texture using a blit command encoder.
///
/// - Parameters:
///   - cmdBufHandle: Handle to the MetalCommandBufferWrapper.
///   - textureHandle: Handle to the MetalTextureWrapper whose mipmaps should be generated.
@_cdecl("metal_generate_mipmaps")
public func metal_generate_mipmaps(_ cmdBufHandle: UInt64, _ textureHandle: UInt64) {
    guard let cmdBufWrapper: MetalCommandBufferWrapper = registry.get(cmdBufHandle) else {
        print("[MetalBlit] ERROR: Invalid command buffer handle \(cmdBufHandle)")
        return
    }

    guard let texWrapper: MetalTextureWrapper = registry.get(textureHandle) else {
        print("[MetalBlit] ERROR: Invalid texture handle \(textureHandle)")
        return
    }

    guard let blitEncoder = cmdBufWrapper.commandBuffer.makeBlitCommandEncoder() else {
        print("[MetalBlit] ERROR: Failed to create blit command encoder")
        return
    }

    blitEncoder.generateMipmaps(for: texWrapper.texture)
    blitEncoder.endEncoding()
}

// MARK: - Copy Texture to Buffer

/// Copy texture data into a Metal buffer using a blit command encoder.
///
/// - Parameters:
///   - cmdBufHandle: Handle to the MetalCommandBufferWrapper.
///   - textureHandle: Handle to the source MetalTextureWrapper.
///   - bufferHandle: Handle to the destination MetalBufferWrapper.
///   - bytesPerRow: Number of bytes per row in the destination buffer.
///   - bytesPerImage: Number of bytes per image slice in the destination buffer.
@_cdecl("metal_copy_texture_to_buffer")
public func metal_copy_texture_to_buffer(_ cmdBufHandle: UInt64, _ textureHandle: UInt64, _ bufferHandle: UInt64, _ bytesPerRow: Int, _ bytesPerImage: Int) {
    guard let cmdBufWrapper: MetalCommandBufferWrapper = registry.get(cmdBufHandle) else {
        print("[MetalBlit] ERROR: Invalid command buffer handle \(cmdBufHandle)")
        return
    }

    guard let texWrapper: MetalTextureWrapper = registry.get(textureHandle) else {
        print("[MetalBlit] ERROR: Invalid texture handle \(textureHandle)")
        return
    }

    guard let bufWrapper: MetalBufferWrapper = registry.get(bufferHandle) else {
        print("[MetalBlit] ERROR: Invalid buffer handle \(bufferHandle)")
        return
    }

    guard let blitEncoder = cmdBufWrapper.commandBuffer.makeBlitCommandEncoder() else {
        print("[MetalBlit] ERROR: Failed to create blit command encoder")
        return
    }

    let texture = texWrapper.texture
    let sourceOrigin = MTLOrigin(x: 0, y: 0, z: 0)
    let sourceSize = MTLSize(width: texture.width, height: texture.height, depth: texture.depth)

    blitEncoder.copy(
        from: texture,
        sourceSlice: 0,
        sourceLevel: 0,
        sourceOrigin: sourceOrigin,
        sourceSize: sourceSize,
        to: bufWrapper.buffer,
        destinationOffset: 0,
        destinationBytesPerRow: bytesPerRow,
        destinationBytesPerImage: bytesPerImage
    )

    blitEncoder.endEncoding()
}

// MARK: - Synchronize Texture

/// Synchronize a managed texture so the CPU can read its contents (macOS only).
///
/// - Parameters:
///   - cmdBufHandle: Handle to the MetalCommandBufferWrapper.
///   - textureHandle: Handle to the MetalTextureWrapper to synchronize.
@_cdecl("metal_synchronize_texture")
public func metal_synchronize_texture(_ cmdBufHandle: UInt64, _ textureHandle: UInt64) {
    guard let cmdBufWrapper: MetalCommandBufferWrapper = registry.get(cmdBufHandle) else {
        print("[MetalBlit] ERROR: Invalid command buffer handle \(cmdBufHandle)")
        return
    }

    guard let texWrapper: MetalTextureWrapper = registry.get(textureHandle) else {
        print("[MetalBlit] ERROR: Invalid texture handle \(textureHandle)")
        return
    }

    guard let blitEncoder = cmdBufWrapper.commandBuffer.makeBlitCommandEncoder() else {
        print("[MetalBlit] ERROR: Failed to create blit command encoder")
        return
    }

    blitEncoder.synchronize(resource: texWrapper.texture)
    blitEncoder.endEncoding()
}
