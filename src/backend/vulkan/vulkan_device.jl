# Vulkan instance, physical device, and logical device creation

"""
    vk_get_required_extensions() -> Vector{String}

Get the Vulkan instance extensions required by GLFW for window surface creation.
"""
function vk_get_required_extensions()
    count_ref = Ref{UInt32}(0)
    names_ptr = ccall((:glfwGetRequiredInstanceExtensions, GLFW.libglfw),
                      Ptr{Cstring}, (Ptr{UInt32},), count_ref)
    names_ptr == C_NULL && error("GLFW: Vulkan not supported on this system")
    count = count_ref[]
    return [unsafe_string(unsafe_load(names_ptr, i)) for i in 1:count]
end

"""
    vk_create_instance(; enable_validation=false) -> Instance

Create a Vulkan instance with the required GLFW surface extensions.
"""
function vk_create_instance(; enable_validation::Bool=false)
    extensions = vk_get_required_extensions()

    layers = String[]
    if enable_validation
        push!(layers, "VK_LAYER_KHRONOS_validation")
    end

    app_info = ApplicationInfo(
        "OpenReality",
        VersionNumber(0, 1, 0),
        "OpenReality Engine",
        VersionNumber(0, 1, 0),
        VK_API_VERSION_1_2
    )

    create_info = InstanceCreateInfo(
        layers,
        extensions;
        application_info=app_info
    )

    instance = unwrap(create_instance(create_info))
    return instance
end

"""
    vk_create_surface(instance, window_handle) -> SurfaceKHR

Create a Vulkan surface from a GLFW window handle.
"""
function vk_create_surface(instance::Instance, window_handle::GLFW.Window)
    surface_ref = Ref{Ptr{Nothing}}()
    result = ccall((:glfwCreateWindowSurface, GLFW.libglfw),
                   Int32,
                   (Ptr{Nothing}, GLFW.Window, Ptr{Cvoid}, Ptr{Ptr{Nothing}}),
                   instance.vks, window_handle, C_NULL, surface_ref)
    result == 0 || error("Failed to create Vulkan window surface: result code $result")
    return SurfaceKHR(surface_ref[], instance)
end

"""
    QueueFamilyIndices

Holds the queue family indices for graphics and presentation.
"""
struct QueueFamilyIndices
    graphics::UInt32
    present::UInt32
end

"""
    vk_find_queue_families(physical_device, surface) -> Union{QueueFamilyIndices, Nothing}

Find queue families that support graphics and presentation.
"""
function vk_find_queue_families(physical_device::PhysicalDevice, surface::SurfaceKHR)
    props = get_physical_device_queue_family_properties(physical_device)
    graphics_idx = nothing
    present_idx = nothing

    for (i, prop) in enumerate(props)
        idx = UInt32(i - 1)  # 0-based
        if (prop.queue_flags & QUEUE_GRAPHICS_BIT) != 0
            graphics_idx = idx
        end
        supported = unwrap(get_physical_device_surface_support_khr(physical_device, idx, surface))
        if supported
            present_idx = idx
        end
        # Prefer a family that supports both
        if graphics_idx !== nothing && present_idx !== nothing
            break
        end
    end

    if graphics_idx === nothing || present_idx === nothing
        return nothing
    end
    return QueueFamilyIndices(graphics_idx, present_idx)
end

"""
    vk_select_physical_device(instance, surface) -> (PhysicalDevice, QueueFamilyIndices)

Select the best physical device that supports graphics and presentation.
Prefers discrete GPUs over integrated.
"""
function vk_select_physical_device(instance::Instance, surface::SurfaceKHR)
    devices = unwrap(enumerate_physical_devices(instance))
    isempty(devices) && error("No Vulkan-capable GPU found")

    best_device = nothing
    best_indices = nothing
    best_score = -1

    for dev in devices
        indices = vk_find_queue_families(dev, surface)
        indices === nothing && continue

        # Check required extensions
        ext_props = unwrap(enumerate_device_extension_properties(dev))
        ext_names = Set(String(e.extension_name) for e in ext_props)
        "VK_KHR_swapchain" in ext_names || continue

        # Score device
        props = get_physical_device_properties(dev)
        score = props.device_type == PHYSICAL_DEVICE_TYPE_DISCRETE_GPU ? 1000 : 100

        if score > best_score
            best_score = score
            best_device = dev
            best_indices = indices
        end
    end

    best_device === nothing && error("No suitable Vulkan GPU found (need graphics + present + swapchain)")
    return best_device, best_indices
end

"""
    vk_create_logical_device(physical_device, indices) -> (Device, Queue, Queue)

Create a logical device and retrieve graphics and present queues.
"""
function vk_create_logical_device(physical_device::PhysicalDevice, indices::QueueFamilyIndices)
    unique_families = unique([indices.graphics, indices.present])

    queue_create_infos = [
        DeviceQueueCreateInfo(family, [1.0f0])
        for family in unique_families
    ]

    features = PhysicalDeviceFeatures(;
        sampler_anisotropy=true,
        fill_mode_non_solid=true,
        independent_blend=true,
        multi_draw_indirect=false
    )

    device_info = DeviceCreateInfo(
        queue_create_infos,
        String[],  # layers (deprecated)
        ["VK_KHR_swapchain"];
        enabled_features=features
    )

    device = unwrap(create_device(physical_device, device_info))
    graphics_queue = get_device_queue(device, indices.graphics, 0)
    present_queue = get_device_queue(device, indices.present, 0)

    return device, graphics_queue, present_queue
end
