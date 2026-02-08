# OpenReality

A declarative, code-first game engine written in Julia.

## Overview

OpenReality is a game engine that emphasizes declarative scene description and reactive state management. It provides a Julia-native approach to game development with first-class support for functional programming patterns.

## Installation

### System Dependencies

Before using OpenReality, ensure you have the following system dependencies installed:

- **Julia 1.9+**: Download from [julialang.org](https://julialang.org/downloads/)
- **GLFW**: For windowing and input
  - Ubuntu/Debian: `sudo apt install libglfw3 libglfw3-dev`
  - Arch Linux: `sudo pacman -S glfw-x11` or `sudo pacman -S glfw-wayland`
  - macOS: `brew install glfw`
  - Windows: Download from [glfw.org](https://www.glfw.org/download.html)
- **Vulkan SDK** (optional, for Vulkan backend): Download from [lunarg.com](https://vulkan.lunarg.com/sdk/home)

### Julia Package Installation

```julia
using Pkg

# For development (local clone)
Pkg.develop(path="/path/to/OpenReality")

# Or add directly from git (when available)
# Pkg.add(url="https://github.com/your-org/OpenReality.jl")
```

## Quick Start

```julia
using OpenReality

# Create a simple scene
s = scene() do sc
    # Add a camera
    entity(sc) do e
        # Components will be added here
    end

    # Add a light
    entity(sc)

    # Add a cube
    entity(sc)
end

# Start the render loop
render(s)
```

## Module Structure

- `src/ecs.jl` - Entity Component System storage
- `src/scene.jl` - Scene graph management
- `src/state.jl` - Reactive state management
- `src/components/` - Component definitions (transform, mesh, material, camera, lights)
- `src/backend/` - Rendering backend abstractions
- `src/rendering/` - Rendering pipeline and systems
- `src/windowing/` - Window management and input handling
- `src/math/` - Transform and math utilities

## Running Tests

```julia
using Pkg
Pkg.activate(".")
Pkg.test()
```

## Dependencies

- [Observables.jl](https://github.com/JuliaGizmos/Observables.jl) - Reactive state management
- [GeometryBasics.jl](https://github.com/JuliaGeometry/GeometryBasics.jl) - Math types (Vec3, Mat4, Point3)
- [ColorTypes.jl](https://github.com/JuliaGraphics/ColorTypes.jl) - Color types (RGB)
- [StaticArrays.jl](https://github.com/JuliaArrays/StaticArrays.jl) - High-performance fixed-size arrays

## License

MIT License
