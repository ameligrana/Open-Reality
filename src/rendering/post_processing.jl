# Post-processing pipeline: backend-agnostic configuration types
# NOTE: OpenGL-specific types (PostProcessPipeline struct, GLSL shaders) moved to backend/opengl/

"""
    ToneMappingMode

Selectable tone mapping operator.
"""
@enum ToneMappingMode TONEMAP_REINHARD TONEMAP_ACES TONEMAP_UNCHARTED2

"""
    PostProcessConfig

User-facing configuration for the post-processing pipeline.
"""
mutable struct PostProcessConfig
    bloom_enabled::Bool
    bloom_threshold::Float32
    bloom_intensity::Float32
    ssao_enabled::Bool
    ssao_radius::Float32
    ssao_samples::Int
    tone_mapping::ToneMappingMode
    fxaa_enabled::Bool
    gamma::Float32

    PostProcessConfig(;
        bloom_enabled::Bool = false,
        bloom_threshold::Float32 = 1.0f0,
        bloom_intensity::Float32 = 0.3f0,
        ssao_enabled::Bool = false,
        ssao_radius::Float32 = 0.5f0,
        ssao_samples::Int = 16,
        tone_mapping::ToneMappingMode = TONEMAP_REINHARD,
        fxaa_enabled::Bool = false,
        gamma::Float32 = 2.2f0
    ) = new(bloom_enabled, bloom_threshold, bloom_intensity,
            ssao_enabled, ssao_radius, ssao_samples,
            tone_mapping, fxaa_enabled, gamma)
end
