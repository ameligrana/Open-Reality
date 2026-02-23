# =============================================================================
# Event Bus — lightweight publish/subscribe for game events
# =============================================================================

"""
    GameEvent

Abstract base type for all game events.
Define concrete event types by subtyping:

```julia
struct EnemyDefeated <: GameEvent
    enemy_id::EntityID
    score::Int
end
```
"""
abstract type GameEvent end

"""
    EventContext

Mutable context passed to event listeners during emission.
Set `cancelled = true` inside a listener to stop propagation to remaining listeners.
"""
mutable struct EventContext
    cancelled::Bool
    EventContext() = new(false)
end

"""
    EventListener

A registered listener with priority, optional filter, and one-shot support.
"""
mutable struct EventListener
    callback::Function
    priority::Int                          # Lower = higher priority (default 100)
    filter::Union{Function, Nothing}       # Predicate: filter(event) -> Bool
    one_shot::Bool                         # Auto-unsubscribe after first invocation
    active::Bool                           # Set to false when scheduled for removal
end

"""
    EventBus

Central event dispatcher. Holds a registry of listeners keyed by event type.
Use the global singleton via `get_event_bus()` rather than constructing directly.
"""
mutable struct EventBus
    listeners::Dict{DataType, Vector{EventListener}}
    deferred_queue::Vector{GameEvent}
    _in_emit::Bool

    EventBus() = new(
        Dict{DataType, Vector{EventListener}}(),
        GameEvent[],
        false
    )
end

# ---------------------------------------------------------------------------
# Global singleton
# ---------------------------------------------------------------------------

const _EVENT_BUS = Ref{Union{EventBus, Nothing}}(nothing)

"""
    get_event_bus() -> EventBus

Return the global `EventBus` singleton, creating it lazily on first access.
"""
function get_event_bus()::EventBus
    if _EVENT_BUS[] === nothing
        _EVENT_BUS[] = EventBus()
    end
    return _EVENT_BUS[]
end

"""
    reset_event_bus!()

Destroy the global `EventBus` singleton so that the next `get_event_bus()` call
creates a fresh instance. Called automatically by `reset_engine_state!()`.
"""
function reset_event_bus!()
    _EVENT_BUS[] = nothing
    return nothing
end

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

"""Insert listener into the list maintaining priority order (lower priority value = earlier execution)."""
function _insert_sorted!(listeners::Vector{EventListener}, listener::EventListener)
    idx = searchsortedfirst(listeners, listener; by=l -> l.priority)
    insert!(listeners, idx, listener)
    return nothing
end

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

"""
    subscribe!(::Type{T}, callback::Function; priority=100, filter=nothing, one_shot=false) where T <: GameEvent

Register `callback` to be invoked whenever an event of type `T` is emitted.
Listeners are called in priority order (lower = earlier). Ties broken by registration order.

The callback can accept either `(event)` or `(event, context::EventContext)`.
Set `context.cancelled = true` to stop propagation.

Returns the `EventListener` handle (can be used for `unsubscribe!`).
"""
function subscribe!(::Type{T}, callback::Function;
                    priority::Int = 100,
                    filter::Union{Function, Nothing} = nothing,
                    one_shot::Bool = false) where T <: GameEvent
    bus = get_event_bus()
    listeners = get!(bus.listeners, T) do
        EventListener[]
    end
    listener = EventListener(callback, priority, filter, one_shot, true)
    _insert_sorted!(listeners, listener)
    return listener
end

"""
    subscribe_once!(::Type{T}, callback::Function; priority=100, filter=nothing) where T <: GameEvent

Convenience for `subscribe!` with `one_shot=true`.
"""
function subscribe_once!(::Type{T}, callback::Function;
                         priority::Int = 100,
                         filter::Union{Function, Nothing} = nothing) where T <: GameEvent
    return subscribe!(T, callback; priority=priority, filter=filter, one_shot=true)
end

"""
    unsubscribe!(::Type{T}, callback::Function) where T <: GameEvent

Remove all listeners for event type `T` whose callback matches `callback` (identity `===`).
"""
function unsubscribe!(::Type{T}, callback::Function) where T <: GameEvent
    bus = get_event_bus()
    haskey(bus.listeners, T) || return nothing
    filter!(l -> l.callback !== callback, bus.listeners[T])
    return nothing
end

"""
    unsubscribe!(listener::EventListener)

Remove a specific listener by handle (marks it inactive).
"""
function unsubscribe!(listener::EventListener)
    listener.active = false
    return nothing
end

"""
    emit!(event::T) where T <: GameEvent -> Bool

Dispatch `event` to all registered listeners for `typeof(event)`.
Listeners are called in priority order. A listener that throws an exception
is caught and logged via `@warn`; remaining listeners still execute.

Returns `true` if the event was NOT cancelled, `false` if a listener cancelled it.
"""
function emit!(event::T) where T <: GameEvent
    bus = get_event_bus()
    cbs = get(bus.listeners, typeof(event), nothing)
    cbs === nothing && return true
    isempty(cbs) && return true

    context = EventContext()
    one_shots_to_remove = EventListener[]
    was_in_emit = bus._in_emit
    bus._in_emit = true

    try
        for listener in copy(cbs)
            !listener.active && continue

            # Apply filter
            if listener.filter !== nothing
                try
                    listener.filter(event) || continue
                catch err
                    @warn "EventBus filter threw" exception=(err, catch_backtrace())
                    continue
                end
            end

            # Call listener
            try
                # Try 2-arg form first (event, context), fall back to 1-arg
                if applicable(listener.callback, event, context)
                    listener.callback(event, context)
                else
                    listener.callback(event)
                end
            catch err
                @warn "EventBus listener threw" exception=(err, catch_backtrace())
            end

            # Track one-shots for removal
            if listener.one_shot
                push!(one_shots_to_remove, listener)
            end

            # Check cancellation
            context.cancelled && break
        end
    finally
        bus._in_emit = was_in_emit
    end

    # Remove one-shot listeners and inactive listeners
    if !isempty(one_shots_to_remove) || any(l -> !l.active, cbs)
        filter!(l -> l.active && l ∉ one_shots_to_remove, bus.listeners[typeof(event)])
    end

    return !context.cancelled
end

"""
    emit_deferred!(event::T) where T <: GameEvent

Queue an event for deferred emission. The event will be dispatched when
`flush_deferred_events!()` is called (typically at the end of the frame).
"""
function emit_deferred!(event::T) where T <: GameEvent
    bus = get_event_bus()
    push!(bus.deferred_queue, event)
    return nothing
end

"""
    flush_deferred_events!()

Dispatch all queued deferred events and clear the queue.
"""
function flush_deferred_events!()
    bus = get_event_bus()
    isempty(bus.deferred_queue) && return nothing
    queue = copy(bus.deferred_queue)
    empty!(bus.deferred_queue)
    for event in queue
        emit!(event)
    end
    return nothing
end
