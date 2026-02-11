# Architecture

This document describes how OpenReality is structured internally. It is intended for contributors and advanced users who want to understand or extend the engine.

---

## High-Level Overview

```
┌─────────────────────────────────────────────────────────────┐
│                        User Code                            │
│   scene([...])  →  render(scene, backend=..., ...)          │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│                     Core Engine                              │
│  ┌──────────┐  ┌───────────┐  ┌──────────┐  ┌───────────┐  │
│  │   ECS    │  │   Scene   │  │   Math   │  │  Loading  │  │
│  │ ecs.jl   │  │ scene.jl  │  │transforms│  │ gltf/obj  │  │
│  └──────────┘  └───────────┘  └──────────┘  └───────────┘  │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│                       Systems                                │
│  ┌────────────────┐  ┌───────────┐  ┌────────────────────┐  │
│  │ Player Control │  │ Animation │  │      Physics       │  │
│  │player_controller│ │animation.jl│ │    physics.jl      │  │
│  └────────────────┘  └───────────┘  └────────────────────┘  │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│                  Rendering Pipeline                          │
│  ┌──────────────────┐  ┌─────────────┐  ┌───────────────┐  │
│  │Frame Preparation │  │   Shader    │  │   Frustum     │  │
│  │(backend-agnostic)│  │  Variants   │  │   Culling     │  │
│  └──────────────────┘  └─────────────┘  └───────────────┘  │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│                   Backend Abstraction                        │
│                     abstract.jl                              │
│  ┌──────────┐      ┌──────────┐      ┌──────────┐          │
│  │  OpenGL  │      │  Metal   │      │  Vulkan  │          │
│  │ 31 files │      │ 18 files │      │ 17 files │          │
│  └──────────┘      └──────────┘      └──────────┘          │
└─────────────────────────────────────────────────────────────┘
```

---

## Entity Component System

**File:** `src/ecs.jl`

OpenReality uses a data-oriented ECS with global component storage.

### Design

- **`EntityID`** is a `UInt64`. A global counter (`ENTITY_COUNTER`) generates unique IDs.
- **`ComponentStore{T}`** holds all components of type `T` in a contiguous `Vector{T}`, with `Dict{EntityID, Int}` for O(1) entity-to-index lookup and a reverse `Dict{Int, EntityID}` map.
- **`COMPONENT_STORES`** is a global `Dict{DataType, ComponentStore}` that maps each component type to its store.
- Component stores are created lazily on first `add_component!` call for a new type.

### Removal Strategy

Components are removed using **swap-and-pop**: the target element is swapped with the last element in the array, then the array is truncated. This keeps the array contiguous (good for cache) and makes removal O(1).

### Thread Safety

The current ECS is single-threaded. All mutations happen in the main thread during system updates.

---

## Scene Graph

**File:** `src/scene.jl`

The scene graph is **immutable and functional**. Every operation that modifies the scene (add entity, remove entity) returns a new `Scene` struct. The original is never mutated.

```julia
struct Scene
    entities::Vector{EntityID}
    hierarchy::Dict{EntityID, Vector{EntityID}}
    root_entities::Vector{EntityID}
end
```

### EntityDef Builder

Users never create entities directly. Instead, they build `EntityDef` blueprints using `entity()` and pass them to `scene()`:

```julia
s = scene([
    entity([component1, component2], children=[
        entity([component3])
    ])
])
```

The `scene()` constructor walks the `EntityDef` tree in DFS order, assigns real `EntityID`s, registers components in the global ECS, and builds the hierarchy.

### Hierarchy

Parent-child relationships are stored in `hierarchy::Dict{EntityID, Vector{EntityID}}`. Transforms are hierarchical: a child's world transform is computed by composing its local transform with its parent's world transform.

---

## Rendering Pipeline

### Per-Frame Flow

```
1. Input
   └─ GLFW poll events → update InputState

2. System Updates (sequential)
   ├─ update_player!(controller, input, dt)
   ├─ update_animations!(dt)
   └─ update_physics!(dt)

3. Frame Preparation (backend-agnostic)
   ├─ Find active camera → compute view + projection matrices
   ├─ Extract frustum planes
   ├─ Iterate entities with MeshComponent
   │   ├─ Frustum cull using bounding spheres
   │   ├─ Classify: opaque vs transparent
   │   └─ Sort transparent entities back-to-front
   ├─ Collect lights (directional, point, IBL)
   └─ Return FrameData struct

4. Backend Rendering
   ├─ CSM shadow depth passes (4 cascades)
   ├─ G-Buffer geometry pass (deferred)
   ├─ Deferred lighting pass (fullscreen quad)
   ├─ Forward pass (transparent objects)
   ├─ SSAO pass
   ├─ SSR pass
   ├─ TAA pass
   ├─ Post-processing (bloom, tone mapping, FXAA)
   └─ Final composite to screen

5. Swap Buffers
```

### Frame Preparation

**File:** `src/rendering/frame_preparation.jl`

`prepare_frame(scene, bounds_cache)` collects everything the backend needs to render:
- Camera matrices (view, projection)
- Frustum for culling
- Opaque and transparent entity lists with their transforms, meshes, materials
- Light data (up to 16 point lights, 4 directional, 1 IBL)

This runs once per frame, independent of which backend is active.

### Shader Variant System

**File:** `src/rendering/shader_variants.jl`

Instead of a single uber-shader with many branches, OpenReality compiles shader **variants** on demand based on which features a material uses:

```
Material has albedo_map + normal_map
  → ShaderVariantKey({FEATURE_ALBEDO_MAP, FEATURE_NORMAL_MAP})
  → Compile with #define FEATURE_ALBEDO_MAP / #define FEATURE_NORMAL_MAP
  → Cache the compiled shader for reuse
```

Feature flags: `FEATURE_ALBEDO_MAP`, `FEATURE_NORMAL_MAP`, `FEATURE_METALLIC_ROUGHNESS_MAP`, `FEATURE_AO_MAP`, `FEATURE_EMISSIVE_MAP`, `FEATURE_ALPHA_CUTOFF`, `FEATURE_CLEARCOAT`, `FEATURE_PARALLAX_MAPPING`, `FEATURE_SUBSURFACE`.

---

## Backend Abstraction

**File:** `src/backend/abstract.jl`

All backends implement the `AbstractBackend` interface. Key methods:

| Method | Purpose |
|--------|---------|
| `initialize!(backend; width, height, title)` | Create window and GPU context |
| `shutdown!(backend)` | Clean up resources |
| `render_frame!(backend, scene)` | Render one frame |
| `backend_create_shader(backend, vert, frag)` | Compile shader program |
| `backend_upload_mesh!(backend, id, mesh)` | Upload mesh to GPU |
| `backend_upload_texture!(backend, path)` | Load and upload texture |
| `backend_create_gbuffer!(backend, w, h)` | Create G-Buffer |
| `backend_draw_fullscreen_quad!(backend)` | Draw screen-space quad |

**GPU resource types** (in `src/backend/gpu_types.jl`) define abstract types that each backend concretely implements:
- `AbstractShaderProgram`
- `AbstractGPUMesh`, `AbstractGPUResourceCache`
- `AbstractGPUTexture`, `AbstractTextureCache`
- `AbstractFramebuffer`, `AbstractGBuffer`
- `AbstractShadowMap`, `AbstractCascadedShadowMap`
- `AbstractIBLEnvironment`
- `AbstractSSRPass`, `AbstractSSAOPass`, `AbstractTAAPass`
- `AbstractPostProcessPipeline`, `AbstractDeferredPipeline`

### OpenGL Backend

**Directory:** `src/backend/opengl/` (31 files)

Uses OpenGL 3.3 core profile via ModernGL.jl. Key features:
- Deferred rendering with 4-target G-Buffer (RGBA16F)
- 4-cascade shadow maps at 2048x2048 resolution
- Inline GLSL shaders in Julia source files
- VAO/VBO mesh management with GPU resource caching
- Lazy texture loading with mipmaps

### Metal Backend

**Directory:** `src/backend/metal/` (18 files)

macOS-only, uses native Metal API via FFI (`metal_ffi.jl`). Shader files live in `src/backend/metal/shaders/` as `.metal` files. Same feature set as OpenGL.

### Vulkan Backend

**Directory:** `src/backend/vulkan/` (17 files)

Linux/Windows, uses Vulkan.jl bindings. Includes device selection, memory management, descriptor sets, and swapchain management.

---

## Physics System

**File:** `src/systems/physics.jl`

Simple collision detection and response:

1. **Broadphase**: Compute world-space AABBs for all entities with colliders. Test all pairs for AABB overlap.
2. **Narrowphase**: For overlapping pairs, compute exact penetration depth and collision normal. Supports AABB-AABB, AABB-Sphere, and Sphere-Sphere pairs.
3. **Response**: Separate overlapping bodies along the collision normal. Adjust velocities based on restitution.
4. **Integration**: Apply gravity to dynamic bodies, integrate velocity into position.

Default gravity: `(0, -9.81, 0)` m/s.

---

## Player Controller

**File:** `src/systems/player_controller.jl`

The FPS player controller activates automatically when the scene contains a `PlayerComponent`. It:
- Finds the player entity and its camera child
- Captures the mouse cursor
- Processes WASD input relative to camera facing direction
- Updates yaw/pitch from mouse delta
- Applies movement via kinematic velocity

---

## Animation System

**File:** `src/systems/animation.jl`

Called once per frame via `update_animations!(dt)`. Advances the timeline for each `AnimationComponent`, interpolates keyframes, and applies the result to target entity transforms.

Interpolation modes: `INTERP_STEP` (snap), `INTERP_LINEAR` (lerp/slerp), `INTERP_CUBICSPLINE` (cubic Hermite).

---

## File Organization

```
src/
├── OpenReality.jl              # Main module — includes, exports
├── ecs.jl                      # Entity Component System
├── scene.jl                    # Immutable scene graph
├── state.jl                    # Reactive state (Observable alias)
│
├── components/
│   ├── transform.jl            # TransformComponent (Observable-based)
│   ├── mesh.jl                 # MeshComponent
│   ├── material.jl             # MaterialComponent (PBR)
│   ├── camera.jl               # CameraComponent
│   ├── lights.jl               # PointLight, DirectionalLight, IBL
│   ├── collider.jl             # ColliderComponent, AABBShape, SphereShape
│   ├── rigidbody.jl            # RigidBodyComponent, BodyType
│   ├── animation.jl            # AnimationComponent, AnimationClip
│   ├── primitives.jl           # cube_mesh, sphere_mesh, plane_mesh
│   └── player.jl               # PlayerComponent, create_player
│
├── math/
│   └── transforms.jl           # Matrix utilities, type aliases
│
├── windowing/
│   ├── glfw.jl                 # GLFW window management
│   └── input.jl                # InputState (keyboard, mouse)
│
├── systems/
│   ├── physics.jl              # Collision detection + response
│   ├── animation.jl            # Animation update loop
│   └── player_controller.jl    # FPS input handling
│
├── rendering/
│   ├── pipeline.jl             # RenderPipeline manager
│   ├── pbr_pipeline.jl         # Main render loop (run_render_loop!)
│   ├── frame_preparation.jl    # Backend-agnostic frame data
│   ├── shader_variants.jl      # Shader permutation system
│   ├── frustum_culling.jl      # View frustum culling
│   ├── camera_utils.jl         # Camera matrix helpers
│   ├── csm.jl                  # Cascaded shadow maps
│   ├── ibl.jl                  # Image-based lighting
│   ├── ssao.jl                 # Screen-space ambient occlusion
│   ├── ssr.jl                  # Screen-space reflections
│   ├── taa.jl                  # Temporal anti-aliasing
│   ├── post_processing.jl      # Tone mapping, bloom, FXAA
│   └── ...                     # Framebuffer, G-Buffer, etc.
│
├── backend/
│   ├── abstract.jl             # AbstractBackend interface
│   ├── gpu_types.jl            # Abstract GPU resource types
│   ├── opengl/                 # OpenGL implementation (31 files)
│   ├── metal/                  # Metal implementation (18 files)
│   └── vulkan/                 # Vulkan implementation (17 files)
│
└── loading/
    ├── loader.jl               # Format dispatcher
    ├── gltf_loader.jl          # glTF 2.0 loader
    └── obj_loader.jl           # OBJ loader

examples/
├── basic_scene.jl              # Simple PBR scene
├── pbr_showcase.jl             # Advanced materials + post-processing
├── boulder_scene.jl            # Primitives showcase
├── vulkan_test.jl              # Vulkan backend test
├── metal_test.jl               # Metal backend test
└── vulkan_minimal_test.jl      # Minimal Vulkan test

test/
└── runtests.jl                 # Test suite
```

---

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| **Immutable scene graph** | Functional composition, no shared mutable state, enables time-travel debugging |
| **Global ECS registry** | Simple, avoids passing World objects everywhere, fits Julia's module system |
| **Observable transforms** | Reactive updates for debugging and future editor integration |
| **Double-precision transforms** | Numerical stability for hierarchical transform chains; converted to float32 for GPU |
| **Shader variants over uber-shaders** | Smaller shader programs, fewer GPU branches, better performance |
| **Backend abstraction** | Single codebase supports OpenGL, Metal, and Vulkan without code duplication |
| **Deferred + forward hybrid** | Efficient multi-light rendering for opaque geometry, correct blending for transparency |
