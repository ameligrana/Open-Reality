# Unified model loading dispatcher

"""
    _fallback_entity_def(reason::String) -> Vector{EntityDef}

Generate a bright magenta cube placeholder entity for when model loading fails.
The color makes broken loads visually obvious in the scene.
"""
function _fallback_entity_def(reason::String)
    @warn "Using fallback placeholder mesh" reason
    fallback_mat = MaterialComponent(
        color = RGB{Float32}(1.0f0, 0.0f0, 1.0f0),
        metallic = 0.0f0,
        roughness = 1.0f0
    )
    return [entity([
        TransformComponent(),
        cube_mesh(),
        fallback_mat
    ])]
end

"""
    load_model(path::String; kwargs...) -> Vector{EntityDef}

Load a 3D model file and return a vector of EntityDefs.

Dispatches by file extension:
- `.obj` → OBJ loader (via MeshIO)
- `.gltf`, `.glb` → glTF 2.0 loader

If loading fails (file not found, parse error, etc.), returns a bright magenta
placeholder cube and logs a warning instead of crashing.

# Keyword Arguments
- For OBJ: `default_material::MaterialComponent` — override material
- For glTF: `base_dir::String` — directory for resolving relative texture paths
"""
function load_model(path::String; kwargs...)
    ext = lowercase(splitext(path)[2])

    if ext == ".obj"
        try
            return load_obj(path; kwargs...)
        catch e
            return _fallback_entity_def("Failed to load OBJ '$path': $e")
        end
    elseif ext == ".gltf" || ext == ".glb"
        try
            return load_gltf(path; kwargs...)
        catch e
            return _fallback_entity_def("Failed to load glTF '$path': $e")
        end
    else
        return _fallback_entity_def("Unsupported model format: '$ext' for path '$path'")
    end
end
