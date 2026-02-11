# Vulkan shader compilation (GLSL → SPIR-V via glslang) and pipeline creation

using glslang_jll

# ==================================================================
# SPIR-V Compilation
# ==================================================================

"""
    vk_compile_glsl_to_spirv(source::String, stage::Symbol) -> Vector{UInt32}

Compile GLSL source to SPIR-V bytecode using glslangValidator.
`stage` should be :vert, :frag, :comp, :geom, :tesc, or :tese.
"""
function vk_compile_glsl_to_spirv(source::String, stage::Symbol)
    stage_str = String(stage)

    # Write source to temp file
    tmp_src = tempname() * ".glsl"
    tmp_spv = tempname() * ".spv"

    try
        write(tmp_src, source)

        # Compile using glslangValidator
        glslang_path = glslang_jll.glslangValidator_path
        cmd = `$glslang_path -V -S $stage_str -o $tmp_spv $tmp_src`
        output = IOBuffer()
        err_output = IOBuffer()
        proc = run(pipeline(cmd; stderr=err_output, stdout=output); wait=true)

        if proc.exitcode != 0
            error_msg = String(take!(err_output))
            error("GLSL compilation failed for $stage shader:\n$error_msg")
        end

        # Read compiled SPIR-V
        spv_bytes = read(tmp_spv)
        spv_words = reinterpret(UInt32, spv_bytes)
        return Vector{UInt32}(spv_words)
    finally
        isfile(tmp_src) && rm(tmp_src)
        isfile(tmp_spv) && rm(tmp_spv)
    end
end

"""
    vk_create_shader_module(device, spirv_code) -> ShaderModule
"""
function vk_create_shader_module(device::Device, spirv_code::Vector{UInt32})
    info = ShaderModuleCreateInfo(spirv_code)
    return unwrap(create_shader_module(device, info))
end

# ==================================================================
# Graphics Pipeline Creation
# ==================================================================

"""
    VulkanPipelineConfig

Configuration for creating a Vulkan graphics pipeline.
"""
struct VulkanPipelineConfig
    render_pass::RenderPass
    subpass::UInt32
    vertex_bindings::Vector{VertexInputBindingDescription}
    vertex_attributes::Vector{VertexInputAttributeDescription}
    descriptor_set_layouts::Vector{DescriptorSetLayout}
    push_constant_ranges::Vector{PushConstantRange}
    blend_enable::Bool
    depth_test::Bool
    depth_write::Bool
    cull_mode::CullModeFlag
    front_face::FrontFace
    color_attachment_count::Int
    width::Int
    height::Int
end

"""
    vk_standard_vertex_bindings() -> Vector{VertexInputBindingDescription}

Standard vertex input bindings: positions (0), normals (1), UVs (2).
"""
function vk_standard_vertex_bindings()
    return [
        VertexInputBindingDescription(UInt32(0), UInt32(sizeof(Point3f)), VERTEX_INPUT_RATE_VERTEX),
        VertexInputBindingDescription(UInt32(1), UInt32(sizeof(Vec3f)), VERTEX_INPUT_RATE_VERTEX),
        VertexInputBindingDescription(UInt32(2), UInt32(sizeof(Vec2f)), VERTEX_INPUT_RATE_VERTEX),
    ]
end

"""
    vk_standard_vertex_attributes() -> Vector{VertexInputAttributeDescription}

Standard vertex input attributes matching layout locations 0=position, 1=normal, 2=UV.
"""
function vk_standard_vertex_attributes()
    return [
        VertexInputAttributeDescription(UInt32(0), UInt32(0), FORMAT_R32G32B32_SFLOAT, UInt32(0)),
        VertexInputAttributeDescription(UInt32(1), UInt32(1), FORMAT_R32G32B32_SFLOAT, UInt32(0)),
        VertexInputAttributeDescription(UInt32(2), UInt32(2), FORMAT_R32G32_SFLOAT, UInt32(0)),
    ]
end

"""
    vk_fullscreen_vertex_bindings() -> Vector{VertexInputBindingDescription}

Vertex binding for fullscreen quad (position + UV interleaved).
"""
function vk_fullscreen_vertex_bindings()
    return [
        VertexInputBindingDescription(UInt32(0), UInt32(4 * sizeof(Float32)), VERTEX_INPUT_RATE_VERTEX),
    ]
end

"""
    vk_fullscreen_vertex_attributes() -> Vector{VertexInputAttributeDescription}

Vertex attributes for fullscreen quad: position (location 0, vec2), UV (location 1, vec2).
"""
function vk_fullscreen_vertex_attributes()
    return [
        VertexInputAttributeDescription(UInt32(0), UInt32(0), FORMAT_R32G32_SFLOAT, UInt32(0)),
        VertexInputAttributeDescription(UInt32(1), UInt32(0), FORMAT_R32G32_SFLOAT, UInt32(2 * sizeof(Float32))),
    ]
end

"""
    vk_create_graphics_pipeline(device, vert_spirv, frag_spirv, config) -> VulkanShaderProgram

Create a complete graphics pipeline from SPIR-V vertex and fragment shaders.
"""
function vk_create_graphics_pipeline(device::Device, vert_spirv::Vector{UInt32},
                                      frag_spirv::Vector{UInt32}, config::VulkanPipelineConfig)
    vert_module = vk_create_shader_module(device, vert_spirv)
    frag_module = vk_create_shader_module(device, frag_spirv)

    vert_stage = PipelineShaderStageCreateInfo(
        SHADER_STAGE_VERTEX_BIT, vert_module, "main"
    )
    frag_stage = PipelineShaderStageCreateInfo(
        SHADER_STAGE_FRAGMENT_BIT, frag_module, "main"
    )

    vertex_input = PipelineVertexInputStateCreateInfo(
        config.vertex_bindings, config.vertex_attributes
    )

    input_assembly = PipelineInputAssemblyStateCreateInfo(
        PRIMITIVE_TOPOLOGY_TRIANGLE_LIST, false
    )

    viewport = Viewport(0.0f0, 0.0f0, Float32(config.width), Float32(config.height), 0.0f0, 1.0f0)
    scissor = Rect2D(Offset2D(0, 0), Extent2D(UInt32(config.width), UInt32(config.height)))
    viewport_state = PipelineViewportStateCreateInfo(;
        viewports=[viewport], scissors=[scissor]
    )

    rasterizer = PipelineRasterizationStateCreateInfo(
        false,  # depth_clamp
        false,  # rasterizer_discard
        POLYGON_MODE_FILL,
        config.cull_mode,
        config.front_face,
        false,  # depth_bias
        0.0f0, 0.0f0, 0.0f0,  # depth bias constant/clamp/slope
        1.0f0  # line_width
    )

    multisample = PipelineMultisampleStateCreateInfo(
        SAMPLE_COUNT_1_BIT, false, 1.0f0, false, false
    )

    depth_stencil = PipelineDepthStencilStateCreateInfo(
        config.depth_test,
        config.depth_write,
        COMPARE_OP_LESS,
        false,  # depth bounds test
        false,  # stencil test
        StencilOpState(STENCIL_OP_KEEP, STENCIL_OP_KEEP, STENCIL_OP_KEEP, COMPARE_OP_ALWAYS, 0, 0, 0),
        StencilOpState(STENCIL_OP_KEEP, STENCIL_OP_KEEP, STENCIL_OP_KEEP, COMPARE_OP_ALWAYS, 0, 0, 0),
        0.0f0, 1.0f0
    )

    blend_attachments = [
        PipelineColorBlendAttachmentState(
            config.blend_enable,
            BLEND_FACTOR_SRC_ALPHA,
            BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
            BLEND_OP_ADD,
            BLEND_FACTOR_ONE,
            BLEND_FACTOR_ZERO,
            BLEND_OP_ADD,
            COLOR_COMPONENT_R_BIT | COLOR_COMPONENT_G_BIT | COLOR_COMPONENT_B_BIT | COLOR_COMPONENT_A_BIT
        )
        for _ in 1:config.color_attachment_count
    ]

    color_blend = PipelineColorBlendStateCreateInfo(
        false,  # logic_op_enable
        LOGIC_OP_COPY,
        blend_attachments,
        (0.0f0, 0.0f0, 0.0f0, 0.0f0)
    )

    # Dynamic state for viewport and scissor
    dynamic_states = [DYNAMIC_STATE_VIEWPORT, DYNAMIC_STATE_SCISSOR]
    dynamic_state = PipelineDynamicStateCreateInfo(dynamic_states)

    layout_info = PipelineLayoutCreateInfo(
        config.descriptor_set_layouts,
        config.push_constant_ranges
    )
    pipeline_layout = unwrap(create_pipeline_layout(device, layout_info))

    pipeline_info = GraphicsPipelineCreateInfo(
        [vert_stage, frag_stage],
        rasterizer,
        pipeline_layout,
        config.render_pass,
        config.subpass;
        vertex_input_state=vertex_input,
        input_assembly_state=input_assembly,
        viewport_state=viewport_state,
        multisample_state=multisample,
        depth_stencil_state=depth_stencil,
        color_blend_state=color_blend,
        dynamic_state=dynamic_state
    )

    result = unwrap(create_graphics_pipelines(device, [pipeline_info]))
    pipeline = result[1]

    return VulkanShaderProgram(pipeline, pipeline_layout, config.descriptor_set_layouts;
                               vert=vert_module, frag=frag_module)
end

"""
    vk_compile_and_create_pipeline(device, vert_src, frag_src, config) -> VulkanShaderProgram

Convenience: compile GLSL sources to SPIR-V and create a graphics pipeline.
"""
function vk_compile_and_create_pipeline(device::Device, vert_src::String, frag_src::String,
                                         config::VulkanPipelineConfig)
    vert_spirv = vk_compile_glsl_to_spirv(vert_src, :vert)
    frag_spirv = vk_compile_glsl_to_spirv(frag_src, :frag)
    return vk_create_graphics_pipeline(device, vert_spirv, frag_spirv, config)
end

# ==================================================================
# Pipeline Cache
# ==================================================================

"""
Global pipeline cache keyed by (vertex_hash, fragment_hash, render_pass) for reuse.
"""
const _VK_PIPELINE_CACHE = Dict{UInt64, VulkanShaderProgram}()

function vk_pipeline_cache_key(vert_src::String, frag_src::String, render_pass_handle::UInt64)
    h = hash(vert_src)
    h = hash(frag_src, h)
    h = hash(render_pass_handle, h)
    return h
end

function vk_destroy_all_cached_pipelines!(device::Device)
    for (_, prog) in _VK_PIPELINE_CACHE
        destroy_pipeline(device, prog.pipeline)
        destroy_pipeline_layout(device, prog.pipeline_layout)
        prog.vert_module !== nothing && destroy_shader_module(device, prog.vert_module)
        prog.frag_module !== nothing && destroy_shader_module(device, prog.frag_module)
    end
    empty!(_VK_PIPELINE_CACHE)
    return nothing
end
