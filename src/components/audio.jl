# Audio components

"""
    AudioListenerComponent <: Component

Represents the audio listener (typically attached to camera/player entity).
Only one active listener per scene. Position and orientation are synced
from the entity's TransformComponent each frame.
"""
struct AudioListenerComponent <: Component
    gain::Float32  # Master volume 0.0-1.0

    AudioListenerComponent(;
        gain::Float32 = 1.0f0
    ) = new(gain)
end

"""
    AudioSourceComponent <: Component

A 3D audio source in the scene. Position is synced from TransformComponent.
Set `spatial=false` for non-positional audio (music, UI sounds).
"""
mutable struct AudioSourceComponent <: Component
    audio_path::String
    playing::Bool
    looping::Bool
    gain::Float32
    pitch::Float32
    spatial::Bool
    reference_distance::Float32
    max_distance::Float32
    rolloff_factor::Float32

    AudioSourceComponent(;
        audio_path::String = "",
        playing::Bool = false,
        looping::Bool = false,
        gain::Float32 = 1.0f0,
        pitch::Float32 = 1.0f0,
        spatial::Bool = true,
        reference_distance::Float32 = 1.0f0,
        max_distance::Float32 = 100.0f0,
        rolloff_factor::Float32 = 1.0f0
    ) = new(audio_path, playing, looping, gain, pitch, spatial,
            reference_distance, max_distance, rolloff_factor)
end
