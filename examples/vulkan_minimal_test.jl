#!/usr/bin/env julia
# Minimal Vulkan backend test
using OpenReality
using OpenReality: initialize!, render_frame!, shutdown!

println("1. Creating backend")
backend = VulkanBackend()

println("2. Initializing...")
initialize!(backend; width=800, height=600, title="Test")
println("3. Init succeeded")

println("Done - shutting down")
shutdown!(backend)
println("Shutdown complete")
