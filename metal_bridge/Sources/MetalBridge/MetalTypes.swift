import Metal
import MetalKit
import QuartzCore

// MARK: - Handle Registry

/// Thread-safe registry that maps UInt64 handles to AnyObject references.
/// Julia calls @_cdecl bridge functions that use these handles to refer to Metal objects.
final class HandleRegistry {
    private var storage: [UInt64: AnyObject] = [:]
    private var nextHandle: UInt64 = 1
    private let queue = DispatchQueue(label: "com.openreality.metal.handleregistry")

    /// Insert an object into the registry and return its handle.
    func insert(_ obj: AnyObject) -> UInt64 {
        return queue.sync {
            let handle = nextHandle
            nextHandle += 1
            storage[handle] = obj
            return handle
        }
    }

    /// Retrieve an object by handle, cast to the requested type.
    func get<T>(_ handle: UInt64) -> T? {
        return queue.sync {
            return storage[handle] as? T
        }
    }

    /// Remove an object from the registry by handle.
    func remove(_ handle: UInt64) {
        queue.sync {
            _ = storage.removeValue(forKey: handle)
        }
    }

    /// Remove all objects from the registry.
    func removeAll() {
        queue.sync {
            storage.removeAll()
            nextHandle = 1
        }
    }
}

/// Global singleton registry used by all bridge functions.
let registry = HandleRegistry()

// MARK: - Wrapper Classes

/// Wraps a Metal device along with its primary command queue and an optional CAMetalLayer.
final class MetalDeviceWrapper {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    var layer: CAMetalLayer?

    init(device: MTLDevice, commandQueue: MTLCommandQueue, layer: CAMetalLayer? = nil) {
        self.device = device
        self.commandQueue = commandQueue
        self.layer = layer
    }
}

/// Wraps a Metal buffer with its length and a label for debugging.
final class MetalBufferWrapper {
    let buffer: MTLBuffer
    let length: Int
    let label: String

    init(buffer: MTLBuffer, length: Int, label: String) {
        self.buffer = buffer
        self.length = length
        self.label = label
    }
}

/// Wraps a Metal texture with its dimensions and pixel format.
final class MetalTextureWrapper {
    let texture: MTLTexture
    let width: Int
    let height: Int
    let pixelFormat: MTLPixelFormat

    init(texture: MTLTexture, width: Int, height: Int, pixelFormat: MTLPixelFormat) {
        self.texture = texture
        self.width = width
        self.height = height
        self.pixelFormat = pixelFormat
    }
}

/// Wraps a Metal render pipeline state together with the descriptor that created it (for introspection).
final class MetalRenderPipelineWrapper {
    let pipelineState: MTLRenderPipelineState
    let descriptor: MTLRenderPipelineDescriptor

    init(pipelineState: MTLRenderPipelineState, descriptor: MTLRenderPipelineDescriptor) {
        self.pipelineState = pipelineState
        self.descriptor = descriptor
    }
}

/// Wraps a Metal depth/stencil state.
final class MetalDepthStencilWrapper {
    let state: MTLDepthStencilState

    init(state: MTLDepthStencilState) {
        self.state = state
    }
}

/// Wraps a Metal sampler state.
final class MetalSamplerWrapper {
    let state: MTLSamplerState

    init(state: MTLSamplerState) {
        self.state = state
    }
}

/// Wraps a render target consisting of one or more color textures and an optional depth texture.
final class MetalRenderTargetWrapper {
    var colorTextures: [MTLTexture]
    var depthTexture: MTLTexture?
    var width: Int
    var height: Int
    let label: String

    init(colorTextures: [MTLTexture], depthTexture: MTLTexture?, width: Int, height: Int, label: String) {
        self.colorTextures = colorTextures
        self.depthTexture = depthTexture
        self.width = width
        self.height = height
        self.label = label
    }
}

/// Wraps a Metal command buffer, with an optional drawable for presentation.
final class MetalCommandBufferWrapper {
    let commandBuffer: MTLCommandBuffer
    var drawable: CAMetalDrawable? = nil

    init(commandBuffer: MTLCommandBuffer) {
        self.commandBuffer = commandBuffer
    }
}

/// Wraps a Metal render command encoder.
final class MetalRenderEncoderWrapper {
    let encoder: MTLRenderCommandEncoder

    init(encoder: MTLRenderCommandEncoder) {
        self.encoder = encoder
    }
}

// MARK: - C Interop Enums

/// Pixel format enum with stable UInt32 values for C/Julia interop.
enum MetalPixelFormat: UInt32 {
    case rgba8Unorm       = 0
    case rgba16Float      = 1
    case r8Unorm          = 2
    case r16Float         = 3
    case depth32Float     = 4
    case bgra8Unorm       = 5
}

/// Load action enum for render pass attachments.
enum MetalLoadAction: UInt32 {
    case dontCare = 0
    case load     = 1
    case clear    = 2
}

/// Store action enum for render pass attachments.
enum MetalStoreAction: UInt32 {
    case dontCare = 0
    case store    = 1
}

/// Cull mode enum for rasterization.
enum MetalCullMode: UInt32 {
    case none  = 0
    case front = 1
    case back  = 2
}

/// Depth/stencil compare function enum.
enum MetalCompareFunction: UInt32 {
    case never        = 0
    case less         = 1
    case equal        = 2
    case lessEqual    = 3
    case greater      = 4
    case notEqual     = 5
    case greaterEqual = 6
    case always       = 7
}

/// Blend factor enum for color attachment blending.
enum MetalBlendFactor: UInt32 {
    case zero              = 0
    case one               = 1
    case srcAlpha          = 2
    case oneMinusSrcAlpha  = 3
    case dstAlpha          = 4
    case oneMinusDstAlpha  = 5
}

/// Primitive type enum for draw calls.
enum MetalPrimitiveType: UInt32 {
    case triangle      = 0
    case triangleStrip = 1
    case line          = 2
    case point         = 3
}

// MARK: - Conversion Helpers

/// Convert a bridge pixel format enum to the corresponding MTLPixelFormat.
func toMTLPixelFormat(_ fmt: MetalPixelFormat) -> MTLPixelFormat {
    switch fmt {
    case .rgba8Unorm:   return .rgba8Unorm
    case .rgba16Float:  return .rgba16Float
    case .r8Unorm:      return .r8Unorm
    case .r16Float:     return .r16Float
    case .depth32Float: return .depth32Float
    case .bgra8Unorm:   return .bgra8Unorm
    }
}

/// Convert a bridge load action enum to the corresponding MTLLoadAction.
func toMTLLoadAction(_ action: MetalLoadAction) -> MTLLoadAction {
    switch action {
    case .dontCare: return .dontCare
    case .load:     return .load
    case .clear:    return .clear
    }
}

/// Convert a bridge store action enum to the corresponding MTLStoreAction.
func toMTLStoreAction(_ action: MetalStoreAction) -> MTLStoreAction {
    switch action {
    case .dontCare: return .dontCare
    case .store:    return .store
    }
}

/// Convert a bridge cull mode enum to the corresponding MTLCullMode.
func toMTLCullMode(_ mode: MetalCullMode) -> MTLCullMode {
    switch mode {
    case .none:  return .none
    case .front: return .front
    case .back:  return .back
    }
}

/// Convert a bridge compare function enum to the corresponding MTLCompareFunction.
func toMTLCompareFunction(_ fn: MetalCompareFunction) -> MTLCompareFunction {
    switch fn {
    case .never:        return .never
    case .less:         return .less
    case .equal:        return .equal
    case .lessEqual:    return .lessEqual
    case .greater:      return .greater
    case .notEqual:     return .notEqual
    case .greaterEqual: return .greaterEqual
    case .always:       return .always
    }
}

/// Convert a bridge primitive type enum to the corresponding MTLPrimitiveType.
func toMTLPrimitiveType(_ type: MetalPrimitiveType) -> MTLPrimitiveType {
    switch type {
    case .triangle:      return .triangle
    case .triangleStrip: return .triangleStrip
    case .line:          return .line
    case .point:         return .point
    }
}
