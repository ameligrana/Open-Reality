# =============================================================================
# Coroutine System — cooperative multitasking with yield helpers
# =============================================================================

const CoroutineID = UInt64

@enum CoroutineStatus CO_RUNNING CO_SUSPENDED CO_COMPLETED CO_CANCELLED

"""
    CoroutineContext

Handle passed to coroutine functions for yielding.
"""
struct CoroutineContext
    _channel::Channel{Symbol}
    _id::CoroutineID
end

"""
    Coroutine

A cooperative task that can suspend and resume across frames.
"""
mutable struct Coroutine
    id::CoroutineID
    channel::Channel{Symbol}
    task::Task
    status::CoroutineStatus
    wait_seconds::Float64
    wait_frames::Int
    wait_condition::Union{Function, Nothing}
    owner::Union{EntityID, Nothing}
end

"""
    CoroutineManager

Manages all active coroutines. Use `get_coroutine_manager()` for the global singleton.
"""
mutable struct CoroutineManager
    coroutines::Dict{CoroutineID, Coroutine}
    next_id::CoroutineID

    CoroutineManager() = new(Dict{CoroutineID, Coroutine}(), CoroutineID(1))
end

# ---------------------------------------------------------------------------
# Global singleton
# ---------------------------------------------------------------------------

const _COROUTINE_MANAGER = Ref{Union{CoroutineManager, Nothing}}(nothing)

function get_coroutine_manager()::CoroutineManager
    if _COROUTINE_MANAGER[] === nothing
        _COROUTINE_MANAGER[] = CoroutineManager()
    end
    return _COROUTINE_MANAGER[]
end

function reset_coroutine_manager!()
    # Cancel all running coroutines
    if _COROUTINE_MANAGER[] !== nothing
        mgr = _COROUTINE_MANAGER[]
        for (_, co) in mgr.coroutines
            co.status = CO_CANCELLED
            try
                close(co.channel)
            catch
            end
        end
    end
    _COROUTINE_MANAGER[] = nothing
    return nothing
end

# ---------------------------------------------------------------------------
# Yield helpers (called from inside coroutine body)
# ---------------------------------------------------------------------------

"""
    yield_wait(ctx::CoroutineContext, seconds::Float64)

Suspend the coroutine for `seconds` seconds.
"""
function yield_wait(ctx::CoroutineContext, seconds::Real)
    # Signal the manager that we want to wait
    mgr = get_coroutine_manager()
    co = get(mgr.coroutines, ctx._id, nothing)
    co === nothing && return
    co.wait_seconds = Float64(seconds)
    co.wait_frames = 0
    co.wait_condition = nothing
    co.status = CO_SUSPENDED
    # Block until the manager resumes us
    try
        take!(ctx._channel)
    catch
        # Channel closed = coroutine cancelled
    end
    return nothing
end

"""
    yield_frames(ctx::CoroutineContext, n::Int)

Suspend the coroutine for `n` frames.
"""
function yield_frames(ctx::CoroutineContext, n::Int)
    mgr = get_coroutine_manager()
    co = get(mgr.coroutines, ctx._id, nothing)
    co === nothing && return
    co.wait_seconds = 0.0
    co.wait_frames = n
    co.wait_condition = nothing
    co.status = CO_SUSPENDED
    try
        take!(ctx._channel)
    catch
    end
    return nothing
end

"""
    yield_until(ctx::CoroutineContext, condition::Function)

Suspend the coroutine until `condition()` returns `true`.
"""
function yield_until(ctx::CoroutineContext, condition::Function)
    mgr = get_coroutine_manager()
    co = get(mgr.coroutines, ctx._id, nothing)
    co === nothing && return
    co.wait_seconds = 0.0
    co.wait_frames = 0
    co.wait_condition = condition
    co.status = CO_SUSPENDED
    try
        take!(ctx._channel)
    catch
    end
    return nothing
end

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

"""
    start_coroutine!(f::Function; owner=nothing) -> CoroutineID

Start a new coroutine. `f` receives a `CoroutineContext` which provides yield helpers.

```julia
start_coroutine!() do ctx
    println("Starting...")
    yield_wait(ctx, 2.0)
    println("After 2 seconds!")
    yield_frames(ctx, 60)
    println("After 60 frames!")
end
```
"""
function start_coroutine!(f::Function;
                          owner::Union{EntityID, Nothing} = nothing)::CoroutineID
    mgr = get_coroutine_manager()
    id = mgr.next_id
    mgr.next_id += CoroutineID(1)

    channel = Channel{Symbol}(1)
    ctx = CoroutineContext(channel, id)

    task = @task begin
        try
            f(ctx)
        catch e
            if !(e isa InvalidStateException)
                @warn "Coroutine error" coroutine_id=id exception=(e, catch_backtrace())
            end
        finally
            co = get(mgr.coroutines, id, nothing)
            if co !== nothing && co.status != CO_CANCELLED
                co.status = CO_COMPLETED
            end
        end
    end

    co = Coroutine(id, channel, task, CO_RUNNING, 0.0, 0, nothing, owner)
    mgr.coroutines[id] = co

    # Start the task (it will run until first yield or completion)
    schedule(task)

    return id
end

"""
    cancel_coroutine!(id::CoroutineID)

Cancel a running coroutine. The coroutine will not resume.
"""
function cancel_coroutine!(id::CoroutineID)
    mgr = get_coroutine_manager()
    co = get(mgr.coroutines, id, nothing)
    co === nothing && return nothing
    co.status = CO_CANCELLED
    try
        close(co.channel)
    catch
    end
    delete!(mgr.coroutines, id)
    return nothing
end

"""
    cancel_entity_coroutines!(entity_id::EntityID)

Cancel all coroutines owned by the given entity. Called automatically on despawn.
"""
function cancel_entity_coroutines!(entity_id::EntityID)
    mgr = get_coroutine_manager()
    to_cancel = CoroutineID[]
    for (id, co) in mgr.coroutines
        if co.owner === entity_id
            push!(to_cancel, id)
        end
    end
    for id in to_cancel
        cancel_coroutine!(id)
    end
    return nothing
end

"""
    update_coroutines!(dt::Float64)

Advance all suspended coroutines. Resume those whose wait condition is met.
Called once per frame from the main loop.
"""
function update_coroutines!(dt::Float64)
    mgr = get_coroutine_manager()
    isempty(mgr.coroutines) && return nothing

    completed = CoroutineID[]

    for (id, co) in mgr.coroutines
        if co.status == CO_COMPLETED || co.status == CO_CANCELLED
            push!(completed, id)
            continue
        end

        if co.status != CO_SUSPENDED
            continue
        end

        should_resume = false

        if co.wait_condition !== nothing
            # Check condition
            try
                should_resume = co.wait_condition()
            catch err
                @warn "Coroutine condition error" coroutine_id=id exception=(err, catch_backtrace())
                should_resume = true  # Resume on error to avoid stuck coroutines
            end
        elseif co.wait_frames > 0
            co.wait_frames -= 1
            should_resume = co.wait_frames <= 0
        elseif co.wait_seconds > 0
            co.wait_seconds -= dt
            should_resume = co.wait_seconds <= 0
        else
            should_resume = true
        end

        if should_resume
            co.status = CO_RUNNING
            try
                put!(co.channel, :resume)
            catch
                co.status = CO_COMPLETED
            end
            # Yield to let the coroutine run until it yields again or completes
            yield()
        end
    end

    for id in completed
        co = get(mgr.coroutines, id, nothing)
        if co !== nothing
            try
                close(co.channel)
            catch
            end
        end
        delete!(mgr.coroutines, id)
    end

    return nothing
end
