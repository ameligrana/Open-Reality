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

**Directory:** `src/physics/`

A full-featured impulse-based physics engine, pure Julia, no external dependencies.

### Architecture

```
types.jl          Core types: PhysicsWorldConfig, ContactPoint, ContactManifold, AABB3D
shapes.jl         Shape definitions + AABB computation + GJK support functions
inertia.jl        Per-shape inertia tensor computation (box, sphere, capsule, compound)
broadphase.jl     Spatial hash grid broadphase (O(n) pair generation)
narrowphase.jl    Shape-pair collision tests (SAT, closest-point, GJK+EPA dispatch)
gjk_epa.jl        GJK overlap test + EPA penetration depth for convex-convex pairs
contact.jl        Manifold caching + warm-starting + manifold reduction (max 4 points)
solver.jl         Sequential impulse solver (PGS) with Coulomb friction
constraints.jl    Joint constraints: ball-socket, distance, hinge, fixed, slider
triggers.jl       Trigger volumes with enter/stay/exit callbacks
raycast.jl        Ray-shape intersection tests + world raycast query
ccd.jl            Continuous collision detection (swept sphere/capsule + AABB binary search)
islands.jl        Union-find simulation islands for sleeping optimization
world.jl          PhysicsWorld orchestrator: fixed timestep sub-stepping
```

### Per-Step Pipeline

```
1. Update inertia tensors (local → world space via R · I⁻¹ · Rᵀ)
2. Apply gravity + damping to dynamic bodies
3. Broadphase: insert AABBs into spatial hash grid → candidate pairs
4. Narrowphase: shape-pair tests → ContactManifold list
5. Update contact cache (warm-starting from previous frame)
6. Solve velocity constraints:
   a. Prepare solver bodies (cache ECS data)
   b. Pre-step: effective mass, Baumgarte bias, restitution bias
   c. Warm-start: apply cached impulses
   d. Iterate (10 PGS iterations):
      - Contact normal impulse (non-penetration)
      - Coulomb friction (2 tangent directions)
      - Joint constraints (interleaved)
7. Write back velocities to ECS
8. CCD: swept tests for fast-moving bodies
9. Integrate positions + quaternion angular integration
10. Update grounded flags from contact normals
11. Trigger detection (AABB broadphase + narrowphase → callbacks)
12. Island-based sleeping (union-find connected components)
```

### Collider Shapes

| Shape | Description | Narrowphase |
|-------|-------------|-------------|
| `AABBShape` | Axis-aligned box | SAT (3 axes) |
| `SphereShape` | Sphere | Analytic |
| `CapsuleShape` | Cylinder + hemisphere caps | Closest-point on segment |
| `OBBShape` | Oriented bounding box | GJK + EPA |
| `ConvexHullShape` | Arbitrary convex hull | GJK + EPA |
| `CompoundShape` | Multi-child collider | Per-child dispatch |

### Solver

The solver uses **Projected Gauss-Seidel (PGS)** with:
- **Warm-starting**: Accumulated impulses from the previous frame bootstrap convergence
- **Baumgarte stabilization**: Velocity bias corrects position errors (factor=0.2, slop=0.005)
- **Coulomb friction**: Two tangent impulses clamped to friction cone
- **Split impulse**: Position correction separated from velocity correction

Fixed timestep: 1/120s, max 8 substeps per frame, 10 solver iterations.

### Sleeping

Bodies below velocity thresholds accumulate sleep time. When all bodies in a simulation island (connected by contacts or joints) exceed the timer, the island sleeps. External forces or new contacts wake islands.

Default gravity: `(0, -9.81, 0)` m/s².

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
│   ├── rigidbody.jl            # RigidBodyComponent, BodyType, CCDMode
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
├── physics/
│   ├── types.jl                # PhysicsWorldConfig, ContactPoint, ContactManifold
│   ├── shapes.jl               # Shape AABB + GJK support functions
│   ├── inertia.jl              # Inertia tensor computation
│   ├── broadphase.jl           # Spatial hash grid
│   ├── narrowphase.jl          # Shape-pair collision tests
│   ├── gjk_epa.jl              # GJK + EPA for convex colliders
│   ├── contact.jl              # Contact cache + warm-starting
│   ├── solver.jl               # Sequential impulse solver (PGS)
│   ├── constraints.jl          # Joint constraints
│   ├── triggers.jl             # Trigger volumes
│   ├── raycast.jl              # Ray-shape intersection
│   ├── ccd.jl                  # Continuous collision detection
│   ├── islands.jl              # Simulation islands + sleeping
│   └── world.jl                # PhysicsWorld orchestrator
│
├── systems/
│   ├── physics.jl              # update_physics!(dt) API (delegates to PhysicsWorld)
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
├── physics_demo.jl             # Physics engine showcase
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
