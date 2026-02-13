# Abstract backend interface
# All rendering backends must implement these methods.

"""
    AbstractBackend

Abstract type for rendering backends (OpenGL, Metal, etc.).
Backends hold all GPU state and provide factory methods for GPU resources.
"""
abstract type AbstractBackend end

# ---- Core lifecycle ----

"""
    initialize!(backend::AbstractBackend; width, height, title)

Initialize the rendering backend, create a window, and set up GPU state.
"""
function initialize!(backend::AbstractBackend; width::Int=1280, height::Int=720, title::String="OpenReality")
    error("initialize! not implemented for $(typeof(backend))")
end

"""
    shutdown!(backend::AbstractBackend)

Shutdown the rendering backend, release all GPU resources, and destroy the window.
"""
function shutdown!(backend::AbstractBackend)
    error("shutdown! not implemented for $(typeof(backend))")
end

"""
    render_frame!(backend::AbstractBackend, scene)

Render a single frame of the given scene.
"""
function render_frame!(backend::AbstractBackend, scene)
    error("render_frame! not implemented for $(typeof(backend))")
end

# ---- Shader operations ----

"""
    backend_create_shader(backend, vertex_src, fragment_src) -> AbstractShaderProgram

Compile vertex and fragment shader sources into a linked shader program.
"""
function backend_create_shader(backend::AbstractBackend, vertex_src::String, fragment_src::String)
    error("backend_create_shader not implemented for $(typeof(backend))")
end

"""
    backend_destroy_shader!(backend, shader::AbstractShaderProgram)

Delete a shader program and release GPU resources.
"""
function backend_destroy_shader!(backend::AbstractBackend, shader::AbstractShaderProgram)
    error("backend_destroy_shader! not implemented for $(typeof(backend))")
end

"""
    backend_use_shader!(backend, shader::AbstractShaderProgram)

Bind a shader program for subsequent draw calls.
"""
function backend_use_shader!(backend::AbstractBackend, shader::AbstractShaderProgram)
    error("backend_use_shader! not implemented for $(typeof(backend))")
end

"""
    backend_set_uniform!(backend, shader, name, value)

Set a uniform variable on the currently bound shader.
"""
function backend_set_uniform!(backend::AbstractBackend, shader::AbstractShaderProgram, name::String, value)
    error("backend_set_uniform! not implemented for $(typeof(backend))")
end

# ---- Mesh operations ----

"""
    backend_upload_mesh!(backend, entity_id, mesh::MeshComponent) -> AbstractGPUMesh

Upload mesh data (vertices, normals, UVs, indices) to GPU buffers.
"""
function backend_upload_mesh!(backend::AbstractBackend, entity_id, mesh)
    error("backend_upload_mesh! not implemented for $(typeof(backend))")
end

"""
    backend_draw_mesh!(backend, gpu_mesh::AbstractGPUMesh)

Issue a draw call for the given GPU mesh.
"""
function backend_draw_mesh!(backend::AbstractBackend, gpu_mesh::AbstractGPUMesh)
    error("backend_draw_mesh! not implemented for $(typeof(backend))")
end

"""
    backend_destroy_mesh!(backend, gpu_mesh::AbstractGPUMesh)

Release GPU resources for a mesh.
"""
function backend_destroy_mesh!(backend::AbstractBackend, gpu_mesh::AbstractGPUMesh)
    error("backend_destroy_mesh! not implemented for $(typeof(backend))")
end

# ---- Texture operations ----

"""
    backend_upload_texture!(backend, pixels, width, height, channels) -> AbstractGPUTexture

Upload raw pixel data to a GPU texture.
"""
function backend_upload_texture!(backend::AbstractBackend, pixels::Vector{UInt8}, width::Int, height::Int, channels::Int)
    error("backend_upload_texture! not implemented for $(typeof(backend))")
end

"""
    backend_bind_texture!(backend, texture::AbstractGPUTexture, unit::Int)

Bind a texture to a given texture unit.
"""
function backend_bind_texture!(backend::AbstractBackend, texture::AbstractGPUTexture, unit::Int)
    error("backend_bind_texture! not implemented for $(typeof(backend))")
end

"""
    backend_destroy_texture!(backend, texture::AbstractGPUTexture)

Release GPU resources for a texture.
"""
function backend_destroy_texture!(backend::AbstractBackend, texture::AbstractGPUTexture)
    error("backend_destroy_texture! not implemented for $(typeof(backend))")
end

# ---- Framebuffer operations ----

"""
    backend_create_framebuffer!(backend, width, height) -> AbstractFramebuffer

Create an HDR off-screen render target.
"""
function backend_create_framebuffer!(backend::AbstractBackend, width::Int, height::Int)
    error("backend_create_framebuffer! not implemented for $(typeof(backend))")
end

"""
    backend_bind_framebuffer!(backend, fb::AbstractFramebuffer)

Bind a framebuffer for rendering.
"""
function backend_bind_framebuffer!(backend::AbstractBackend, fb::AbstractFramebuffer)
    error("backend_bind_framebuffer! not implemented for $(typeof(backend))")
end

"""
    backend_unbind_framebuffer!(backend)

Bind the default framebuffer (screen).
"""
function backend_unbind_framebuffer!(backend::AbstractBackend)
    error("backend_unbind_framebuffer! not implemented for $(typeof(backend))")
end

"""
    backend_destroy_framebuffer!(backend, fb::AbstractFramebuffer)

Release GPU resources for a framebuffer.
"""
function backend_destroy_framebuffer!(backend::AbstractBackend, fb::AbstractFramebuffer)
    error("backend_destroy_framebuffer! not implemented for $(typeof(backend))")
end

# ---- G-Buffer operations ----

"""
    backend_create_gbuffer!(backend, width, height) -> AbstractGBuffer

Create a G-Buffer with multiple render targets for deferred rendering.
"""
function backend_create_gbuffer!(backend::AbstractBackend, width::Int, height::Int)
    error("backend_create_gbuffer! not implemented for $(typeof(backend))")
end

# ---- Shadow map operations ----

"""
    backend_create_shadow_map!(backend, width, height) -> AbstractShadowMap

Create a depth-only shadow map.
"""
function backend_create_shadow_map!(backend::AbstractBackend, width::Int, height::Int)
    error("backend_create_shadow_map! not implemented for $(typeof(backend))")
end

"""
    backend_create_csm!(backend, num_cascades, resolution, near, far) -> AbstractCascadedShadowMap

Create cascaded shadow maps.
"""
function backend_create_csm!(backend::AbstractBackend, num_cascades::Int, resolution::Int, near::Float32, far::Float32)
    error("backend_create_csm! not implemented for $(typeof(backend))")
end

# ---- IBL operations ----

"""
    backend_create_ibl_environment!(backend, path, intensity) -> AbstractIBLEnvironment

Create an image-based lighting environment from an HDR map or procedural sky.
"""
function backend_create_ibl_environment!(backend::AbstractBackend, path::String, intensity::Float32)
    error("backend_create_ibl_environment! not implemented for $(typeof(backend))")
end

# ---- Screen-space effect operations ----

"""
    backend_create_ssr_pass!(backend, width, height) -> AbstractSSRPass

Create a screen-space reflections pass.
"""
function backend_create_ssr_pass!(backend::AbstractBackend, width::Int, height::Int)
    error("backend_create_ssr_pass! not implemented for $(typeof(backend))")
end

"""
    backend_create_ssao_pass!(backend, width, height) -> AbstractSSAOPass

Create a screen-space ambient occlusion pass.
"""
function backend_create_ssao_pass!(backend::AbstractBackend, width::Int, height::Int)
    error("backend_create_ssao_pass! not implemented for $(typeof(backend))")
end

"""
    backend_create_taa_pass!(backend, width, height) -> AbstractTAAPass

Create a temporal anti-aliasing pass.
"""
function backend_create_taa_pass!(backend::AbstractBackend, width::Int, height::Int)
    error("backend_create_taa_pass! not implemented for $(typeof(backend))")
end

# ---- Post-processing operations ----

"""
    backend_create_post_process!(backend, width, height, config) -> AbstractPostProcessPipeline

Create a post-processing pipeline (bloom, tone mapping, FXAA).
"""
function backend_create_post_process!(backend::AbstractBackend, width::Int, height::Int, config)
    error("backend_create_post_process! not implemented for $(typeof(backend))")
end

# ---- Render state operations ----

"""
    backend_set_viewport!(backend, x, y, width, height)

Set the rendering viewport rectangle.
"""
function backend_set_viewport!(backend::AbstractBackend, x::Int, y::Int, width::Int, height::Int)
    error("backend_set_viewport! not implemented for $(typeof(backend))")
end

"""
    backend_clear!(backend; color=true, depth=true)

Clear the current framebuffer.
"""
function backend_clear!(backend::AbstractBackend; color::Bool=true, depth::Bool=true)
    error("backend_clear! not implemented for $(typeof(backend))")
end

"""
    backend_set_depth_test!(backend, enabled, write, func)

Configure depth testing state.
"""
function backend_set_depth_test!(backend::AbstractBackend; enabled::Bool=true, write::Bool=true)
    error("backend_set_depth_test! not implemented for $(typeof(backend))")
end

"""
    backend_set_blend!(backend; enabled, src_factor, dst_factor)

Configure alpha blending state.
"""
function backend_set_blend!(backend::AbstractBackend; enabled::Bool=false)
    error("backend_set_blend! not implemented for $(typeof(backend))")
end

"""
    backend_set_cull_face!(backend; enabled, face)

Configure face culling state.
"""
function backend_set_cull_face!(backend::AbstractBackend; enabled::Bool=true, front::Bool=false)
    error("backend_set_cull_face! not implemented for $(typeof(backend))")
end

"""
    backend_swap_buffers!(backend)

Present the rendered frame to the screen.
"""
function backend_swap_buffers!(backend::AbstractBackend)
    error("backend_swap_buffers! not implemented for $(typeof(backend))")
end

"""
    backend_draw_fullscreen_quad!(backend, quad_handle)

Draw a fullscreen quad (for post-processing passes).
"""
function backend_draw_fullscreen_quad!(backend::AbstractBackend, quad_handle)
    error("backend_draw_fullscreen_quad! not implemented for $(typeof(backend))")
end

"""
    backend_blit_framebuffer!(backend, src, dst, width, height; color, depth)

Blit (copy) framebuffer contents from source to destination.
"""
function backend_blit_framebuffer!(backend::AbstractBackend, src, dst, width::Int, height::Int;
                                    color::Bool=false, depth::Bool=false)
    error("backend_blit_framebuffer! not implemented for $(typeof(backend))")
end

# ---- Windowing / event loop operations ----

"""
    backend_should_close(backend) -> Bool

Return true if the window should close (user clicked X, etc.).
"""
function backend_should_close(backend::AbstractBackend)
    error("backend_should_close not implemented for $(typeof(backend))")
end

"""
    backend_poll_events!(backend)

Poll window system events (keyboard, mouse, resize, etc.).
"""
function backend_poll_events!(backend::AbstractBackend)
    error("backend_poll_events! not implemented for $(typeof(backend))")
end

"""
    backend_get_time(backend) -> Float64

Return elapsed time in seconds since backend initialization.
"""
function backend_get_time(backend::AbstractBackend)
    error("backend_get_time not implemented for $(typeof(backend))")
end

"""
    backend_capture_cursor!(backend)

Hide and lock the cursor for FPS-style input.
"""
function backend_capture_cursor!(backend::AbstractBackend)
    error("backend_capture_cursor! not implemented for $(typeof(backend))")
end

"""
    backend_release_cursor!(backend)

Show and unlock the cursor.
"""
function backend_release_cursor!(backend::AbstractBackend)
    error("backend_release_cursor! not implemented for $(typeof(backend))")
end

"""
    backend_is_key_pressed(backend, key) -> Bool

Check if a key is currently pressed.
"""
function backend_is_key_pressed(backend::AbstractBackend, key)
    error("backend_is_key_pressed not implemented for $(typeof(backend))")
end

"""
    backend_get_input(backend) -> InputState

Return the backend's input state for player controllers.
"""
function backend_get_input(backend::AbstractBackend)
    error("backend_get_input not implemented for $(typeof(backend))")
end

# ---- Instanced rendering ----

"""
    backend_draw_mesh_instanced!(backend, gpu_mesh, instance_count)

Issue an instanced draw call for the given GPU mesh.
"""
function backend_draw_mesh_instanced!(backend::AbstractBackend, gpu_mesh::AbstractGPUMesh, instance_count::Int)
    error("backend_draw_mesh_instanced! not implemented for $(typeof(backend))")
end

# ---- Depth of Field ----

"""
    backend_create_dof_pass!(backend, width, height) -> AbstractDOFPass

Create a depth-of-field post-processing pass.
"""
function backend_create_dof_pass!(backend::AbstractBackend, width::Int, height::Int)
    error("backend_create_dof_pass! not implemented for $(typeof(backend))")
end

# ---- Motion Blur ----

"""
    backend_create_motion_blur_pass!(backend, width, height) -> AbstractMotionBlurPass

Create a motion blur post-processing pass.
"""
function backend_create_motion_blur_pass!(backend::AbstractBackend, width::Int, height::Int)
    error("backend_create_motion_blur_pass! not implemented for $(typeof(backend))")
end

# ---- Terrain ----

"""
    backend_render_terrain!(backend, terrain_data, view, proj, cam_pos, texture_cache)

Render terrain chunks to the current framebuffer (typically G-Buffer).
"""
function backend_render_terrain!(backend::AbstractBackend, terrain_data, view, proj, cam_pos, texture_cache)
    error("backend_render_terrain! not implemented for $(typeof(backend))")
end
