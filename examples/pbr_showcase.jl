# PBR & Deferred Rendering Showcase
# Demonstrates AAA rendering features: Deferred Rendering, CSM, PBR materials

using OpenReality

reset_entity_counter!()
reset_component_stores!()

# Build a comprehensive PBR showcase scene
s = scene([
    # FPS Player (WASD + mouse look)
    create_player(position=Vec3d(0, 2.0, 15)),

    # ====== Lighting Setup ======

    # Image-Based Lighting (IBL) for photorealistic environment lighting
    entity([
        IBLComponent(
            environment_path="sky",  # Procedural sky
            intensity=1.0f0,
            enabled=true
        )
    ]),

    # Directional light (sun) with CSM shadows
    entity([
        DirectionalLightComponent(
            direction=Vec3f(0.3, -1.0, -0.5),  # Angled sunlight
            intensity=3.0f0,
            color=RGB{Float32}(1.0, 0.95, 0.9)  # Warm sunlight
        )
    ]),

    # Point lights to showcase deferred rendering's multi-light capability
    entity([
        PointLightComponent(
            color=RGB{Float32}(1.0, 0.3, 0.3),  # Red
            intensity=25.0f0,
            range=15.0f0
        ),
        transform(position=Vec3d(-8, 3, 0))
    ]),

    entity([
        PointLightComponent(
            color=RGB{Float32}(0.3, 1.0, 0.3),  # Green
            intensity=25.0f0,
            range=15.0f0
        ),
        transform(position=Vec3d(8, 3, 0))
    ]),

    entity([
        PointLightComponent(
            color=RGB{Float32}(0.3, 0.3, 1.0),  # Blue
            intensity=25.0f0,
            range=15.0f0
        ),
        transform(position=Vec3d(0, 3, -8))
    ]),

    # ====== PBR Material Showcase ======

    # Metallic spheres (varying roughness)
    entity([
        sphere_mesh(radius=0.8f0),
        MaterialComponent(
            color=RGB{Float32}(0.9, 0.8, 0.6),  # Gold-ish
            metallic=1.0f0,
            roughness=0.0f0  # Mirror-smooth
        ),
        transform(position=Vec3d(-6, 1.5, 0)),
        ColliderComponent(shape=SphereShape(0.8f0)),
        RigidBodyComponent(body_type=BODY_STATIC)
    ]),

    entity([
        sphere_mesh(radius=0.8f0),
        MaterialComponent(
            color=RGB{Float32}(0.9, 0.8, 0.6),
            metallic=1.0f0,
            roughness=0.3f0
        ),
        transform(position=Vec3d(-4, 1.5, 0)),
        ColliderComponent(shape=SphereShape(0.8f0)),
        RigidBodyComponent(body_type=BODY_STATIC)
    ]),

    entity([
        sphere_mesh(radius=0.8f0),
        MaterialComponent(
            color=RGB{Float32}(0.9, 0.8, 0.6),
            metallic=1.0f0,
            roughness=0.6f0
        ),
        transform(position=Vec3d(-2, 1.5, 0)),
        ColliderComponent(shape=SphereShape(0.8f0)),
        RigidBodyComponent(body_type=BODY_STATIC)
    ]),

    entity([
        sphere_mesh(radius=0.8f0),
        MaterialComponent(
            color=RGB{Float32}(0.9, 0.8, 0.6),
            metallic=1.0f0,
            roughness=1.0f0  # Very rough
        ),
        transform(position=Vec3d(0, 1.5, 0)),
        ColliderComponent(shape=SphereShape(0.8f0)),
        RigidBodyComponent(body_type=BODY_STATIC)
    ]),

    # Non-metallic spheres (dielectric materials)
    entity([
        sphere_mesh(radius=0.8f0),
        MaterialComponent(
            color=RGB{Float32}(0.8, 0.2, 0.2),  # Red
            metallic=0.0f0,
            roughness=0.2f0
        ),
        transform(position=Vec3d(2, 1.5, 0)),
        ColliderComponent(shape=SphereShape(0.8f0)),
        RigidBodyComponent(body_type=BODY_STATIC)
    ]),

    entity([
        sphere_mesh(radius=0.8f0),
        MaterialComponent(
            color=RGB{Float32}(0.2, 0.8, 0.2),  # Green
            metallic=0.0f0,
            roughness=0.5f0
        ),
        transform(position=Vec3d(4, 1.5, 0)),
        ColliderComponent(shape=SphereShape(0.8f0)),
        RigidBodyComponent(body_type=BODY_STATIC)
    ]),

    entity([
        sphere_mesh(radius=0.8f0),
        MaterialComponent(
            color=RGB{Float32}(0.2, 0.2, 0.8),  # Blue
            metallic=0.0f0,
            roughness=0.8f0
        ),
        transform(position=Vec3d(6, 1.5, 0)),
        ColliderComponent(shape=SphereShape(0.8f0)),
        RigidBodyComponent(body_type=BODY_STATIC)
    ]),

    # ====== CSM Shadow Quality Demonstration ======

    # Tall columns at various distances to show cascade transitions
    entity([
        cube_mesh(),
        MaterialComponent(
            color=RGB{Float32}(0.7, 0.7, 0.7),
            metallic=0.0f0,
            roughness=0.6f0
        ),
        transform(
            position=Vec3d(-10, 2.5, -5),
            scale=Vec3d(0.5, 5.0, 0.5)
        ),
        ColliderComponent(shape=AABBShape(Vec3f(0.5, 5.0, 0.5))),
        RigidBodyComponent(body_type=BODY_STATIC)
    ]),

    entity([
        cube_mesh(),
        MaterialComponent(
            color=RGB{Float32}(0.7, 0.7, 0.7),
            metallic=0.0f0,
            roughness=0.6f0
        ),
        transform(
            position=Vec3d(10, 2.5, -5),
            scale=Vec3d(0.5, 5.0, 0.5)
        ),
        ColliderComponent(shape=AABBShape(Vec3f(0.5, 5.0, 0.5))),
        RigidBodyComponent(body_type=BODY_STATIC)
    ]),

    # Row of cubes extending into the distance (shows cascade quality)
    [entity([
        cube_mesh(),
        MaterialComponent(
            color=RGB{Float32}(0.6, 0.4, 0.2),
            metallic=0.0f0,
            roughness=0.7f0
        ),
        transform(
            position=Vec3d(0, 0.5, -Float64(i * 5)),
            scale=Vec3d(0.8, 1.0, 0.8)
        ),
        ColliderComponent(shape=AABBShape(Vec3f(0.8, 1.0, 0.8))),
        RigidBodyComponent(body_type=BODY_STATIC)
    ]) for i in 1:20]...,

    # ====== Large Floor (with shadows) ======
    entity([
        plane_mesh(width=100.0f0, depth=100.0f0),
        MaterialComponent(
            color=RGB{Float32}(0.3, 0.3, 0.3),  # Dark gray
            metallic=0.0f0,
            roughness=0.9f0
        ),
        transform(),
        ColliderComponent(shape=AABBShape(Vec3f(50.0, 0.01, 50.0)), offset=Vec3f(0, -0.01, 0)),
        RigidBodyComponent(body_type=BODY_STATIC)
    ]),

    # ====== Additional decorative elements ======

    # Central pedestal
    entity([
        cube_mesh(),
        MaterialComponent(
            color=RGB{Float32}(0.5, 0.5, 0.5),
            metallic=0.2f0,
            roughness=0.4f0
        ),
        transform(
            position=Vec3d(0, 0.25, 0),
            scale=Vec3d(10.0, 0.5, 3.0)
        ),
        ColliderComponent(shape=AABBShape(Vec3f(10.0, 0.5, 3.0))),
        RigidBodyComponent(body_type=BODY_STATIC)
    ]),

    # ====== Advanced Material Showcase ======

    # Clear coat sphere (car paint effect)
    entity([
        sphere_mesh(radius=0.8f0),
        MaterialComponent(
            color=RGB{Float32}(0.8, 0.1, 0.1),  # Deep red
            metallic=0.9f0,
            roughness=0.4f0,
            clearcoat=1.0f0,
            clearcoat_roughness=0.03f0
        ),
        transform(position=Vec3d(-4, 1.5, 4)),
        ColliderComponent(shape=SphereShape(0.8f0)),
        RigidBodyComponent(body_type=BODY_STATIC)
    ]),

    # Clear coat sphere (glossy blue)
    entity([
        sphere_mesh(radius=0.8f0),
        MaterialComponent(
            color=RGB{Float32}(0.1, 0.2, 0.8),  # Deep blue
            metallic=0.7f0,
            roughness=0.5f0,
            clearcoat=0.8f0,
            clearcoat_roughness=0.1f0
        ),
        transform(position=Vec3d(-2, 1.5, 4)),
        ColliderComponent(shape=SphereShape(0.8f0)),
        RigidBodyComponent(body_type=BODY_STATIC)
    ]),

    # Subsurface scattering sphere (wax/skin-like)
    entity([
        sphere_mesh(radius=0.8f0),
        MaterialComponent(
            color=RGB{Float32}(0.9, 0.7, 0.5),  # Skin tone
            metallic=0.0f0,
            roughness=0.6f0,
            subsurface=0.8f0,
            subsurface_color=Vec3f(1.0f0, 0.2f0, 0.1f0)
        ),
        transform(position=Vec3d(0, 1.5, 4)),
        ColliderComponent(shape=SphereShape(0.8f0)),
        RigidBodyComponent(body_type=BODY_STATIC)
    ]),

    # Subsurface scattering sphere (jade-like)
    entity([
        sphere_mesh(radius=0.8f0),
        MaterialComponent(
            color=RGB{Float32}(0.3, 0.7, 0.4),  # Jade green
            metallic=0.0f0,
            roughness=0.3f0,
            subsurface=0.6f0,
            subsurface_color=Vec3f(0.1f0, 0.8f0, 0.2f0)
        ),
        transform(position=Vec3d(2, 1.5, 4)),
        ColliderComponent(shape=SphereShape(0.8f0)),
        RigidBodyComponent(body_type=BODY_STATIC)
    ]),

    # Combined: Clear coat + metallic (chrome-like)
    entity([
        sphere_mesh(radius=0.8f0),
        MaterialComponent(
            color=RGB{Float32}(0.95, 0.95, 0.95),  # Bright silver
            metallic=1.0f0,
            roughness=0.1f0,
            clearcoat=1.0f0,
            clearcoat_roughness=0.05f0
        ),
        transform(position=Vec3d(4, 1.5, 4)),
        ColliderComponent(shape=SphereShape(0.8f0)),
        RigidBodyComponent(body_type=BODY_STATIC)
    ]),
])

@info """
PBR & Deferred Rendering Showcase
==================================
Features demonstrated:
- Image-Based Lighting (IBL): Procedural sky with photorealistic ambient lighting
- Deferred Rendering: 4 lights (1 directional + 3 point)
- Cascaded Shadow Maps: 4 cascades with PSSM for high-quality shadows
- PBR Materials: Metallic/roughness workflow
  - Front row: Metallic (gold) with varying roughness + dielectric materials
- Bloom + HDR: ACES tone mapping with bloom on bright surfaces
- Advanced Materials (back row):
  - Clear coat: Car paint / lacquered surfaces (red, blue, chrome spheres)
  - Subsurface scattering: Skin-like and jade-like translucent materials
- Cook-Torrance BRDF with energy-conserving clear coat layer
- FXAA anti-aliasing

Controls:
- WASD: Move
- Mouse: Look around
- Shift: Sprint
- ESC: Release cursor

Scene stats: $(entity_count(s)) entities
"""

render(s, post_process=PostProcessConfig(
    bloom_enabled=true,
    bloom_threshold=1.0f0,
    bloom_intensity=0.3f0,
    tone_mapping=TONEMAP_ACES,
    fxaa_enabled=true,
    gamma=2.2f0
))
