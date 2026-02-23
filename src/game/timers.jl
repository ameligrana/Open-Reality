# =============================================================================
# Timer System — one-shot and repeating timers with entity-scoped ownership
# =============================================================================

const TimerID = UInt64

"""
    Timer

A scheduled callback that fires after a delay, optionally repeating.
"""
mutable struct Timer
    id::TimerID
    delay::Float64
    interval::Float64        # 0 = one-shot, >0 = repeating
    callback::Function
    remaining_repeats::Int   # -1 = infinite, 0 = expired
    elapsed::Float64
    paused::Bool
    owner::Union{EntityID, Nothing}
end

"""
    TimerManager

Manages all active timers. Use `get_timer_manager()` for the global singleton.
"""
mutable struct TimerManager
    timers::Dict{TimerID, Timer}
    next_id::TimerID

    TimerManager() = new(Dict{TimerID, Timer}(), TimerID(1))
end

# ---------------------------------------------------------------------------
# Global singleton
# ---------------------------------------------------------------------------

const _TIMER_MANAGER = Ref{Union{TimerManager, Nothing}}(nothing)

function get_timer_manager()::TimerManager
    if _TIMER_MANAGER[] === nothing
        _TIMER_MANAGER[] = TimerManager()
    end
    return _TIMER_MANAGER[]
end

function reset_timer_manager!()
    _TIMER_MANAGER[] = nothing
    return nothing
end

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

"""
    timer_once!(delay, callback; owner=nothing) -> TimerID

Schedule `callback()` to fire once after `delay` seconds.
If `owner` is an EntityID, the timer is auto-cancelled when the entity is despawned.
"""
function timer_once!(delay::Real, callback::Function;
                     owner::Union{EntityID, Nothing} = nothing)::TimerID
    mgr = get_timer_manager()
    id = mgr.next_id
    mgr.next_id += TimerID(1)
    timer = Timer(id, Float64(delay), 0.0, callback, 1, 0.0, false, owner)
    mgr.timers[id] = timer
    return id
end

"""
    timer_interval!(interval, callback; repeats=-1, owner=nothing) -> TimerID

Schedule `callback()` to fire every `interval` seconds.
`repeats`: number of times to fire (-1 = infinite).
"""
function timer_interval!(interval::Real, callback::Function;
                         repeats::Int = -1,
                         owner::Union{EntityID, Nothing} = nothing)::TimerID
    mgr = get_timer_manager()
    id = mgr.next_id
    mgr.next_id += TimerID(1)
    timer = Timer(id, Float64(interval), Float64(interval), callback, repeats, 0.0, false, owner)
    mgr.timers[id] = timer
    return id
end

"""
    cancel_timer!(id::TimerID)

Cancel a timer by its ID. No-op if the timer doesn't exist or already expired.
"""
function cancel_timer!(id::TimerID)
    mgr = get_timer_manager()
    delete!(mgr.timers, id)
    return nothing
end

"""
    pause_timer!(id::TimerID)

Pause a timer. Elapsed time is frozen until `resume_timer!` is called.
"""
function pause_timer!(id::TimerID)
    mgr = get_timer_manager()
    timer = get(mgr.timers, id, nothing)
    timer !== nothing && (timer.paused = true)
    return nothing
end

"""
    resume_timer!(id::TimerID)

Resume a paused timer.
"""
function resume_timer!(id::TimerID)
    mgr = get_timer_manager()
    timer = get(mgr.timers, id, nothing)
    timer !== nothing && (timer.paused = false)
    return nothing
end

"""
    cancel_entity_timers!(entity_id::EntityID)

Cancel all timers owned by the given entity. Called automatically on despawn.
"""
function cancel_entity_timers!(entity_id::EntityID)
    mgr = get_timer_manager()
    to_remove = TimerID[]
    for (id, timer) in mgr.timers
        if timer.owner === entity_id
            push!(to_remove, id)
        end
    end
    for id in to_remove
        delete!(mgr.timers, id)
    end
    return nothing
end

"""
    update_timers!(dt::Float64)

Advance all timers by `dt` seconds. Fire callbacks for expired timers.
Called once per frame from the main loop.
"""
function update_timers!(dt::Float64)
    mgr = get_timer_manager()
    isempty(mgr.timers) && return nothing

    expired = TimerID[]

    for (id, timer) in mgr.timers
        timer.paused && continue

        timer.elapsed += dt

        if timer.elapsed >= timer.delay
            # Fire callback
            try
                timer.callback()
            catch err
                @warn "Timer callback threw" timer_id=id exception=(err, catch_backtrace())
            end

            if timer.interval > 0 && timer.remaining_repeats != 0
                # Repeating timer: reset elapsed, decrement repeats
                timer.elapsed -= timer.delay
                if timer.remaining_repeats > 0
                    timer.remaining_repeats -= 1
                end
                if timer.remaining_repeats == 0
                    push!(expired, id)
                end
            else
                # One-shot timer: mark for removal
                push!(expired, id)
            end
        end
    end

    for id in expired
        delete!(mgr.timers, id)
    end

    return nothing
end
