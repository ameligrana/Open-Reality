# Test: bloom enabled, FXAA disabled — does the window render?
using OpenReality

reset_entity_counter!()
reset_component_stores!()

s = scene([
    create_player(position=Vec3d(0, 1.7, 8)),
    entity([DirectionalLightComponent(direction=Vec3f(0.3, -1.0, -0.5), intensity=2.0f0)]),
    entity([
        sphere_mesh(radius=0.6f0),
        MaterialComponent(color=RGB{Float32}(0.2, 0.8, 0.2), metallic=0.3f0, roughness=0.4f0),
        transform(position=Vec3d(0, 0.6, 0))
    ]),
    entity([
        plane_mesh(width=20.0f0, depth=20.0f0),
        MaterialComponent(color=RGB{Float32}(0.5, 0.5, 0.5), roughness=0.9f0),
        transform()
    ])
])

@info "Test: bloom ON, FXAA OFF"
render(s, post_process=PostProcessConfig(
    bloom_enabled=true,
    bloom_intensity=0.2f0,
    tone_mapping=TONEMAP_ACES,
    fxaa_enabled=false
))
