# Shader Permutation System
# Compiles shader variants based on material features to avoid massive uber-shaders

"""
    ShaderFeature

Enum of shader features that can be enabled/disabled per material.
Each feature adds a #define to the shader compilation.
"""
@enum ShaderFeature begin
    FEATURE_ALBEDO_MAP
    FEATURE_NORMAL_MAP
    FEATURE_METALLIC_ROUGHNESS_MAP
    FEATURE_AO_MAP
    FEATURE_EMISSIVE_MAP
    FEATURE_ALPHA_CUTOFF
end

"""
    ShaderVariantKey

Key for caching shader variants based on enabled features.
"""
struct ShaderVariantKey
    features::Set{ShaderFeature}
end

# Implement hash and equality for dictionary lookups
Base.hash(key::ShaderVariantKey, h::UInt) = hash(key.features, h)
Base.:(==)(a::ShaderVariantKey, b::ShaderVariantKey) = a.features == b.features

"""
    ShaderLibrary

Manages shader variants with lazy compilation.
Stores template shaders and compiles variants on-demand based on feature sets.
"""
mutable struct ShaderLibrary
    variants::Dict{ShaderVariantKey, ShaderProgram}
    template_vertex::String
    template_fragment::String
    shader_name::String  # For debugging

    ShaderLibrary(name::String, vertex_template::String, fragment_template::String) =
        new(Dict{ShaderVariantKey, ShaderProgram}(), vertex_template, fragment_template, name)
end

"""
    get_or_compile_variant!(lib::ShaderLibrary, key::ShaderVariantKey) -> ShaderProgram

Get a cached shader variant or compile a new one if it doesn't exist.
"""
function get_or_compile_variant!(lib::ShaderLibrary, key::ShaderVariantKey)::ShaderProgram
    # Check cache
    if haskey(lib.variants, key)
        return lib.variants[key]
    end

    # Generate #defines from features
    defines = String[]
    for feature in key.features
        push!(defines, "#define $(uppercase(string(feature)))")
    end

    # Prepend defines to templates
    define_block = join(defines, "\n")
    vertex_src = define_block * "\n" * lib.template_vertex
    fragment_src = define_block * "\n" * lib.template_fragment

    # Compile shader
    try
        program = create_shader_program(vertex_src, fragment_src)
        lib.variants[key] = program

        # Debug info
        feature_names = join([string(f) for f in key.features], ", ")
        @info "Compiled shader variant: $(lib.shader_name) [$(feature_names)]"

        return program
    catch e
        @error "Failed to compile shader variant: $(lib.shader_name)" exception=e
        rethrow()
    end
end

"""
    determine_shader_variant(material::MaterialComponent) -> ShaderVariantKey

Determine which shader variant to use based on material properties.
"""
function determine_shader_variant(material::MaterialComponent)::ShaderVariantKey
    features = Set{ShaderFeature}()

    # Check texture presence
    if material.albedo_map !== nothing
        push!(features, FEATURE_ALBEDO_MAP)
    end
    if material.normal_map !== nothing
        push!(features, FEATURE_NORMAL_MAP)
    end
    if material.metallic_roughness_map !== nothing
        push!(features, FEATURE_METALLIC_ROUGHNESS_MAP)
    end
    if material.ao_map !== nothing
        push!(features, FEATURE_AO_MAP)
    end
    if material.emissive_map !== nothing
        push!(features, FEATURE_EMISSIVE_MAP)
    end

    # Check alpha cutoff
    if material.alpha_cutoff > 0.0f0
        push!(features, FEATURE_ALPHA_CUTOFF)
    end

    return ShaderVariantKey(features)
end

"""
    destroy_shader_library!(lib::ShaderLibrary)

Destroy all compiled shader variants in the library.
"""
function destroy_shader_library!(lib::ShaderLibrary)
    for (key, program) in lib.variants
        destroy_shader_program!(program)
    end
    empty!(lib.variants)
    return nothing
end

"""
    get_variant_count(lib::ShaderLibrary) -> Int

Get the number of compiled variants in the library.
"""
function get_variant_count(lib::ShaderLibrary)::Int
    return length(lib.variants)
end
