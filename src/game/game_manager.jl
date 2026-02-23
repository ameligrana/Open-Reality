# =============================================================================
# Game Manager — helpers for building and managing the FSM
# =============================================================================

# Note: add_state! is defined in state_machine.jl alongside the FSM struct.
# This file provides additional convenience helpers.

"""
    has_state(fsm, name) -> Bool

Check if a state is registered in the FSM.
"""
function has_state(fsm::GameStateMachine, name::Symbol)::Bool
    return haskey(fsm.states, name)
end

"""
    remove_state!(fsm, name) -> GameStateMachine

Remove a state from the FSM. No-op if the state doesn't exist.
"""
function remove_state!(fsm::GameStateMachine, name::Symbol)
    delete!(fsm.states, name)
    filter!(td -> td.from != name && td.to != name, fsm.transitions)
    return fsm
end
