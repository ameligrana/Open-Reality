# WebGPU FFI wrappers — ccall bindings to the Rust openreality-wgpu cdylib.

# Library path discovery
const _WEBGPU_LIB_REF = Ref{String}("")

function _find_webgpu_lib()
    # Check environment variable first (set by Bazel julia_run rules)
    env_path = get(ENV, "OPENREALITY_WGPU_LIB", "")
    if !isempty(env_path) && isfile(env_path)
        return env_path
    end

    # Check several locations in order of priority
    candidates = [
        joinpath(@__DIR__, "..", "..", "..", "openreality-wgpu", "target", "release",
            Sys.iswindows() ? "openreality_wgpu.dll" :
            Sys.isapple() ? "libopenreality_wgpu.dylib" :
            "libopenreality_wgpu.so"),
        joinpath(@__DIR__, "..", "..", "..", "openreality-wgpu", "target", "debug",
            Sys.iswindows() ? "openreality_wgpu.dll" :
            Sys.isapple() ? "libopenreality_wgpu.dylib" :
            "libopenreality_wgpu.so"),
    ]
    for path in candidates
        if isfile(path)
            return path
        end
    end
    error("Could not find openreality_wgpu library. Build it with: cd openreality-wgpu && cargo build --release")
end

function _webgpu_lib()
    if isempty(_WEBGPU_LIB_REF[])
        _WEBGPU_LIB_REF[] = _find_webgpu_lib()
    end
    return _WEBGPU_LIB_REF[]
end

# ---- Lifecycle ----

function wgpu_initialize(window_handle::UInt64, display_handle::Ptr{Nothing}, width::Int, height::Int)
    ccall((:or_wgpu_initialize, _webgpu_lib()), UInt64,
          (UInt64, Ptr{Nothing}, Int32, Int32),
          window_handle, display_handle, Int32(width), Int32(height))
end

function wgpu_shutdown(backend::UInt64)
    ccall((:or_wgpu_shutdown, _webgpu_lib()), Cvoid, (UInt64,), backend)
end

function wgpu_resize(backend::UInt64, width::Int, height::Int)
    ccall((:or_wgpu_resize, _webgpu_lib()), Cvoid,
          (UInt64, Int32, Int32),
          backend, Int32(width), Int32(height))
end

# ---- Simple rendering ----

function wgpu_render_clear(backend::UInt64, r::Float64, g::Float64, b::Float64)
    ccall((:or_wgpu_render_clear, _webgpu_lib()), Int32,
          (UInt64, Float64, Float64, Float64),
          backend, r, g, b)
end

# ---- Mesh operations ----

function wgpu_upload_mesh(backend::UInt64,
                           positions::Vector{Float32}, normals::Vector{Float32},
                           uvs::Vector{Float32}, indices::Vector{UInt32})
    num_vertices = UInt32(length(positions) ÷ 3)
    num_indices = UInt32(length(indices))
    ccall((:or_wgpu_upload_mesh, _webgpu_lib()), UInt64,
          (UInt64, Ptr{Float32}, UInt32, Ptr{Float32}, Ptr{Float32}, Ptr{UInt32}, UInt32),
          backend, positions, num_vertices, normals, uvs, indices, num_indices)
end

function wgpu_destroy_mesh(backend::UInt64, mesh::UInt64)
    ccall((:or_wgpu_destroy_mesh, _webgpu_lib()), Cvoid,
          (UInt64, UInt64), backend, mesh)
end

# ---- Texture operations ----

function wgpu_upload_texture(backend::UInt64, pixels::Vector{UInt8},
                              width::Int, height::Int, channels::Int)
    ccall((:or_wgpu_upload_texture, _webgpu_lib()), UInt64,
          (UInt64, Ptr{UInt8}, Int32, Int32, Int32),
          backend, pixels, Int32(width), Int32(height), Int32(channels))
end

function wgpu_destroy_texture(backend::UInt64, texture::UInt64)
    ccall((:or_wgpu_destroy_texture, _webgpu_lib()), Cvoid,
          (UInt64, UInt64), backend, texture)
end

# ---- Shadow maps ----

function wgpu_create_csm(backend::UInt64, num_cascades::Int, resolution::Int,
                          near::Float32, far::Float32)
    ccall((:or_wgpu_create_csm, _webgpu_lib()), UInt64,
          (UInt64, Int32, Int32, Float32, Float32),
          backend, Int32(num_cascades), Int32(resolution), near, far)
end

# ---- Post-processing ----

function wgpu_create_post_process(backend::UInt64, width::Int, height::Int,
                                    bloom_threshold::Float32, bloom_intensity::Float32,
                                    gamma::Float32, tone_mapping_mode::Int,
                                    fxaa_enabled::Bool)
    ccall((:or_wgpu_create_post_process, _webgpu_lib()), UInt64,
          (UInt64, Int32, Int32, Float32, Float32, Float32, Int32, Int32),
          backend, Int32(width), Int32(height),
          bloom_threshold, bloom_intensity, gamma,
          Int32(tone_mapping_mode), Int32(fxaa_enabled ? 1 : 0))
end

# ---- Error handling ----

function wgpu_last_error(backend::UInt64)
    ptr = ccall((:or_wgpu_last_error, _webgpu_lib()), Ptr{UInt8}, (UInt64,), backend)
    if ptr == C_NULL
        return nothing
    end
    return unsafe_string(ptr)
end
