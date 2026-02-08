# Abstract backend interface
# Stub - to be implemented

"""
    AbstractBackend

Abstract type for rendering backends.
"""
abstract type AbstractBackend end

"""
    initialize!(backend::AbstractBackend)

Initialize the rendering backend.
"""
function initialize!(backend::AbstractBackend)
    error("initialize! not implemented for $(typeof(backend))")
end

"""
    shutdown!(backend::AbstractBackend)

Shutdown the rendering backend.
"""
function shutdown!(backend::AbstractBackend)
    error("shutdown! not implemented for $(typeof(backend))")
end

"""
    render_frame!(backend::AbstractBackend, scene)

Render a single frame.
"""
function render_frame!(backend::AbstractBackend, scene)
    error("render_frame! not implemented for $(typeof(backend))")
end
