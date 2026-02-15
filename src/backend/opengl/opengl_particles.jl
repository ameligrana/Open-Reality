# OpenGL particle rendering

# ---- Particle Shaders ----

const PARTICLE_VERTEX_SHADER = """
#version 330 core
layout(location = 0) in vec3 a_Position;
layout(location = 1) in vec2 a_TexCoord;
layout(location = 2) in vec4 a_Color;

uniform mat4 u_View;
uniform mat4 u_Projection;

out vec2 v_TexCoord;
out vec4 v_Color;

void main() {
    v_TexCoord = a_TexCoord;
    v_Color = a_Color;
    gl_Position = u_Projection * u_View * vec4(a_Position, 1.0);
}
"""

const PARTICLE_FRAGMENT_SHADER = """
#version 330 core
in vec2 v_TexCoord;
in vec4 v_Color;

out vec4 FragColor;

void main() {
    // Soft circular falloff (no texture needed for basic particles)
    vec2 center = v_TexCoord - vec2(0.5);
    float dist = dot(center, center) * 4.0;  // 0 at center, 1 at edges
    float alpha = 1.0 - smoothstep(0.5, 1.0, dist);

    FragColor = vec4(v_Color.rgb, v_Color.a * alpha);
    if (FragColor.a < 0.01) discard;
}
"""

# ---- GPU State ----

mutable struct ParticleRendererState
    shader::Union{ShaderProgram, Nothing}
    vao::GLuint
    vbo::GLuint
    initialized::Bool
end

const _PARTICLE_RENDERER = ParticleRendererState(nothing, GLuint(0), GLuint(0), false)

"""
    init_particle_renderer!()

Initialize particle rendering resources (shader, VAO, VBO).
Automatically enables GPU compute path on OpenGL 4.3+.
"""
function init_particle_renderer!()
    _PARTICLE_RENDERER.initialized && return

    # Initialize GPU compute particle shaders if supported
    init_gpu_particle_shaders!()

    _PARTICLE_RENDERER.shader = create_shader_program(PARTICLE_VERTEX_SHADER, PARTICLE_FRAGMENT_SHADER)

    # Create VAO
    vao_ref = Ref(GLuint(0))
    glGenVertexArrays(1, vao_ref)
    _PARTICLE_RENDERER.vao = vao_ref[]

    # Create dynamic VBO
    vbo_ref = Ref(GLuint(0))
    glGenBuffers(1, vbo_ref)
    _PARTICLE_RENDERER.vbo = vbo_ref[]

    # Set up vertex attributes
    glBindVertexArray(_PARTICLE_RENDERER.vao)
    glBindBuffer(GL_ARRAY_BUFFER, _PARTICLE_RENDERER.vbo)

    stride = Int32(9 * sizeof(Float32))  # pos3 + uv2 + color4

    # Position (location 0)
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, stride, C_NULL)
    glEnableVertexAttribArray(0)

    # UV (location 1)
    glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, stride, Ptr{Nothing}(3 * sizeof(Float32)))
    glEnableVertexAttribArray(1)

    # Color RGBA (location 2)
    glVertexAttribPointer(2, 4, GL_FLOAT, GL_FALSE, stride, Ptr{Nothing}(5 * sizeof(Float32)))
    glEnableVertexAttribArray(2)

    glBindVertexArray(GLuint(0))
    glBindBuffer(GL_ARRAY_BUFFER, GLuint(0))

    _PARTICLE_RENDERER.initialized = true
end

"""
    shutdown_particle_renderer!()

Release particle rendering resources.
"""
function shutdown_particle_renderer!()
    shutdown_gpu_particle_shaders!()

    !_PARTICLE_RENDERER.initialized && return

    if _PARTICLE_RENDERER.shader !== nothing
        destroy_shader_program!(_PARTICLE_RENDERER.shader)
        _PARTICLE_RENDERER.shader = nothing
    end

    if _PARTICLE_RENDERER.vbo != GLuint(0)
        bufs = GLuint[_PARTICLE_RENDERER.vbo]
        glDeleteBuffers(1, bufs)
        _PARTICLE_RENDERER.vbo = GLuint(0)
    end

    if _PARTICLE_RENDERER.vao != GLuint(0)
        vaos = GLuint[_PARTICLE_RENDERER.vao]
        glDeleteVertexArrays(1, vaos)
        _PARTICLE_RENDERER.vao = GLuint(0)
    end

    _PARTICLE_RENDERER.initialized = false
end

"""
    reset_particle_renderer!()

Reset particle renderer state (for testing).
"""
function reset_particle_renderer!()
    _PARTICLE_RENDERER.shader = nothing
    _PARTICLE_RENDERER.vao = GLuint(0)
    _PARTICLE_RENDERER.vbo = GLuint(0)
    _PARTICLE_RENDERER.initialized = false
    reset_gpu_particle_emitters!()
end

"""
    render_particles!(view, proj)

Render all active particle systems. Call after transparent pass.
Uses GPU compute path on OpenGL 4.3+, CPU fallback otherwise.
"""
function render_particles!(view::Mat4f, proj::Mat4f)
    # GPU path: extract camera vectors from view matrix and delegate
    if has_gpu_particles() && _GPU_PARTICLE_SHADERS.initialized
        cam_right = Vec3f(view[1,1], view[2,1], view[3,1])
        cam_up    = Vec3f(view[1,2], view[2,2], view[3,2])
        render_gpu_particles!(view, proj, cam_right, cam_up)
        return
    end

    # CPU fallback
    isempty(PARTICLE_POOLS) && return
    !_PARTICLE_RENDERER.initialized && return

    sp = _PARTICLE_RENDERER.shader
    sp === nothing && return

    glUseProgram(sp.id)
    set_uniform!(sp, "u_View", view)
    set_uniform!(sp, "u_Projection", proj)

    glBindVertexArray(_PARTICLE_RENDERER.vao)
    glBindBuffer(GL_ARRAY_BUFFER, _PARTICLE_RENDERER.vbo)

    # Depth test on but no writes
    glEnable(GL_DEPTH_TEST)
    glDepthMask(GL_FALSE)
    glDisable(GL_CULL_FACE)

    # Render each emitter's particles
    for (eid, pool) in PARTICLE_POOLS
        pool.vertex_count <= 0 && continue

        comp = get_component(eid, ParticleSystemComponent)

        # Set blend mode
        glEnable(GL_BLEND)
        if comp !== nothing && comp.additive
            glBlendFunc(GL_SRC_ALPHA, GL_ONE)
        else
            glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
        end

        # Upload vertex data
        byte_size = pool.vertex_count * 9 * sizeof(Float32)
        glBufferData(GL_ARRAY_BUFFER, byte_size,
                     pointer(pool.vertex_data), GL_DYNAMIC_DRAW)

        # Draw
        glDrawArrays(GL_TRIANGLES, 0, pool.vertex_count)
    end

    # Restore state
    glBindVertexArray(GLuint(0))
    glBindBuffer(GL_ARRAY_BUFFER, GLuint(0))
    glDepthMask(GL_TRUE)
    glDisable(GL_BLEND)
    glEnable(GL_CULL_FACE)
end
