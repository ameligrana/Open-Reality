# Terrain System demo
# Demonstrates procedural Perlin noise terrain with automatic splatmap blending,
# chunk-based LOD, and heightmap physics collision.

using OpenReality

reset_entity_counter!()
reset_component_stores!()

# Create terrain entity with procedural heightmap
terrain_entity = entity([
    TerrainComponent(
        heightmap=HeightmapSource(
            source_type=HEIGHTMAP_PERLIN,
            perlin_octaves=6,
            perlin_frequency=0.008f0,
            perlin_persistence=0.5f0,
            perlin_seed=12345
        ),
        terrain_size=Vec2f(256.0f0, 256.0f0),
        max_height=40.0f0,
        chunk_size=33,
        num_lod_levels=3,
        # Empty splatmap_path → auto-generate altitude-based splatmap
        splatmap_path="",
        layers=TerrainLayer[]  # No custom textures → use default coloring
    ),
    transform()
])

# Dynamic rigid body cubes that fall onto the terrain
falling_cubes = []
shared_cube = cube_mesh()
for i in 1:20
    x = Float64(rand() * 80 - 40)
    z = Float64(rand() * 80 - 40)
    y = 60.0 + Float64(i) * 3.0  # Start high above terrain

    push!(falling_cubes, entity([
        shared_cube,
        MaterialComponent(
            color=RGB{Float32}(0.3 + 0.7 * rand(Float32), 0.3 + 0.7 * rand(Float32), 0.3 + 0.7 * rand(Float32)),
            metallic=0.6f0,
            roughness=0.3f0
        ),
        transform(position=Vec3d(x, y, z)),
        ColliderComponent(shape=AABBShape(Vec3f(0.5, 0.5, 0.5))),
        RigidBodyComponent(body_type=BODY_DYNAMIC)
    ]))
end

s = scene([
    # Player on top of terrain
    create_player(position=Vec3d(0, 50, 30)),

    # Sun (angled to show terrain relief)
    entity([
        DirectionalLightComponent(
            direction=Vec3f(0.4, -0.7, -0.3),
            intensity=2.5f0
        )
    ]),

    # Fill light
    entity([
        PointLightComponent(color=RGB{Float32}(0.5, 0.6, 0.8), intensity=60.0f0, range=50.0f0),
        transform(position=Vec3d(0, 45, 0))
    ]),

    terrain_entity,
    falling_cubes...
])

@info "Terrain Demo: Procedural Perlin terrain (256x256) with $(length(falling_cubes)) falling cubes"
@info "Terrain uses chunk-based LOD and altitude-based splatmap blending"
render(s, post_process=PostProcessConfig(
    bloom_enabled=true,
    bloom_intensity=0.15f0,
    tone_mapping=TONEMAP_ACES,
    fxaa_enabled=true,
    vignette_enabled=true,
    vignette_intensity=0.3f0
))
