# Audio system — syncs ECS audio components with OpenAL backend

"""
    AudioConfig

Configuration for the audio system.
"""
struct AudioConfig
    doppler_factor::Float32
    speed_of_sound::Float32

    AudioConfig(;
        doppler_factor::Float32 = 1.0f0,
        speed_of_sound::Float32 = 343.3f0
    ) = new(doppler_factor, speed_of_sound)
end

const DEFAULT_AUDIO_CONFIG = AudioConfig()

"""
    update_audio!(dt::Float64; config::AudioConfig = DEFAULT_AUDIO_CONFIG)

Update the audio system each frame:
1. Sync listener position/orientation from entity with AudioListenerComponent
2. Sync source positions, gains, and playback state from AudioSourceComponent entities
3. Clean up sources for removed entities
"""
function update_audio!(dt::Float64; config::AudioConfig = DEFAULT_AUDIO_CONFIG)
    state = get_audio_state()
    if !state.initialized
        return
    end

    # Track which entities still have audio sources
    active_entities = Set{EntityID}()

    # Update listener
    iterate_components(AudioListenerComponent) do entity_id, listener
        al_listenerf(AL_GAIN, listener.gain)

        transform = get_component(entity_id, TransformComponent)
        if transform !== nothing
            world = get_world_transform(entity_id)
            pos_x = Float32(world[1, 4])
            pos_y = Float32(world[2, 4])
            pos_z = Float32(world[3, 4])
            al_listener3f(AL_POSITION, pos_x, pos_y, pos_z)

            # Extract forward (-Z) and up (+Y) from world transform for orientation
            fwd_x = Float32(-world[1, 3])
            fwd_y = Float32(-world[2, 3])
            fwd_z = Float32(-world[3, 3])
            up_x  = Float32(world[1, 2])
            up_y  = Float32(world[2, 2])
            up_z  = Float32(world[3, 2])
            al_listenerfv(AL_ORIENTATION, Float32[fwd_x, fwd_y, fwd_z, up_x, up_y, up_z])
        end
    end

    # Update sources
    iterate_components(AudioSourceComponent) do entity_id, source
        push!(active_entities, entity_id)

        al_source = get_or_create_source!(entity_id)

        # Load and attach buffer if not yet attached
        if !isempty(source.audio_path)
            current_buffer = al_get_sourcei(al_source, AL_BUFFER)
            if current_buffer == 0
                buffer = get_or_load_buffer!(source.audio_path)
                al_sourcei(al_source, AL_BUFFER, Int32(buffer))
            end
        end

        # Sync properties
        al_sourcef(al_source, AL_GAIN, source.gain)
        al_sourcef(al_source, AL_PITCH, source.pitch)
        al_sourcei(al_source, AL_LOOPING, source.looping ? AL_TRUE : AL_FALSE)

        # Spatial properties
        if source.spatial
            al_sourcei(al_source, AL_SOURCE_RELATIVE, AL_FALSE)
            al_sourcef(al_source, AL_REFERENCE_DISTANCE, source.reference_distance)
            al_sourcef(al_source, AL_MAX_DISTANCE, source.max_distance)
            al_sourcef(al_source, AL_ROLLOFF_FACTOR, source.rolloff_factor)

            transform = get_component(entity_id, TransformComponent)
            if transform !== nothing
                world = get_world_transform(entity_id)
                al_source3f(al_source, AL_POSITION,
                           Float32(world[1, 4]), Float32(world[2, 4]), Float32(world[3, 4]))
            end
        else
            # Non-spatial: source relative to listener at origin
            al_sourcei(al_source, AL_SOURCE_RELATIVE, AL_TRUE)
            al_source3f(al_source, AL_POSITION, 0.0f0, 0.0f0, 0.0f0)
        end

        # Playback state
        al_state = al_get_sourcei(al_source, AL_SOURCE_STATE)
        if source.playing && al_state != AL_PLAYING
            al_source_play(al_source)
        elseif !source.playing && al_state == AL_PLAYING
            al_source_stop(al_source)
        end
    end

    # Clean up sources for removed entities
    for (eid, _) in collect(state.sources)
        if eid ∉ active_entities
            remove_source!(eid)
        end
    end

    return nothing
end
