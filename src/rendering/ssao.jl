# Screen-Space Ambient Occlusion (SSAO): pure math / backend-agnostic utilities
# Alchemy SSAO with hemisphere sampling
# NOTE: OpenGL-specific types (SSAOPass struct, GLSL shaders) moved to backend/opengl/

# =============================================================================
# Helper Functions (Pure Math)
# =============================================================================

"""
    generate_ssao_kernel(kernel_size::Int) -> Vector{Vec3f}

Generate hemisphere sample kernel with non-uniform distribution.
Samples are more concentrated near the origin for better AO.
"""
function generate_ssao_kernel(kernel_size::Int)
    kernel = Vec3f[]

    for i in 1:kernel_size
        # Random sample in hemisphere
        sample = Vec3f(
            rand() * 2.0f0 - 1.0f0,
            rand() * 2.0f0 - 1.0f0,
            rand()  # Positive Z (hemisphere)
        )
        sample = normalize(sample)

        # Scale samples so more are closer to origin
        scale = Float32(i) / Float32(kernel_size)
        scale = lerp(0.1f0, 1.0f0, scale * scale)  # Quadratic falloff
        sample *= scale

        push!(kernel, sample)
    end

    return kernel
end

"""
    lerp(a, b, t)

Linear interpolation.
"""
lerp(a::Float32, b::Float32, t::Float32) = a + (b - a) * t
