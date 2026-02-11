# Cascaded Shadow Maps (CSM): pure math / backend-agnostic utilities
# Eliminates shadow aliasing by using multiple shadow maps at different distances
# NOTE: OpenGL-specific types (CascadedShadowMap struct) moved to backend/opengl/

"""
    compute_cascade_splits(near::Float32, far::Float32, num_cascades::Int, lambda::Float32=0.5f0) -> Vector{Float32}

Compute cascade split distances using Practical Split Scheme (PSSM).
Lambda controls the split distribution:
- lambda = 0.0: uniform split (linear)
- lambda = 1.0: logarithmic split
- lambda = 0.5: balanced (recommended)

Returns split distances in view space (including near and far).
"""
function compute_cascade_splits(near::Float32, far::Float32, num_cascades::Int, lambda::Float32=0.5f0)
    splits = zeros(Float32, num_cascades + 1)
    splits[1] = near
    splits[end] = far

    for i in 1:num_cascades-1
        # Linear split
        c_linear = near + (far - near) * (Float32(i) / Float32(num_cascades))

        # Logarithmic split
        c_log = near * (far / near)^(Float32(i) / Float32(num_cascades))

        # PSSM blend
        splits[i + 1] = lambda * c_log + (1.0f0 - lambda) * c_linear
    end

    return splits
end

"""
    compute_cascade_frustum_corners(view::Mat4f, proj::Mat4f, near::Float32, far::Float32) -> Vector{Vec3f}

Compute the 8 corners of a frustum in world space.
"""
function compute_cascade_frustum_corners(view::Mat4f, proj::Mat4f, near::Float32, far::Float32)
    # Create projection matrix for this cascade's near/far range
    inv_vp = inv(proj * view)

    corners = Vec3f[]

    # NDC corners of the frustum
    for x in [-1.0f0, 1.0f0]
        for y in [-1.0f0, 1.0f0]
            for z in [0.0f0, 1.0f0]  # near=0, far=1 in NDC
                ndc = Vec4f(x, y, z, 1.0f0)
                world = inv_vp * ndc
                push!(corners, Vec3f(world[1], world[2], world[3]) / world[4])
            end
        end
    end

    return corners
end

"""
    compute_cascade_light_matrix(view::Mat4f, proj::Mat4f, near::Float32, far::Float32,
                                  light_dir::Vec3f) -> Mat4f

Compute tight orthographic projection matrix for a cascade based on frustum corners.
"""
function compute_cascade_light_matrix(view::Mat4f, proj::Mat4f, near::Float32, far::Float32,
                                      light_dir::Vec3f)
    # Get frustum corners in world space
    corners = compute_cascade_frustum_corners(view, proj, near, far)

    # Compute frustum center
    center = Vec3f(0, 0, 0)
    for corner in corners
        center += corner
    end
    center /= length(corners)

    # Light view matrix (looking down the light direction)
    light_view = look_at_matrix(center, center + light_dir, Vec3f(0, 1, 0))

    # Transform corners to light space
    light_space_corners = [Vec3f((light_view * Vec4f(c[1], c[2], c[3], 1.0f0))[1:3]...) for c in corners]

    # Find min/max in light space (AABB)
    min_x = minimum([c[1] for c in light_space_corners])
    max_x = maximum([c[1] for c in light_space_corners])
    min_y = minimum([c[2] for c in light_space_corners])
    max_y = maximum([c[2] for c in light_space_corners])
    min_z = minimum([c[3] for c in light_space_corners])
    max_z = maximum([c[3] for c in light_space_corners])

    # Extend Z range to capture shadow casters outside frustum
    z_mult = 10.0f0
    if min_z < 0
        min_z *= z_mult
    else
        min_z /= z_mult
    end
    if max_z < 0
        max_z /= z_mult
    else
        max_z *= z_mult
    end

    # Orthographic projection
    light_proj = Mat4f(
        2.0f0/(max_x - min_x), 0, 0, -(max_x + min_x)/(max_x - min_x),
        0, 2.0f0/(max_y - min_y), 0, -(max_y + min_y)/(max_y - min_y),
        0, 0, -2.0f0/(max_z - min_z), -(max_z + min_z)/(max_z - min_z),
        0, 0, 0, 1
    )

    return light_proj * light_view
end
