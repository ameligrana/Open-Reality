# Script system — runs ScriptComponent lifecycle callbacks

"""
    _script_record_error!(comp::ScriptComponent, eid::EntityID, phase::String, e)

Record a script error and disable the script if the error budget is exceeded.
"""
function _script_record_error!(comp::ScriptComponent, eid::EntityID, phase::String, e)
    comp._error_count += 1
    budget = SCRIPT_ERROR_BUDGET[]
    if budget > 0 && comp._error_count >= budget
        comp._disabled = true
        @warn "ScriptComponent disabled after $(comp._error_count) errors" entity=eid phase
    else
        @warn "ScriptComponent $phase error" entity=eid errors=comp._error_count exception=e
    end
end

"""
    update_scripts!(dt, ctx)

Run script lifecycle callbacks for all entities with a ScriptComponent.
On the first tick, `on_start` is called once. Every tick, `on_update` is called.
A snapshot of entities is taken before iteration to tolerate mid-tick mutations.

Scripts that exceed `SCRIPT_ERROR_BUDGET` consecutive errors are automatically
disabled to prevent log spam and performance degradation.
"""
function update_scripts!(dt::Float64, ctx)
    entities = entities_with_component(ScriptComponent)
    isempty(entities) && return

    for eid in entities
        comp = get_component(eid, ScriptComponent)
        comp === nothing && continue
        comp._disabled && continue

        if !comp._started
            if comp.on_start !== nothing
                try
                    comp.on_start(eid, ctx)
                catch e
                    _script_record_error!(comp, eid, "on_start", e)
                end
            end
            comp._started = true
        end

        if comp.on_update !== nothing
            try
                comp.on_update(eid, dt, ctx)
            catch e
                _script_record_error!(comp, eid, "on_update", e)
            end
        end
    end
end
