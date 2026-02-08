# Input handling

"""
    InputState

Current state of input devices.
"""
mutable struct InputState
    keys_pressed::Set{Int}
    mouse_position::Tuple{Float64, Float64}
    mouse_buttons::Set{Int}

    InputState() = new(Set{Int}(), (0.0, 0.0), Set{Int}())
end

"""
    is_key_pressed(state::InputState, key::Int) -> Bool

Check if a key is currently pressed.
"""
function is_key_pressed(state::InputState, key::Int)
    return key in state.keys_pressed
end

"""
    get_mouse_position(state::InputState) -> Tuple{Float64, Float64}

Get the current mouse position.
"""
function get_mouse_position(state::InputState)
    return state.mouse_position
end

"""
    setup_input_callbacks!(window::Window, input::InputState)

Register GLFW key, cursor, and mouse button callbacks that update the InputState.
"""
function setup_input_callbacks!(window::Window, input::InputState)
    GLFW.SetKeyCallback(window.handle, (_, key, _, action, _) -> begin
        if action == GLFW.PRESS
            push!(input.keys_pressed, Int(key))
        elseif action == GLFW.RELEASE
            delete!(input.keys_pressed, Int(key))
        end
    end)

    GLFW.SetCursorPosCallback(window.handle, (_, x, y) -> begin
        input.mouse_position = (x, y)
    end)

    GLFW.SetMouseButtonCallback(window.handle, (_, button, action, _) -> begin
        if action == GLFW.PRESS
            push!(input.mouse_buttons, Int(button))
        elseif action == GLFW.RELEASE
            delete!(input.mouse_buttons, Int(button))
        end
    end)

    return nothing
end
