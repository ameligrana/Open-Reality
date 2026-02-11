#!/usr/bin/env julia
# Vulkan backend test
# Run: julia --project=. examples/vulkan_test.jl
#
# Demonstrates the Vulkan deferred PBR renderer with:
# - Multiple PBR materials (metallic/dielectric, varying roughness)
# - Directional + point lights
# - Cascaded shadow maps
# - IBL (procedural sky)
# - Bloom, ACES tone mapping, FXAA
# - FPS player controls (WASD + mouse)

using OpenReality

reset_entity_counter!()
reset_component_stores!()

s = scene([
    # FPS Player
    create_player(position=Vec3d(0, 2.0, 10)),

    # ====== Lighting ======

    # IBL environment (procedural sky)
    entity([
        IBLComponent(environment_path="sky", intensity=1.0f0, enabled=true)
    ]),

    # Directional light (sun)
    entity([
        DirectionalLightComponent(
            direction=Vec3f(0.3, -1.0, -0.5),
            intensity=3.0f0,
            color=RGB{Float32}(1.0, 0.95, 0.9)
        )
    ]),

    # Warm point light
    entity([
        PointLightComponent(
            color=RGB{Float32}(1.0, 0.7, 0.4),
            intensity=30.0f0,
            range=20.0f0
        ),
        transform(position=Vec3d(-5, 4, 3))
    ]),

    # Cool point light
    entity([
        PointLightComponent(
            color=RGB{Float32}(0.4, 0.6, 1.0),
            intensity=30.0f0,
            range=20.0f0
        ),
        transform(position=Vec3d(5, 4, -3))
    ]),

    # ====== PBR Material Showcase ======

    # Gold sphere (mirror smooth)
    entity([
        sphere_mesh(radius=0.8f0),
        MaterialComponent(
            color=RGB{Float32}(0.9, 0.8, 0.5),
            metallic=1.0f0,
            roughness=0.05f0
        ),
        transform(position=Vec3d(-4, 1.5, 0)),
        ColliderComponent(shape=SphereShape(0.8f0)),
        RigidBodyComponent(body_type=BODY_STATIC)
    ]),

    # Copper sphere (slightly rough)
    entity([
        sphere_mesh(radius=0.8f0),
        MaterialComponent(
            color=RGB{Float32}(0.85, 0.55, 0.4),
            metallic=1.0f0,
            roughness=0.35f0
        ),
        transform(position=Vec3d(-2, 1.5, 0)),
        ColliderComponent(shape=SphereShape(0.8f0)),
        RigidBodyComponent(body_type=BODY_STATIC)
    ]),

    # Red plastic sphere (dielectric, smooth)
    entity([
        sphere_mesh(radius=0.8f0),
        MaterialComponent(
            color=RGB{Float32}(0.8, 0.1, 0.1),
            metallic=0.0f0,
            roughness=0.2f0
        ),
        transform(position=Vec3d(0, 1.5, 0)),
        ColliderComponent(shape=SphereShape(0.8f0)),
        RigidBodyComponent(body_type=BODY_STATIC)
    ]),

    # Green rubber sphere (dielectric, rough)
    entity([
        sphere_mesh(radius=0.8f0),
        MaterialComponent(
            color=RGB{Float32}(0.2, 0.7, 0.2),
            metallic=0.0f0,
            roughness=0.8f0
        ),
        transform(position=Vec3d(2, 1.5, 0)),
        ColliderComponent(shape=SphereShape(0.8f0)),
        RigidBodyComponent(body_type=BODY_STATIC)
    ]),

    # Chrome sphere (mirror)
    entity([
        sphere_mesh(radius=0.8f0),
        MaterialComponent(
            color=RGB{Float32}(0.95, 0.95, 0.95),
            metallic=1.0f0,
            roughness=0.0f0,
            clearcoat=1.0f0,
            clearcoat_roughness=0.03f0
        ),
        transform(position=Vec3d(4, 1.5, 0)),
        ColliderComponent(shape=SphereShape(0.8f0)),
        RigidBodyComponent(body_type=BODY_STATIC)
    ]),

    # ====== Geometry ======

    # Cube casting shadows
    entity([
        cube_mesh(),
        MaterialComponent(
            color=RGB{Float32}(0.6, 0.4, 0.2),
            metallic=0.0f0,
            roughness=0.6f0
        ),
        transform(position=Vec3d(-3, 0.5, -4)),
        ColliderComponent(shape=AABBShape(Vec3f(0.5, 0.5, 0.5))),
        RigidBodyComponent(body_type=BODY_STATIC)
    ]),

    # Tall column
    entity([
        cube_mesh(),
        MaterialComponent(
            color=RGB{Float32}(0.7, 0.7, 0.7),
            metallic=0.1f0,
            roughness=0.5f0
        ),
        transform(position=Vec3d(3, 2.0, -4), scale=Vec3d(0.5, 4.0, 0.5)),
        ColliderComponent(shape=AABBShape(Vec3f(0.5, 4.0, 0.5))),
        RigidBodyComponent(body_type=BODY_STATIC)
    ]),

    # Pedestal for the spheres
    entity([
        cube_mesh(),
        MaterialComponent(
            color=RGB{Float32}(0.4, 0.4, 0.4),
            metallic=0.2f0,
            roughness=0.4f0
        ),
        transform(position=Vec3d(0, 0.25, 0), scale=Vec3d(7.0, 0.5, 2.0)),
        ColliderComponent(shape=AABBShape(Vec3f(7.0, 0.5, 2.0))),
        RigidBodyComponent(body_type=BODY_STATIC)
    ]),

    # Floor
    entity([
        plane_mesh(width=40.0f0, depth=40.0f0),
        MaterialComponent(
            color=RGB{Float32}(0.35, 0.35, 0.35),
            metallic=0.0f0,
            roughness=0.9f0
        ),
        transform(),
        ColliderComponent(shape=AABBShape(Vec3f(20.0, 0.01, 20.0)), offset=Vec3f(0, -0.01, 0)),
        RigidBodyComponent(body_type=BODY_STATIC)
    ])
])

@info """
Vulkan Backend Test
====================
Features:
- Deferred PBR rendering with Cook-Torrance BRDF
- Cascaded shadow maps (4 cascades)
- Image-based lighting (procedural sky)
- Bloom + ACES tone mapping + FXAA
- Screen-space reflections & ambient occlusion

Materials (left to right): Gold, Copper, Red Plastic, Green Rubber, Chrome

Controls: WASD move, Mouse look, Shift sprint, ESC release cursor

Scene: $(entity_count(s)) entities
"""

render(s,
    backend=VulkanBackend(),
    width=1280,
    height=720,
    title="OpenReality — Vulkan PBR Test",
    post_process=PostProcessConfig(
        bloom_enabled=true,
        bloom_threshold=1.0f0,
        bloom_intensity=0.3f0,
        ssao_enabled=true,
        tone_mapping=TONEMAP_ACES,
        fxaa_enabled=true,
        gamma=2.2f0
    )
)
