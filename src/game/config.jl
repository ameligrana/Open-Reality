# =============================================================================
# Game Config — centralized configuration with hot-reload and difficulty presets
# =============================================================================

import TOML

"""
    GameConfig

Centralized key-value configuration store with section support.
Access values via `get_config(Type, "section.key"; default=value)`.
"""
mutable struct GameConfig
    flat::Dict{String, Any}
    file_path::Union{String, Nothing}
    file_mtime::Float64
    difficulty_presets::Dict{Symbol, Dict{String, Any}}
    _active_difficulty::Union{Symbol, Nothing}

    GameConfig() = new(
        Dict{String, Any}(),
        nothing, 0.0,
        Dict{Symbol, Dict{String, Any}}(),
        nothing
    )
end

# ---------------------------------------------------------------------------
# Global singleton
# ---------------------------------------------------------------------------

const _GAME_CONFIG = Ref{Union{GameConfig, Nothing}}(nothing)

"""
    get_game_config() -> GameConfig

Return the global `GameConfig` singleton, creating it lazily on first access.
"""
function get_game_config()::GameConfig
    if _GAME_CONFIG[] === nothing
        _GAME_CONFIG[] = GameConfig()
    end
    return _GAME_CONFIG[]
end

"""
    reset_game_config!()

Destroy the global config singleton so that the next access creates a fresh instance.
"""
function reset_game_config!()
    _GAME_CONFIG[] = nothing
    return nothing
end

# ---------------------------------------------------------------------------
# Flatten helper
# ---------------------------------------------------------------------------

"""Recursively flatten a nested Dict into dot-separated keys."""
function _flatten_dict!(flat::Dict{String, Any}, d::Dict, prefix::String="")
    for (k, v) in d
        key = isempty(prefix) ? string(k) : "$prefix.$k"
        if v isa Dict
            _flatten_dict!(flat, v, key)
        else
            flat[key] = v
        end
    end
end

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

"""
    get_config(::Type{T}, key::String; default::T) where T -> T

Retrieve a config value by dotted key (e.g., `"player.move_speed"`).
Returns `default` if the key does not exist. Converts to the requested type.
"""
function get_config(::Type{T}, key::String; default::T = zero(T)) where T
    cfg = get_game_config()
    val = get(cfg.flat, key, nothing)
    val === nothing && return default
    try
        return convert(T, val)
    catch
        return default
    end
end

"""
    get_config(key::String; default=nothing)

Retrieve a config value without type conversion.
"""
function get_config(key::String; default=nothing)
    cfg = get_game_config()
    return get(cfg.flat, key, default)
end

"""
    set_config!(key::String, value)

Set a config value. Creates the key if it doesn't exist.
"""
function set_config!(key::String, value)
    cfg = get_game_config()
    cfg.flat[key] = value
    return nothing
end

"""
    load_config!(dict::Dict)

Load configuration from a Dict (typically parsed from TOML/JSON).
Flattens nested sections into dot-separated keys.
"""
function load_config!(dict::Dict)
    cfg = get_game_config()
    _flatten_dict!(cfg.flat, dict)
    return nothing
end

"""
    load_config_from_file!(path::String)

Load configuration from a TOML file. Sets up the file path for hot-reload.
"""
function load_config_from_file!(path::String)
    cfg = get_game_config()
    if !isfile(path)
        @warn "Config file not found" path=path
        return nothing
    end
    dict = TOML.parsefile(path)
    cfg.flat = Dict{String, Any}()
    _flatten_dict!(cfg.flat, dict)
    cfg.file_path = path
    cfg.file_mtime = mtime(path)
    return nothing
end

"""
    check_config_reload!() -> Bool

Check if the config file has been modified since last load.
If modified, re-reads the file. Returns `true` if a reload occurred.
"""
function check_config_reload!()::Bool
    cfg = get_game_config()
    cfg.file_path === nothing && return false
    !isfile(cfg.file_path) && return false
    current_mtime = mtime(cfg.file_path)
    if current_mtime > cfg.file_mtime
        try
            dict = TOML.parsefile(cfg.file_path)
            # Preserve difficulty preset overrides if active
            new_flat = Dict{String, Any}()
            _flatten_dict!(new_flat, dict)
            cfg.flat = new_flat
            cfg.file_mtime = current_mtime
            if cfg._active_difficulty !== nothing
                _apply_difficulty_overrides!(cfg, cfg._active_difficulty)
            end
            return true
        catch e
            @warn "Config reload failed" exception=e
        end
    end
    return false
end

"""
    register_difficulty!(name::Symbol, overrides::Dict{String, Any})

Register a difficulty preset. Overrides are dot-separated keys that replace
base config values when the difficulty is applied.

```julia
register_difficulty!(:easy, Dict("enemy.damage" => 5.0, "player.max_hp" => 200.0))
register_difficulty!(:hard, Dict("enemy.damage" => 20.0, "player.max_hp" => 75.0))
```
"""
function register_difficulty!(name::Symbol, overrides::Dict{String, Any})
    cfg = get_game_config()
    cfg.difficulty_presets[name] = overrides
    return nothing
end

"""
    apply_difficulty!(name::Symbol) -> Bool

Apply a registered difficulty preset, overriding matching config keys.
Returns `false` if the preset is not registered.
"""
function apply_difficulty!(name::Symbol)::Bool
    cfg = get_game_config()
    haskey(cfg.difficulty_presets, name) || return false
    cfg._active_difficulty = name
    _apply_difficulty_overrides!(cfg, name)
    return true
end

function _apply_difficulty_overrides!(cfg::GameConfig, name::Symbol)
    overrides = cfg.difficulty_presets[name]
    for (k, v) in overrides
        cfg.flat[k] = v
    end
end

"""
    get_active_difficulty() -> Union{Symbol, Nothing}

Return the currently active difficulty preset name, or `nothing`.
"""
function get_active_difficulty()
    return get_game_config()._active_difficulty
end
