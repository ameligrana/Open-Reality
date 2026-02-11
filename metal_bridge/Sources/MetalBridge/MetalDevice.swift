import Metal
import MetalKit
import QuartzCore
import AppKit

// MARK: - Global Device

/// The currently active Metal device wrapper, set during metal_init and cleared on metal_shutdown.
var globalDevice: MetalDeviceWrapper? = nil

// MARK: - Device Lifecycle

/// Initialize a Metal device, command queue, and CAMetalLayer attached to the given NSWindow.
///
/// - Parameters:
///   - nswindow: A raw pointer to an NSWindow obtained from Julia (e.g. via GLFW).
///   - width: Initial drawable width in pixels.
///   - height: Initial drawable height in pixels.
/// - Returns: A handle to the MetalDeviceWrapper stored in the global registry.
@_cdecl("metal_init")
func metal_init(_ nswindow: UnsafeMutableRawPointer, _ width: Int32, _ height: Int32) -> UInt64 {
    guard let device = MTLCreateSystemDefaultDevice() else {
        fatalError("metal_init: Failed to create system default Metal device.")
    }

    guard let commandQueue = device.makeCommandQueue() else {
        fatalError("metal_init: Failed to create Metal command queue.")
    }

    // Bridge the raw pointer to an NSObject (the NSWindow).
    let window = Unmanaged<NSObject>.fromOpaque(nswindow).takeUnretainedValue()

    // Get the window's contentView.
    guard let contentView = window.value(forKey: "contentView") as? NSObject else {
        fatalError("metal_init: Could not obtain contentView from NSWindow.")
    }

    // Create and configure the CAMetalLayer.
    let layer = CAMetalLayer()
    layer.device = device
    layer.pixelFormat = .bgra8Unorm
    layer.framebufferOnly = false
    layer.drawableSize = CGSize(width: CGFloat(width), height: CGFloat(height))

    // Attach the Metal layer to the content view.
    contentView.setValue(layer, forKey: "layer")
    contentView.setValue(true, forKey: "wantsLayer")

    // Create the wrapper, register it, and set as the global device.
    let wrapper = MetalDeviceWrapper(device: device, commandQueue: commandQueue, layer: layer)
    let handle = registry.insert(wrapper)
    globalDevice = wrapper

    return handle
}

/// Shut down the Metal device and clean up all registered handles.
///
/// - Parameter deviceHandle: The handle returned by `metal_init`.
@_cdecl("metal_shutdown")
func metal_shutdown(_ deviceHandle: UInt64) {
    guard let _: MetalDeviceWrapper = registry.get(deviceHandle) else {
        return
    }

    // Remove every object in the registry (device, buffers, textures, etc.).
    registry.removeAll()
    globalDevice = nil
}

// MARK: - Resize

/// Update the CAMetalLayer's drawable size (e.g. after the window is resized).
///
/// - Parameters:
///   - deviceHandle: The handle returned by `metal_init`.
///   - width: New drawable width in pixels.
///   - height: New drawable height in pixels.
@_cdecl("metal_resize")
func metal_resize(_ deviceHandle: UInt64, _ width: Int32, _ height: Int32) {
    guard let wrapper: MetalDeviceWrapper = registry.get(deviceHandle) else {
        return
    }

    wrapper.layer?.drawableSize = CGSize(width: CGFloat(width), height: CGFloat(height))
}

// MARK: - Frame Lifecycle

/// Begin a new frame: acquire the next drawable and create a command buffer.
///
/// - Parameter deviceHandle: The handle returned by `metal_init`.
/// - Returns: A handle to a MetalCommandBufferWrapper for this frame.
@_cdecl("metal_begin_frame")
func metal_begin_frame(_ deviceHandle: UInt64) -> UInt64 {
    guard let wrapper: MetalDeviceWrapper = registry.get(deviceHandle) else {
        fatalError("metal_begin_frame: Invalid device handle \(deviceHandle).")
    }

    guard let layer = wrapper.layer else {
        fatalError("metal_begin_frame: Device has no CAMetalLayer.")
    }

    let drawable = layer.nextDrawable()

    guard let commandBuffer = wrapper.commandQueue.makeCommandBuffer() else {
        fatalError("metal_begin_frame: Failed to create command buffer.")
    }

    let cmdBufWrapper = MetalCommandBufferWrapper(commandBuffer: commandBuffer)
    cmdBufWrapper.drawable = drawable

    let handle = registry.insert(cmdBufWrapper)
    return handle
}

/// End the current frame: present the drawable and commit the command buffer.
///
/// - Parameter cmdBufHandle: The handle returned by `metal_begin_frame`.
@_cdecl("metal_end_frame")
func metal_end_frame(_ cmdBufHandle: UInt64) {
    guard let wrapper: MetalCommandBufferWrapper = registry.get(cmdBufHandle) else {
        return
    }

    if let drawable = wrapper.drawable {
        wrapper.commandBuffer.present(drawable)
    }

    wrapper.commandBuffer.commit()

    registry.remove(cmdBufHandle)
}
