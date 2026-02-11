# OpenReality

A declarative, code-first game engine written in Julia.

OpenReality provides AAA-quality rendering with a clean functional API. Define scenes as composable entity trees, attach PBR materials and physics, and render with a single function call — on OpenGL, Vulkan, or Metal.

## Features

**Rendering**
- Physically-Based Rendering (Cook-Torrance BRDF, metallic/roughness workflow)
- Deferred + forward hybrid pipeline
- Cascaded Shadow Maps (4 cascades)
- Image-Based Lighting (procedural sky, HDR environment maps)
- Screen-Space Reflections (SSR)
- Screen-Space Ambient Occlusion (SSAO)
- Temporal Anti-Aliasing (TAA)
- Post-processing: bloom, tone mapping (Reinhard, ACES, Uncharted2), FXAA
- Advanced materials: clear coat, subsurface scattering, parallax occlusion mapping, emissive

**Engine**
- Entity Component System with O(1) component operations
- Immutable, functional scene graph
- Three rendering backends: OpenGL, Metal (macOS), Vulkan (Linux/Windows)
- AABB and sphere collision detection with gravity
- Keyframe animation with step, linear, and cubic spline interpolation
- glTF 2.0 and OBJ model loading
- Built-in FPS player controller

## Quick Start

### Prerequisites

- **Julia 1.9+** — [julialang.org](https://julialang.org/downloads/)
- **GLFW** — `sudo apt install libglfw3 libglfw3-dev` (Ubuntu) / `brew install glfw` (macOS)
- **Vulkan SDK** (optional) — [lunarg.com](https://vulkan.lunarg.com/sdk/home)

### Install

```julia
using Pkg
Pkg.develop(path="/path/to/OpenReality")
```

### Hello World

```julia
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
        MaterialComponent(color=RGB{Float32}(0.9, 0.1, 0.1), metallic=0.9f0, roughness=0.1f0),
        transform(position=Vec3d(0, 0.5, 0)),
        ColliderComponent(shape=AABBShape(Vec3f(0.5, 0.5, 0.5))),
        RigidBodyComponent(body_type=BODY_STATIC)
    ]),

    entity([
        plane_mesh(width=20.0f0, depth=20.0f0),
        MaterialComponent(color=RGB{Float32}(0.5, 0.5, 0.5), roughness=0.9f0),
        transform()
    ])
])

render(s)
```

### Controls

| Key | Action |
|-----|--------|
| W / A / S / D | Move |
| Mouse | Look around |
| Shift | Sprint |
| Space | Up |
| Ctrl | Down |
| Escape | Release cursor |

## Documentation

| Guide | Description |
|-------|-------------|
| [Getting Started](docs/getting-started.md) | Installation, tutorials, and your first scene |
| [API Reference](docs/api-reference.md) | Complete reference for all components, functions, and types |
| [Architecture](docs/architecture.md) | Engine internals and design decisions |
| [Examples](docs/examples.md) | Annotated code samples for common patterns |

## Running Tests

```julia
using Pkg
Pkg.activate(".")
Pkg.test()
```

## License

MIT License. See [LICENSE](LICENSE) for details.
