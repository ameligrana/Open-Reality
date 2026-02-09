# Cascaded Shadow Maps (CSM)
# Eliminates shadow aliasing by using multiple shadow maps at different distances

"""
    CascadedShadowMap

Cascaded shadow mapping with multiple frustum splits for improved shadow quality.
Uses Practical Split Scheme (PSSM) for optimal split distribution.
"""
mutable struct CascadedShadowMap
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

"""
    compute_cascade_splits(near::Float32, far::Float32, num_cascades::Int, lambda::Float32=0.5f0) -> Vector{Float32}

Compute cascade split distances using Practical Split Scheme (PSSM).
Lambda controls the split distribution:
- lambda = 0.0: uniform split (linear)
- lambda = 1.0: logarithmic split
- lambda = 0.5: balanced (recommended)

Returns split distances in view space (including near and far).
"""
function compute_cascade_splits(near::Float32, far::Float32, num_cascades::Int, lambda::Float32=0.5f0)
    splits = zeros(Float32, num_cascades + 1)
    splits[1] = near
    splits[end] = far

    for i in 1:num_cascades-1
        # Linear split
        c_linear = near + (far - near) * (Float32(i) / Float32(num_cascades))

        # Logarithmic split
        c_log = near * (far / near)^(Float32(i) / Float32(num_cascades))

        # PSSM blend
        splits[i + 1] = lambda * c_log + (1.0f0 - lambda) * c_linear
    end

    return splits
end

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

"""
    compute_cascade_frustum_corners(view::Mat4f, proj::Mat4f, near::Float32, far::Float32) -> Vector{Vec3f}

Compute the 8 corners of a frustum in world space.
"""
function compute_cascade_frustum_corners(view::Mat4f, proj::Mat4f, near::Float32, far::Float32)
    # Create projection matrix for this cascade's near/far range
    inv_vp = inv(proj * view)

    corners = Vec3f[]

    # NDC corners of the frustum
    for x in [-1.0f0, 1.0f0]
        for y in [-1.0f0, 1.0f0]
            for z in [0.0f0, 1.0f0]  # near=0, far=1 in NDC
                ndc = Vec4f(x, y, z, 1.0f0)
                world = inv_vp * ndc
                push!(corners, Vec3f(world[1], world[2], world[3]) / world[4])
            end
        end
    end

    return corners
end

"""
    compute_cascade_light_matrix(view::Mat4f, proj::Mat4f, near::Float32, far::Float32,
                                  light_dir::Vec3f) -> Mat4f

Compute tight orthographic projection matrix for a cascade based on frustum corners.
"""
function compute_cascade_light_matrix(view::Mat4f, proj::Mat4f, near::Float32, far::Float32,
                                      light_dir::Vec3f)
    # Get frustum corners in world space
    corners = compute_cascade_frustum_corners(view, proj, near, far)

    # Compute frustum center
    center = Vec3f(0, 0, 0)
    for corner in corners
        center += corner
    end
    center /= length(corners)

    # Light view matrix (looking down the light direction)
    light_view = look_at_matrix(center, center + light_dir, Vec3f(0, 1, 0))

    # Transform corners to light space
    light_space_corners = [Vec3f((light_view * Vec4f(c[1], c[2], c[3], 1.0f0))[1:3]...) for c in corners]

    # Find min/max in light space (AABB)
    min_x = minimum([c[1] for c in light_space_corners])
    max_x = maximum([c[1] for c in light_space_corners])
    min_y = minimum([c[2] for c in light_space_corners])
    max_y = maximum([c[2] for c in light_space_corners])
    min_z = minimum([c[3] for c in light_space_corners])
    max_z = maximum([c[3] for c in light_space_corners])

    # Extend Z range to capture shadow casters outside frustum
    z_mult = 10.0f0
    if min_z < 0
        min_z *= z_mult
    else
        min_z /= z_mult
    end
    if max_z < 0
        max_z /= z_mult
    else
        max_z *= z_mult
    end

    # Orthographic projection
    light_proj = Mat4f(
        2.0f0/(max_x - min_x), 0, 0, -(max_x + min_x)/(max_x - min_x),
        0, 2.0f0/(max_y - min_y), 0, -(max_y + min_y)/(max_y - min_y),
        0, 0, -2.0f0/(max_z - min_z), -(max_z + min_z)/(max_z - min_z),
        0, 0, 0, 1
    )

    return light_proj * light_view
end

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
