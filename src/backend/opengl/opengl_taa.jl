# OpenGL TAA (Temporal Anti-Aliasing) implementation

# ---- Type definition ----

"""
    TAAPass

Temporal Anti-Aliasing pass using history buffer reprojection.

Features:
- Camera jitter with 8-sample Halton sequence
- History reprojection using previous view-projection matrix
- Neighborhood clamping (3×3 AABB) to prevent ghosting
- Configurable feedback (default 0.9 = 90% history)
"""
mutable struct TAAPass <: AbstractTAAPass
    history_fbo::GLuint
    history_texture::GLuint
    current_fbo::GLuint
    current_texture::GLuint
    taa_shader::Union{ShaderProgram, Nothing}

    # Configuration
    feedback::Float32           # 0.9 = 90% history, 0.1 = 10% current
    jitter_index::Int           # Current jitter sample (0-7)

    # Previous frame data for reprojection
    prev_view_proj::Mat4f
    first_frame::Bool           # Skip history blend on first frame

    width::Int
    height::Int
end

get_width(taa::TAAPass) = taa.width
get_height(taa::TAAPass) = taa.height

# =============================================================================
# TAA Shader and Implementation
# =============================================================================

"""
    compile_taa_shader() -> ShaderProgram

Compile TAA shader with history reprojection and neighborhood clamping.
"""
function compile_taa_shader()
    vert = """
    #version 410 core
    layout (location = 0) in vec2 aPos;
    layout (location = 1) in vec2 aTexCoord;

    out vec2 TexCoord;

    void main() {
        gl_Position = vec4(aPos, 0.0, 1.0);
        TexCoord = aTexCoord;
    }
    """

    frag = """
    #version 410 core
    out vec4 FragColor;
    in vec2 TexCoord;

    uniform sampler2D u_CurrentFrame;
    uniform sampler2D u_HistoryFrame;
    uniform sampler2D u_DepthTexture;

    uniform mat4 u_InvViewProj;      // Current frame inverse view-projection
    uniform mat4 u_PrevViewProj;     // Previous frame view-projection
    uniform float u_Feedback;        // History weight (0.9 = 90% history)
    uniform int u_FirstFrame;        // Skip history on first frame (0 or 1)

    vec3 RGB_to_YCoCg(vec3 rgb) {
        float Y  =  0.25 * rgb.r + 0.5 * rgb.g + 0.25 * rgb.b;
        float Co =  0.5  * rgb.r - 0.5 * rgb.b;
        float Cg = -0.25 * rgb.r + 0.5 * rgb.g - 0.25 * rgb.b;
        return vec3(Y, Co, Cg);
    }

    vec3 YCoCg_to_RGB(vec3 ycocg) {
        float tmp = ycocg.x - ycocg.z;
        float r = tmp + ycocg.y;
        float g = ycocg.x + ycocg.z;
        float b = tmp - ycocg.y;
        return vec3(r, g, b);
    }

    void main() {
        vec3 current_color = texture(u_CurrentFrame, TexCoord).rgb;

        // On first frame, no history available
        if (u_FirstFrame == 1) {
            FragColor = vec4(current_color, 1.0);
            return;
        }

        // Reconstruct world position from depth
        float depth = texture(u_DepthTexture, TexCoord).r;
        vec4 ndc = vec4(TexCoord * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
        vec4 world_pos = u_InvViewProj * ndc;
        world_pos /= world_pos.w;

        // Reproject to previous frame
        vec4 prev_clip = u_PrevViewProj * world_pos;
        prev_clip.xyz /= prev_clip.w;
        vec2 prev_uv = prev_clip.xy * 0.5 + 0.5;

        // If reprojection goes off-screen, use current color only
        if (prev_uv.x < 0.0 || prev_uv.x > 1.0 || prev_uv.y < 0.0 || prev_uv.y > 1.0) {
            FragColor = vec4(current_color, 1.0);
            return;
        }

        // Sample history
        vec3 history_color = texture(u_HistoryFrame, prev_uv).rgb;

        // Neighborhood clamping (3x3 AABB) to prevent ghosting
        // Sample 3x3 neighborhood around current pixel
        vec2 texel_size = 1.0 / textureSize(u_CurrentFrame, 0);
        vec3 neighborhood_min = vec3(1e10);
        vec3 neighborhood_max = vec3(-1e10);

        for (int x = -1; x <= 1; x++) {
            for (int y = -1; y <= 1; y++) {
                vec2 offset = vec2(float(x), float(y)) * texel_size;
                vec3 neighbor = texture(u_CurrentFrame, TexCoord + offset).rgb;

                // Work in YCoCg space for better color clamping
                neighbor = RGB_to_YCoCg(neighbor);

                neighborhood_min = min(neighborhood_min, neighbor);
                neighborhood_max = max(neighborhood_max, neighbor);
            }
        }

        // Clamp history to neighborhood AABB
        vec3 history_ycocg = RGB_to_YCoCg(history_color);
        history_ycocg = clamp(history_ycocg, neighborhood_min, neighborhood_max);
        history_color = YCoCg_to_RGB(history_ycocg);

        // Temporal blend
        vec3 result = mix(current_color, history_color, u_Feedback);

        FragColor = vec4(result, 1.0);
    }
    """

    return create_shader_program(vert, frag)
end

"""
    create_taa_pass!(width::Int, height::Int; feedback::Float32 = 0.9f0) -> TAAPass

Create TAA pass with history buffer.
"""
function create_taa_pass!(width::Int, height::Int; feedback::Float32 = 0.9f0)
    pass = TAAPass(
        GLuint(0), GLuint(0),  # history FBO/texture
        GLuint(0), GLuint(0),  # current FBO/texture
        nothing,               # shader
        feedback,
        1,                     # jitter_index
        Mat4f(I),             # prev_view_proj
        true,                  # first_frame
        width, height
    )

    # Create history framebuffer (RGBA16F to preserve precision)
    fbo_ref = Ref{GLuint}()
    glGenFramebuffers(1, fbo_ref)
    pass.history_fbo = fbo_ref[]
    glBindFramebuffer(GL_FRAMEBUFFER, pass.history_fbo)

    tex_ref = Ref{GLuint}()
    glGenTextures(1, tex_ref)
    pass.history_texture = tex_ref[]
    glBindTexture(GL_TEXTURE_2D, pass.history_texture)
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F, width, height, 0, GL_RGBA, GL_FLOAT, C_NULL)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, pass.history_texture, 0)

    # Create current framebuffer (output of TAA)
    fbo_ref = Ref{GLuint}()
    glGenFramebuffers(1, fbo_ref)
    pass.current_fbo = fbo_ref[]
    glBindFramebuffer(GL_FRAMEBUFFER, pass.current_fbo)

    tex_ref = Ref{GLuint}()
    glGenTextures(1, tex_ref)
    pass.current_texture = tex_ref[]
    glBindTexture(GL_TEXTURE_2D, pass.current_texture)
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F, width, height, 0, GL_RGBA, GL_FLOAT, C_NULL)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, pass.current_texture, 0)

    # Check framebuffer status
    status = glCheckFramebufferStatus(GL_FRAMEBUFFER)
    if status != GL_FRAMEBUFFER_COMPLETE
        error("TAA framebuffer incomplete: $status")
    end

    glBindFramebuffer(GL_FRAMEBUFFER, 0)

    # Create shader
    pass.taa_shader = compile_taa_shader()

    @info "Created TAA pass" width height feedback

    return pass
end

"""
    render_taa!(pass::TAAPass,
                current_scene::GLuint,
                depth_texture::GLuint,
                view::Mat4f,
                proj::Mat4f,
                quad_vao::GLuint) -> GLuint

Execute TAA pass - blend current frame with reprojected history.

Returns the anti-aliased texture (pass.current_texture).
"""
function render_taa!(pass::TAAPass,
                     current_scene::GLuint,
                     depth_texture::GLuint,
                     view::Mat4f,
                     proj::Mat4f,
                     quad_vao::GLuint)

    # Bind current FBO for output
    glBindFramebuffer(GL_FRAMEBUFFER, pass.current_fbo)
    glViewport(0, 0, pass.width, pass.height)
    glClear(GL_COLOR_BUFFER_BIT)

    # Disable depth test (fullscreen pass)
    glDisable(GL_DEPTH_TEST)
    glDisable(GL_BLEND)

    glUseProgram(pass.taa_shader.id)

    # Set texture uniforms first
    set_uniform!(pass.taa_shader, "u_CurrentFrame", Int32(0))
    set_uniform!(pass.taa_shader, "u_HistoryFrame", Int32(1))
    set_uniform!(pass.taa_shader, "u_DepthTexture", Int32(2))

    # Bind textures to their units
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, current_scene)

    glActiveTexture(GL_TEXTURE1)
    glBindTexture(GL_TEXTURE_2D, pass.history_texture)

    glActiveTexture(GL_TEXTURE2)
    glBindTexture(GL_TEXTURE_2D, depth_texture)

    # Set uniforms
    view_proj = proj * view
    inv_view_proj = Mat4f(inv(view_proj))

    set_uniform!(pass.taa_shader, "u_InvViewProj", inv_view_proj)
    set_uniform!(pass.taa_shader, "u_PrevViewProj", pass.prev_view_proj)
    set_uniform!(pass.taa_shader, "u_Feedback", pass.feedback)
    set_uniform!(pass.taa_shader, "u_FirstFrame", Int32(pass.first_frame ? 1 : 0))

    # Render fullscreen quad
    glBindVertexArray(quad_vao)
    glDrawArrays(GL_TRIANGLES, 0, 6)
    glBindVertexArray(0)

    # Copy current result to history for next frame
    glBindFramebuffer(GL_READ_FRAMEBUFFER, pass.current_fbo)
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, pass.history_fbo)
    glBlitFramebuffer(
        0, 0, pass.width, pass.height,
        0, 0, pass.width, pass.height,
        GL_COLOR_BUFFER_BIT, GL_NEAREST
    )

    # Update state for next frame
    pass.prev_view_proj = view_proj
    pass.first_frame = false
    pass.jitter_index = mod1(pass.jitter_index + 1, 8)

    glBindFramebuffer(GL_FRAMEBUFFER, 0)
    glEnable(GL_DEPTH_TEST)

    return pass.current_texture
end

"""
    destroy_taa_pass!(pass::TAAPass)

Cleanup TAA pass resources.
"""
function destroy_taa_pass!(pass::TAAPass)
    if pass.history_fbo != GLuint(0)
        glDeleteFramebuffers(1, Ref(pass.history_fbo))
    end
    if pass.history_texture != GLuint(0)
        glDeleteTextures(1, Ref(pass.history_texture))
    end
    if pass.current_fbo != GLuint(0)
        glDeleteFramebuffers(1, Ref(pass.current_fbo))
    end
    if pass.current_texture != GLuint(0)
        glDeleteTextures(1, Ref(pass.current_texture))
    end

    pass.history_fbo = GLuint(0)
    pass.history_texture = GLuint(0)
    pass.current_fbo = GLuint(0)
    pass.current_texture = GLuint(0)
end

"""
    resize_taa_pass!(pass::TAAPass, width::Int, height::Int)

Resize TAA pass framebuffers.
"""
function resize_taa_pass!(pass::TAAPass, width::Int, height::Int)
    if pass.width == width && pass.height == height
        return
    end

    pass.width = width
    pass.height = height

    # Recreate textures
    if pass.history_texture != GLuint(0)
        glBindTexture(GL_TEXTURE_2D, pass.history_texture)
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F, width, height, 0, GL_RGBA, GL_FLOAT, C_NULL)
    end

    if pass.current_texture != GLuint(0)
        glBindTexture(GL_TEXTURE_2D, pass.current_texture)
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F, width, height, 0, GL_RGBA, GL_FLOAT, C_NULL)
    end

    glBindTexture(GL_TEXTURE_2D, 0)

    # Reset first frame flag (history is now invalid)
    pass.first_frame = true
end
