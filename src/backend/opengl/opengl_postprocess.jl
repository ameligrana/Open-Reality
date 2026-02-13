# OpenGL post-processing implementation

# ---- Type definition ----

"""
    PostProcessPipeline <: AbstractPostProcessPipeline

Owns all GPU resources for post-processing effects.
"""
mutable struct PostProcessPipeline <: AbstractPostProcessPipeline
    config::PostProcessConfig
    scene_fbo::Framebuffer
    bloom_fbos::Vector{Framebuffer}
    bright_fbo::Framebuffer
    quad_vao::GLuint
    quad_vbo::GLuint
    composite_shader::Union{ShaderProgram, Nothing}
    bright_extract_shader::Union{ShaderProgram, Nothing}
    blur_shader::Union{ShaderProgram, Nothing}
    fxaa_shader::Union{ShaderProgram, Nothing}
    dof_pass::Union{DOFPass, Nothing}
    motion_blur_pass::Union{MotionBlurPass, Nothing}
    dof_temp_fbo::Framebuffer   # Temp FBO for DoF output

    PostProcessPipeline(; config::PostProcessConfig = PostProcessConfig()) =
        new(config, Framebuffer(), Framebuffer[], Framebuffer(),
            GLuint(0), GLuint(0), nothing, nothing, nothing, nothing,
            nothing, nothing, Framebuffer())
end

# ---- Shader sources ----

const PP_QUAD_VERTEX = """
#version 330 core

layout(location = 0) in vec2 a_Position;
layout(location = 1) in vec2 a_TexCoord;

out vec2 v_TexCoord;

void main()
{
    v_TexCoord = a_TexCoord;
    gl_Position = vec4(a_Position, 0.0, 1.0);
}
"""

const PP_BRIGHT_EXTRACT_FRAGMENT = """
#version 330 core

in vec2 v_TexCoord;
out vec4 FragColor;

uniform sampler2D u_SceneTexture;
uniform float u_Threshold;

void main()
{
    vec3 color = texture(u_SceneTexture, v_TexCoord).rgb;
    float brightness = dot(color, vec3(0.2126, 0.7152, 0.0722));
    if (brightness > u_Threshold)
        FragColor = vec4(color, 1.0);
    else
        FragColor = vec4(0.0, 0.0, 0.0, 1.0);
}
"""

const PP_BLUR_FRAGMENT = """
#version 330 core

in vec2 v_TexCoord;
out vec4 FragColor;

uniform sampler2D u_Image;
uniform int u_Horizontal;

// 5-tap Gaussian weights
const float weight[5] = float[](0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216);

void main()
{
    vec2 texel_size = 1.0 / textureSize(u_Image, 0);
    vec3 result = texture(u_Image, v_TexCoord).rgb * weight[0];

    if (u_Horizontal == 1) {
        for (int i = 1; i < 5; ++i) {
            result += texture(u_Image, v_TexCoord + vec2(texel_size.x * float(i), 0.0)).rgb * weight[i];
            result += texture(u_Image, v_TexCoord - vec2(texel_size.x * float(i), 0.0)).rgb * weight[i];
        }
    } else {
        for (int i = 1; i < 5; ++i) {
            result += texture(u_Image, v_TexCoord + vec2(0.0, texel_size.y * float(i))).rgb * weight[i];
            result += texture(u_Image, v_TexCoord - vec2(0.0, texel_size.y * float(i))).rgb * weight[i];
        }
    }

    FragColor = vec4(result, 1.0);
}
"""

const PP_COMPOSITE_FRAGMENT = """
#version 330 core

in vec2 v_TexCoord;
out vec4 FragColor;

uniform sampler2D u_SceneTexture;
uniform sampler2D u_BloomTexture;
uniform int u_BloomEnabled;
uniform float u_BloomIntensity;
uniform int u_ToneMapping;   // 0 = Reinhard, 1 = ACES, 2 = Uncharted2
uniform float u_Gamma;

// Vignette uniforms
uniform int u_VignetteEnabled;
uniform float u_VignetteIntensity;
uniform float u_VignetteRadius;
uniform float u_VignetteSoftness;

// Color grading uniforms
uniform int u_ColorGradingEnabled;
uniform float u_Brightness;
uniform float u_Contrast;
uniform float u_Saturation;

// ACES tone mapping
vec3 ACESFilm(vec3 x)
{
    float a = 2.51;
    float b = 0.03;
    float c = 2.43;
    float d = 0.59;
    float e = 0.14;
    return clamp((x*(a*x+b))/(x*(c*x+d)+e), 0.0, 1.0);
}

// Uncharted 2 tone mapping
vec3 Uncharted2Helper(vec3 x)
{
    float A = 0.15; float B = 0.50; float C = 0.10;
    float D = 0.20; float E = 0.02; float F = 0.30;
    return ((x*(A*x+C*B)+D*E)/(x*(A*x+B)+D*F))-E/F;
}

vec3 Uncharted2(vec3 color)
{
    float W = 11.2;
    vec3 curr = Uncharted2Helper(color * 2.0);
    vec3 white_scale = vec3(1.0) / Uncharted2Helper(vec3(W));
    return curr * white_scale;
}

void main()
{
    vec3 color = texture(u_SceneTexture, v_TexCoord).rgb;

    // Add bloom
    if (u_BloomEnabled == 1) {
        vec3 bloom = texture(u_BloomTexture, v_TexCoord).rgb;
        color += bloom * u_BloomIntensity;
    }

    // Tone mapping
    if (u_ToneMapping == 0)
        color = color / (color + vec3(1.0));           // Reinhard
    else if (u_ToneMapping == 1)
        color = ACESFilm(color);                       // ACES
    else if (u_ToneMapping == 2)
        color = Uncharted2(color);                     // Uncharted 2

    // Color grading (applied in LDR after tone mapping)
    if (u_ColorGradingEnabled == 1) {
        // Brightness
        color += vec3(u_Brightness);

        // Contrast (pivot around mid-gray 0.5)
        color = (color - 0.5) * u_Contrast + 0.5;

        // Saturation
        float luminance = dot(color, vec3(0.2126, 0.7152, 0.0722));
        color = mix(vec3(luminance), color, u_Saturation);

        color = clamp(color, 0.0, 1.0);
    }

    // Vignette (darkens edges of the screen)
    if (u_VignetteEnabled == 1) {
        vec2 uv = v_TexCoord * 2.0 - 1.0;  // Remap to [-1, 1]
        float dist = length(uv);
        float vignette = 1.0 - smoothstep(u_VignetteRadius, u_VignetteRadius + u_VignetteSoftness, dist);
        color *= mix(1.0, vignette, u_VignetteIntensity);
    }

    // Gamma correction
    color = pow(color, vec3(1.0 / u_Gamma));

    FragColor = vec4(color, 1.0);
}
"""

const PP_FXAA_FRAGMENT = """
#version 330 core

in vec2 v_TexCoord;
out vec4 FragColor;

uniform sampler2D u_SceneTexture;
uniform vec2 u_InverseScreenSize;

void main()
{
    float FXAA_SPAN_MAX = 8.0;
    float FXAA_REDUCE_MUL = 1.0 / 8.0;
    float FXAA_REDUCE_MIN = 1.0 / 128.0;

    vec3 rgbNW = texture(u_SceneTexture, v_TexCoord + vec2(-1.0, -1.0) * u_InverseScreenSize).rgb;
    vec3 rgbNE = texture(u_SceneTexture, v_TexCoord + vec2( 1.0, -1.0) * u_InverseScreenSize).rgb;
    vec3 rgbSW = texture(u_SceneTexture, v_TexCoord + vec2(-1.0,  1.0) * u_InverseScreenSize).rgb;
    vec3 rgbSE = texture(u_SceneTexture, v_TexCoord + vec2( 1.0,  1.0) * u_InverseScreenSize).rgb;
    vec3 rgbM  = texture(u_SceneTexture, v_TexCoord).rgb;

    vec3 luma = vec3(0.299, 0.587, 0.114);
    float lumaNW = dot(rgbNW, luma);
    float lumaNE = dot(rgbNE, luma);
    float lumaSW = dot(rgbSW, luma);
    float lumaSE = dot(rgbSE, luma);
    float lumaM  = dot(rgbM,  luma);

    float lumaMin = min(lumaM, min(min(lumaNW, lumaNE), min(lumaSW, lumaSE)));
    float lumaMax = max(lumaM, max(max(lumaNW, lumaNE), max(lumaSW, lumaSE)));

    vec2 dir;
    dir.x = -((lumaNW + lumaNE) - (lumaSW + lumaSE));
    dir.y =  ((lumaNW + lumaSW) - (lumaNE + lumaSE));

    float dirReduce = max((lumaNW + lumaNE + lumaSW + lumaSE) * 0.25 * FXAA_REDUCE_MUL, FXAA_REDUCE_MIN);
    float rcpDirMin = 1.0 / (min(abs(dir.x), abs(dir.y)) + dirReduce);

    dir = min(vec2(FXAA_SPAN_MAX), max(vec2(-FXAA_SPAN_MAX), dir * rcpDirMin)) * u_InverseScreenSize;

    vec3 rgbA = 0.5 * (
        texture(u_SceneTexture, v_TexCoord + dir * (1.0/3.0 - 0.5)).rgb +
        texture(u_SceneTexture, v_TexCoord + dir * (2.0/3.0 - 0.5)).rgb);
    vec3 rgbB = rgbA * 0.5 + 0.25 * (
        texture(u_SceneTexture, v_TexCoord + dir * -0.5).rgb +
        texture(u_SceneTexture, v_TexCoord + dir *  0.5).rgb);

    float lumaB = dot(rgbB, luma);
    if (lumaB < lumaMin || lumaB > lumaMax)
        FragColor = vec4(rgbA, 1.0);
    else
        FragColor = vec4(rgbB, 1.0);
}
"""

# ---- Fullscreen quad ----

function _create_fullscreen_quad!()
    # Two triangles covering NDC [-1,1]
    quad_vertices = Float32[
        # positions   texcoords
        -1.0f0, -1.0f0,  0.0f0, 0.0f0,
         1.0f0, -1.0f0,  1.0f0, 0.0f0,
         1.0f0,  1.0f0,  1.0f0, 1.0f0,
        -1.0f0, -1.0f0,  0.0f0, 0.0f0,
         1.0f0,  1.0f0,  1.0f0, 1.0f0,
        -1.0f0,  1.0f0,  0.0f0, 1.0f0,
    ]

    vao_ref = Ref(GLuint(0))
    glGenVertexArrays(1, vao_ref)
    vao = vao_ref[]
    glBindVertexArray(vao)

    vbo_ref = Ref(GLuint(0))
    glGenBuffers(1, vbo_ref)
    vbo = vbo_ref[]
    glBindBuffer(GL_ARRAY_BUFFER, vbo)
    glBufferData(GL_ARRAY_BUFFER, sizeof(quad_vertices), quad_vertices, GL_STATIC_DRAW)

    # Position (location 0)
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(Float32), C_NULL)
    glEnableVertexAttribArray(0)
    # TexCoord (location 1)
    glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(Float32), Ptr{Cvoid}(2 * sizeof(Float32)))
    glEnableVertexAttribArray(1)

    glBindVertexArray(GLuint(0))
    return (vao, vbo)
end

function _render_fullscreen_quad(quad_vao::GLuint)
    glBindVertexArray(quad_vao)
    glDrawArrays(GL_TRIANGLES, 0, 6)
    glBindVertexArray(GLuint(0))
end

# ---- Pipeline lifecycle ----

"""
    create_post_process_pipeline!(pp::PostProcessPipeline, width::Int, height::Int)

Allocate all framebuffers, compile shaders, and create the fullscreen quad.
"""
function create_post_process_pipeline!(pp::PostProcessPipeline, width::Int, height::Int)
    # Scene FBO (full resolution HDR)
    create_framebuffer!(pp.scene_fbo, width, height)

    # Bloom FBOs (half resolution, ping-pong pair)
    half_w = max(1, width ÷ 2)
    half_h = max(1, height ÷ 2)
    pp.bloom_fbos = [Framebuffer(), Framebuffer()]
    create_framebuffer!(pp.bloom_fbos[1], half_w, half_h)
    create_framebuffer!(pp.bloom_fbos[2], half_w, half_h)

    # Bright extraction FBO (half resolution)
    pp.bright_fbo = Framebuffer()
    create_framebuffer!(pp.bright_fbo, half_w, half_h)

    # Fullscreen quad
    pp.quad_vao, pp.quad_vbo = _create_fullscreen_quad!()

    # Compile shaders
    pp.bright_extract_shader = create_shader_program(PP_QUAD_VERTEX, PP_BRIGHT_EXTRACT_FRAGMENT)
    pp.blur_shader = create_shader_program(PP_QUAD_VERTEX, PP_BLUR_FRAGMENT)
    pp.composite_shader = create_shader_program(PP_QUAD_VERTEX, PP_COMPOSITE_FRAGMENT)
    pp.fxaa_shader = create_shader_program(PP_QUAD_VERTEX, PP_FXAA_FRAGMENT)

    # DoF pass
    if pp.config.dof_enabled
        pp.dof_pass = DOFPass()
        create_dof_pass!(pp.dof_pass, width, height)
        pp.dof_temp_fbo = Framebuffer()
        create_framebuffer!(pp.dof_temp_fbo, width, height)
    end

    # Motion blur pass
    if pp.config.motion_blur_enabled
        pp.motion_blur_pass = MotionBlurPass()
        create_motion_blur_pass!(pp.motion_blur_pass, width, height)
    end

    return nothing
end

"""
    destroy_post_process_pipeline!(pp::PostProcessPipeline)

Release all GPU resources.
"""
function destroy_post_process_pipeline!(pp::PostProcessPipeline)
    destroy_framebuffer!(pp.scene_fbo)
    for fb in pp.bloom_fbos
        destroy_framebuffer!(fb)
    end
    destroy_framebuffer!(pp.bright_fbo)

    if pp.quad_vao != GLuint(0)
        glDeleteVertexArrays(1, Ref(pp.quad_vao))
        pp.quad_vao = GLuint(0)
    end
    if pp.quad_vbo != GLuint(0)
        glDeleteBuffers(1, Ref(pp.quad_vbo))
        pp.quad_vbo = GLuint(0)
    end

    for shader_field in (:composite_shader, :bright_extract_shader, :blur_shader, :fxaa_shader)
        sp = getfield(pp, shader_field)
        if sp !== nothing
            destroy_shader_program!(sp)
            setfield!(pp, shader_field, nothing)
        end
    end

    if pp.dof_pass !== nothing
        destroy_dof_pass!(pp.dof_pass)
        pp.dof_pass = nothing
        destroy_framebuffer!(pp.dof_temp_fbo)
    end

    if pp.motion_blur_pass !== nothing
        destroy_motion_blur_pass!(pp.motion_blur_pass)
        pp.motion_blur_pass = nothing
    end

    return nothing
end

"""
    resize_post_process!(pp::PostProcessPipeline, width::Int, height::Int)

Recreate all framebuffers at new dimensions.
"""
function resize_post_process!(pp::PostProcessPipeline, width::Int, height::Int)
    resize_framebuffer!(pp.scene_fbo, width, height)
    half_w = max(1, width ÷ 2)
    half_h = max(1, height ÷ 2)
    for fb in pp.bloom_fbos
        resize_framebuffer!(fb, half_w, half_h)
    end
    resize_framebuffer!(pp.bright_fbo, half_w, half_h)
    if pp.dof_pass !== nothing
        resize_dof_pass!(pp.dof_pass, width, height)
        resize_framebuffer!(pp.dof_temp_fbo, width, height)
    end
    if pp.motion_blur_pass !== nothing
        resize_motion_blur_pass!(pp.motion_blur_pass, width, height)
    end
end

# ---- Begin / End ----

"""
    begin_post_process!(pp::PostProcessPipeline)

Bind the HDR scene framebuffer so subsequent rendering goes to it.
"""
function begin_post_process!(pp::PostProcessPipeline)
    glBindFramebuffer(GL_FRAMEBUFFER, pp.scene_fbo.fbo)
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT)
end

"""
    end_post_process!(pp::PostProcessPipeline, screen_width::Int, screen_height::Int;
                      input_texture::GLuint = GLuint(0),
                      depth_texture::GLuint = GLuint(0),
                      view_proj::Mat4f = Mat4f(I),
                      prev_view_proj::Mat4f = Mat4f(I))

Execute the full post-processing chain and render to the default framebuffer.
When `input_texture` is provided (non-zero), it is used as the HDR source instead of
the internal scene FBO. This allows the deferred rendering path to feed its final
HDR output (after TAA) into the post-processing chain.

Chain order: Bloom → DoF → Motion Blur → Composite (tone mapping + vignette + color grading) → FXAA
"""
function end_post_process!(pp::PostProcessPipeline, screen_width::Int, screen_height::Int;
                           input_texture::GLuint = GLuint(0),
                           depth_texture::GLuint = GLuint(0),
                           view_proj::Mat4f = Mat4f(I),
                           prev_view_proj::Mat4f = Mat4f(I))
    # Use provided input texture or fall back to internal scene FBO
    scene_texture = input_texture != GLuint(0) ? input_texture : pp.scene_fbo.color_texture
    # Track the "current" HDR texture through the chain
    current_texture = scene_texture

    glBindFramebuffer(GL_FRAMEBUFFER, GLuint(0))
    glDisable(GL_DEPTH_TEST)

    bloom_texture = GLuint(0)

    # --- Bloom pass ---
    if pp.config.bloom_enabled && pp.bright_extract_shader !== nothing && pp.blur_shader !== nothing
        # 1. Extract bright pixels
        glBindFramebuffer(GL_FRAMEBUFFER, pp.bright_fbo.fbo)
        glViewport(0, 0, pp.bright_fbo.width, pp.bright_fbo.height)
        glClear(GL_COLOR_BUFFER_BIT)
        sp_bright = pp.bright_extract_shader
        glUseProgram(sp_bright.id)
        glActiveTexture(GL_TEXTURE0)
        glBindTexture(GL_TEXTURE_2D, current_texture)
        set_uniform!(sp_bright, "u_SceneTexture", Int32(0))
        set_uniform!(sp_bright, "u_Threshold", pp.config.bloom_threshold)
        _render_fullscreen_quad(pp.quad_vao)

        # 2. Gaussian blur (ping-pong, 5 iterations)
        horizontal = true
        first_iteration = true
        sp_blur = pp.blur_shader
        glUseProgram(sp_blur.id)

        for _ in 1:10
            idx = horizontal ? 1 : 2
            glBindFramebuffer(GL_FRAMEBUFFER, pp.bloom_fbos[idx].fbo)
            glViewport(0, 0, pp.bloom_fbos[idx].width, pp.bloom_fbos[idx].height)
            glClear(GL_COLOR_BUFFER_BIT)
            set_uniform!(sp_blur, "u_Horizontal", Int32(horizontal ? 1 : 0))
            glActiveTexture(GL_TEXTURE0)
            if first_iteration
                glBindTexture(GL_TEXTURE_2D, pp.bright_fbo.color_texture)
                first_iteration = false
            else
                other_idx = horizontal ? 2 : 1
                glBindTexture(GL_TEXTURE_2D, pp.bloom_fbos[other_idx].color_texture)
            end
            set_uniform!(sp_blur, "u_Image", Int32(0))
            _render_fullscreen_quad(pp.quad_vao)
            horizontal = !horizontal
        end

        bloom_texture = pp.bloom_fbos[2].color_texture
    end

    # --- Depth of Field pass ---
    if pp.config.dof_enabled && pp.dof_pass !== nothing && depth_texture != GLuint(0)
        current_texture = render_dof!(pp.dof_pass, current_texture, depth_texture,
                                       pp.config, pp.quad_vao, pp.dof_temp_fbo)
    end

    # --- Motion Blur pass ---
    if pp.config.motion_blur_enabled && pp.motion_blur_pass !== nothing && depth_texture != GLuint(0)
        current_texture = render_motion_blur!(pp.motion_blur_pass, current_texture, depth_texture,
                                               view_proj, prev_view_proj,
                                               pp.config, pp.quad_vao)
    end

    # --- Composite pass (tone mapping + bloom combine + vignette + color grading) ---
    if pp.config.fxaa_enabled && pp.fxaa_shader !== nothing
        # Render composite to scene_fbo (reuse as temp), then FXAA to screen
        glBindFramebuffer(GL_FRAMEBUFFER, pp.scene_fbo.fbo)
        glViewport(0, 0, pp.scene_fbo.width, pp.scene_fbo.height)
        glClear(GL_COLOR_BUFFER_BIT)
    else
        glBindFramebuffer(GL_FRAMEBUFFER, GLuint(0))
        glViewport(0, 0, screen_width, screen_height)
    end

    sp_comp = pp.composite_shader
    if sp_comp !== nothing
        glUseProgram(sp_comp.id)
        glActiveTexture(GL_TEXTURE0)
        glBindTexture(GL_TEXTURE_2D, current_texture)
        set_uniform!(sp_comp, "u_SceneTexture", Int32(0))

        if bloom_texture != GLuint(0)
            glActiveTexture(GL_TEXTURE1)
            glBindTexture(GL_TEXTURE_2D, bloom_texture)
            set_uniform!(sp_comp, "u_BloomTexture", Int32(1))
            set_uniform!(sp_comp, "u_BloomEnabled", Int32(1))
            set_uniform!(sp_comp, "u_BloomIntensity", pp.config.bloom_intensity)
        else
            set_uniform!(sp_comp, "u_BloomEnabled", Int32(0))
        end

        tone_map_idx = Int32(pp.config.tone_mapping == TONEMAP_REINHARD ? 0 :
                             pp.config.tone_mapping == TONEMAP_ACES ? 1 : 2)
        set_uniform!(sp_comp, "u_ToneMapping", tone_map_idx)
        set_uniform!(sp_comp, "u_Gamma", pp.config.gamma)

        # Vignette uniforms
        set_uniform!(sp_comp, "u_VignetteEnabled", Int32(pp.config.vignette_enabled ? 1 : 0))
        if pp.config.vignette_enabled
            set_uniform!(sp_comp, "u_VignetteIntensity", pp.config.vignette_intensity)
            set_uniform!(sp_comp, "u_VignetteRadius", pp.config.vignette_radius)
            set_uniform!(sp_comp, "u_VignetteSoftness", pp.config.vignette_softness)
        end

        # Color grading uniforms
        set_uniform!(sp_comp, "u_ColorGradingEnabled", Int32(pp.config.color_grading_enabled ? 1 : 0))
        if pp.config.color_grading_enabled
            set_uniform!(sp_comp, "u_Brightness", pp.config.color_grading_brightness)
            set_uniform!(sp_comp, "u_Contrast", pp.config.color_grading_contrast)
            set_uniform!(sp_comp, "u_Saturation", pp.config.color_grading_saturation)
        end

        _render_fullscreen_quad(pp.quad_vao)
    end

    # --- FXAA pass ---
    if pp.config.fxaa_enabled && pp.fxaa_shader !== nothing
        glBindFramebuffer(GL_FRAMEBUFFER, GLuint(0))
        glViewport(0, 0, screen_width, screen_height)
        sp_fxaa = pp.fxaa_shader
        glUseProgram(sp_fxaa.id)
        glActiveTexture(GL_TEXTURE0)
        glBindTexture(GL_TEXTURE_2D, pp.scene_fbo.color_texture)
        set_uniform!(sp_fxaa, "u_SceneTexture", Int32(0))
        set_uniform!(sp_fxaa, "u_InverseScreenSize", Vec2f(1.0f0 / screen_width, 1.0f0 / screen_height))
        _render_fullscreen_quad(pp.quad_vao)
    end

    glEnable(GL_DEPTH_TEST)
    return nothing
end
