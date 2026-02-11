# Examples

Annotated code samples demonstrating common patterns in OpenReality.

---

## Basic Scene

A complete scene with FPS controls, lighting, and PBR objects.

```julia
using OpenReality

reset_entity_counter!()
reset_component_stores!()

s = scene([
    # FPS player at eye height
    create_player(position=Vec3d(0, 1.7, 8)),

    # Sunlight
    entity([
        DirectionalLightComponent(
            direction=Vec3f(0.3, -1.0, -0.5),
            intensity=2.0f0
        )
    ]),

    # Warm point light, elevated and offset
    entity([
        PointLightComponent(
            color=RGB{Float32}(1.0, 0.9, 0.8),
            intensity=30.0f0,
            range=20.0f0
        ),
        transform(position=Vec3d(3, 4, 2))
    ]),

    # Red metallic cube
    entity([
        cube_mesh(),
        MaterialComponent(
            color=RGB{Float32}(0.9, 0.1, 0.1),
            metallic=0.9f0,
            roughness=0.1f0
        ),
        transform(position=Vec3d(-2, 0.5, 0)),
        ColliderComponent(shape=AABBShape(Vec3f(0.5, 0.5, 0.5))),
        RigidBodyComponent(body_type=BODY_STATIC)
    ]),

    # Green sphere
    entity([
        sphere_mesh(radius=0.6f0),
        MaterialComponent(
            color=RGB{Float32}(0.2, 0.8, 0.2),
            metallic=0.3f0,
            roughness=0.4f0
        ),
        transform(position=Vec3d(0, 0.6, 0)),
        ColliderComponent(shape=SphereShape(0.6f0)),
        RigidBodyComponent(body_type=BODY_STATIC)
    ]),

    # Floor
    entity([
        plane_mesh(width=20.0f0, depth=20.0f0),
        MaterialComponent(color=RGB{Float32}(0.5, 0.5, 0.5), roughness=0.9f0),
        transform(),
        ColliderComponent(shape=AABBShape(Vec3f(10.0, 0.01, 10.0)), offset=Vec3f(0, -0.01, 0)),
        RigidBodyComponent(body_type=BODY_STATIC)
    ])
])

render(s)
```

---

## PBR Material Variations

Demonstrates how `metallic` and `roughness` affect appearance.

```julia
# Metallic gold, varying roughness (mirror → rough)
for (i, r) in enumerate([0.0f0, 0.3f0, 0.6f0, 1.0f0])
    entity([
        sphere_mesh(radius=0.8f0),
        MaterialComponent(
            color=RGB{Float32}(0.9, 0.8, 0.6),   # Gold
            metallic=1.0f0,
            roughness=r
        ),
        transform(position=Vec3d(-6 + (i-1)*2, 1.5, 0)),
        ColliderComponent(shape=SphereShape(0.8f0)),
        RigidBodyComponent(body_type=BODY_STATIC)
    ])
end

# Dielectric (non-metallic) colored spheres
for (i, (r, g, b)) in enumerate([(0.8,0.2,0.2), (0.2,0.8,0.2), (0.2,0.2,0.8)])
    entity([
        sphere_mesh(radius=0.8f0),
        MaterialComponent(
            color=RGB{Float32}(r, g, b),
            metallic=0.0f0,
            roughness=0.3f0 + i * 0.2f0
        ),
        transform(position=Vec3d(2 + (i-1)*2, 1.5, 0)),
        ColliderComponent(shape=SphereShape(0.8f0)),
        RigidBodyComponent(body_type=BODY_STATIC)
    ])
end
```

---

## Advanced Materials

### Clear Coat (car paint, lacquer)

```julia
entity([
    sphere_mesh(radius=0.8f0),
    MaterialComponent(
        color=RGB{Float32}(0.8, 0.1, 0.1),       # Deep red base
        metallic=0.9f0,
        roughness=0.4f0,
        clearcoat=1.0f0,                           # Full clear coat
        clearcoat_roughness=0.03f0                  # Very smooth top layer
    ),
    transform(position=Vec3d(0, 1.5, 0))
])
```

### Subsurface Scattering (skin, wax, jade)

```julia
# Skin-like material
entity([
    sphere_mesh(radius=0.8f0),
    MaterialComponent(
        color=RGB{Float32}(0.9, 0.7, 0.5),
        metallic=0.0f0,
        roughness=0.6f0,
        subsurface=0.8f0,
        subsurface_color=Vec3f(1.0f0, 0.2f0, 0.1f0)  # Reddish glow
    ),
    transform(position=Vec3d(-2, 1.5, 0))
])

# Jade-like material
entity([
    sphere_mesh(radius=0.8f0),
    MaterialComponent(
        color=RGB{Float32}(0.3, 0.7, 0.4),
        metallic=0.0f0,
        roughness=0.3f0,
        subsurface=0.6f0,
        subsurface_color=Vec3f(0.1f0, 0.8f0, 0.2f0)  # Green glow
    ),
    transform(position=Vec3d(2, 1.5, 0))
])
```

### Emissive (glowing objects)

```julia
entity([
    cube_mesh(),
    MaterialComponent(
        color=RGB{Float32}(1.0, 1.0, 1.0),
        emissive_factor=Vec3f(5.0f0, 1.5f0, 0.3f0)   # Warm orange glow
    ),
    transform(position=Vec3d(0, 1, 0))
])
```

Emissive values above 1.0 will trigger bloom when `bloom_enabled=true` in the post-process config.

---

## Image-Based Lighting + Cascaded Shadows

For photorealistic outdoor scenes, combine IBL with a directional light for CSM shadows.

```julia
s = scene([
    create_player(position=Vec3d(0, 2.0, 15)),

    # Procedural sky IBL
    entity([
        IBLComponent(
            environment_path="sky",
            intensity=1.0f0,
            enabled=true
        )
    ]),

    # Sun with warm tint (triggers CSM automatically)
    entity([
        DirectionalLightComponent(
            direction=Vec3f(0.3, -1.0, -0.5),
            intensity=3.0f0,
            color=RGB{Float32}(1.0, 0.95, 0.9)
        )
    ]),

    # Colored point lights to showcase deferred multi-light rendering
    entity([
        PointLightComponent(color=RGB{Float32}(1.0, 0.3, 0.3), intensity=25.0f0, range=15.0f0),
        transform(position=Vec3d(-8, 3, 0))
    ]),
    entity([
        PointLightComponent(color=RGB{Float32}(0.3, 1.0, 0.3), intensity=25.0f0, range=15.0f0),
        transform(position=Vec3d(8, 3, 0))
    ]),
    entity([
        PointLightComponent(color=RGB{Float32}(0.3, 0.3, 1.0), intensity=25.0f0, range=15.0f0),
        transform(position=Vec3d(0, 3, -8))
    ]),

    # Scene geometry...
    entity([
        plane_mesh(width=100.0f0, depth=100.0f0),
        MaterialComponent(color=RGB{Float32}(0.3, 0.3, 0.3), roughness=0.9f0),
        transform(),
        ColliderComponent(shape=AABBShape(Vec3f(50.0, 0.01, 50.0)), offset=Vec3f(0, -0.01, 0)),
        RigidBodyComponent(body_type=BODY_STATIC)
    ])
])

render(s, post_process=PostProcessConfig(
    bloom_enabled=true,
    bloom_threshold=1.0f0,
    bloom_intensity=0.3f0,
    tone_mapping=TONEMAP_ACES,
    fxaa_enabled=true,
    gamma=2.2f0
))
```

---

## Post-Processing Configurations

### Cinematic (film look)

```julia
PostProcessConfig(
    bloom_enabled=true,
    bloom_threshold=1.0f0,
    bloom_intensity=0.3f0,
    tone_mapping=TONEMAP_ACES,
    fxaa_enabled=true,
    gamma=2.2f0
)
```

### High-Quality (maximum visual fidelity)

```julia
PostProcessConfig(
    bloom_enabled=true,
    bloom_threshold=0.8f0,
    bloom_intensity=0.4f0,
    ssao_enabled=true,
    ssao_radius=0.5f0,
    ssao_samples=16,
    tone_mapping=TONEMAP_ACES,
    fxaa_enabled=true,
    gamma=2.2f0
)
```

### Minimal (best performance)

```julia
PostProcessConfig(
    tone_mapping=TONEMAP_REINHARD,
    gamma=2.2f0
)
```

---

## Loading 3D Models

```julia
using OpenReality

reset_entity_counter!()
reset_component_stores!()

# Load a glTF model — returns Vector{EntityDef}
entities = load_model("assets/helmet.gltf")

s = scene([
    create_player(position=Vec3d(0, 1.7, 3)),
    entity([DirectionalLightComponent(direction=Vec3f(0.3, -1.0, -0.5), intensity=2.0f0)]),
    entity([IBLComponent(environment_path="sky", intensity=1.0f0)]),
    entities...   # Splat model entities into the scene
])

render(s)
```

Supported formats:
- `.gltf` / `.glb` — glTF 2.0 (meshes, materials, hierarchy, animations)
- `.obj` — Wavefront OBJ (meshes only, optional material override)

---

## Hierarchical Entities

Create parent-child relationships for grouped transforms.

```julia
# A "table" made from a top and four legs
table = entity([
    transform(position=Vec3d(0, 0.75, 0))
], children=[
    # Table top
    entity([
        cube_mesh(),
        MaterialComponent(color=RGB{Float32}(0.6, 0.4, 0.2), roughness=0.7f0),
        transform(scale=Vec3d(2.0, 0.1, 1.0))
    ]),
    # Legs (positioned relative to parent)
    entity([
        cube_mesh(),
        MaterialComponent(color=RGB{Float32}(0.5, 0.3, 0.1), roughness=0.8f0),
        transform(position=Vec3d(-0.9, -0.4, -0.4), scale=Vec3d(0.1, 0.7, 0.1))
    ]),
    entity([
        cube_mesh(),
        MaterialComponent(color=RGB{Float32}(0.5, 0.3, 0.1), roughness=0.8f0),
        transform(position=Vec3d(0.9, -0.4, -0.4), scale=Vec3d(0.1, 0.7, 0.1))
    ]),
    entity([
        cube_mesh(),
        MaterialComponent(color=RGB{Float32}(0.5, 0.3, 0.1), roughness=0.8f0),
        transform(position=Vec3d(-0.9, -0.4, 0.4), scale=Vec3d(0.1, 0.7, 0.1))
    ]),
    entity([
        cube_mesh(),
        MaterialComponent(color=RGB{Float32}(0.5, 0.3, 0.1), roughness=0.8f0),
        transform(position=Vec3d(0.9, -0.4, 0.4), scale=Vec3d(0.1, 0.7, 0.1))
    ])
])
```

Child transforms are relative to their parent. Moving the parent moves all children together.

---

## Generating Entities Programmatically

Use Julia's standard array comprehensions and splatting to generate entities:

```julia
# Row of cubes extending into the distance
cubes = [entity([
    cube_mesh(),
    MaterialComponent(
        color=RGB{Float32}(0.6, 0.4, 0.2),
        roughness=0.7f0
    ),
    transform(
        position=Vec3d(0, 0.5, -Float64(i * 5)),
        scale=Vec3d(0.8, 1.0, 0.8)
    ),
    ColliderComponent(shape=AABBShape(Vec3f(0.8, 1.0, 0.8))),
    RigidBodyComponent(body_type=BODY_STATIC)
]) for i in 1:20]

s = scene([
    create_player(position=Vec3d(0, 1.7, 5)),
    entity([DirectionalLightComponent(direction=Vec3f(0.3, -1.0, -0.5), intensity=2.0f0)]),
    entity([plane_mesh(width=100.0f0, depth=100.0f0), MaterialComponent(roughness=0.9f0), transform()]),
    cubes...   # Splat generated entities
])
```

---

## Using Different Backends

```julia
# OpenGL (default)
render(s)
render(s, backend=OpenGLBackend())

# Vulkan (Linux/Windows)
render(s, backend=VulkanBackend(), title="OpenReality — Vulkan")

# Metal (macOS)
render(s, backend=MetalBackend())

# Custom window size
render(s, width=1920, height=1080, title="Full HD Scene")
```

All three backends support the full feature set: deferred rendering, PBR, CSM, IBL, SSR, SSAO, TAA, and post-processing.
