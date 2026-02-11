# OpenGL IBL (Image-Based Lighting) implementation

# ---- Type definition ----

"""
    IBLEnvironment

Stores precomputed IBL textures for PBR rendering.
Uses split-sum approximation for real-time IBL.
"""
mutable struct IBLEnvironment <: AbstractIBLEnvironment
    environment_map::GLuint      # Original HDR cubemap (for skybox)
    irradiance_map::GLuint       # Diffuse irradiance convolution (32×32)
    prefilter_map::GLuint        # Specular prefiltered with roughness mips (128×128, 5 mips)
    brdf_lut::GLuint             # BRDF integration LUT (512×512, 2D texture)
    intensity::Float32           # Global intensity multiplier

    IBLEnvironment(; intensity::Float32 = 1.0f0) =
        new(GLuint(0), GLuint(0), GLuint(0), GLuint(0), intensity)
end

# ---- Shaders for IBL Preprocessing ----

const EQUIRECT_TO_CUBEMAP_VERTEX = """
#version 330 core
layout (location = 0) in vec3 a_Position;

out vec3 v_LocalPos;

uniform mat4 u_Projection;
uniform mat4 u_View;

void main()
{
    v_LocalPos = a_Position;
    gl_Position = u_Projection * u_View * vec4(a_Position, 1.0);
}
"""

const EQUIRECT_TO_CUBEMAP_FRAGMENT = """
#version 330 core
in vec3 v_LocalPos;
out vec4 FragColor;

uniform sampler2D u_EquirectangularMap;

const vec2 invAtan = vec2(0.1591, 0.3183);

vec2 sampleSphericalMap(vec3 v)
{
    vec2 uv = vec2(atan(v.z, v.x), asin(v.y));
    uv *= invAtan;
    uv += 0.5;
    return uv;
}

void main()
{
    vec2 uv = sampleSphericalMap(normalize(v_LocalPos));
    vec3 color = texture(u_EquirectangularMap, uv).rgb;
    FragColor = vec4(color, 1.0);
}
"""

const IRRADIANCE_CONVOLUTION_FRAGMENT = """
#version 330 core
in vec3 v_LocalPos;
out vec4 FragColor;

uniform samplerCube u_EnvironmentMap;

const float PI = 3.14159265359;

void main()
{
    // Sample direction
    vec3 N = normalize(v_LocalPos);

    vec3 irradiance = vec3(0.0);

    // Tangent space from N
    vec3 up    = vec3(0.0, 1.0, 0.0);
    vec3 right = normalize(cross(up, N));
    up         = normalize(cross(N, right));

    float sampleDelta = 0.025;
    float nrSamples = 0.0;

    for(float phi = 0.0; phi < 2.0 * PI; phi += sampleDelta)
    {
        for(float theta = 0.0; theta < 0.5 * PI; theta += sampleDelta)
        {
            // Spherical to cartesian (in tangent space)
            vec3 tangentSample = vec3(sin(theta) * cos(phi),  sin(theta) * sin(phi), cos(theta));
            // Tangent space to world
            vec3 sampleVec = tangentSample.x * right + tangentSample.y * up + tangentSample.z * N;

            irradiance += texture(u_EnvironmentMap, sampleVec).rgb * cos(theta) * sin(theta);
            nrSamples++;
        }
    }

    irradiance = PI * irradiance * (1.0 / float(nrSamples));

    FragColor = vec4(irradiance, 1.0);
}
"""

const PREFILTER_CONVOLUTION_FRAGMENT = """
#version 330 core
in vec3 v_LocalPos;
out vec4 FragColor;

uniform samplerCube u_EnvironmentMap;
uniform float u_Roughness;

const float PI = 3.14159265359;

float DistributionGGX(vec3 N, vec3 H, float roughness)
{
    float a = roughness * roughness;
    float a2 = a * a;
    float NdotH = max(dot(N, H), 0.0);
    float NdotH2 = NdotH * NdotH;

    float nom   = a2;
    float denom = (NdotH2 * (a2 - 1.0) + 1.0);
    denom = PI * denom * denom;

    return nom / denom;
}

// Hammersley sequence for low-discrepancy sampling
float RadicalInverse_VdC(uint bits)
{
    bits = (bits << 16u) | (bits >> 16u);
    bits = ((bits & 0x55555555u) << 1u) | ((bits & 0xAAAAAAAAu) >> 1u);
    bits = ((bits & 0x33333333u) << 2u) | ((bits & 0xCCCCCCCCu) >> 2u);
    bits = ((bits & 0x0F0F0F0Fu) << 4u) | ((bits & 0xF0F0F0F0u) >> 4u);
    bits = ((bits & 0x00FF00FFu) << 8u) | ((bits & 0xFF00FF00u) >> 8u);
    return float(bits) * 2.3283064365386963e-10; // / 0x100000000
}

vec2 Hammersley(uint i, uint N)
{
    return vec2(float(i)/float(N), RadicalInverse_VdC(i));
}

vec3 ImportanceSampleGGX(vec2 Xi, vec3 N, float roughness)
{
    float a = roughness * roughness;

    float phi = 2.0 * PI * Xi.x;
    float cosTheta = sqrt((1.0 - Xi.y) / (1.0 + (a*a - 1.0) * Xi.y));
    float sinTheta = sqrt(1.0 - cosTheta*cosTheta);

    // Spherical to cartesian
    vec3 H;
    H.x = cos(phi) * sinTheta;
    H.y = sin(phi) * sinTheta;
    H.z = cosTheta;

    // Tangent to world space
    vec3 up        = abs(N.z) < 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
    vec3 tangent   = normalize(cross(up, N));
    vec3 bitangent = cross(N, tangent);

    vec3 sampleVec = tangent * H.x + bitangent * H.y + N * H.z;
    return normalize(sampleVec);
}

void main()
{
    vec3 N = normalize(v_LocalPos);
    vec3 R = N;
    vec3 V = R;

    const uint SAMPLE_COUNT = 1024u;
    vec3 prefilteredColor = vec3(0.0);
    float totalWeight = 0.0;

    for(uint i = 0u; i < SAMPLE_COUNT; ++i)
    {
        vec2 Xi = Hammersley(i, SAMPLE_COUNT);
        vec3 H = ImportanceSampleGGX(Xi, N, u_Roughness);
        vec3 L = normalize(2.0 * dot(V, H) * H - V);

        float NdotL = max(dot(N, L), 0.0);
        if(NdotL > 0.0)
        {
            prefilteredColor += texture(u_EnvironmentMap, L).rgb * NdotL;
            totalWeight += NdotL;
        }
    }

    prefilteredColor = prefilteredColor / totalWeight;

    FragColor = vec4(prefilteredColor, 1.0);
}
"""

const BRDF_LUT_VERTEX = """
#version 330 core
layout (location = 0) in vec3 a_Position;
layout (location = 1) in vec2 a_TexCoord;

out vec2 v_TexCoord;

void main()
{
    v_TexCoord = a_TexCoord;
    gl_Position = vec4(a_Position, 1.0);
}
"""

const BRDF_LUT_FRAGMENT = """
#version 330 core
in vec2 v_TexCoord;
out vec2 FragColor;

const float PI = 3.14159265359;

float RadicalInverse_VdC(uint bits)
{
    bits = (bits << 16u) | (bits >> 16u);
    bits = ((bits & 0x55555555u) << 1u) | ((bits & 0xAAAAAAAAu) >> 1u);
    bits = ((bits & 0x33333333u) << 2u) | ((bits & 0xCCCCCCCCu) >> 2u);
    bits = ((bits & 0x0F0F0F0Fu) << 4u) | ((bits & 0xF0F0F0F0u) >> 4u);
    bits = ((bits & 0x00FF00FFu) << 8u) | ((bits & 0xFF00FF00u) >> 8u);
    return float(bits) * 2.3283064365386963e-10;
}

vec2 Hammersley(uint i, uint N)
{
    return vec2(float(i)/float(N), RadicalInverse_VdC(i));
}

vec3 ImportanceSampleGGX(vec2 Xi, vec3 N, float roughness)
{
    float a = roughness*roughness;

    float phi = 2.0 * PI * Xi.x;
    float cosTheta = sqrt((1.0 - Xi.y) / (1.0 + (a*a - 1.0) * Xi.y));
    float sinTheta = sqrt(1.0 - cosTheta*cosTheta);

    vec3 H;
    H.x = cos(phi) * sinTheta;
    H.y = sin(phi) * sinTheta;
    H.z = cosTheta;

    vec3 up        = abs(N.z) < 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
    vec3 tangent   = normalize(cross(up, N));
    vec3 bitangent = cross(N, tangent);

    vec3 sampleVec = tangent * H.x + bitangent * H.y + N * H.z;
    return normalize(sampleVec);
}

float GeometrySchlickGGX(float NdotV, float roughness)
{
    float a = roughness;
    float k = (a * a) / 2.0;

    float nom   = NdotV;
    float denom = NdotV * (1.0 - k) + k;

    return nom / denom;
}

float GeometrySmith(vec3 N, vec3 V, vec3 L, float roughness)
{
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    float ggx2 = GeometrySchlickGGX(NdotV, roughness);
    float ggx1 = GeometrySchlickGGX(NdotL, roughness);

    return ggx1 * ggx2;
}

vec2 IntegrateBRDF(float NdotV, float roughness)
{
    vec3 V;
    V.x = sqrt(1.0 - NdotV*NdotV);
    V.y = 0.0;
    V.z = NdotV;

    float A = 0.0;
    float B = 0.0;

    vec3 N = vec3(0.0, 0.0, 1.0);

    const uint SAMPLE_COUNT = 1024u;
    for(uint i = 0u; i < SAMPLE_COUNT; ++i)
    {
        vec2 Xi = Hammersley(i, SAMPLE_COUNT);
        vec3 H  = ImportanceSampleGGX(Xi, N, roughness);
        vec3 L  = normalize(2.0 * dot(V, H) * H - V);

        float NdotL = max(L.z, 0.0);
        float NdotH = max(H.z, 0.0);
        float VdotH = max(dot(V, H), 0.0);

        if(NdotL > 0.0)
        {
            float G = GeometrySmith(N, V, L, roughness);
            float G_Vis = (G * VdotH) / (NdotH * NdotV);
            float Fc = pow(1.0 - VdotH, 5.0);

            A += (1.0 - Fc) * G_Vis;
            B += Fc * G_Vis;
        }
    }

    A /= float(SAMPLE_COUNT);
    B /= float(SAMPLE_COUNT);
    return vec2(A, B);
}

void main()
{
    vec2 integratedBRDF = IntegrateBRDF(v_TexCoord.x, v_TexCoord.y);
    FragColor = integratedBRDF;
}
"""

# =============================================================================
# IBL Creation and Preprocessing
# =============================================================================

"""
    create_ibl_environment!(env::IBLEnvironment, hdr_path::String)

Load HDR environment map and precompute IBL textures.
This is computationally expensive and should be done once at load time.
"""
function create_ibl_environment!(env::IBLEnvironment, hdr_path::String)
    @info "Creating IBL environment from HDR" path=hdr_path

    # TODO: Load HDR image (requires HDR loader - FileIO with proper format support)
    # For now, we'll create placeholder textures
    # In a full implementation, you'd use something like:
    # hdr_image = load(hdr_path)  # Returns RGB{Float32} array

    # Create cubemap from equirectangular map
    env.environment_map = create_environment_cubemap(hdr_path)

    # Generate irradiance map (diffuse convolution)
    env.irradiance_map = generate_irradiance_map(env.environment_map)

    # Generate prefiltered specular map
    env.prefilter_map = generate_prefilter_map(env.environment_map)

    # Generate BRDF LUT (can be cached and reused across environments)
    env.brdf_lut = generate_brdf_lut()

    @info "IBL environment created successfully"
    return nothing
end

"""
Helper to create a simple cube mesh for rendering cubemaps
"""
function create_cube_vao()
    vertices = Float32[
        # positions
        -1.0,  1.0, -1.0,
        -1.0, -1.0, -1.0,
         1.0, -1.0, -1.0,
         1.0, -1.0, -1.0,
         1.0,  1.0, -1.0,
        -1.0,  1.0, -1.0,

        -1.0, -1.0,  1.0,
        -1.0, -1.0, -1.0,
        -1.0,  1.0, -1.0,
        -1.0,  1.0, -1.0,
        -1.0,  1.0,  1.0,
        -1.0, -1.0,  1.0,

         1.0, -1.0, -1.0,
         1.0, -1.0,  1.0,
         1.0,  1.0,  1.0,
         1.0,  1.0,  1.0,
         1.0,  1.0, -1.0,
         1.0, -1.0, -1.0,

        -1.0, -1.0,  1.0,
        -1.0,  1.0,  1.0,
         1.0,  1.0,  1.0,
         1.0,  1.0,  1.0,
         1.0, -1.0,  1.0,
        -1.0, -1.0,  1.0,

        -1.0,  1.0, -1.0,
         1.0,  1.0, -1.0,
         1.0,  1.0,  1.0,
         1.0,  1.0,  1.0,
        -1.0,  1.0,  1.0,
        -1.0,  1.0, -1.0,

        -1.0, -1.0, -1.0,
        -1.0, -1.0,  1.0,
         1.0, -1.0, -1.0,
         1.0, -1.0, -1.0,
        -1.0, -1.0,  1.0,
         1.0, -1.0,  1.0
    ]

    vao_ref = Ref(GLuint(0))
    glGenVertexArrays(1, vao_ref)
    vao = vao_ref[]

    vbo_ref = Ref(GLuint(0))
    glGenBuffers(1, vbo_ref)
    vbo = vbo_ref[]

    glBindVertexArray(vao)
    glBindBuffer(GL_ARRAY_BUFFER, vbo)
    glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW)
    glEnableVertexAttribArray(0)
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 3 * sizeof(Float32), Ptr{Cvoid}(0))
    glBindVertexArray(GLuint(0))

    return vao, vbo
end

"""
    create_environment_cubemap(hdr_path::String) -> GLuint

Convert equirectangular HDR to cubemap (or create procedural sky if no HDR).
Returns cubemap texture ID.
"""
function create_environment_cubemap(hdr_path::String)
    cubemap_size = 512

    # Create cubemap texture
    tex_ref = Ref(GLuint(0))
    glGenTextures(1, tex_ref)
    cubemap = tex_ref[]

    glBindTexture(GL_TEXTURE_CUBE_MAP, cubemap)

    # Allocate storage for all 6 faces
    for i in 0:5
        glTexImage2D(GL_TEXTURE_CUBE_MAP_POSITIVE_X + i, 0, GL_RGB16F,
                     cubemap_size, cubemap_size, 0, GL_RGB, GL_FLOAT, C_NULL)
    end

    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR)
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_R, GL_CLAMP_TO_EDGE)

    # Generate procedural sky gradient (blue sky -> white horizon -> warm ground)
    # This provides a realistic-looking environment without HDR files
    render_procedural_sky_to_cubemap!(cubemap, cubemap_size)

    glBindTexture(GL_TEXTURE_CUBE_MAP, cubemap)
    glGenerateMipmap(GL_TEXTURE_CUBE_MAP)
    glBindTexture(GL_TEXTURE_CUBE_MAP, GLuint(0))

    @info "Created environment cubemap (procedural sky)" size=cubemap_size

    return cubemap
end

"""
Render a procedural sky gradient to all 6 cubemap faces.
"""
function render_procedural_sky_to_cubemap!(cubemap::GLuint, size::Int)
    # Create cube mesh for rendering
    cube_vao, cube_vbo = create_cube_vao()

    # Compile procedural sky shader
    sky_shader = create_shader_program(
        EQUIRECT_TO_CUBEMAP_VERTEX,
        """
        #version 330 core
        in vec3 v_LocalPos;
        out vec4 FragColor;

        void main()
        {
            vec3 dir = normalize(v_LocalPos);

            // Sky gradient: blue at top, white at horizon, warm at bottom
            float elevation = dir.y;  // -1 (down) to +1 (up)

            vec3 skyColor = vec3(0.4, 0.6, 1.0);      // Blue sky
            vec3 horizonColor = vec3(0.9, 0.9, 1.0);  // White horizon
            vec3 groundColor = vec3(0.2, 0.15, 0.1);  // Dark ground

            vec3 color;
            if (elevation > 0.0) {
                // Sky -> horizon
                color = mix(horizonColor, skyColor, elevation);
            } else {
                // Horizon -> ground
                color = mix(horizonColor, groundColor, -elevation);
            }

            // HDR intensity
            color *= 1.5;

            FragColor = vec4(color, 1.0);
        }
        """
    )

    # Create framebuffer for rendering to cubemap faces
    fbo_ref = Ref(GLuint(0))
    glGenFramebuffers(1, fbo_ref)
    fbo = fbo_ref[]

    # Projection matrix for 90deg FOV cubemap (perspective_matrix expects degrees)
    projection = perspective_matrix(90.0f0, 1.0f0, 0.1f0, 10.0f0)

    # View matrices for each cubemap face
    view_matrices = [
        look_at_matrix(Vec3f(0,0,0), Vec3f( 1, 0, 0), Vec3f(0,-1, 0)),  # +X
        look_at_matrix(Vec3f(0,0,0), Vec3f(-1, 0, 0), Vec3f(0,-1, 0)),  # -X
        look_at_matrix(Vec3f(0,0,0), Vec3f( 0, 1, 0), Vec3f(0, 0, 1)),  # +Y
        look_at_matrix(Vec3f(0,0,0), Vec3f( 0,-1, 0), Vec3f(0, 0,-1)),  # -Y
        look_at_matrix(Vec3f(0,0,0), Vec3f( 0, 0, 1), Vec3f(0,-1, 0)),  # +Z
        look_at_matrix(Vec3f(0,0,0), Vec3f( 0, 0,-1), Vec3f(0,-1, 0)),  # -Z
    ]

    glBindFramebuffer(GL_FRAMEBUFFER, fbo)
    glViewport(0, 0, size, size)
    glDisable(GL_CULL_FACE)  # Render all cube faces (inside of the cube)

    glUseProgram(sky_shader.id)
    set_uniform!(sky_shader, "u_Projection", projection)

    # Render each face
    for face in 0:5
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                               GL_TEXTURE_CUBE_MAP_POSITIVE_X + face, cubemap, 0)

        glClear(GL_COLOR_BUFFER_BIT)

        set_uniform!(sky_shader, "u_View", view_matrices[face + 1])

        glBindVertexArray(cube_vao)
        glDrawArrays(GL_TRIANGLES, 0, 36)
        glBindVertexArray(GLuint(0))
    end

    # Cleanup
    glEnable(GL_CULL_FACE)  # Restore face culling
    glBindFramebuffer(GL_FRAMEBUFFER, GLuint(0))
    glDeleteFramebuffers(1, Ref(fbo))
    glDeleteVertexArrays(1, Ref(cube_vao))
    glDeleteBuffers(1, Ref(cube_vbo))
    glDeleteProgram(sky_shader.id)
end

"""
    generate_irradiance_map(env_cubemap::GLuint) -> GLuint

Convolve environment map for diffuse irradiance.
"""
function generate_irradiance_map(env_cubemap::GLuint)
    irradiance_size = 32

    # Create irradiance cubemap
    tex_ref = Ref(GLuint(0))
    glGenTextures(1, tex_ref)
    irradiance_map = tex_ref[]

    glBindTexture(GL_TEXTURE_CUBE_MAP, irradiance_map)

    for i in 0:5
        glTexImage2D(GL_TEXTURE_CUBE_MAP_POSITIVE_X + i, 0, GL_RGB16F,
                     irradiance_size, irradiance_size, 0, GL_RGB, GL_FLOAT, C_NULL)
    end

    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_R, GL_CLAMP_TO_EDGE)

    glBindTexture(GL_TEXTURE_CUBE_MAP, GLuint(0))

    # Render irradiance convolution
    render_convolution_to_cubemap!(irradiance_map, env_cubemap, irradiance_size, :irradiance)

    @info "Generated irradiance map" size=irradiance_size

    return irradiance_map
end

"""
    generate_prefilter_map(env_cubemap::GLuint) -> GLuint

Generate prefiltered specular map with roughness mip levels.
"""
function generate_prefilter_map(env_cubemap::GLuint)
    prefilter_size = 128
    max_mip_levels = 5

    # Create prefilter cubemap
    tex_ref = Ref(GLuint(0))
    glGenTextures(1, tex_ref)
    prefilter_map = tex_ref[]

    glBindTexture(GL_TEXTURE_CUBE_MAP, prefilter_map)

    # Allocate storage with mipmaps
    for mip in 0:(max_mip_levels - 1)
        mip_size = Int(prefilter_size / (2^mip))
        for i in 0:5
            glTexImage2D(GL_TEXTURE_CUBE_MAP_POSITIVE_X + i, mip, GL_RGB16F,
                         mip_size, mip_size, 0, GL_RGB, GL_FLOAT, C_NULL)
        end
    end

    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR)
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_R, GL_CLAMP_TO_EDGE)
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_BASE_LEVEL, 0)
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MAX_LEVEL, max_mip_levels - 1)

    glBindTexture(GL_TEXTURE_CUBE_MAP, GLuint(0))

    # Render prefilter convolution for each mip level (roughness)
    for mip in 0:(max_mip_levels - 1)
        mip_size = Int(prefilter_size / (2^mip))
        roughness = Float32(mip) / Float32(max_mip_levels - 1)
        render_convolution_to_cubemap!(prefilter_map, env_cubemap, mip_size, :prefilter, mip, roughness)
    end

    @info "Generated prefilter map" size=prefilter_size mip_levels=max_mip_levels

    return prefilter_map
end

"""
    generate_brdf_lut() -> GLuint

Generate BRDF integration lookup table.
This can be cached and reused for all environments.
"""
function generate_brdf_lut()
    lut_size = 512

    # Create LUT texture
    tex_ref = Ref(GLuint(0))
    glGenTextures(1, tex_ref)
    brdf_lut = tex_ref[]

    glBindTexture(GL_TEXTURE_2D, brdf_lut)
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RG16F, lut_size, lut_size, 0, GL_RG, GL_FLOAT, C_NULL)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)

    glBindTexture(GL_TEXTURE_2D, GLuint(0))

    # Render BRDF integration using shader
    render_brdf_lut!(brdf_lut, lut_size)

    @info "Generated BRDF LUT" size=lut_size

    return brdf_lut
end

"""
Render BRDF integration LUT to a 2D texture.
"""
function render_brdf_lut!(lut_texture::GLuint, size::Int)
    # Create fullscreen quad
    quad_vao, quad_vbo = create_fullscreen_quad_vao()

    # Compile BRDF LUT shader
    lut_shader = create_shader_program(BRDF_LUT_VERTEX, BRDF_LUT_FRAGMENT)

    # Create framebuffer
    fbo_ref = Ref(GLuint(0))
    glGenFramebuffers(1, fbo_ref)
    fbo = fbo_ref[]

    glBindFramebuffer(GL_FRAMEBUFFER, fbo)
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, lut_texture, 0)

    glViewport(0, 0, size, size)
    glClear(GL_COLOR_BUFFER_BIT)

    glUseProgram(lut_shader.id)

    glBindVertexArray(quad_vao)
    glDrawArrays(GL_TRIANGLES, 0, 6)
    glBindVertexArray(GLuint(0))

    # Cleanup
    glBindFramebuffer(GL_FRAMEBUFFER, GLuint(0))
    glDeleteFramebuffers(1, Ref(fbo))
    glDeleteVertexArrays(1, Ref(quad_vao))
    glDeleteBuffers(1, Ref(quad_vbo))
    glDeleteProgram(lut_shader.id)
end

"""
Create a fullscreen quad VAO for rendering 2D textures.
"""
function create_fullscreen_quad_vao()
    vertices = Float32[
        # positions   # texcoords
        -1.0,  1.0,   0.0, 1.0,
        -1.0, -1.0,   0.0, 0.0,
         1.0, -1.0,   1.0, 0.0,

        -1.0,  1.0,   0.0, 1.0,
         1.0, -1.0,   1.0, 0.0,
         1.0,  1.0,   1.0, 1.0
    ]

    vao_ref = Ref(GLuint(0))
    glGenVertexArrays(1, vao_ref)
    vao = vao_ref[]

    vbo_ref = Ref(GLuint(0))
    glGenBuffers(1, vbo_ref)
    vbo = vbo_ref[]

    glBindVertexArray(vao)
    glBindBuffer(GL_ARRAY_BUFFER, vbo)
    glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW)

    # Position attribute
    glEnableVertexAttribArray(0)
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(Float32), Ptr{Cvoid}(0))

    # Texcoord attribute
    glEnableVertexAttribArray(1)
    glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(Float32), Ptr{Cvoid}(2 * sizeof(Float32)))

    glBindVertexArray(GLuint(0))

    return vao, vbo
end

"""
Render convolution shader to all 6 cubemap faces.
"""
function render_convolution_to_cubemap!(
    target_cubemap::GLuint,
    source_cubemap::GLuint,
    size::Int,
    convolution_type::Symbol,
    mip_level::Int=0,
    roughness::Float32=0.0f0
)
    # Create cube mesh for rendering
    cube_vao, cube_vbo = create_cube_vao()

    # Select shader based on convolution type
    fragment_shader = if convolution_type == :irradiance
        IRRADIANCE_CONVOLUTION_FRAGMENT
    elseif convolution_type == :prefilter
        PREFILTER_CONVOLUTION_FRAGMENT
    else
        error("Unknown convolution type: $convolution_type")
    end

    # Compile shader
    conv_shader = create_shader_program(EQUIRECT_TO_CUBEMAP_VERTEX, fragment_shader)

    # Create framebuffer
    fbo_ref = Ref(GLuint(0))
    glGenFramebuffers(1, fbo_ref)
    fbo = fbo_ref[]

    # Projection matrix for 90deg FOV cubemap (perspective_matrix expects degrees)
    projection = perspective_matrix(90.0f0, 1.0f0, 0.1f0, 10.0f0)

    # View matrices for each cubemap face
    view_matrices = [
        look_at_matrix(Vec3f(0,0,0), Vec3f( 1, 0, 0), Vec3f(0,-1, 0)),  # +X
        look_at_matrix(Vec3f(0,0,0), Vec3f(-1, 0, 0), Vec3f(0,-1, 0)),  # -X
        look_at_matrix(Vec3f(0,0,0), Vec3f( 0, 1, 0), Vec3f(0, 0, 1)),  # +Y
        look_at_matrix(Vec3f(0,0,0), Vec3f( 0,-1, 0), Vec3f(0, 0,-1)),  # -Y
        look_at_matrix(Vec3f(0,0,0), Vec3f( 0, 0, 1), Vec3f(0,-1, 0)),  # +Z
        look_at_matrix(Vec3f(0,0,0), Vec3f( 0, 0,-1), Vec3f(0,-1, 0)),  # -Z
    ]

    glBindFramebuffer(GL_FRAMEBUFFER, fbo)
    glViewport(0, 0, size, size)
    glDisable(GL_CULL_FACE)  # Render all cube faces (inside of the cube)

    glUseProgram(conv_shader.id)
    set_uniform!(conv_shader, "u_Projection", projection)

    # Bind source cubemap
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_CUBE_MAP, source_cubemap)
    set_uniform!(conv_shader, "u_EnvironmentMap", Int32(0))

    # Set roughness for prefilter convolution
    if convolution_type == :prefilter
        set_uniform!(conv_shader, "u_Roughness", roughness)
    end

    # Render each face
    for face in 0:5
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                               GL_TEXTURE_CUBE_MAP_POSITIVE_X + face, target_cubemap, mip_level)

        glClear(GL_COLOR_BUFFER_BIT)

        set_uniform!(conv_shader, "u_View", view_matrices[face + 1])

        glBindVertexArray(cube_vao)
        glDrawArrays(GL_TRIANGLES, 0, 36)
        glBindVertexArray(GLuint(0))
    end

    # Cleanup
    glEnable(GL_CULL_FACE)  # Restore face culling
    glBindFramebuffer(GL_FRAMEBUFFER, GLuint(0))
    glDeleteFramebuffers(1, Ref(fbo))
    glDeleteVertexArrays(1, Ref(cube_vao))
    glDeleteBuffers(1, Ref(cube_vbo))
    glDeleteProgram(conv_shader.id)
end

"""
    destroy_ibl_environment!(env::IBLEnvironment)

Release GPU resources for IBL environment.
"""
function destroy_ibl_environment!(env::IBLEnvironment)
    if env.environment_map != GLuint(0)
        glDeleteTextures(1, Ref(env.environment_map))
        env.environment_map = GLuint(0)
    end
    if env.irradiance_map != GLuint(0)
        glDeleteTextures(1, Ref(env.irradiance_map))
        env.irradiance_map = GLuint(0)
    end
    if env.prefilter_map != GLuint(0)
        glDeleteTextures(1, Ref(env.prefilter_map))
        env.prefilter_map = GLuint(0)
    end
    if env.brdf_lut != GLuint(0)
        glDeleteTextures(1, Ref(env.brdf_lut))
        env.brdf_lut = GLuint(0)
    end
    return nothing
end
