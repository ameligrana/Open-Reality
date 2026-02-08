# Rendering pipeline

"""
    RenderPipeline

Manages the rendering pipeline stages and backend lifecycle.
"""
mutable struct RenderPipeline
    backend::AbstractBackend
    active::Bool

    RenderPipeline(backend::AbstractBackend) = new(backend, false)
end

"""
    execute!(pipeline::RenderPipeline, scene::Scene)

Execute the rendering pipeline for the given scene.
Auto-initializes the backend on first call.
"""
function execute!(pipeline::RenderPipeline, scene::Scene)
    if !pipeline.active
        initialize!(pipeline.backend)
        pipeline.active = true
    end
    render_frame!(pipeline.backend, scene)
end

"""
    shutdown!(pipeline::RenderPipeline)

Shutdown the rendering pipeline and its backend.
"""
function shutdown!(pipeline::RenderPipeline)
    if pipeline.active
        shutdown!(pipeline.backend)
        pipeline.active = false
    end
end
