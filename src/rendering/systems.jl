# Rendering systems

"""
    RenderSystem

System responsible for rendering entities with mesh and material components.
"""
mutable struct RenderSystem
    pipeline::RenderPipeline

    RenderSystem(backend::AbstractBackend) = new(RenderPipeline(backend))
end

"""
    update!(system::RenderSystem, scene::Scene)

Update the render system for the current frame.
"""
function update!(system::RenderSystem, scene::Scene)
    execute!(system.pipeline, scene)
end
