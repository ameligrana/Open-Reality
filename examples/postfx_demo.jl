# Post-Processing Effects demo
# Demonstrates Depth of Field, Motion Blur, Vignette, and Color Grading.
# All effects are enabled simultaneously for a cinematic look.

using OpenReality

reset_entity_counter!()
reset_component_stores!()

# Build a scene with objects at varying depths for DoF showcase
s = scene([
    # Player
    create_player(position=Vec3d(0, 1.7, 8)),

    # Sun
    entity([
        DirectionalLightComponent(direction=Vec3f(0.2, -0.9, -0.4), intensity=2.5f0)
    ]),

    # Point lights for atmosphere
    entity([
        PointLightComponent(color=RGB{Float32}(1.0, 0.6, 0.3), intensity=40.0f0, range=15.0f0),
        transform(position=Vec3d(-3, 3, 2))
    ]),
    entity([
        PointLightComponent(color=RGB{Float32}(0.3, 0.6, 1.0), intensity=30.0f0, range=15.0f0),
        transform(position=Vec3d(4, 3, -3))
    ]),

    # Near objects (will be blurred by DoF - out of focus)
    entity([
        cube_mesh(),
        MaterialComponent(color=RGB{Float32}(0.9, 0.2, 0.2), metallic=0.8f0, roughness=0.15f0),
        transform(position=Vec3d(-1.5, 0.5, 5), scale=Vec3d(0.7, 0.7, 0.7))
    ]),

    # Mid-distance objects (in focus for DoF)
    entity([
        sphere_mesh(radius=0.8f0, segments=32),
        MaterialComponent(color=RGB{Float32}(0.9, 0.85, 0.0), metallic=0.95f0, roughness=0.05f0),
        transform(position=Vec3d(0, 0.8, 0))
    ]),
    entity([
        cube_mesh(),
        MaterialComponent(color=RGB{Float32}(0.2, 0.8, 0.3), metallic=0.4f0, roughness=0.5f0),
        transform(position=Vec3d(2, 0.5, -1))
    ]),

    # Far objects (will be blurred by DoF - out of focus)
    entity([
        sphere_mesh(radius=1.2f0, segments=24),
        MaterialComponent(color=RGB{Float32}(0.3, 0.3, 0.9), metallic=0.6f0, roughness=0.3f0),
        transform(position=Vec3d(-3, 1.2, -15))
    ]),
    entity([
        cube_mesh(),
        MaterialComponent(color=RGB{Float32}(0.7, 0.1, 0.7), metallic=0.5f0, roughness=0.4f0),
        transform(position=Vec3d(5, 1.0, -20), scale=Vec3d(2, 2, 2))
    ]),

    # Floor
    entity([
        plane_mesh(width=40.0f0, depth=40.0f0),
        MaterialComponent(color=RGB{Float32}(0.35, 0.35, 0.35), roughness=0.85f0),
        transform(),
        ColliderComponent(shape=AABBShape(Vec3f(20.0, 0.01, 20.0)), offset=Vec3f(0, -0.01, 0)),
        RigidBodyComponent(body_type=BODY_STATIC)
    ])
])

@info "Post-FX Demo: DoF, Motion Blur, Vignette, Color Grading all enabled"
@info "Move around to see motion blur; objects at different depths show DoF effect"
render(s, post_process=PostProcessConfig(
    # Bloom
    bloom_enabled=true,
    bloom_threshold=0.8f0,
    bloom_intensity=0.25f0,
    # Tone mapping
    tone_mapping=TONEMAP_ACES,
    gamma=2.2f0,
    # FXAA
    fxaa_enabled=true,
    # Depth of Field
    dof_enabled=true,
    dof_focus_distance=8.0f0,   # Focus on mid-distance objects
    dof_focus_range=4.0f0,
    dof_bokeh_radius=3.0f0,
    # Motion Blur
    motion_blur_enabled=true,
    motion_blur_intensity=0.8f0,
    motion_blur_samples=8,
    # Vignette
    vignette_enabled=true,
    vignette_intensity=0.5f0,
    vignette_radius=0.75f0,
    vignette_softness=0.45f0,
    # Color Grading (warm cinematic look)
    color_grading_enabled=true,
    color_grading_brightness=0.02f0,
    color_grading_contrast=1.1f0,
    color_grading_saturation=1.15f0
))
