#!/usr/bin/env julia
# Minimal Metal backend test
# Run: julia --project=. examples/metal_test.jl

using OpenReality

reset_entity_counter!()
reset_component_stores!()

s = scene([
    create_player(position=Vec3d(0, 1.7, 5)),

    entity([
        DirectionalLightComponent(direction=Vec3f(0.3, -1.0, -0.5), intensity=2.0f0)
    ]),

    entity([
        cube_mesh(),
        MaterialComponent(color=RGB{Float32}(0.9, 0.1, 0.1), metallic=0.0f0, roughness=0.5f0),
        transform(position=Vec3d(0, 0.5, 0))
    ]),

    entity([
        plane_mesh(width=20.0f0, depth=20.0f0),
        MaterialComponent(color=RGB{Float32}(0.5, 0.5, 0.5)),
        transform()
    ])
])

@info "Scene created with $(entity_count(s)) entities — launching Metal backend..."

render(s, backend=MetalBackend())
