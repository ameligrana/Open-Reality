# =============================================================================
# Game State Machine — states, transitions with guards, history, and nesting
# =============================================================================

abstract type GameState end

# ---------------------------------------------------------------------------
# Transition types
# ---------------------------------------------------------------------------

"""
    TransitionGuard

A condition that must return `true` for a transition to proceed.
"""
struct TransitionGuard
    condition::Function     # () -> Bool
    description::String

    TransitionGuard(condition::Function; description::String = "") =
        new(condition, description)
end

"""
    TransitionDef

A defined transition between two states with optional guards and callbacks.
"""
mutable struct TransitionDef
    from::Symbol
    to::Symbol
    guards::Vector{TransitionGuard}
    on_transition::Union{Function, Nothing}
    new_scene_defs::Union{Vector, Nothing}
end

"""
    StateTransition

Result object returned from `transition!` or `on_update!` to trigger a state switch.
"""
mutable struct StateTransition
    target::Symbol
    new_scene_defs::Union{Vector, Nothing}
end

StateTransition(target::Symbol) = StateTransition(target, nothing)

# ---------------------------------------------------------------------------
# Events
# ---------------------------------------------------------------------------

struct StateChangedEvent <: GameEvent
    from::Symbol
    to::Symbol
end

# ---------------------------------------------------------------------------
# FSM container
# ---------------------------------------------------------------------------

"""
    GameStateMachine

Manages game states, transitions, and state history.
"""
mutable struct GameStateMachine
    states::Dict{Symbol, GameState}
    transitions::Vector{TransitionDef}
    current_state::Union{Symbol, Nothing}
    history::Vector{Symbol}
    initial_state::Symbol
    initial_scene_defs::Vector
    _entered::Bool

    function GameStateMachine(initial_state::Symbol, initial_scene_defs::Vector)
        new(
            Dict{Symbol, GameState}(),
            TransitionDef[],
            nothing,
            Symbol[],
            initial_state,
            initial_scene_defs,
            false
        )
    end
end

# ---------------------------------------------------------------------------
# Composite (nested) state
# ---------------------------------------------------------------------------

"""
    CompositeState <: GameState

A state that contains a sub-FSM, enabling hierarchical state machines.
"""
mutable struct CompositeState <: GameState
    sub_fsm::GameStateMachine
    _ui_callback::Union{Function, Nothing}

    CompositeState(sub_fsm::GameStateMachine; ui_callback=nothing) =
        new(sub_fsm, ui_callback)
end

# ---------------------------------------------------------------------------
# Default dispatch — users override what they need
# ---------------------------------------------------------------------------

on_enter!(state::GameState, sc::Scene) = nothing
on_update!(state::GameState, sc::Scene, dt::Float64, ctx::GameContext) = nothing
on_exit!(state::GameState, sc::Scene) = nothing
get_ui_callback(state::GameState) = nothing

# CompositeState delegates to its sub-FSM's current state
function on_enter!(state::CompositeState, sc::Scene)
    fsm = state.sub_fsm
    if fsm.current_state === nothing
        fsm.current_state = fsm.initial_state
    end
    sub_state = get(fsm.states, fsm.current_state, nothing)
    sub_state !== nothing && on_enter!(sub_state, sc)
    return nothing
end

function on_update!(state::CompositeState, sc::Scene, dt::Float64, ctx::GameContext)
    fsm = state.sub_fsm
    sub_state = get(fsm.states, fsm.current_state, nothing)
    sub_state === nothing && return nothing
    result = on_update!(sub_state, sc, dt, ctx)
    # Handle sub-FSM transitions internally
    if result isa StateTransition
        _execute_transition!(fsm, result.target, sc; new_scene_defs=result.new_scene_defs)
        return nothing  # Don't propagate sub-transitions to parent
    end
    return result
end

function on_exit!(state::CompositeState, sc::Scene)
    fsm = state.sub_fsm
    sub_state = get(fsm.states, fsm.current_state, nothing)
    sub_state !== nothing && on_exit!(sub_state, sc)
    return nothing
end

function get_ui_callback(state::CompositeState)
    if state._ui_callback !== nothing
        return state._ui_callback
    end
    fsm = state.sub_fsm
    sub_state = get(fsm.states, fsm.current_state, nothing)
    return sub_state !== nothing ? get_ui_callback(sub_state) : nothing
end

# ---------------------------------------------------------------------------
# FSM management
# ---------------------------------------------------------------------------

"""
    add_state!(fsm, name, state) -> GameStateMachine

Register a state in the FSM. Returns the FSM for chaining.
"""
function add_state!(fsm::GameStateMachine, name::Symbol, state::GameState)
    fsm.states[name] = state
    return fsm
end

"""
    add_transition!(fsm, from, to; guards=[], on_transition=nothing, new_scene_defs=nothing)

Define a valid transition between two states with optional guards and callbacks.
"""
function add_transition!(fsm::GameStateMachine, from::Symbol, to::Symbol;
                         guards::Vector{TransitionGuard} = TransitionGuard[],
                         on_transition::Union{Function, Nothing} = nothing,
                         new_scene_defs::Union{Vector, Nothing} = nothing)
    push!(fsm.transitions, TransitionDef(from, to, guards, on_transition, new_scene_defs))
    return fsm
end

"""
    transition!(fsm, target; new_scene_defs=nothing) -> Union{StateTransition, Nothing}

Attempt to transition to `target` state. Checks all matching `TransitionDef` guards.
Returns a `StateTransition` on success, or `nothing` if guards reject or no valid transition exists.

If no `TransitionDef` is registered for the from→to pair, the transition proceeds
unconditionally (unguarded transition).
"""
function transition!(fsm::GameStateMachine, target::Symbol;
                     new_scene_defs::Union{Vector, Nothing} = nothing)::Union{StateTransition, Nothing}
    current = fsm.current_state !== nothing ? fsm.current_state : fsm.initial_state

    # Find matching transition definitions
    matching = filter(fsm.transitions) do td
        td.from == current && td.to == target
    end

    if !isempty(matching)
        # Check guards on the first matching transition
        td = matching[1]
        for guard in td.guards
            try
                if !guard.condition()
                    return nothing  # Guard rejected
                end
            catch e
                @warn "Transition guard error" from=current to=target description=guard.description exception=e
                return nothing
            end
        end
        # Fire transition callback
        if td.on_transition !== nothing
            try
                td.on_transition()
            catch e
                @warn "on_transition callback error" from=current to=target exception=e
            end
        end
        # Use scene defs from transition def if not provided explicitly
        scene = new_scene_defs !== nothing ? new_scene_defs : td.new_scene_defs
        return StateTransition(target, scene)
    end

    # No transition def: allow unconditionally
    return StateTransition(target, new_scene_defs)
end

"""
    transition_to_previous!(fsm) -> Union{StateTransition, Nothing}

Transition back to the most recent previous state from history.
Returns `nothing` if there is no history.
"""
function transition_to_previous!(fsm::GameStateMachine)::Union{StateTransition, Nothing}
    isempty(fsm.history) && return nothing
    prev = pop!(fsm.history)
    return StateTransition(prev, nothing)
end

"""
    get_current_state(fsm) -> Union{Symbol, Nothing}

Return the name of the current state.
"""
function get_current_state(fsm::GameStateMachine)::Union{Symbol, Nothing}
    return fsm.current_state
end

"""
    get_state_history(fsm) -> Vector{Symbol}

Return the state history stack (most recent last).
"""
function get_state_history(fsm::GameStateMachine)::Vector{Symbol}
    return copy(fsm.history)
end

# ---------------------------------------------------------------------------
# Internal: execute a transition (used by CompositeState)
# ---------------------------------------------------------------------------

function _execute_transition!(fsm::GameStateMachine, target::Symbol, sc::Scene;
                              new_scene_defs=nothing)
    current = fsm.current_state
    if current !== nothing
        push!(fsm.history, current)
        sub_state = get(fsm.states, current, nothing)
        sub_state !== nothing && on_exit!(sub_state, sc)
    end
    fsm.current_state = target
    new_state = get(fsm.states, target, nothing)
    new_state !== nothing && on_enter!(new_state, sc)
    try
        emit!(StateChangedEvent(current !== nothing ? current : :none, target))
    catch
    end
    return nothing
end
