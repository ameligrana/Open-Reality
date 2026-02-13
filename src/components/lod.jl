# Level of Detail (LOD) component

"""
    LODTransitionMode

How LOD transitions are handled visually.
"""
@enum LODTransitionMode begin
    LOD_TRANSITION_INSTANT   # Hard swap, no blending
    LOD_TRANSITION_DITHER    # Bayer dither pattern crossfade (single geometry pass per LOD)
end

"""
    LODLevel

A single LOD level: a mesh and the maximum camera distance at which it's used.
Levels should be sorted by `max_distance` ascending (finest to coarsest).
"""
struct LODLevel
    mesh::MeshComponent
    max_distance::Float32

    LODLevel(; mesh::MeshComponent, max_distance::Float32) = new(mesh, max_distance)
end

"""
    LODComponent <: Component

Holds multiple mesh LOD levels with distance thresholds.

The entity's own `MeshComponent` is used as the finest level (LOD 0) if present,
but the `LODComponent.levels` list provides the authoritative mesh for each distance.

Levels must be sorted by `max_distance` ascending (finest → coarsest).
The last level is used for all distances beyond its `max_distance`.

# Fields
- `levels::Vector{LODLevel}` — LOD levels sorted by max_distance (finest first)
- `transition_mode::LODTransitionMode` — How transitions are rendered
- `transition_width::Float32` — Distance range over which crossfade occurs (world units)
- `hysteresis::Float32` — Multiplier to prevent LOD flickering (e.g., 1.1 = 10% hysteresis band)
"""
struct LODComponent <: Component
    levels::Vector{LODLevel}
    transition_mode::LODTransitionMode
    transition_width::Float32
    hysteresis::Float32

    LODComponent(;
        levels::Vector{LODLevel} = LODLevel[],
        transition_mode::LODTransitionMode = LOD_TRANSITION_DITHER,
        transition_width::Float32 = 2.0f0,
        hysteresis::Float32 = 1.1f0
    ) = new(levels, transition_mode, transition_width, hysteresis)
end
