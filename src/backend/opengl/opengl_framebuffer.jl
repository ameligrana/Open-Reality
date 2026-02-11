# OpenGL framebuffer and G-buffer implementation

# ── Type definitions ────────────────────────────────────────────────

"""
    Framebuffer

Off-screen render target with an HDR (RGBA16F) color texture and a
depth renderbuffer.
"""
mutable struct Framebuffer <: AbstractFramebuffer
    fbo::GLuint
    color_texture::GLuint    # GL_RGBA16F
    depth_rbo::GLuint        # GL_DEPTH_COMPONENT24
    width::Int
    height::Int

    Framebuffer(; width::Int=1280, height::Int=720) =
        new(GLuint(0), GLuint(0), GLuint(0), width, height)
end

get_width(fb::Framebuffer) = fb.width
get_height(fb::Framebuffer) = fb.height

# G-Buffer: Multiple Render Targets for Deferred Rendering
# MRT Layout:
#   - MRT 0 (RGBA16F): RGB = albedo (linear), A = metallic
#   - MRT 1 (RGBA16F): RGB = world-space normal (packed), A = roughness
#   - MRT 2 (RGBA16F): RGB = emissive, A = ambient occlusion
#   - MRT 3 (RGBA8):   R = clearcoat, G = clearcoat_roughness, B = subsurface, A = reserved
#   - Depth: GL_DEPTH_COMPONENT24 (shared with final framebuffer)

"""
    GBuffer

G-Buffer for deferred rendering with 4 color attachments and depth.
Stores material properties for the lighting pass.
"""
mutable struct GBuffer <: AbstractGBuffer
    fbo::GLuint
    albedo_metallic_texture::GLuint      # MRT 0: RGBA16F
    normal_roughness_texture::GLuint     # MRT 1: RGBA16F
    emissive_ao_texture::GLuint          # MRT 2: RGBA16F
    advanced_material_texture::GLuint    # MRT 3: RGBA8 (clearcoat, SSS, etc.)
    depth_texture::GLuint                # Depth texture (can be sampled in shaders)
    width::Int
    height::Int

    GBuffer(; width::Int=1280, height::Int=720) =
        new(GLuint(0), GLuint(0), GLuint(0), GLuint(0), GLuint(0), GLuint(0), width, height)
end

get_width(gb::GBuffer) = gb.width
get_height(gb::GBuffer) = gb.height

# ── Framebuffer functions ─────────────────────────────────────────────

"""
    create_framebuffer!(fb::Framebuffer, width::Int, height::Int)

Allocate GPU resources for the framebuffer.
"""
function create_framebuffer!(fb::Framebuffer, width::Int, height::Int)
    fb.width = width
    fb.height = height

    # Color texture (HDR)
    tex_ref = Ref(GLuint(0))
    glGenTextures(1, tex_ref)
    fb.color_texture = tex_ref[]
    glBindTexture(GL_TEXTURE_2D, fb.color_texture)
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F, width, height, 0, GL_RGBA, GL_FLOAT, C_NULL)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)

    # Depth renderbuffer
    rbo_ref = Ref(GLuint(0))
    glGenRenderbuffers(1, rbo_ref)
    fb.depth_rbo = rbo_ref[]
    glBindRenderbuffer(GL_RENDERBUFFER, fb.depth_rbo)
    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT24, width, height)

    # FBO
    fbo_ref = Ref(GLuint(0))
    glGenFramebuffers(1, fbo_ref)
    fb.fbo = fbo_ref[]
    glBindFramebuffer(GL_FRAMEBUFFER, fb.fbo)
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, fb.color_texture, 0)
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, fb.depth_rbo)

    glBindFramebuffer(GL_FRAMEBUFFER, GLuint(0))
    return nothing
end

"""
    destroy_framebuffer!(fb::Framebuffer)

Release GPU resources.
"""
function destroy_framebuffer!(fb::Framebuffer)
    if fb.fbo != GLuint(0)
        glDeleteFramebuffers(1, Ref(fb.fbo))
        fb.fbo = GLuint(0)
    end
    if fb.color_texture != GLuint(0)
        glDeleteTextures(1, Ref(fb.color_texture))
        fb.color_texture = GLuint(0)
    end
    if fb.depth_rbo != GLuint(0)
        glDeleteRenderbuffers(1, Ref(fb.depth_rbo))
        fb.depth_rbo = GLuint(0)
    end
    return nothing
end

"""
    resize_framebuffer!(fb::Framebuffer, width::Int, height::Int)

Destroy and recreate at new dimensions.
"""
function resize_framebuffer!(fb::Framebuffer, width::Int, height::Int)
    destroy_framebuffer!(fb)
    create_framebuffer!(fb, width, height)
end

# ── G-Buffer functions ────────────────────────────────────────────────

"""
    create_gbuffer!(gb::GBuffer, width::Int, height::Int)

Allocate GPU resources for the G-Buffer with multiple render targets.
"""
function create_gbuffer!(gb::GBuffer, width::Int, height::Int)
    gb.width = width
    gb.height = height

    # Generate FBO
    fbo_ref = Ref(GLuint(0))
    glGenFramebuffers(1, fbo_ref)
    gb.fbo = fbo_ref[]
    glBindFramebuffer(GL_FRAMEBUFFER, gb.fbo)

    # MRT 0: Albedo (RGB) + Metallic (A)
    tex_ref = Ref(GLuint(0))
    glGenTextures(1, tex_ref)
    gb.albedo_metallic_texture = tex_ref[]
    glBindTexture(GL_TEXTURE_2D, gb.albedo_metallic_texture)
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F, width, height, 0, GL_RGBA, GL_FLOAT, C_NULL)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, gb.albedo_metallic_texture, 0)

    # MRT 1: Normal (RGB) + Roughness (A)
    tex_ref = Ref(GLuint(0))
    glGenTextures(1, tex_ref)
    gb.normal_roughness_texture = tex_ref[]
    glBindTexture(GL_TEXTURE_2D, gb.normal_roughness_texture)
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F, width, height, 0, GL_RGBA, GL_FLOAT, C_NULL)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT1, GL_TEXTURE_2D, gb.normal_roughness_texture, 0)

    # MRT 2: Emissive (RGB) + AO (A)
    tex_ref = Ref(GLuint(0))
    glGenTextures(1, tex_ref)
    gb.emissive_ao_texture = tex_ref[]
    glBindTexture(GL_TEXTURE_2D, gb.emissive_ao_texture)
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F, width, height, 0, GL_RGBA, GL_FLOAT, C_NULL)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT2, GL_TEXTURE_2D, gb.emissive_ao_texture, 0)

    # MRT 3: Advanced material data (clearcoat, SSS, etc.) — RGBA8 is sufficient for [0,1] values
    tex_ref = Ref(GLuint(0))
    glGenTextures(1, tex_ref)
    gb.advanced_material_texture = tex_ref[]
    glBindTexture(GL_TEXTURE_2D, gb.advanced_material_texture)
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, C_NULL)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT3, GL_TEXTURE_2D, gb.advanced_material_texture, 0)

    # Depth texture (can be sampled for SSR, SSAO, etc.)
    tex_ref = Ref(GLuint(0))
    glGenTextures(1, tex_ref)
    gb.depth_texture = tex_ref[]
    glBindTexture(GL_TEXTURE_2D, gb.depth_texture)
    glTexImage2D(GL_TEXTURE_2D, 0, GL_DEPTH_COMPONENT24, width, height, 0, GL_DEPTH_COMPONENT, GL_FLOAT, C_NULL)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D, gb.depth_texture, 0)

    # Specify which color attachments to use for rendering (MRT)
    attachments = GLenum[GL_COLOR_ATTACHMENT0, GL_COLOR_ATTACHMENT1, GL_COLOR_ATTACHMENT2, GL_COLOR_ATTACHMENT3]
    glDrawBuffers(GLsizei(4), pointer(attachments))

    # Verify framebuffer completeness
    status = glCheckFramebufferStatus(GL_FRAMEBUFFER)
    if status != GL_FRAMEBUFFER_COMPLETE
        error("G-Buffer framebuffer is incomplete! Status: $status")
    end

    glBindFramebuffer(GL_FRAMEBUFFER, GLuint(0))
    return nothing
end

"""
    destroy_gbuffer!(gb::GBuffer)

Release GPU resources for the G-Buffer.
"""
function destroy_gbuffer!(gb::GBuffer)
    if gb.fbo != GLuint(0)
        glDeleteFramebuffers(1, Ref(gb.fbo))
        gb.fbo = GLuint(0)
    end
    if gb.albedo_metallic_texture != GLuint(0)
        glDeleteTextures(1, Ref(gb.albedo_metallic_texture))
        gb.albedo_metallic_texture = GLuint(0)
    end
    if gb.normal_roughness_texture != GLuint(0)
        glDeleteTextures(1, Ref(gb.normal_roughness_texture))
        gb.normal_roughness_texture = GLuint(0)
    end
    if gb.emissive_ao_texture != GLuint(0)
        glDeleteTextures(1, Ref(gb.emissive_ao_texture))
        gb.emissive_ao_texture = GLuint(0)
    end
    if gb.advanced_material_texture != GLuint(0)
        glDeleteTextures(1, Ref(gb.advanced_material_texture))
        gb.advanced_material_texture = GLuint(0)
    end
    if gb.depth_texture != GLuint(0)
        glDeleteTextures(1, Ref(gb.depth_texture))
        gb.depth_texture = GLuint(0)
    end
    return nothing
end

"""
    resize_gbuffer!(gb::GBuffer, width::Int, height::Int)

Destroy and recreate G-Buffer at new dimensions.
"""
function resize_gbuffer!(gb::GBuffer, width::Int, height::Int)
    destroy_gbuffer!(gb)
    create_gbuffer!(gb, width, height)
end

"""
    bind_gbuffer_for_write!(gb::GBuffer)

Bind G-Buffer for writing (geometry pass).
"""
function bind_gbuffer_for_write!(gb::GBuffer)
    glBindFramebuffer(GL_FRAMEBUFFER, gb.fbo)
    # Ensure all 4 color attachments are active for writing
    attachments = GLenum[GL_COLOR_ATTACHMENT0, GL_COLOR_ATTACHMENT1, GL_COLOR_ATTACHMENT2, GL_COLOR_ATTACHMENT3]
    glDrawBuffers(GLsizei(4), pointer(attachments))
    return nothing
end

"""
    bind_gbuffer_textures_for_read!(gb::GBuffer, start_unit::Int=0)

Bind G-Buffer textures for reading in shaders.
Returns the next available texture unit.

Bindings:
- start_unit + 0: albedo_metallic
- start_unit + 1: normal_roughness
- start_unit + 2: emissive_ao
- start_unit + 3: depth
- start_unit + 4: advanced_material
"""
function bind_gbuffer_textures_for_read!(gb::GBuffer, start_unit::Int=0)
    glActiveTexture(GL_TEXTURE0 + start_unit)
    glBindTexture(GL_TEXTURE_2D, gb.albedo_metallic_texture)

    glActiveTexture(GL_TEXTURE0 + start_unit + 1)
    glBindTexture(GL_TEXTURE_2D, gb.normal_roughness_texture)

    glActiveTexture(GL_TEXTURE0 + start_unit + 2)
    glBindTexture(GL_TEXTURE_2D, gb.emissive_ao_texture)

    glActiveTexture(GL_TEXTURE0 + start_unit + 3)
    glBindTexture(GL_TEXTURE_2D, gb.depth_texture)

    glActiveTexture(GL_TEXTURE0 + start_unit + 4)
    glBindTexture(GL_TEXTURE_2D, gb.advanced_material_texture)

    return start_unit + 5
end

"""
    unbind_framebuffer!()

Unbind framebuffer (bind default framebuffer).
"""
function unbind_framebuffer!()
    glBindFramebuffer(GL_FRAMEBUFFER, GLuint(0))
    return nothing
end
