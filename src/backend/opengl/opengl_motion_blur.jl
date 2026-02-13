# OpenGL Motion Blur pass

"""
    MotionBlurPass <: AbstractMotionBlurPass

Camera-based motion blur using per-pixel velocity from previous/current view-projection matrices.
Pipeline: velocity buffer computation → directional blur along velocity vectors.
"""
mutable struct MotionBlurPass <: AbstractMotionBlurPass
    velocity_fbo::Framebuffer    # RG16F — screen-space velocity per pixel
    blur_fbo::Framebuffer        # RGBA16F — final blurred result
    velocity_shader::Union{ShaderProgram, Nothing}
    blur_shader::Union{ShaderProgram, Nothing}
    width::Int
    height::Int

    MotionBlurPass() = new(Framebuffer(), Framebuffer(), nothing, nothing, 0, 0)
end

# ---- GLSL shaders ----

const MBLUR_VELOCITY_FRAGMENT = """
#version 330 core

in vec2 v_TexCoord;
out vec2 FragColor;

uniform sampler2D u_DepthTexture;
uniform mat4 u_InvViewProj;
uniform mat4 u_PrevViewProj;
uniform float u_MaxVelocity;

void main()
{
    float depth = texture(u_DepthTexture, v_TexCoord).r;

    // Reconstruct clip-space position
    vec4 clip_pos = vec4(v_TexCoord * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);

    // Reconstruct world-space position
    vec4 world_pos = u_InvViewProj * clip_pos;
    world_pos /= world_pos.w;

    // Project to previous frame's clip space
    vec4 prev_clip = u_PrevViewProj * world_pos;
    prev_clip /= prev_clip.w;
    vec2 prev_uv = prev_clip.xy * 0.5 + 0.5;

    // Screen-space velocity
    vec2 velocity = (v_TexCoord - prev_uv);

    // Clamp velocity magnitude
    float speed = length(velocity);
    float max_speed = u_MaxVelocity / textureSize(u_DepthTexture, 0).x;
    if (speed > max_speed)
        velocity = velocity / speed * max_speed;

    FragColor = velocity;
}
"""

const MBLUR_BLUR_FRAGMENT = """
#version 330 core

in vec2 v_TexCoord;
out vec4 FragColor;

uniform sampler2D u_SceneTexture;
uniform sampler2D u_VelocityTexture;
uniform int u_Samples;
uniform float u_Intensity;

void main()
{
    vec2 velocity = texture(u_VelocityTexture, v_TexCoord).rg * u_Intensity;

    vec3 result = texture(u_SceneTexture, v_TexCoord).rgb;
    float total = 1.0;

    for (int i = 1; i < u_Samples; ++i) {
        float t = float(i) / float(u_Samples - 1) - 0.5;
        vec2 offset = velocity * t;
        result += texture(u_SceneTexture, v_TexCoord + offset).rgb;
        total += 1.0;
    }

    FragColor = vec4(result / total, 1.0);
}
"""

# ---- Lifecycle ----

function create_motion_blur_pass!(pass::MotionBlurPass, width::Int, height::Int)
    pass.width = width
    pass.height = height

    # Velocity buffer (RG16F at full resolution)
    pass.velocity_fbo = Framebuffer()
    _create_rg16f_framebuffer!(pass.velocity_fbo, width, height)

    # Blur output
    create_framebuffer!(pass.blur_fbo, width, height)

    # Compile shaders
    pass.velocity_shader = create_shader_program(PP_QUAD_VERTEX, MBLUR_VELOCITY_FRAGMENT)
    pass.blur_shader = create_shader_program(PP_QUAD_VERTEX, MBLUR_BLUR_FRAGMENT)

    return nothing
end

function destroy_motion_blur_pass!(pass::MotionBlurPass)
    destroy_framebuffer!(pass.velocity_fbo)
    destroy_framebuffer!(pass.blur_fbo)
    for field in (:velocity_shader, :blur_shader)
        sp = getfield(pass, field)
        if sp !== nothing
            destroy_shader_program!(sp)
            setfield!(pass, field, nothing)
        end
    end
    return nothing
end

function resize_motion_blur_pass!(pass::MotionBlurPass, width::Int, height::Int)
    pass.width = width
    pass.height = height
    _resize_rg16f_framebuffer!(pass.velocity_fbo, width, height)
    resize_framebuffer!(pass.blur_fbo, width, height)
    return nothing
end

"""
    render_motion_blur!(pass, scene_texture, depth_texture, view_proj, prev_view_proj, config, quad_vao) -> GLuint

Execute motion blur pipeline. Returns the texture containing the result.
"""
function render_motion_blur!(pass::MotionBlurPass, scene_texture::GLuint, depth_texture::GLuint,
                             view_proj::Mat4f, prev_view_proj::Mat4f,
                             config::PostProcessConfig, quad_vao::GLuint)
    inv_view_proj = inv(view_proj)

    # 1. Velocity buffer
    glBindFramebuffer(GL_FRAMEBUFFER, pass.velocity_fbo.fbo)
    glViewport(0, 0, pass.width, pass.height)
    glClear(GL_COLOR_BUFFER_BIT)
    sp = pass.velocity_shader
    glUseProgram(sp.id)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, depth_texture)
    set_uniform!(sp, "u_DepthTexture", Int32(0))
    set_uniform!(sp, "u_InvViewProj", inv_view_proj)
    set_uniform!(sp, "u_PrevViewProj", prev_view_proj)
    set_uniform!(sp, "u_MaxVelocity", config.motion_blur_max_velocity)
    _render_fullscreen_quad(quad_vao)

    # 2. Directional blur along velocity vectors
    glBindFramebuffer(GL_FRAMEBUFFER, pass.blur_fbo.fbo)
    glViewport(0, 0, pass.width, pass.height)
    glClear(GL_COLOR_BUFFER_BIT)
    sp = pass.blur_shader
    glUseProgram(sp.id)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, scene_texture)
    set_uniform!(sp, "u_SceneTexture", Int32(0))
    glActiveTexture(GL_TEXTURE1)
    glBindTexture(GL_TEXTURE_2D, pass.velocity_fbo.color_texture)
    set_uniform!(sp, "u_VelocityTexture", Int32(1))
    set_uniform!(sp, "u_Samples", Int32(config.motion_blur_samples))
    set_uniform!(sp, "u_Intensity", config.motion_blur_intensity)
    _render_fullscreen_quad(quad_vao)

    return pass.blur_fbo.color_texture
end

# ---- RG16F framebuffer helper ----

function _create_rg16f_framebuffer!(fb::Framebuffer, width::Int, height::Int)
    fbo_ref = Ref(GLuint(0))
    glGenFramebuffers(1, fbo_ref)
    fb.fbo = fbo_ref[]
    fb.width = width
    fb.height = height

    glBindFramebuffer(GL_FRAMEBUFFER, fb.fbo)

    tex_ref = Ref(GLuint(0))
    glGenTextures(1, tex_ref)
    fb.color_texture = tex_ref[]
    glBindTexture(GL_TEXTURE_2D, fb.color_texture)
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RG16F, width, height, 0, GL_RG, GL_FLOAT, C_NULL)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, fb.color_texture, 0)

    glBindFramebuffer(GL_FRAMEBUFFER, GLuint(0))
    return nothing
end

function _resize_rg16f_framebuffer!(fb::Framebuffer, width::Int, height::Int)
    fb.width = width
    fb.height = height
    if fb.color_texture != GLuint(0)
        glBindTexture(GL_TEXTURE_2D, fb.color_texture)
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RG16F, width, height, 0, GL_RG, GL_FLOAT, C_NULL)
    end
    return nothing
end
