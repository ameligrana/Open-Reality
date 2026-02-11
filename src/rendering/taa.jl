# Temporal Anti-Aliasing (TAA): pure math / backend-agnostic utilities
# Industry-standard AA that blends current frame with reprojected history
# Removes jaggies and stabilizes SSR/SSAO
# NOTE: OpenGL-specific types (TAAPass struct) moved to backend/opengl/

# Halton sequence for camera jitter (8 samples)
const HALTON_SAMPLES = [
    Vec2f(-0.5f0, -0.333333f0),
    Vec2f(0.5f0, 0.333333f0),
    Vec2f(-0.25f0, 0.111111f0),
    Vec2f(0.25f0, -0.111111f0),
    Vec2f(-0.375f0, 0.444444f0),
    Vec2f(0.375f0, -0.444444f0),
    Vec2f(-0.125f0, -0.222222f0),
    Vec2f(0.125f0, 0.222222f0)
]

"""
    get_halton_jitter(index::Int) -> Vec2f

Get Halton sequence jitter offset for given index (0-7).
Returns normalized device coordinate offset ([-0.5, 0.5] range).
"""
function get_halton_jitter(index::Int)
    return HALTON_SAMPLES[mod1(index, 8)]
end

"""
    apply_taa_jitter!(proj::Mat4f, jitter_index::Int, width::Int, height::Int) -> Mat4f

Apply TAA jitter to projection matrix.
Offsets projection by subpixel amount based on Halton sequence.
"""
function apply_taa_jitter!(proj::Mat4f, jitter_index::Int, width::Int, height::Int)
    jitter = get_halton_jitter(jitter_index)

    # Convert from [-0.5, 0.5] pixel offset to NDC space [-1, 1]
    jitter_ndc = Vec2f(
        2.0f0 * jitter[1] / Float32(width),
        2.0f0 * jitter[2] / Float32(height)
    )

    # For perspective projection, jitter is applied to the third row (projection offset)
    # This shifts the projection center, creating the sub-pixel offset effect
    # In column-major notation: row 3 is the perspective divide row
    jittered = Mat4f(
        proj[1,1], proj[1,2], proj[1,3], proj[1,4],
        proj[2,1], proj[2,2], proj[2,3], proj[2,4],
        proj[3,1] + jitter_ndc[1], proj[3,2] + jitter_ndc[2], proj[3,3], proj[3,4],
        proj[4,1], proj[4,2], proj[4,3], proj[4,4]
    )

    return jittered
end
