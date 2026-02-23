# =============================================================================
# Tween / Easing System — smooth property interpolation with easing curves
# =============================================================================

const TweenID = UInt64

@enum TweenStatus TWEEN_ACTIVE TWEEN_PAUSED TWEEN_COMPLETED TWEEN_CANCELLED
@enum TweenLoopMode TWEEN_ONCE TWEEN_LOOP TWEEN_PING_PONG

# ---------------------------------------------------------------------------
# Easing functions (all map [0,1] -> [0,1])
# ---------------------------------------------------------------------------

ease_linear(t::Float64) = t

ease_in_quad(t::Float64) = t * t
ease_out_quad(t::Float64) = t * (2.0 - t)
ease_in_out_quad(t::Float64) = t < 0.5 ? 2.0 * t * t : -1.0 + (4.0 - 2.0 * t) * t

ease_in_cubic(t::Float64) = t^3
ease_out_cubic(t::Float64) = (t - 1.0)^3 + 1.0
ease_in_out_cubic(t::Float64) = t < 0.5 ? 4.0 * t^3 : (t - 1.0) * (2.0 * t - 2.0)^2 + 1.0

ease_in_sine(t::Float64) = 1.0 - cos(t * π / 2.0)
ease_out_sine(t::Float64) = sin(t * π / 2.0)
ease_in_out_sine(t::Float64) = -(cos(π * t) - 1.0) / 2.0

ease_in_expo(t::Float64) = t ≈ 0.0 ? 0.0 : 2.0^(10.0 * (t - 1.0))
ease_out_expo(t::Float64) = t ≈ 1.0 ? 1.0 : 1.0 - 2.0^(-10.0 * t)

ease_in_back(t::Float64) = begin s = 1.70158; t * t * ((s + 1.0) * t - s) end
ease_out_back(t::Float64) = begin s = 1.70158; t2 = t - 1.0; t2 * t2 * ((s + 1.0) * t2 + s) + 1.0 end

function ease_out_bounce(t::Float64)
    if t < 1.0 / 2.75
        return 7.5625 * t * t
    elseif t < 2.0 / 2.75
        t2 = t - 1.5 / 2.75
        return 7.5625 * t2 * t2 + 0.75
    elseif t < 2.5 / 2.75
        t2 = t - 2.25 / 2.75
        return 7.5625 * t2 * t2 + 0.9375
    else
        t2 = t - 2.625 / 2.75
        return 7.5625 * t2 * t2 + 0.984375
    end
end
ease_in_bounce(t::Float64) = 1.0 - ease_out_bounce(1.0 - t)

function ease_in_elastic(t::Float64)
    t ≈ 0.0 && return 0.0
    t ≈ 1.0 && return 1.0
    p = 0.3
    s = p / 4.0
    return -(2.0^(10.0 * (t - 1.0)) * sin((t - 1.0 - s) * 2.0 * π / p))
end

function ease_out_elastic(t::Float64)
    t ≈ 0.0 && return 0.0
    t ≈ 1.0 && return 1.0
    p = 0.3
    s = p / 4.0
    return 2.0^(-10.0 * t) * sin((t - s) * 2.0 * π / p) + 1.0
end

# ---------------------------------------------------------------------------
# Tween struct
# ---------------------------------------------------------------------------

"""
    Tween

Represents an active property interpolation on an entity.
"""
mutable struct Tween
    id::TweenID
    entity::EntityID
    property::Symbol
    start_value::Any
    end_value::Any
    duration::Float64
    elapsed::Float64
    easing::Function
    status::TweenStatus
    loop_mode::TweenLoopMode
    loop_count::Int          # -1 = infinite
    _current_loop::Int
    _forward::Bool
    on_complete::Union{Function, Nothing}
    _next_tween::Union{TweenID, Nothing}
    _start_captured::Bool
end

"""
    TweenManager

Manages all active tweens. Use `get_tween_manager()` for the global singleton.
"""
mutable struct TweenManager
    tweens::Dict{TweenID, Tween}
    next_id::TweenID

    TweenManager() = new(Dict{TweenID, Tween}(), TweenID(1))
end

# ---------------------------------------------------------------------------
# Global singleton
# ---------------------------------------------------------------------------

const _TWEEN_MANAGER = Ref{Union{TweenManager, Nothing}}(nothing)

function get_tween_manager()::TweenManager
    if _TWEEN_MANAGER[] === nothing
        _TWEEN_MANAGER[] = TweenManager()
    end
    return _TWEEN_MANAGER[]
end

function reset_tween_manager!()
    _TWEEN_MANAGER[] = nothing
    return nothing
end

# ---------------------------------------------------------------------------
# Property accessors
# ---------------------------------------------------------------------------

function _tween_get(entity::EntityID, prop::Symbol)
    if prop == :position
        tc = get_component(entity, TransformComponent)
        return tc !== nothing ? Vec3d(tc.position[]) : nothing
    elseif prop == :scale
        tc = get_component(entity, TransformComponent)
        return tc !== nothing ? Vec3d(tc.scale[]) : nothing
    elseif prop == :rotation
        tc = get_component(entity, TransformComponent)
        if tc !== nothing
            return Quaterniond(tc.rotation_w[], tc.rotation_x[], tc.rotation_y[], tc.rotation_z[])
        end
        return nothing
    elseif prop == :color
        mc = get_component(entity, MaterialComponent)
        if mc !== nothing
            return Vec3f(red(mc.color), green(mc.color), blue(mc.color))
        end
        return nothing
    elseif prop == :opacity
        mc = get_component(entity, MaterialComponent)
        return mc !== nothing ? mc.opacity : nothing
    end
    return nothing
end

function _tween_set!(entity::EntityID, prop::Symbol, value)
    if prop == :position
        tc = get_component(entity, TransformComponent)
        tc !== nothing && (tc.position[] = value)
    elseif prop == :scale
        tc = get_component(entity, TransformComponent)
        tc !== nothing && (tc.scale[] = value)
    elseif prop == :rotation
        tc = get_component(entity, TransformComponent)
        if tc !== nothing
            tc.rotation_w[] = value.s
            tc.rotation_x[] = value.v1
            tc.rotation_y[] = value.v2
            tc.rotation_z[] = value.v3
        end
    elseif prop == :color
        mc = get_component(entity, MaterialComponent)
        if mc !== nothing
            new_mc = MaterialComponent(
                color = RGB{Float32}(value[1], value[2], value[3]),
                metallic = mc.metallic,
                roughness = mc.roughness,
                opacity = mc.opacity,
                albedo_map = mc.albedo_map,
                normal_map = mc.normal_map,
                metallic_roughness_map = mc.metallic_roughness_map,
                ao_map = mc.ao_map,
                emissive_map = mc.emissive_map,
                emissive_color = mc.emissive_color,
                emissive_intensity = mc.emissive_intensity,
                alpha_cutoff = mc.alpha_cutoff,
                clear_coat = mc.clear_coat,
                clear_coat_roughness = mc.clear_coat_roughness,
                parallax_scale = mc.parallax_scale,
                subsurface = mc.subsurface,
                height_map = mc.height_map
            )
            add_component!(entity, new_mc)
        end
    elseif prop == :opacity
        mc = get_component(entity, MaterialComponent)
        if mc !== nothing
            new_mc = MaterialComponent(
                color = mc.color,
                metallic = mc.metallic,
                roughness = mc.roughness,
                opacity = Float32(value),
                albedo_map = mc.albedo_map,
                normal_map = mc.normal_map,
                metallic_roughness_map = mc.metallic_roughness_map,
                ao_map = mc.ao_map,
                emissive_map = mc.emissive_map,
                emissive_color = mc.emissive_color,
                emissive_intensity = mc.emissive_intensity,
                alpha_cutoff = mc.alpha_cutoff,
                clear_coat = mc.clear_coat,
                clear_coat_roughness = mc.clear_coat_roughness,
                parallax_scale = mc.parallax_scale,
                subsurface = mc.subsurface,
                height_map = mc.height_map
            )
            add_component!(entity, new_mc)
        end
    end
    return nothing
end

function _tween_lerp(a, b, t::Float64)
    # Generic lerp for Vec3d, Vec3f, Float32, Float64
    return a + (b - a) * t
end

function _tween_lerp(a::Quaterniond, b::Quaterniond, t::Float64)
    # Spherical linear interpolation for quaternions
    dot_val = a.s * b.s + a.v1 * b.v1 + a.v2 * b.v2 + a.v3 * b.v3
    b_adj = dot_val < 0 ? Quaterniond(-b.s, -b.v1, -b.v2, -b.v3) : b
    dot_val = abs(dot_val)
    if dot_val > 0.9995
        # Very close: use linear interpolation to avoid division by zero
        result = a + (b_adj - a) * t
        norm = sqrt(result.s^2 + result.v1^2 + result.v2^2 + result.v3^2)
        return Quaterniond(result.s / norm, result.v1 / norm, result.v2 / norm, result.v3 / norm)
    end
    theta = acos(dot_val)
    sin_theta = sin(theta)
    wa = sin((1.0 - t) * theta) / sin_theta
    wb = sin(t * theta) / sin_theta
    return Quaterniond(
        wa * a.s + wb * b_adj.s,
        wa * a.v1 + wb * b_adj.v1,
        wa * a.v2 + wb * b_adj.v2,
        wa * a.v3 + wb * b_adj.v3
    )
end

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

"""
    tween!(entity, property, target, duration; easing, loop_mode, loop_count, on_complete) -> TweenID

Create a tween that interpolates `property` of `entity` toward `target` over `duration` seconds.

Supported properties: `:position`, `:scale`, `:rotation`, `:color`, `:opacity`.

```julia
tween!(entity_id, :position, Vec3d(10, 0, 0), 2.0; easing=ease_out_quad)
tween!(entity_id, :opacity, 0.0f0, 1.0; easing=ease_in_sine, on_complete=() -> println("done"))
```
"""
function tween!(entity::EntityID, property::Symbol, target, duration::Real;
                easing::Function = ease_linear,
                loop_mode::TweenLoopMode = TWEEN_ONCE,
                loop_count::Int = 1,
                on_complete::Union{Function, Nothing} = nothing)::TweenID
    mgr = get_tween_manager()
    id = mgr.next_id
    mgr.next_id += TweenID(1)

    tw = Tween(id, entity, property,
               nothing, target,   # start_value captured on first update
               Float64(duration), 0.0,
               easing, TWEEN_ACTIVE,
               loop_mode, loop_count, 0, true,
               on_complete, nothing, false)
    mgr.tweens[id] = tw
    return id
end

"""
    then!(first_id::TweenID, next_id::TweenID) -> TweenID

Chain `next_id` to start when `first_id` completes. Returns `next_id`.
The next tween is paused until the first completes.
"""
function then!(first_id::TweenID, next_id::TweenID)::TweenID
    mgr = get_tween_manager()
    first = get(mgr.tweens, first_id, nothing)
    next = get(mgr.tweens, next_id, nothing)
    first === nothing && return next_id
    next === nothing && return next_id
    first._next_tween = next_id
    next.status = TWEEN_PAUSED
    return next_id
end

"""
    tween_sequence!(ids::Vector{TweenID}) -> TweenID

Chain multiple tweens in sequence. Returns the first tween's ID.
"""
function tween_sequence!(ids::Vector{TweenID})::TweenID
    for i in 1:(length(ids)-1)
        then!(ids[i], ids[i+1])
    end
    return ids[1]
end

"""
    cancel_tween!(id::TweenID)

Cancel a tween by ID.
"""
function cancel_tween!(id::TweenID)
    mgr = get_tween_manager()
    delete!(mgr.tweens, id)
    return nothing
end

"""
    pause_tween!(id::TweenID)

Pause a tween.
"""
function pause_tween!(id::TweenID)
    mgr = get_tween_manager()
    tw = get(mgr.tweens, id, nothing)
    tw !== nothing && (tw.status = TWEEN_PAUSED)
    return nothing
end

"""
    resume_tween!(id::TweenID)

Resume a paused tween.
"""
function resume_tween!(id::TweenID)
    mgr = get_tween_manager()
    tw = get(mgr.tweens, id, nothing)
    tw !== nothing && tw.status == TWEEN_PAUSED && (tw.status = TWEEN_ACTIVE)
    return nothing
end

"""
    cancel_entity_tweens!(entity::EntityID)

Cancel all tweens targeting the given entity. Called automatically on despawn.
"""
function cancel_entity_tweens!(entity::EntityID)
    mgr = get_tween_manager()
    to_remove = TweenID[]
    for (id, tw) in mgr.tweens
        if tw.entity === entity
            push!(to_remove, id)
        end
    end
    for id in to_remove
        delete!(mgr.tweens, id)
    end
    return nothing
end

"""
    update_tweens!(dt::Float64)

Advance all active tweens by `dt` seconds. Called once per frame.
"""
function update_tweens!(dt::Float64)
    mgr = get_tween_manager()
    isempty(mgr.tweens) && return nothing

    completed = TweenID[]

    for (id, tw) in mgr.tweens
        tw.status != TWEEN_ACTIVE && continue

        # Capture start value on first update
        if !tw._start_captured
            tw.start_value = _tween_get(tw.entity, tw.property)
            tw.start_value === nothing && (push!(completed, id); continue)
            tw._start_captured = true
        end

        tw.elapsed += dt
        raw_t = clamp(tw.elapsed / tw.duration, 0.0, 1.0)

        # Apply direction for ping-pong
        t = tw._forward ? raw_t : 1.0 - raw_t

        # Apply easing
        eased_t = tw.easing(t)

        # Interpolate and set
        new_value = _tween_lerp(tw.start_value, tw.end_value, eased_t)
        _tween_set!(tw.entity, tw.property, new_value)

        # Check completion
        if tw.elapsed >= tw.duration
            if tw.loop_mode == TWEEN_LOOP
                tw._current_loop += 1
                if tw.loop_count > 0 && tw._current_loop >= tw.loop_count
                    push!(completed, id)
                else
                    tw.elapsed = 0.0
                end
            elseif tw.loop_mode == TWEEN_PING_PONG
                tw._forward = !tw._forward
                tw._current_loop += 1
                if tw.loop_count > 0 && tw._current_loop >= tw.loop_count * 2
                    push!(completed, id)
                else
                    tw.elapsed = 0.0
                end
            else
                push!(completed, id)
            end
        end
    end

    for id in completed
        tw = get(mgr.tweens, id, nothing)
        tw === nothing && continue
        tw.status = TWEEN_COMPLETED

        # Fire on_complete callback
        if tw.on_complete !== nothing
            try
                tw.on_complete()
            catch e
                @warn "Tween on_complete error" tween_id=id exception=e
            end
        end

        # Activate chained tween
        if tw._next_tween !== nothing
            next = get(mgr.tweens, tw._next_tween, nothing)
            if next !== nothing
                next.status = TWEEN_ACTIVE
            end
        end

        delete!(mgr.tweens, id)
    end

    return nothing
end
