# LOD (Level of Detail) demo
# Demonstrates automatic LOD switching with dithered crossfade transitions.
# Place spheres at varying distances — each has 3 LOD levels (high, medium, low poly).
# Walk around with WASD to see LOD transitions happen smoothly.

using OpenReality

reset_entity_counter!()
reset_component_stores!()

# Create mesh LODs: high (32 segments), medium (16), low (8)
mesh_high   = sphere_mesh(radius=1.0f0, segments=32)
mesh_medium = sphere_mesh(radius=1.0f0, segments=16)
mesh_low    = sphere_mesh(radius=1.0f0, segments=8)

# Build entities with LODComponent
lod_entities = []
for row in 1:5, col in 1:5
    x = Float64((col - 3) * 6)
    z = Float64(-(row - 1) * 8 - 5)
    push!(lod_entities, entity([
        mesh_high,
        MaterialComponent(
            color=RGB{Float32}(0.2 + 0.15 * col, 0.3, 0.8 - 0.1 * row),
            metallic=0.5f0,
            roughness=0.3f0
        ),
        LODComponent(
            levels=[
                LODLevel(mesh=mesh_high,   max_distance=15.0f0),
                LODLevel(mesh=mesh_medium, max_distance=30.0f0),
                LODLevel(mesh=mesh_low,    max_distance=60.0f0)
            ],
            transition_mode=LOD_TRANSITION_DITHER,
            transition_width=3.0f0,
            hysteresis=1.0f0
        ),
        transform(position=Vec3d(x, 1.0, z))
    ]))
end

s = scene([
    # Player
    create_player(position=Vec3d(0, 1.7, 10)),

    # Sun
    entity([
        DirectionalLightComponent(direction=Vec3f(0.3, -1.0, -0.5), intensity=2.5f0)
    ]),

    # Floor
    entity([
        plane_mesh(width=60.0f0, depth=60.0f0),
        MaterialComponent(color=RGB{Float32}(0.4, 0.4, 0.4), roughness=0.9f0),
        transform(),
        ColliderComponent(shape=AABBShape(Vec3f(30.0, 0.01, 30.0)), offset=Vec3f(0, -0.01, 0)),
        RigidBodyComponent(body_type=BODY_STATIC)
    ]),

    lod_entities...
])

@info "LOD Demo: $(entity_count(s)) entities with 3 LOD levels each"
@info "Walk closer/further to see LOD transitions (dithered crossfade)"
render(s, post_process=PostProcessConfig(
    bloom_enabled=true,
    bloom_intensity=0.2f0,
    tone_mapping=TONEMAP_ACES,
    fxaa_enabled=true
))
