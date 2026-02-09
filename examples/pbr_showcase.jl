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
])

@info """
PBR & Deferred Rendering Showcase
==================================
Features demonstrated:
- Image-Based Lighting (IBL): Procedural sky with photorealistic ambient lighting
  - Irradiance map for diffuse lighting
  - Prefiltered specular reflections based on roughness
  - Split-sum approximation for real-time PBR
- Deferred Rendering: 4 lights (1 directional + 3 point)
- Cascaded Shadow Maps: 4 cascades with PSSM for high-quality shadows
- PBR Materials: Metallic/roughness workflow
  - Left spheres: Metallic (gold) with varying roughness (0.0 to 1.0)
  - Right spheres: Non-metallic (dielectric) materials
- Cook-Torrance BRDF: Industry-standard physically-based lighting
- Dynamic lights with physically-based falloff

Controls:
- WASD: Move
- Mouse: Look around
- Shift: Sprint
- ESC: Release cursor

Scene stats: $(entity_count(s)) entities
"""

render(s)
