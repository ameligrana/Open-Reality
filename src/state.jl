# Reactive state management
# Stub - to be implemented

using Observables

"""
    State{T}

Reactive state container using Observables.
"""
const State{T} = Observable{T}

"""
    state(value)

Create a reactive state with the given initial value.
"""
state(value) = Observable(value)
