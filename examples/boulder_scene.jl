# Boulder Scene — glTF Model Loading Demo
# Demonstrates loading a textured glTF model with PBR materials

using OpenReality

reset_entity_counter!()
reset_component_stores!()

# Load the boulder glTF model
boulder_entities = load_model(joinpath(@__DIR__, "..", "boulder_01_4k.gltf", "boulder_01_4k.gltf"))

s = scene([
    # FPS Player
    create_player(position=Vec3d(0, 1.7, 3.5)),

    # ====== Lighting ======

    # IBL for ambient environment lighting
    entity([
        IBLComponent(
            environment_path="sky",
            intensity=1.0f0,
            enabled=true
        )
    ]),

    # Directional light (sun) — angled for shadow detail on rock crevices
    entity([
        DirectionalLightComponent(
            direction=Vec3f(0.4, -1.0, -0.3),
            intensity=3.0f0,
            color=RGB{Float32}(1.0, 0.95, 0.9)
        )
    ]),

    # Subtle fill light from the left
    entity([
        PointLightComponent(
            color=RGB{Float32}(0.9, 0.9, 1.0),
            intensity=8.0f0,
            range=10.0f0
        ),
        transform(position=Vec3d(-3, 2, 1))
    ]),

    # ====== Boulder ======
    boulder_entities...,

    # ====== Ground Plane ======
    entity([
        plane_mesh(width=30.0f0, depth=30.0f0),
        MaterialComponent(
            color=RGB{Float32}(0.3, 0.3, 0.3),
            metallic=0.0f0,
            roughness=0.9f0
        ),
        transform(),
        ColliderComponent(shape=AABBShape(Vec3f(15.0, 0.01, 15.0)), offset=Vec3f(0, -0.01, 0)),
        RigidBodyComponent(body_type=BODY_STATIC)
    ]),
])

@info """
Boulder Scene — glTF Model Loading Demo
=========================================
Features demonstrated:
- glTF 2.0 model loading with PBR textures
- Albedo, normal map, and metallic-roughness texture maps
- Image-Based Lighting (IBL) with procedural sky
- Directional light with cascaded shadow maps
- ACES tone mapping, bloom, FXAA

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
