# Metal shader/pipeline state creation and caching

# Pipeline state cache key
struct MetalPipelineKey
    source_hash::UInt64
    vertex_func::String
    fragment_func::String
    num_color_attachments::Int32
    color_formats::Vector{UInt32}
    depth_format::UInt32
    blend_enabled::Int32
end

function Base.hash(k::MetalPipelineKey, h::UInt)
    h = hash(k.source_hash, h)
    h = hash(k.vertex_func, h)
    h = hash(k.fragment_func, h)
    h = hash(k.num_color_attachments, h)
    for f in k.color_formats
        h = hash(f, h)
    end
    h = hash(k.depth_format, h)
    h = hash(k.blend_enabled, h)
    return h
end

function Base.:(==)(a::MetalPipelineKey, b::MetalPipelineKey)
    return a.source_hash == b.source_hash &&
           a.vertex_func == b.vertex_func &&
           a.fragment_func == b.fragment_func &&
           a.num_color_attachments == b.num_color_attachments &&
           a.color_formats == b.color_formats &&
           a.depth_format == b.depth_format &&
           a.blend_enabled == b.blend_enabled
end

# Global pipeline cache
const _METAL_PIPELINE_CACHE = Dict{MetalPipelineKey, UInt64}()

function metal_get_or_create_pipeline(msl_source::String, vertex_func::String, fragment_func::String;
                                       num_color_attachments::Int32 = Int32(1),
                                       color_formats::Vector{UInt32} = UInt32[MTL_PIXEL_FORMAT_BGRA8_UNORM],
                                       depth_format::UInt32 = MTL_PIXEL_FORMAT_DEPTH32_FLOAT,
                                       blend_enabled::Int32 = Int32(0))
    key = MetalPipelineKey(hash(msl_source), vertex_func, fragment_func,
                            num_color_attachments, color_formats, depth_format, blend_enabled)

    existing = get(_METAL_PIPELINE_CACHE, key, nothing)
    if existing !== nothing
        return existing
    end

    handle = metal_create_render_pipeline(msl_source, vertex_func, fragment_func,
                                           num_color_attachments, color_formats,
                                           depth_format, blend_enabled)
    _METAL_PIPELINE_CACHE[key] = handle
    return handle
end

function metal_destroy_all_pipelines!()
    for (_, handle) in _METAL_PIPELINE_CACHE
        metal_destroy_render_pipeline(handle)
    end
    empty!(_METAL_PIPELINE_CACHE)
    return nothing
end

# MSL shader loading from file
function _load_msl_shader(filename::String)
    path = joinpath(@__DIR__, "shaders", filename)
    return read(path, String)
end

# Insert #define directives into MSL source (at the top, since MSL has no #version line)
function _insert_msl_defines(source::String, defines::Vector{String})
    if isempty(defines)
        return source
    end
    define_block = join(defines, "\n") * "\n"
    return define_block * source
end

# Metal shader variant compiler for ShaderLibrary{MetalShaderProgram}
function metal_compile_shader_variant(vertex_template::String, fragment_template::String,
                                       variant_key::ShaderVariantKey;
                                       num_color_attachments::Int32 = Int32(4),
                                       color_formats::Vector{UInt32} = UInt32[
                                           MTL_PIXEL_FORMAT_RGBA16_FLOAT,
                                           MTL_PIXEL_FORMAT_RGBA16_FLOAT,
                                           MTL_PIXEL_FORMAT_RGBA16_FLOAT,
                                           MTL_PIXEL_FORMAT_RGBA8_UNORM
                                       ],
                                       depth_format::UInt32 = MTL_PIXEL_FORMAT_DEPTH32_FLOAT,
                                       blend_enabled::Int32 = Int32(0),
                                       vertex_func::String = "gbuffer_vertex",
                                       fragment_func::String = "gbuffer_fragment")
    # Generate #define directives
    defines = String[]
    for feature in variant_key.features
        push!(defines, "#define $(feature)")
    end

    # MSL: vertex and fragment are in the same source file
    # Use fragment_template as the combined MSL source
    msl_source = _insert_msl_defines(fragment_template, defines)

    handle = metal_get_or_create_pipeline(msl_source, vertex_func, fragment_func;
                                           num_color_attachments=num_color_attachments,
                                           color_formats=color_formats,
                                           depth_format=depth_format,
                                           blend_enabled=blend_enabled)

    return MetalShaderProgram(handle, vertex_func, fragment_func)
end
