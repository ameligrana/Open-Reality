# Getting Started with OpenReality

This guide walks you through installing OpenReality and building your first 3D scene.

## Prerequisites

### Julia

OpenReality requires **Julia 1.9** or later. Download it from [julialang.org](https://julialang.org/downloads/).

### System Dependencies

**GLFW** (required for windowing and input):

| OS | Command |
|----|---------|
| Ubuntu / Debian | `sudo apt install libglfw3 libglfw3-dev` |
| Arch Linux | `sudo pacman -S glfw-x11` (or `glfw-wayland`) |
| Fedora | `sudo dnf install glfw glfw-devel` |
| macOS | `brew install glfw` |
| Windows | Download from [glfw.org](https://www.glfw.org/download.html) |

**Vulkan SDK** (optional, only needed for the Vulkan backend):

Download from [lunarg.com](https://vulkan.lunarg.com/sdk/home). On Linux you can also install via your package manager (e.g. `sudo apt install vulkan-tools libvulkan-dev`).

## Installation

Clone the repository and install it as a development package:

```julia
using Pkg
Pkg.develop(path="/path/to/OpenReality")
```

Then load it:

```julia
using OpenReality
```

The first load will precompile all dependencies. This may take a minute.

---

## Tutorial 1: Your First Scene

Let's create a minimal scene with a floor, a light, and a camera you can fly around with.

```julia
using OpenReality

reset_entity_counter!()
reset_component_stores!()

s = scene([
    # FPS camera — gives you WASD + mouse look controls
    create_player(position=Vec3d(0, 1.7, 5)),

    # Sun light
    entity([
        DirectionalLightComponent(
            direction=Vec3f(0.3, -1.0, -0.5),
            intensity=2.0f0
        )
    ]),

    # Floor
    entity([
        plane_mesh(width=20.0f0, depth=20.0f0),
        MaterialComponent(color=RGB{Float32}(0.4, 0.4, 0.4), roughness=0.9f0),
        transform()
    ])
])

render(s)
```

Save this as `my_scene.jl` and run it with `julia my_scene.jl`. A window opens with a gray floor lit by sunlight. Use the controls below to look around.

### Controls

| Key | Action |
|-----|--------|
| W / A / S / D | Move forward / left / back / right |
| Mouse | Look around |
| Shift | Sprint (2x speed) |
| Space | Move up |
| Ctrl | Move down |
| Escape | Release / capture cursor |

---

## Tutorial 2: Adding Objects

Add some geometry to the scene. OpenReality provides three built-in primitives: `cube_mesh()`, `sphere_mesh()`, and `plane_mesh()`.

```julia
using OpenReality

reset_entity_counter!()
reset_component_stores!()

s = scene([
    create_player(position=Vec3d(0, 1.7, 8)),

    # Sun
    entity([
        DirectionalLightComponent(direction=Vec3f(0.3, -1.0, -0.5), intensity=2.0f0)
    ]),

    # Warm point light
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
        transform(position=Vec3d(-2, 0.5, 0))
    ]),

    # Green sphere
    entity([
        sphere_mesh(radius=0.6f0),
        MaterialComponent(
            color=RGB{Float32}(0.2, 0.8, 0.2),
            metallic=0.3f0,
            roughness=0.4f0
        ),
        transform(position=Vec3d(0, 0.6, 0))
    ]),

    # Blue rough cube
    entity([
        cube_mesh(),
        MaterialComponent(
            color=RGB{Float32}(0.1, 0.3, 0.9),
            metallic=0.0f0,
            roughness=0.8f0
        ),
        transform(position=Vec3d(2, 0.5, 0))
    ]),

    # Floor
    entity([
        plane_mesh(width=20.0f0, depth=20.0f0),
        MaterialComponent(color=RGB{Float32}(0.5, 0.5, 0.5), roughness=0.9f0),
        transform()
    ])
])

render(s)
```

Each entity is a list of components. The `MaterialComponent` uses a PBR metallic/roughness workflow:

- **metallic** `0.0` = dielectric (plastic, wood, stone) / `1.0` = metal (gold, chrome)
- **roughness** `0.0` = mirror-smooth / `1.0` = completely rough

---

## Tutorial 3: Physics

Add colliders and rigid bodies to make objects interact physically.

```julia
using OpenReality

reset_entity_counter!()
reset_component_stores!()

s = scene([
    create_player(position=Vec3d(0, 1.7, 8)),

    entity([
        DirectionalLightComponent(direction=Vec3f(0.3, -1.0, -0.5), intensity=2.0f0)
    ]),

    # A ball that falls under gravity
    entity([
        sphere_mesh(radius=0.5f0),
        MaterialComponent(
            color=RGB{Float32}(0.9, 0.3, 0.1),
            metallic=0.0f0,
            roughness=0.5f0
        ),
        transform(position=Vec3d(0, 5, 0)),
        ColliderComponent(shape=SphereShape(0.5f0)),
        RigidBodyComponent(body_type=BODY_DYNAMIC, mass=1.0, restitution=0.6f0)
    ]),

    # Static floor (won't move, but will stop falling objects)
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

Key concepts:
- **`BODY_STATIC`**: Never moves. Use for floors, walls, and terrain.
- **`BODY_KINEMATIC`**: Moved by code (e.g. the player controller), not by forces.
- **`BODY_DYNAMIC`**: Affected by gravity and collisions.
- **`restitution`**: Bounciness. `0.0` = no bounce, `1.0` = perfectly elastic.
- **`ColliderComponent`** defines the collision shape: `AABBShape(half_extents)` for boxes, `SphereShape(radius)` for spheres.

---

## Tutorial 4: Post-Processing

Enable bloom, tone mapping, and anti-aliasing by passing a `PostProcessConfig` to `render()`.

```julia
render(s, post_process=PostProcessConfig(
    bloom_enabled=true,
    bloom_threshold=1.0f0,
    bloom_intensity=0.3f0,
    tone_mapping=TONEMAP_ACES,
    fxaa_enabled=true,
    gamma=2.2f0
))
```

Available tone mapping modes:
- `TONEMAP_REINHARD` — classic, preserves color
- `TONEMAP_ACES` — filmic, cinematic look (recommended)
- `TONEMAP_UNCHARTED2` — similar to the game's tone curve

You can also enable **SSAO** (Screen-Space Ambient Occlusion) for subtle contact shadows:

```julia
render(s, post_process=PostProcessConfig(
    ssao_enabled=true,
    ssao_radius=0.5f0,
    ssao_samples=16,
    tone_mapping=TONEMAP_ACES
))
```

---

## Tutorial 5: Switching Backends

OpenReality supports three rendering backends. Pass the backend you want to `render()`:

```julia
# OpenGL (default, works everywhere)
render(s, backend=OpenGLBackend())

# Vulkan (Linux / Windows)
render(s, backend=VulkanBackend())

# Metal (macOS)
render(s, backend=MetalBackend())
```

All backends support the same features: deferred rendering, PBR, cascaded shadow maps, IBL, SSR, SSAO, TAA, and post-processing.

---

## Tutorial 6: Loading 3D Models

Import glTF 2.0 (`.gltf` / `.glb`) or Wavefront OBJ (`.obj`) models:

```julia
using OpenReality

reset_entity_counter!()
reset_component_stores!()

# load_model returns a Vector{EntityDef}
model_entities = load_model("path/to/model.gltf")

s = scene([
    create_player(position=Vec3d(0, 1.7, 5)),
    entity([DirectionalLightComponent(direction=Vec3f(0.3, -1.0, -0.5), intensity=2.0f0)]),
    model_entities...
])

render(s)
```

The loader automatically extracts meshes, materials, transforms, and animations from the file.

---

## Tutorial 7: Advanced Materials

OpenReality's PBR material system supports several advanced effects:

```julia
# Car paint with clear coat
MaterialComponent(
    color=RGB{Float32}(0.8, 0.1, 0.1),
    metallic=0.9f0,
    roughness=0.4f0,
    clearcoat=1.0f0,
    clearcoat_roughness=0.03f0
)

# Subsurface scattering (skin, wax, jade)
MaterialComponent(
    color=RGB{Float32}(0.9, 0.7, 0.5),
    metallic=0.0f0,
    roughness=0.6f0,
    subsurface=0.8f0,
    subsurface_color=Vec3f(1.0f0, 0.2f0, 0.1f0)
)

# Emissive (glowing objects — works great with bloom)
MaterialComponent(
    color=RGB{Float32}(1.0, 1.0, 1.0),
    emissive_factor=Vec3f(5.0f0, 1.5f0, 0.3f0)
)

# Textured material
MaterialComponent(
    albedo_map=TextureRef("textures/albedo.png"),
    normal_map=TextureRef("textures/normal.png"),
    metallic_roughness_map=TextureRef("textures/mr.png"),
    ao_map=TextureRef("textures/ao.png")
)
```

---

## Troubleshooting

### "GLFW not found" or window fails to open
Make sure GLFW is installed on your system (see Prerequisites above). On Linux, you may also need `libgl1-mesa-dev`.

### Vulkan backend crashes or shows no output
Ensure the Vulkan SDK is installed and your GPU drivers support Vulkan. Run `vulkaninfo` in your terminal to verify.

### Long first load time
Julia compiles everything on first use. Subsequent loads in the same session are instant. Consider using [PackageCompiler.jl](https://github.com/JuliaLang/PackageCompiler.jl) for faster startup.

### Objects are invisible
Make sure every visible entity has both a `MeshComponent` (or a primitive like `cube_mesh()`) and a `MaterialComponent`. Also ensure there is at least one light in the scene.

---

## Next Steps

- [API Reference](api-reference.md) — full documentation of every component, function, and type
- [Architecture](architecture.md) — how the engine works internally
- [Examples](examples.md) — annotated code samples for common patterns
