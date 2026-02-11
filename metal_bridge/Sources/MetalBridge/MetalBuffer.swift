import Metal

// MARK: - Buffer Creation

@_cdecl("metal_create_buffer")
func metal_create_buffer(_ deviceHandle: UInt64, _ data: UnsafeRawPointer?, _ length: Int, _ label: UnsafePointer<CChar>) -> UInt64 {
    guard let device: MetalDeviceWrapper = globalDevice else {
        print("[MetalBuffer] ERROR: globalDevice is nil")
        return 0
    }

    let mtlBuffer: MTLBuffer?
    if let data = data {
        mtlBuffer = device.device.makeBuffer(bytes: data, length: length, options: .storageModeShared)
    } else {
        mtlBuffer = device.device.makeBuffer(length: length, options: .storageModeShared)
    }

    guard let buffer = mtlBuffer else {
        print("[MetalBuffer] ERROR: Failed to create buffer of length \(length)")
        return 0
    }

    let labelString = String(cString: label)
    buffer.label = labelString

    let wrapper = MetalBufferWrapper(buffer: buffer, length: length, label: labelString)
    return registry.insert(wrapper)
}

// MARK: - Buffer Update

@_cdecl("metal_update_buffer")
func metal_update_buffer(_ bufferHandle: UInt64, _ data: UnsafeRawPointer, _ offset: Int, _ length: Int) {
    guard let wrapper: MetalBufferWrapper = registry.get(bufferHandle) else {
        print("[MetalBuffer] ERROR: Invalid buffer handle \(bufferHandle)")
        return
    }

    memcpy(wrapper.buffer.contents() + offset, data, length)
}

// MARK: - Buffer Destruction

@_cdecl("metal_destroy_buffer")
func metal_destroy_buffer(_ handle: UInt64) {
    registry.remove(handle)
}

// MARK: - Buffer Contents Access

@_cdecl("metal_get_buffer_contents")
func metal_get_buffer_contents(_ bufferHandle: UInt64) -> UnsafeMutableRawPointer? {
    guard let wrapper: MetalBufferWrapper = registry.get(bufferHandle) else {
        print("[MetalBuffer] ERROR: Invalid buffer handle \(bufferHandle)")
        return nil
    }

    return wrapper.buffer.contents()
}

// MARK: - Buffer Length Query

@_cdecl("metal_get_buffer_length")
func metal_get_buffer_length(_ bufferHandle: UInt64) -> Int {
    guard let wrapper: MetalBufferWrapper = registry.get(bufferHandle) else {
        print("[MetalBuffer] ERROR: Invalid buffer handle \(bufferHandle)")
        return 0
    }

    return wrapper.length
}
