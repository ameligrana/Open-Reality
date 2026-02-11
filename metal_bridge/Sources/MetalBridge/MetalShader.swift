import Metal

// MARK: - Render Pipeline

/// Create a Metal render pipeline state from MSL source code.
///
/// Julia calls this via ccall. The pipeline is stored in the global registry and a
/// handle is returned. Returns 0 on any failure (compilation error, missing functions, etc.).
@_cdecl("metal_create_render_pipeline")
public func metal_create_render_pipeline(
    _ mslSource: UnsafePointer<CChar>,
    _ vertexFunc: UnsafePointer<CChar>,
    _ fragmentFunc: UnsafePointer<CChar>,
    _ numColorAttachments: Int32,
    _ colorFormats: UnsafePointer<UInt32>,
    _ depthFormat: UInt32,
    _ blendEnabled: Int32
) -> UInt64 {
    let vertexName_ = String(cString: vertexFunc)
    let fragmentName_ = String(cString: fragmentFunc)
    print("[MetalShader] Creating pipeline: vert=\(vertexName_) frag=\(fragmentName_) colors=\(numColorAttachments) depthFmt=\(depthFormat) blend=\(blendEnabled)")

    guard let deviceWrapper = globalDevice else {
        print("[MetalShader] ERROR: globalDevice is nil — call metal_init first")
        return 0
    }
    let device = deviceWrapper.device

    // Compile the MSL source into a Metal library.
    let source = String(cString: mslSource)
    let library: MTLLibrary
    do {
        library = try device.makeLibrary(source: source, options: nil)
    } catch {
        print("[MetalShader] ERROR: Failed to compile MSL library: \(error)")
        return 0
    }

    // Look up vertex and fragment functions by name.
    let vertexName = String(cString: vertexFunc)
    let fragmentName = String(cString: fragmentFunc)

    guard let vertexFunction = library.makeFunction(name: vertexName) else {
        print("[MetalShader] ERROR: Vertex function '\(vertexName)' not found in library")
        return 0
    }
    guard let fragmentFunction = library.makeFunction(name: fragmentName) else {
        print("[MetalShader] ERROR: Fragment function '\(fragmentName)' not found in library")
        return 0
    }

    // Build the render pipeline descriptor.
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = vertexFunction
    descriptor.fragmentFunction = fragmentFunction

    // Configure color attachments.
    let count = Int(numColorAttachments)
    for i in 0..<count {
        let rawFormat = colorFormats[i]
        guard let bridgeFormat = MetalPixelFormat(rawValue: rawFormat) else {
            print("[MetalShader] ERROR: Unknown pixel format \(rawFormat) for color attachment \(i)")
            return 0
        }
        let mtlFormat = toMTLPixelFormat(bridgeFormat)
        descriptor.colorAttachments[i].pixelFormat = mtlFormat

        if blendEnabled != 0 {
            descriptor.colorAttachments[i].isBlendingEnabled = true

            // RGB: srcAlpha * src + oneMinusSrcAlpha * dst
            descriptor.colorAttachments[i].sourceRGBBlendFactor = .sourceAlpha
            descriptor.colorAttachments[i].destinationRGBBlendFactor = .oneMinusSourceAlpha

            // Alpha: one * srcA + oneMinusSrcAlpha * dstA
            descriptor.colorAttachments[i].sourceAlphaBlendFactor = .one
            descriptor.colorAttachments[i].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }
    }

    // Configure depth attachment (only if a depth-renderable format is specified).
    if let depthBridgeFormat = MetalPixelFormat(rawValue: depthFormat),
       depthBridgeFormat == .depth32Float {
        descriptor.depthAttachmentPixelFormat = toMTLPixelFormat(depthBridgeFormat)
    }

    // Create the pipeline state object.
    let pipelineState: MTLRenderPipelineState
    do {
        pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
    } catch {
        print("[MetalShader] ERROR: Failed to create render pipeline state: \(error)")
        return 0
    }

    let wrapper = MetalRenderPipelineWrapper(pipelineState: pipelineState, descriptor: descriptor)
    return registry.insert(wrapper)
}

// MARK: - Destroy Render Pipeline

/// Destroy a previously created render pipeline, releasing the Metal resources.
@_cdecl("metal_destroy_render_pipeline")
public func metal_destroy_render_pipeline(_ handle: UInt64) {
    registry.remove(handle)
}

// MARK: - Depth / Stencil State

/// Create a Metal depth/stencil state.
///
/// - Parameters:
///   - deviceHandle: Handle to a MetalDeviceWrapper in the registry.
///   - depthCompare: Compare function as a MetalCompareFunction raw value.
///   - depthWrite: Non-zero to enable depth writes.
/// - Returns: Handle to the new depth/stencil state, or 0 on failure.
@_cdecl("metal_create_depth_stencil_state")
public func metal_create_depth_stencil_state(
    _ deviceHandle: UInt64,
    _ depthCompare: UInt32,
    _ depthWrite: Int32
) -> UInt64 {
    guard let deviceWrapper: MetalDeviceWrapper = registry.get(deviceHandle) else {
        print("[MetalShader] ERROR: Invalid device handle \(deviceHandle)")
        return 0
    }
    let device = deviceWrapper.device

    let descriptor = MTLDepthStencilDescriptor()

    if let compareFn = MetalCompareFunction(rawValue: depthCompare) {
        descriptor.depthCompareFunction = toMTLCompareFunction(compareFn)
    } else {
        print("[MetalShader] WARNING: Unknown compare function \(depthCompare), defaulting to .less")
        descriptor.depthCompareFunction = .less
    }

    descriptor.isDepthWriteEnabled = (depthWrite != 0)

    guard let state = device.makeDepthStencilState(descriptor: descriptor) else {
        print("[MetalShader] ERROR: Failed to create depth/stencil state")
        return 0
    }

    let wrapper = MetalDepthStencilWrapper(state: state)
    return registry.insert(wrapper)
}

// MARK: - Sampler State

/// Create a Metal sampler state.
///
/// Filter / address mode encoding (from Julia):
///   - minFilter / magFilter: 0 = nearest, 1 = linear
///   - mipFilter: 0 = notMipmapped, 1 = nearest, 2 = linear
///   - addressMode: 0 = clampToEdge, 1 = repeat, 2 = mirrorRepeat, 3 = clampToBorderColor
///
/// - Returns: Handle to the new sampler state, or 0 on failure.
@_cdecl("metal_create_sampler")
public func metal_create_sampler(
    _ deviceHandle: UInt64,
    _ minFilter: Int32,
    _ magFilter: Int32,
    _ mipFilter: Int32,
    _ addressMode: Int32
) -> UInt64 {
    guard let deviceWrapper: MetalDeviceWrapper = registry.get(deviceHandle) else {
        print("[MetalShader] ERROR: Invalid device handle \(deviceHandle)")
        return 0
    }
    let device = deviceWrapper.device

    let descriptor = MTLSamplerDescriptor()

    // Min filter
    switch minFilter {
    case 1:  descriptor.minFilter = .linear
    default: descriptor.minFilter = .nearest
    }

    // Mag filter
    switch magFilter {
    case 1:  descriptor.magFilter = .linear
    default: descriptor.magFilter = .nearest
    }

    // Mip filter
    switch mipFilter {
    case 1:  descriptor.mipFilter = .nearest
    case 2:  descriptor.mipFilter = .linear
    default: descriptor.mipFilter = .notMipmapped
    }

    // Address mode (applied to all three axes)
    let mode: MTLSamplerAddressMode
    switch addressMode {
    case 1:  mode = .repeat
    case 2:  mode = .mirrorRepeat
    case 3:  mode = .clampToBorderColor
    default: mode = .clampToEdge
    }
    descriptor.sAddressMode = mode
    descriptor.tAddressMode = mode
    descriptor.rAddressMode = mode

    guard let state = device.makeSamplerState(descriptor: descriptor) else {
        print("[MetalShader] ERROR: Failed to create sampler state")
        return 0
    }

    let wrapper = MetalSamplerWrapper(state: state)
    return registry.insert(wrapper)
}
