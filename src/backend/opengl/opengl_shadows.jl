# OpenGL shadow mapping implementation

# ---- Type definitions ----

"""
    ShadowMap

Stores OpenGL resources for directional shadow mapping:
depth-only FBO, depth texture, and the depth-pass shader.
"""
mutable struct ShadowMap <: AbstractShadowMap
    fbo::GLuint
    depth_texture::GLuint
    width::Int
    height::Int
    shader::Union{ShaderProgram, Nothing}

    ShadowMap(; width::Int=2048, height::Int=2048) =
        new(GLuint(0), GLuint(0), width, height, nothing)
end

get_width(sm::ShadowMap) = sm.width
get_height(sm::ShadowMap) = sm.height

"""
    CascadedShadowMap

Cascaded shadow mapping with multiple frustum splits for improved shadow quality.
Uses Practical Split Scheme (PSSM) for optimal split distribution.
"""
mutable struct CascadedShadowMap <: AbstractCascadedShadowMap
    num_cascades::Int
    cascade_fbos::Vector{GLuint}
    cascade_textures::Vector{GLuint}
    cascade_matrices::Vector{Mat4f}
    split_distances::Vector{Float32}  # View-space split distances
    resolution::Int
    depth_shader::Union{ShaderProgram, Nothing}

    CascadedShadowMap(; num_cascades::Int = 4, resolution::Int = 2048) =
        new(num_cascades, GLuint[], GLuint[], Mat4f[], Float32[], resolution, nothing)
end

# ---- Depth shader sources ----

const SHADOW_VERTEX_SHADER = """
#version 330 core

layout(location = 0) in vec3 a_Position;

uniform mat4 u_LightSpaceMatrix;
uniform mat4 u_Model;

void main()
{
    gl_Position = u_LightSpaceMatrix * u_Model * vec4(a_Position, 1.0);
}
"""

const SHADOW_FRAGMENT_SHADER = """
#version 330 core

void main()
{
    // Depth is written automatically
}
"""

# ---- ShadowMap: Create / Destroy ----

"""
    create_shadow_map!(sm::ShadowMap)

Allocate the depth FBO, depth texture, and compile the depth shader.
"""
function create_shadow_map!(sm::ShadowMap)
    # Create depth texture
    tex_ref = Ref(GLuint(0))
    glGenTextures(1, tex_ref)
    sm.depth_texture = tex_ref[]
    glBindTexture(GL_TEXTURE_2D, sm.depth_texture)
    glTexImage2D(GL_TEXTURE_2D, 0, GL_DEPTH_COMPONENT24,
                 sm.width, sm.height, 0, GL_DEPTH_COMPONENT, GL_FLOAT, C_NULL)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_BORDER)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_BORDER)
    border_color = Float32[1.0, 1.0, 1.0, 1.0]
    glTexParameterfv(GL_TEXTURE_2D, GL_TEXTURE_BORDER_COLOR, border_color)

    # Create FBO
    fbo_ref = Ref(GLuint(0))
    glGenFramebuffers(1, fbo_ref)
    sm.fbo = fbo_ref[]
    glBindFramebuffer(GL_FRAMEBUFFER, sm.fbo)
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D, sm.depth_texture, 0)
    glDrawBuffer(GL_NONE)
    glReadBuffer(GL_NONE)
    glBindFramebuffer(GL_FRAMEBUFFER, GLuint(0))

    # Compile depth shader
    sm.shader = create_shader_program(SHADOW_VERTEX_SHADER, SHADOW_FRAGMENT_SHADER)

    return nothing
end

"""
    destroy_shadow_map!(sm::ShadowMap)

Clean up shadow map GPU resources.
"""
function destroy_shadow_map!(sm::ShadowMap)
    if sm.fbo != GLuint(0)
        glDeleteFramebuffers(1, Ref(sm.fbo))
        sm.fbo = GLuint(0)
    end
    if sm.depth_texture != GLuint(0)
        glDeleteTextures(1, Ref(sm.depth_texture))
        sm.depth_texture = GLuint(0)
    end
    if sm.shader !== nothing
        destroy_shader_program!(sm.shader)
        sm.shader = nothing
    end
    return nothing
end

# ---- ShadowMap: Shadow render pass ----

"""
    render_shadow_pass!(sm::ShadowMap, light_space::Mat4f, gpu_cache::GPUResourceCache)

Render all mesh entities into the shadow depth buffer.
"""
function render_shadow_pass!(sm::ShadowMap, light_space::Mat4f, gpu_cache::GPUResourceCache)
    sm.shader === nothing && return nothing

    # Save current viewport
    viewport = Int32[0, 0, 0, 0]
    glGetIntegerv(GL_VIEWPORT, viewport)

    glViewport(0, 0, sm.width, sm.height)
    glBindFramebuffer(GL_FRAMEBUFFER, sm.fbo)
    glClear(GL_DEPTH_BUFFER_BIT)

    # Disable face culling for shadow pass to avoid peter-panning
    glDisable(GL_CULL_FACE)

    sp = sm.shader
    glUseProgram(sp.id)
    set_uniform!(sp, "u_LightSpaceMatrix", light_space)

    iterate_components(MeshComponent) do entity_id, mesh
        isempty(mesh.indices) && return

        world_transform = get_world_transform(entity_id)
        model = Mat4f(world_transform)
        set_uniform!(sp, "u_Model", model)

        gpu_mesh = get_or_upload_mesh!(gpu_cache, entity_id, mesh)
        glBindVertexArray(gpu_mesh.vao)
        glDrawElements(GL_TRIANGLES, gpu_mesh.index_count, GL_UNSIGNED_INT, C_NULL)
        glBindVertexArray(GLuint(0))
    end

    # Restore
    glEnable(GL_CULL_FACE)
    glBindFramebuffer(GL_FRAMEBUFFER, GLuint(0))
    glViewport(viewport[1], viewport[2], viewport[3], viewport[4])

    return nothing
end

# ---- CascadedShadowMap: Create / Destroy ----

"""
    create_csm!(csm::CascadedShadowMap, near::Float32, far::Float32)

Create GPU resources for cascaded shadow maps.
"""
function create_csm!(csm::CascadedShadowMap, near::Float32, far::Float32)
    # Compute split distances
    csm.split_distances = compute_cascade_splits(near, far, csm.num_cascades)

    @info "Creating CSM" cascades=csm.num_cascades resolution=csm.resolution splits=csm.split_distances

    # Create framebuffers and textures for each cascade
    resize!(csm.cascade_fbos, csm.num_cascades)
    resize!(csm.cascade_textures, csm.num_cascades)
    resize!(csm.cascade_matrices, csm.num_cascades)

    for i in 1:csm.num_cascades
        # Create framebuffer
        fbo_ref = Ref(GLuint(0))
        glGenFramebuffers(1, fbo_ref)
        csm.cascade_fbos[i] = fbo_ref[]

        # Create depth texture
        tex_ref = Ref(GLuint(0))
        glGenTextures(1, tex_ref)
        csm.cascade_textures[i] = tex_ref[]

        glBindTexture(GL_TEXTURE_2D, csm.cascade_textures[i])
        glTexImage2D(GL_TEXTURE_2D, 0, GL_DEPTH_COMPONENT24, csm.resolution, csm.resolution,
                     0, GL_DEPTH_COMPONENT, GL_FLOAT, C_NULL)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_BORDER)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_BORDER)

        # Border color white (1.0) so samples outside shadow map are fully lit
        border_color = Float32[1.0, 1.0, 1.0, 1.0]
        glTexParameterfv(GL_TEXTURE_2D, GL_TEXTURE_BORDER_COLOR, border_color)

        # Attach to framebuffer
        glBindFramebuffer(GL_FRAMEBUFFER, csm.cascade_fbos[i])
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D,
                               csm.cascade_textures[i], 0)
        glDrawBuffer(GL_NONE)
        glReadBuffer(GL_NONE)

        # Verify completeness
        status = glCheckFramebufferStatus(GL_FRAMEBUFFER)
        if status != GL_FRAMEBUFFER_COMPLETE
            error("CSM framebuffer $i incomplete! Status: $status")
        end

        # Initialize matrix
        csm.cascade_matrices[i] = Mat4f(I)
    end

    glBindFramebuffer(GL_FRAMEBUFFER, GLuint(0))

    # Create depth-only shader (reuse from shadow_map.jl if available)
    # For now, we'll assume it's created elsewhere

    return nothing
end

"""
    destroy_csm!(csm::CascadedShadowMap)

Release GPU resources for cascaded shadow maps.
"""
function destroy_csm!(csm::CascadedShadowMap)
    for i in 1:csm.num_cascades
        if i <= length(csm.cascade_fbos) && csm.cascade_fbos[i] != GLuint(0)
            glDeleteFramebuffers(1, Ref(csm.cascade_fbos[i]))
        end
        if i <= length(csm.cascade_textures) && csm.cascade_textures[i] != GLuint(0)
            glDeleteTextures(1, Ref(csm.cascade_textures[i]))
        end
    end

    empty!(csm.cascade_fbos)
    empty!(csm.cascade_textures)
    empty!(csm.cascade_matrices)
    empty!(csm.split_distances)

    if csm.depth_shader !== nothing
        destroy_shader_program!(csm.depth_shader)
        csm.depth_shader = nothing
    end

    return nothing
end

# ---- CascadedShadowMap: Render cascade ----

"""
    render_csm_cascade!(csm::CascadedShadowMap, cascade_idx::Int, entities,
                        view::Mat4f, proj::Mat4f, light_dir::Vec3f, gpu_cache, depth_shader)

Render a single cascade of the CSM.
"""
function render_csm_cascade!(csm::CascadedShadowMap, cascade_idx::Int, entities,
                            view::Mat4f, proj::Mat4f, light_dir::Vec3f,
                            gpu_cache, depth_shader)
    # Compute light space matrix for this cascade
    near = csm.split_distances[cascade_idx]
    far = csm.split_distances[cascade_idx + 1]

    light_matrix = compute_cascade_light_matrix(view, proj, near, far, light_dir)
    csm.cascade_matrices[cascade_idx] = light_matrix

    # Bind framebuffer
    glBindFramebuffer(GL_FRAMEBUFFER, csm.cascade_fbos[cascade_idx])
    glViewport(0, 0, csm.resolution, csm.resolution)
    glClear(GL_DEPTH_BUFFER_BIT)

    # Render depth only
    glUseProgram(depth_shader.id)
    set_uniform!(depth_shader, "u_LightSpaceMatrix", light_matrix)

    # TODO: Frustum culling per cascade
    # For now, render all entities
    for (entity_id, mesh, model, _) in entities
        set_uniform!(depth_shader, "u_Model", model)

        gpu_mesh = get_or_upload_mesh!(gpu_cache, entity_id, mesh)
        glBindVertexArray(gpu_mesh.vao)
        glDrawElements(GL_TRIANGLES, gpu_mesh.index_count, GL_UNSIGNED_INT, C_NULL)
        glBindVertexArray(GLuint(0))
    end

    glBindFramebuffer(GL_FRAMEBUFFER, GLuint(0))

    return nothing
end
