# GPU Abstraction Layer — Abstract resource types
# All rendering backends (OpenGL, Metal, etc.) implement concrete subtypes of these.

"""
    AbstractShaderProgram

Abstract compiled shader program. Backend-specific subtypes hold
platform handles (GLuint for OpenGL, MTLRenderPipelineState for Metal).
"""
abstract type AbstractShaderProgram end

"""
    AbstractGPUMesh

Abstract GPU-resident mesh (vertex + index buffers).
"""
abstract type AbstractGPUMesh end

"""
    AbstractGPUTexture

Abstract GPU-resident texture with metadata.
"""
abstract type AbstractGPUTexture end

"""
    AbstractFramebuffer

Abstract off-screen render target (color attachment + optional depth).
"""
abstract type AbstractFramebuffer end

"""
    AbstractGBuffer

Abstract G-Buffer for deferred rendering with multiple render targets.
"""
abstract type AbstractGBuffer end

"""
    AbstractShadowMap

Abstract single shadow map (depth-only FBO).
"""
abstract type AbstractShadowMap end

"""
    AbstractCascadedShadowMap

Abstract cascaded shadow map with multiple frustum splits.
"""
abstract type AbstractCascadedShadowMap end

"""
    AbstractIBLEnvironment

Abstract image-based lighting environment (cubemap, irradiance, prefilter, BRDF LUT).
"""
abstract type AbstractIBLEnvironment end

"""
    AbstractSSRPass

Abstract screen-space reflections pass.
"""
abstract type AbstractSSRPass end

"""
    AbstractSSAOPass

Abstract screen-space ambient occlusion pass.
"""
abstract type AbstractSSAOPass end

"""
    AbstractTAAPass

Abstract temporal anti-aliasing pass.
"""
abstract type AbstractTAAPass end

"""
    AbstractDOFPass

Abstract depth-of-field post-processing pass.
"""
abstract type AbstractDOFPass end

"""
    AbstractMotionBlurPass

Abstract motion blur post-processing pass.
"""
abstract type AbstractMotionBlurPass end

"""
    AbstractPostProcessPipeline

Abstract post-processing pipeline (bloom, tone mapping, FXAA).
"""
abstract type AbstractPostProcessPipeline end

"""
    AbstractDeferredPipeline

Abstract deferred rendering pipeline (G-Buffer + lighting pass + screen-space effects).
"""
abstract type AbstractDeferredPipeline end

"""
    AbstractGPUResourceCache

Abstract cache for GPU-resident mesh resources, keyed by EntityID.
"""
abstract type AbstractGPUResourceCache end

"""
    AbstractTextureCache

Abstract cache for GPU-resident textures, keyed by file path.
"""
abstract type AbstractTextureCache end

# ---- Abstract accessors ----
# Backends must implement these to allow backend-agnostic orchestration code
# to query properties without knowing the concrete type.

"""
    get_index_count(mesh::AbstractGPUMesh) -> Int32

Return the number of indices in the mesh (for draw calls).
"""
function get_index_count(mesh::AbstractGPUMesh)
    error("get_index_count not implemented for $(typeof(mesh))")
end

"""
    get_width(target) -> Int
    get_height(target) -> Int

Return dimensions of a framebuffer, G-Buffer, or render pass.
"""
function get_width(target)
    error("get_width not implemented for $(typeof(target))")
end

function get_height(target)
    error("get_height not implemented for $(typeof(target))")
end
