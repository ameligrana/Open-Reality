# PBR Primitives Showcase
# Demonstrates the rendering pipeline with built-in primitives and varied PBR materials

using OpenReality

reset_entity_counter!()
reset_component_stores!()

s = scene([
    # FPS Player — positioned to view the showcase row
    create_player(position=Vec3d(0, 1.7, 6)),

    # ====== Lighting ======

    # IBL for ambient environment reflections
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

    # Warm point light (right side)
    entity([
        PointLightComponent(color=RGB{Float32}(1.0, 0.6, 0.3), intensity=20.0f0, range=12.0f0),
        transform(position=Vec3d(4, 3, 3))
    ]),

    # Cool point light (left side)
    entity([
        PointLightComponent(color=RGB{Float32}(0.3, 0.5, 1.0), intensity=15.0f0, range=12.0f0),
        transform(position=Vec3d(-4, 3, 3))
    ]),

    # ====== Material Showcase (main row) ======

    # 1. Gold sphere — polished metal
    entity([
        sphere_mesh(radius=0.6f0, segments=64, rings=32),
        MaterialComponent(
            color=RGB{Float32}(1.0, 0.84, 0.0),
            metallic=1.0f0,
            roughness=0.1f0
        ),
        transform(position=Vec3d(-4, 0.6, 0))
    ]),

    # 2. Red plastic sphere — rough dielectric
    entity([
        sphere_mesh(radius=0.6f0, segments=64, rings=32),
        MaterialComponent(
            color=RGB{Float32}(0.9, 0.1, 0.1),
            metallic=0.0f0,
            roughness=0.8f0
        ),
        transform(position=Vec3d(-2, 0.6, 0))
    ]),

    # 3. Blue car-paint sphere — clearcoat
    entity([
        sphere_mesh(radius=0.6f0, segments=64, rings=32),
        MaterialComponent(
            color=RGB{Float32}(0.05, 0.15, 0.6),
            metallic=0.9f0,
            roughness=0.4f0,
            clearcoat=1.0f0,
            clearcoat_roughness=0.03f0
        ),
        transform(position=Vec3d(0, 0.6, 0))
    ]),

    # 4. Green jade sphere — subsurface scattering
    entity([
        sphere_mesh(radius=0.6f0, segments=64, rings=32),
        MaterialComponent(
            color=RGB{Float32}(0.3, 0.7, 0.4),
            metallic=0.0f0,
            roughness=0.3f0,
            subsurface=0.6f0,
            subsurface_color=Vec3f(0.1f0, 0.8f0, 0.2f0)
        ),
        transform(position=Vec3d(2, 0.6, 0))
    ]),

    # 5. Emissive cube — glowing hot
    entity([
        cube_mesh(size=1.0f0),
        MaterialComponent(
            color=RGB{Float32}(1.0, 0.3, 0.05),
            metallic=0.0f0,
            roughness=0.5f0,
            emissive_factor=Vec3f(5.0f0, 1.5f0, 0.3f0)
        ),
        transform(position=Vec3d(4, 0.5, 0))
    ]),

    # ====== Roughness gradient (back row) ======
    [entity([
        sphere_mesh(radius=0.3f0, segments=48, rings=24),
        MaterialComponent(
            color=RGB{Float32}(0.9, 0.9, 0.9),
            metallic=1.0f0,
            roughness=Float32(i / 10)
        ),
        transform(position=Vec3d(-4.5 + i, 0.3, -2))
    ]) for i in 0:9]...,

    # ====== Ground Plane ======
    entity([
        plane_mesh(width=30.0f0, depth=30.0f0),
        MaterialComponent(
            color=RGB{Float32}(0.25, 0.25, 0.25),
            metallic=0.0f0,
            roughness=0.9f0
        ),
        transform(),
        ColliderComponent(shape=AABBShape(Vec3f(15.0, 0.01, 15.0)), offset=Vec3f(0, -0.01, 0)),
        RigidBodyComponent(body_type=BODY_STATIC)
    ]),
])

@info """
PBR Primitives Showcase
========================
Front row (left to right):
  Gold metal | Red plastic | Blue clearcoat | Green jade (SSS) | Emissive cube
Back row:
  Metallic roughness gradient (0.0 → 1.0)

Controls: WASD + Mouse | Shift: Sprint | ESC: Release cursor
Entities: $(entity_count(s))
"""

render(s, post_process=PostProcessConfig(
    bloom_enabled=true,
    bloom_threshold=1.0f0,
    bloom_intensity=0.3f0,
    tone_mapping=TONEMAP_ACES,
    fxaa_enabled=true,
    gamma=2.2f0
))
