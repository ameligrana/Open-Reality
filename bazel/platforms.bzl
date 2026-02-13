"""Platform constraint helpers for Open Reality."""

# Use with select() to conditionally include macOS-only dependencies.
# Example:
#   data = select({
#       "@platforms//os:macos": ["//metal_bridge:MetalBridge"],
#       "//conditions:default": [],
#   })
