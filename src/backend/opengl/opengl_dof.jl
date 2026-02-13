# OpenGL Depth of Field pass

"""
    DOFPass <: AbstractDOFPass

Circle-of-Confusion based depth of field with separable bokeh blur.
Pipeline: CoC computation → separable blur weighted by CoC → composite.
"""
mutable struct DOFPass <: AbstractDOFPass
    coc_fbo::Framebuffer        # R16F — Circle of Confusion per pixel
    blur_fbo_h::Framebuffer     # RGBA16F — horizontal blur result
    blur_fbo_v::Framebuffer     # RGBA16F — vertical blur result (final blurred)
    coc_shader::Union{ShaderProgram, Nothing}
    blur_shader::Union{ShaderProgram, Nothing}
    composite_shader::Union{ShaderProgram, Nothing}
    width::Int
    height::Int

    DOFPass() = new(Framebuffer(), Framebuffer(), Framebuffer(),
                    nothing, nothing, nothing, 0, 0)
end

# ---- GLSL shaders ----

const DOF_COC_FRAGMENT = """
#version 330 core

in vec2 v_TexCoord;
out float FragColor;

uniform sampler2D u_DepthTexture;
uniform float u_FocusDistance;
uniform float u_FocusRange;
uniform float u_NearPlane;
uniform float u_FarPlane;

float linearize_depth(float d)
{
    float z = d * 2.0 - 1.0;
    return (2.0 * u_NearPlane * u_FarPlane) / (u_FarPlane + u_NearPlane - z * (u_FarPlane - u_NearPlane));
}

void main()
{
    float depth = texture(u_DepthTexture, v_TexCoord).r;
    float linear_depth = linearize_depth(depth);

    // CoC: distance from focus plane, normalized by focus range
    float coc = clamp(abs(linear_depth - u_FocusDistance) / u_FocusRange, 0.0, 1.0);
    FragColor = coc;
}
"""

const DOF_BLUR_FRAGMENT = """
#version 330 core

in vec2 v_TexCoord;
out vec4 FragColor;

uniform sampler2D u_SceneTexture;
uniform sampler2D u_CoCTexture;
uniform int u_Horizontal;
uniform float u_BokehRadius;

// 9-tap Gaussian kernel
const float weights[9] = float[](0.0625, 0.09375, 0.125, 0.15625, 0.15625, 0.15625, 0.125, 0.09375, 0.0625);

void main()
{
    vec2 texel_size = 1.0 / textureSize(u_SceneTexture, 0);
    float center_coc = texture(u_CoCTexture, v_TexCoord).r;

    vec3 result = vec3(0.0);
    float total_weight = 0.0;

    for (int i = -4; i <= 4; ++i) {
        vec2 offset = u_Horizontal == 1
            ? vec2(texel_size.x * float(i) * u_BokehRadius, 0.0)
            : vec2(0.0, texel_size.y * float(i) * u_BokehRadius);

        vec2 sample_uv = v_TexCoord + offset;
        float sample_coc = texture(u_CoCTexture, sample_uv).r;

        // Weight by max of center and sample CoC to prevent sharp objects bleeding into blur
        float w = weights[i + 4] * max(center_coc, sample_coc);
        result += texture(u_SceneTexture, sample_uv).rgb * w;
        total_weight += w;
    }

    if (total_weight > 0.0)
        result /= total_weight;
    else
        result = texture(u_SceneTexture, v_TexCoord).rgb;

    FragColor = vec4(result, 1.0);
}
"""

const DOF_COMPOSITE_FRAGMENT = """
#version 330 core

in vec2 v_TexCoord;
out vec4 FragColor;

uniform sampler2D u_SharpTexture;
uniform sampler2D u_BlurredTexture;
uniform sampler2D u_CoCTexture;

void main()
{
    vec3 sharp = texture(u_SharpTexture, v_TexCoord).rgb;
    vec3 blurred = texture(u_BlurredTexture, v_TexCoord).rgb;
    float coc = texture(u_CoCTexture, v_TexCoord).r;

    // Smooth blend between sharp and blurred based on CoC
    vec3 color = mix(sharp, blurred, smoothstep(0.0, 1.0, coc));
    FragColor = vec4(color, 1.0);
}
"""

# ---- Lifecycle ----

function create_dof_pass!(pass::DOFPass, width::Int, height::Int)
    half_w = max(1, width ÷ 2)
    half_h = max(1, height ÷ 2)
    pass.width = width
    pass.height = height

    # CoC texture at full resolution (R16F)
    pass.coc_fbo = Framebuffer()
    _create_r16f_framebuffer!(pass.coc_fbo, width, height)

    # Blur FBOs at half resolution
    create_framebuffer!(pass.blur_fbo_h, half_w, half_h)
    create_framebuffer!(pass.blur_fbo_v, half_w, half_h)

    # Compile shaders (reuse PP_QUAD_VERTEX from opengl_postprocess.jl)
    pass.coc_shader = create_shader_program(PP_QUAD_VERTEX, DOF_COC_FRAGMENT)
    pass.blur_shader = create_shader_program(PP_QUAD_VERTEX, DOF_BLUR_FRAGMENT)
    pass.composite_shader = create_shader_program(PP_QUAD_VERTEX, DOF_COMPOSITE_FRAGMENT)

    return nothing
end

function destroy_dof_pass!(pass::DOFPass)
    destroy_framebuffer!(pass.coc_fbo)
    destroy_framebuffer!(pass.blur_fbo_h)
    destroy_framebuffer!(pass.blur_fbo_v)
    for field in (:coc_shader, :blur_shader, :composite_shader)
        sp = getfield(pass, field)
        if sp !== nothing
            destroy_shader_program!(sp)
            setfield!(pass, field, nothing)
        end
    end
    return nothing
end

function resize_dof_pass!(pass::DOFPass, width::Int, height::Int)
    pass.width = width
    pass.height = height
    half_w = max(1, width ÷ 2)
    half_h = max(1, height ÷ 2)
    _resize_r16f_framebuffer!(pass.coc_fbo, width, height)
    resize_framebuffer!(pass.blur_fbo_h, half_w, half_h)
    resize_framebuffer!(pass.blur_fbo_v, half_w, half_h)
    return nothing
end

"""
    render_dof!(pass, scene_texture, depth_texture, config, quad_vao, output_fbo) -> GLuint

Execute DoF pipeline. Returns the texture containing the DoF result.
Renders into output_fbo.
"""
function render_dof!(pass::DOFPass, scene_texture::GLuint, depth_texture::GLuint,
                     config::PostProcessConfig, quad_vao::GLuint,
                     output_fbo::Framebuffer)
    # 1. CoC pass
    glBindFramebuffer(GL_FRAMEBUFFER, pass.coc_fbo.fbo)
    glViewport(0, 0, pass.width, pass.height)
    glClear(GL_COLOR_BUFFER_BIT)
    sp = pass.coc_shader
    glUseProgram(sp.id)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, depth_texture)
    set_uniform!(sp, "u_DepthTexture", Int32(0))
    set_uniform!(sp, "u_FocusDistance", config.dof_focus_distance)
    set_uniform!(sp, "u_FocusRange", config.dof_focus_range)
    set_uniform!(sp, "u_NearPlane", 0.1f0)
    set_uniform!(sp, "u_FarPlane", 500.0f0)
    _render_fullscreen_quad(quad_vao)

    # 2. Horizontal blur
    half_w = max(1, pass.width ÷ 2)
    half_h = max(1, pass.height ÷ 2)
    glBindFramebuffer(GL_FRAMEBUFFER, pass.blur_fbo_h.fbo)
    glViewport(0, 0, half_w, half_h)
    glClear(GL_COLOR_BUFFER_BIT)
    sp = pass.blur_shader
    glUseProgram(sp.id)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, scene_texture)
    set_uniform!(sp, "u_SceneTexture", Int32(0))
    glActiveTexture(GL_TEXTURE1)
    glBindTexture(GL_TEXTURE_2D, pass.coc_fbo.color_texture)
    set_uniform!(sp, "u_CoCTexture", Int32(1))
    set_uniform!(sp, "u_Horizontal", Int32(1))
    set_uniform!(sp, "u_BokehRadius", config.dof_bokeh_radius)
    _render_fullscreen_quad(quad_vao)

    # 3. Vertical blur
    glBindFramebuffer(GL_FRAMEBUFFER, pass.blur_fbo_v.fbo)
    glViewport(0, 0, half_w, half_h)
    glClear(GL_COLOR_BUFFER_BIT)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, pass.blur_fbo_h.color_texture)
    set_uniform!(sp, "u_SceneTexture", Int32(0))
    set_uniform!(sp, "u_Horizontal", Int32(0))
    _render_fullscreen_quad(quad_vao)

    # 4. Composite: blend sharp + blurred by CoC
    glBindFramebuffer(GL_FRAMEBUFFER, output_fbo.fbo)
    glViewport(0, 0, output_fbo.width, output_fbo.height)
    glClear(GL_COLOR_BUFFER_BIT)
    sp = pass.composite_shader
    glUseProgram(sp.id)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, scene_texture)
    set_uniform!(sp, "u_SharpTexture", Int32(0))
    glActiveTexture(GL_TEXTURE1)
    glBindTexture(GL_TEXTURE_2D, pass.blur_fbo_v.color_texture)
    set_uniform!(sp, "u_BlurredTexture", Int32(1))
    glActiveTexture(GL_TEXTURE2)
    glBindTexture(GL_TEXTURE_2D, pass.coc_fbo.color_texture)
    set_uniform!(sp, "u_CoCTexture", Int32(2))
    _render_fullscreen_quad(quad_vao)

    return output_fbo.color_texture
end

# ---- R16F framebuffer helper ----

function _create_r16f_framebuffer!(fb::Framebuffer, width::Int, height::Int)
    fbo_ref = Ref(GLuint(0))
    glGenFramebuffers(1, fbo_ref)
    fb.fbo = fbo_ref[]
    fb.width = width
    fb.height = height

    glBindFramebuffer(GL_FRAMEBUFFER, fb.fbo)

    # R16F color attachment
    tex_ref = Ref(GLuint(0))
    glGenTextures(1, tex_ref)
    fb.color_texture = tex_ref[]
    glBindTexture(GL_TEXTURE_2D, fb.color_texture)
    glTexImage2D(GL_TEXTURE_2D, 0, GL_R16F, width, height, 0, GL_RED, GL_FLOAT, C_NULL)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, fb.color_texture, 0)

    glBindFramebuffer(GL_FRAMEBUFFER, GLuint(0))
    return nothing
end

function _resize_r16f_framebuffer!(fb::Framebuffer, width::Int, height::Int)
    fb.width = width
    fb.height = height
    if fb.color_texture != GLuint(0)
        glBindTexture(GL_TEXTURE_2D, fb.color_texture)
        glTexImage2D(GL_TEXTURE_2D, 0, GL_R16F, width, height, 0, GL_RED, GL_FLOAT, C_NULL)
    end
    return nothing
end
