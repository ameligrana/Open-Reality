# =============================================================================
# Behavior Tree System — composable AI logic with blackboard state
# =============================================================================

# ---------------------------------------------------------------------------
# Status enum
# ---------------------------------------------------------------------------

@enum BTStatus BT_SUCCESS BT_FAILURE BT_RUNNING

# ---------------------------------------------------------------------------
# Abstract node
# ---------------------------------------------------------------------------

abstract type BTNode end

# ---------------------------------------------------------------------------
# Composite nodes
# ---------------------------------------------------------------------------

"""
    SequenceNode <: BTNode

Runs children left-to-right. Returns FAILURE on the first child that fails.
Returns RUNNING if a child is running (resumes from that child next tick).
Returns SUCCESS if all children succeed.
"""
mutable struct SequenceNode <: BTNode
    children::Vector{BTNode}
    _running_index::Int
    SequenceNode(children::BTNode...) = new(collect(BTNode, children), 1)
    SequenceNode(children::Vector{BTNode}) = new(children, 1)
end

"""
    SelectorNode <: BTNode

Runs children left-to-right. Returns SUCCESS on the first child that succeeds.
Returns RUNNING if a child is running. Returns FAILURE if all children fail.
"""
mutable struct SelectorNode <: BTNode
    children::Vector{BTNode}
    _running_index::Int
    SelectorNode(children::BTNode...) = new(collect(BTNode, children), 1)
    SelectorNode(children::Vector{BTNode}) = new(children, 1)
end

"""
    ParallelNode <: BTNode

Runs all children each tick. Returns SUCCESS when `success_threshold` children succeed.
Returns FAILURE when it's impossible to reach the threshold.
"""
mutable struct ParallelNode <: BTNode
    children::Vector{BTNode}
    success_threshold::Int
    ParallelNode(children::BTNode...; success_threshold::Int=0) =
        new(collect(BTNode, children), success_threshold == 0 ? length(children) : success_threshold)
    ParallelNode(children::Vector{BTNode}; success_threshold::Int=0) =
        new(children, success_threshold == 0 ? length(children) : success_threshold)
end

# ---------------------------------------------------------------------------
# Leaf nodes
# ---------------------------------------------------------------------------

"""
    ActionNode <: BTNode

Leaf node that executes a function: `(entity_id, blackboard, dt) -> BTStatus`.
"""
struct ActionNode <: BTNode
    action::Function
end

"""
    ConditionNode <: BTNode

Leaf node that evaluates a predicate: `(entity_id, blackboard) -> Bool`.
Returns SUCCESS if true, FAILURE if false.
"""
struct ConditionNode <: BTNode
    predicate::Function
end

# ---------------------------------------------------------------------------
# Decorator nodes
# ---------------------------------------------------------------------------

"""
    InverterNode <: BTNode

Inverts the child's result: SUCCESS ↔ FAILURE. RUNNING passes through.
"""
struct InverterNode <: BTNode
    child::BTNode
end

"""
    RepeatNode <: BTNode

Repeats the child `count` times (-1 = infinite). Returns RUNNING until all repetitions complete.
"""
mutable struct RepeatNode <: BTNode
    child::BTNode
    count::Int
    _current::Int
    RepeatNode(child::BTNode; count::Int=-1) = new(child, count, 0)
end

"""
    SucceederNode <: BTNode

Always returns SUCCESS regardless of child result (except RUNNING).
"""
struct SucceederNode <: BTNode
    child::BTNode
end

"""
    TimeoutNode <: BTNode

Wraps a child with a time limit. Returns FAILURE if timeout expires.
"""
mutable struct TimeoutNode <: BTNode
    child::BTNode
    timeout::Float64
    _elapsed::Float64
    TimeoutNode(child::BTNode, timeout::Real) = new(child, Float64(timeout), 0.0)
end

# ---------------------------------------------------------------------------
# Blackboard
# ---------------------------------------------------------------------------

"""
    Blackboard

Per-entity key-value store for sharing state between behavior tree nodes.
"""
mutable struct Blackboard
    data::Dict{Symbol, Any}
    Blackboard() = new(Dict{Symbol, Any}())
end

"""Get a value from the blackboard, returning `default` if not found."""
function bb_get(bb::Blackboard, key::Symbol, default=nothing)
    return get(bb.data, key, default)
end

"""Set a value in the blackboard."""
function bb_set!(bb::Blackboard, key::Symbol, value)
    bb.data[key] = value
    return nothing
end

"""Check if a key exists in the blackboard."""
function bb_has(bb::Blackboard, key::Symbol)::Bool
    return haskey(bb.data, key)
end

"""Remove a key from the blackboard."""
function bb_delete!(bb::Blackboard, key::Symbol)
    delete!(bb.data, key)
    return nothing
end

# ---------------------------------------------------------------------------
# BehaviorTreeComponent
# ---------------------------------------------------------------------------

"""
    BehaviorTreeComponent <: Component

Attaches a behavior tree to an entity for AI control.

`tick_rate`: Seconds between ticks (0 = every frame). Useful for reducing AI CPU cost.
"""
mutable struct BehaviorTreeComponent <: Component
    root::BTNode
    blackboard::Blackboard
    enabled::Bool
    _tick_rate::Float64
    _accumulator::Float64

    BehaviorTreeComponent(root::BTNode;
        blackboard::Blackboard = Blackboard(),
        tick_rate::Real = 0.0
    ) = new(root, blackboard, true, Float64(tick_rate), 0.0)
end

# ---------------------------------------------------------------------------
# Tick dispatch
# ---------------------------------------------------------------------------

function tick(node::SequenceNode, eid::EntityID, bb::Blackboard, dt::Float64)::BTStatus
    for i in node._running_index:length(node.children)
        status = tick(node.children[i], eid, bb, dt)
        if status == BT_RUNNING
            node._running_index = i
            return BT_RUNNING
        elseif status == BT_FAILURE
            node._running_index = 1
            return BT_FAILURE
        end
    end
    node._running_index = 1
    return BT_SUCCESS
end

function tick(node::SelectorNode, eid::EntityID, bb::Blackboard, dt::Float64)::BTStatus
    for i in node._running_index:length(node.children)
        status = tick(node.children[i], eid, bb, dt)
        if status == BT_RUNNING
            node._running_index = i
            return BT_RUNNING
        elseif status == BT_SUCCESS
            node._running_index = 1
            return BT_SUCCESS
        end
    end
    node._running_index = 1
    return BT_FAILURE
end

function tick(node::ParallelNode, eid::EntityID, bb::Blackboard, dt::Float64)::BTStatus
    success_count = 0
    failure_count = 0
    for child in node.children
        status = tick(child, eid, bb, dt)
        if status == BT_SUCCESS
            success_count += 1
        elseif status == BT_FAILURE
            failure_count += 1
        end
    end
    if success_count >= node.success_threshold
        return BT_SUCCESS
    end
    remaining = length(node.children) - failure_count
    if remaining < node.success_threshold
        return BT_FAILURE
    end
    return BT_RUNNING
end

function tick(node::ActionNode, eid::EntityID, bb::Blackboard, dt::Float64)::BTStatus
    return node.action(eid, bb, dt)
end

function tick(node::ConditionNode, eid::EntityID, bb::Blackboard, dt::Float64)::BTStatus
    return node.predicate(eid, bb) ? BT_SUCCESS : BT_FAILURE
end

function tick(node::InverterNode, eid::EntityID, bb::Blackboard, dt::Float64)::BTStatus
    status = tick(node.child, eid, bb, dt)
    status == BT_SUCCESS && return BT_FAILURE
    status == BT_FAILURE && return BT_SUCCESS
    return BT_RUNNING
end

function tick(node::RepeatNode, eid::EntityID, bb::Blackboard, dt::Float64)::BTStatus
    status = tick(node.child, eid, bb, dt)
    if status == BT_RUNNING
        return BT_RUNNING
    end
    node._current += 1
    if node.count > 0 && node._current >= node.count
        node._current = 0
        return BT_SUCCESS
    end
    return BT_RUNNING
end

function tick(node::SucceederNode, eid::EntityID, bb::Blackboard, dt::Float64)::BTStatus
    status = tick(node.child, eid, bb, dt)
    return status == BT_RUNNING ? BT_RUNNING : BT_SUCCESS
end

function tick(node::TimeoutNode, eid::EntityID, bb::Blackboard, dt::Float64)::BTStatus
    node._elapsed += dt
    if node._elapsed >= node.timeout
        node._elapsed = 0.0
        return BT_FAILURE
    end
    status = tick(node.child, eid, bb, dt)
    if status != BT_RUNNING
        node._elapsed = 0.0
    end
    return status
end

# ---------------------------------------------------------------------------
# Builder API — convenience constructors
# ---------------------------------------------------------------------------

bt_sequence(children::BTNode...) = SequenceNode(children...)
bt_selector(children::BTNode...) = SelectorNode(children...)
bt_parallel(children::BTNode...; threshold::Int=0) = ParallelNode(children...; success_threshold=threshold)
bt_action(f::Function) = ActionNode(f)
bt_condition(f::Function) = ConditionNode(f)
bt_invert(child::BTNode) = InverterNode(child)
bt_repeat(child::BTNode; count::Int=-1) = RepeatNode(child; count=count)
bt_succeed(child::BTNode) = SucceederNode(child)
bt_timeout(child::BTNode, seconds::Real) = TimeoutNode(child, seconds)

# ---------------------------------------------------------------------------
# Helper actions — common AI patterns
# ---------------------------------------------------------------------------

"""
    bt_move_to(target_key; speed=5.0, arrival_distance=0.5)

Action node that moves the entity toward a position stored in the blackboard.
Returns RUNNING while moving, SUCCESS on arrival, FAILURE if target is missing.
"""
function bt_move_to(target_key::Symbol; speed::Float64=5.0, arrival_distance::Float64=0.5)
    return ActionNode((eid, bb, dt) -> begin
        target = bb_get(bb, target_key)
        target === nothing && return BT_FAILURE
        tc = get_component(eid, TransformComponent)
        tc === nothing && return BT_FAILURE
        pos = tc.position[]
        dx = target[1] - pos[1]
        dz = target[3] - pos[3]
        dist = sqrt(dx * dx + dz * dz)
        if dist < arrival_distance
            return BT_SUCCESS
        end
        move = Vec3d(dx / dist * speed * dt, 0.0, dz / dist * speed * dt)
        tc.position[] = pos + move
        return BT_RUNNING
    end)
end

"""
    bt_wait(seconds)

Action node that waits for the given duration using blackboard state.
Returns RUNNING during the wait, SUCCESS when done.
"""
function bt_wait(seconds::Real)
    key = gensym(:bt_wait)
    return ActionNode((eid, bb, dt) -> begin
        elapsed = bb_get(bb, key, 0.0)::Float64
        elapsed += dt
        bb_set!(bb, key, elapsed)
        if elapsed >= Float64(seconds)
            bb_set!(bb, key, 0.0)
            return BT_SUCCESS
        end
        return BT_RUNNING
    end)
end

"""
    bt_set_bb(key, value)

Action node that sets a blackboard value and returns SUCCESS.
"""
function bt_set_bb(key::Symbol, value)
    return ActionNode((eid, bb, dt) -> begin
        bb_set!(bb, key, value)
        return BT_SUCCESS
    end)
end

"""
    bt_has_bb(key)

Condition node that checks if a blackboard key exists.
"""
function bt_has_bb(key::Symbol)
    return ConditionNode((eid, bb) -> bb_has(bb, key))
end

# ---------------------------------------------------------------------------
# System update
# ---------------------------------------------------------------------------

"""
    update_behavior_trees!(dt::Float64)

Tick all enabled behavior trees. Respects per-tree tick_rate for throttling.
"""
function update_behavior_trees!(dt::Float64)
    iterate_components(BehaviorTreeComponent) do eid, btc
        btc.enabled || return

        # Throttle by tick_rate
        if btc._tick_rate > 0
            btc._accumulator += dt
            btc._accumulator < btc._tick_rate && return
            btc._accumulator -= btc._tick_rate
        end

        try
            tick(btc.root, eid, btc.blackboard, dt)
        catch e
            @warn "BehaviorTree tick error" entity=eid exception=(e, catch_backtrace())
        end
    end
    return nothing
end
