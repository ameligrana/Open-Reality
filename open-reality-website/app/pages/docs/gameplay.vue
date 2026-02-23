<script setup lang="ts">
definePageMeta({ layout: 'docs' })
useSeoMeta({
  title: 'Gameplay Systems - OpenReality Docs',
  ogTitle: 'Gameplay Systems - OpenReality Docs',
  description: 'Complete game logic toolkit: FSM, EventBus, Timers, Coroutines, Tweens, Behavior Trees, Health/Damage, Inventory, Quests, Dialogue, Config, and Debug Console.',
  ogDescription: 'Complete game logic toolkit: FSM, EventBus, Timers, Coroutines, Tweens, Behavior Trees, Health/Damage, Inventory, Quests, Dialogue, Config, and Debug Console.',
})

const fsmCode = `# Define your game states by subtyping GameState
struct MenuState <: GameState end
struct PlayState <: GameState end
struct PauseState <: GameState end

# Create the FSM with an initial state and scene
fsm = GameStateMachine(:menu, menu_scene_defs)
add_state!(fsm, :menu, MenuState())
add_state!(fsm, :play, PlayState())
add_state!(fsm, :pause, PauseState())

# Add transitions with optional guards
add_transition!(fsm, :menu, :play;
    guard=() -> is_ready(),
    on_transition=() -> setup_game!()
)
add_transition!(fsm, :play, :pause)
add_transition!(fsm, :pause, :play)`

const stateCallbacksCode = `# Override these for each concrete state type:

# Called when entering this state (scene is already built)
on_enter!(state::PlayState, sc::Scene) = begin
    @info "Entering play state"
end

# Called every frame — return StateTransition to switch states
on_update!(state::PlayState, sc::Scene, dt::Float64, ctx::GameContext) = begin
    if should_pause()
        return StateTransition(:pause)
    end
    return nothing  # stay in current state
end

# Called when leaving this state
on_exit!(state::PlayState, sc::Scene) = begin
    @info "Leaving play state"
end

# Optional: return a UI callback for this state
get_ui_callback(state::PlayState) = function(ui_ctx)
    ui_text(ui_ctx, "Playing..."; x=10, y=10, size=18)
end`

const contextCode = `# GameContext provides deferred entity creation/removal.
# Scripts receive it as the ctx parameter.

# Spawn a new entity (deferred until apply_mutations!)
new_id = spawn!(ctx, entity([
    transform(position=Vec3d(0, 5, 0)),
    cube_mesh(),
    MaterialComponent(color=RGB{Float32}(1, 0, 0))
]))

# Remove an entity (deferred until apply_mutations!)
despawn!(ctx, entity_id)

# The engine calls apply_mutations! once per frame
# to flush all queued spawns and despawns.`

const prefabCode = `# Define a reusable entity template
enemy_prefab = Prefab(; position=Vec3d(0,0,0), health=100) do (; position, health)
    entity([
        transform(; position),
        sphere_mesh(),
        MaterialComponent(color=RGB{Float32}(1, 0, 0)),
        ColliderComponent(shape=SphereShape(0.5f0)),
        RigidBodyComponent(body_type=BODY_DYNAMIC, mass=1.0),
    ])
end

# Instantiate with default values
def = instantiate(enemy_prefab)

# Or override specific parameters
def = instantiate(enemy_prefab; position=Vec3d(10, 0, 5), health=200)

# Spawn via GameContext (preferred in scripts)
eid = spawn!(ctx, enemy_prefab; position=Vec3d(3, 0, 0))`

const eventBusCode = `# Define custom event types
struct EnemyDefeated <: GameEvent
    enemy_id::EntityID
    score::Int
end

# Subscribe with priority (lower = called first)
subscribe!(EnemyDefeated, event -> begin
    @info "Enemy \$(event.enemy_id) defeated! +\$(event.score) pts"
end; priority=10)

# One-shot listener (auto-unsubscribes after first trigger)
subscribe_once!(EnemyDefeated, event -> begin
    @info "First kill!"
end)

# Listener with filter and cancellation
subscribe!(EnemyDefeated, (event, ctx) -> begin
    ctx.cancelled = true  # stop propagation to lower-priority listeners
end; priority=1, filter=e -> e.score > 100)

# Emit immediately, or defer to end of frame
emit!(EnemyDefeated(enemy_id, 50))
emit_deferred!(EnemyDefeated(enemy_id, 50))  # queued until flush_deferred_events!()`

const configCode = `# Set config values at runtime
set_config!("player.max_hp", 100.0)
set_config!("enemy.speed", 5.0)

# Retrieve typed values with defaults
hp = get_config(Float64, "player.max_hp"; default=100.0)

# Register difficulty presets
register_difficulty!(:easy, Dict(
    "player.max_hp" => 150.0,
    "enemy.speed" => 3.0
))
register_difficulty!(:hard, Dict(
    "player.max_hp" => 75.0,
    "enemy.speed" => 8.0
))

# Apply a preset (overwrites matching keys)
apply_difficulty!(:easy)

# Hot-reload from TOML file
load_config_from_file!("config/game.toml")
check_config_reload!()  # call each frame for hot-reload`

const timersCode = `# One-shot timer (fires once after delay)
id = timer_once!(3.0, () -> @info "3 seconds passed!")

# Repeating timer (fires every interval)
id = timer_interval!(1.0, () -> begin
    @info "Tick!"
end; repeats=10)  # -1 for infinite

# Entity-scoped timer (auto-cancels when entity is despawned)
timer_once!(2.0, () -> explode!(eid); owner=eid)

# Control timers
pause_timer!(id)
resume_timer!(id)
cancel_timer!(id)
cancel_entity_timers!(eid)  # cancel all timers owned by entity`

const coroutinesCode = `# Start a cooperative coroutine
start_coroutine!(; owner=player_eid) do ctx
    # Wait 1 second
    yield_wait(ctx, 1.0)
    @info "1 second passed"

    # Wait 60 frames
    yield_frames(ctx, 60)
    @info "60 frames passed"

    # Wait until a condition is true
    yield_until(ctx, () -> is_quest_completed(:rescue))
    @info "Quest completed!"
end

# Cancel coroutines
cancel_coroutine!(id)
cancel_entity_coroutines!(eid)  # auto-cancel on despawn`

const tweensCode = `# Tween an entity's position over 2 seconds
tween!(eid, :position, Vec3d(10, 5, 0), 2.0;
       easing=ease_in_out_cubic)

# Ping-pong scale animation (loops forever)
tween!(eid, :scale, Vec3d(1.5, 1.5, 1.5), 0.8;
       easing=ease_in_out_sine,
       loop_mode=TWEEN_PING_PONG,
       loop_count=-1)

# Chain tweens into a sequence
a = tween!(eid, :position, Vec3d(5, 0, 0), 1.0)
b = tween!(eid, :position, Vec3d(5, 5, 0), 1.0)
c = tween!(eid, :position, Vec3d(0, 0, 0), 1.0)
tween_sequence!([a, b, c])

# Callback on completion
tween!(eid, :position, target, 1.0;
       on_complete=() -> @info "Arrived!")

# Available easings:
# ease_linear, ease_in/out/in_out_quad, ease_in/out/in_out_cubic,
# ease_in/out/in_out_sine, ease_in/out_expo, ease_in/out_back,
# ease_in/out_bounce, ease_in/out_elastic`

const behaviorTreeCode = `# Build an enemy AI behavior tree
tree = bt_selector(
    # Branch 1: chase + attack if player nearby
    bt_sequence(
        bt_condition((eid, bb) -> begin
            player_dist = bb_get(bb, :player_distance, Inf)
            player_dist < 10.0
        end),
        bt_action((eid, bb, dt) -> begin
            # Move toward player
            move_toward!(eid, bb_get(bb, :player_pos), 5.0 * dt)
            return bb_get(bb, :player_distance, Inf) < 2.0 ?
                BT_SUCCESS : BT_RUNNING
        end),
        bt_action((eid, bb, dt) -> begin
            apply_damage!(bb_get(bb, :player_eid), 10.0;
                          damage_type=DAMAGE_PHYSICAL)
            return BT_SUCCESS
        end)
    ),
    # Branch 2: patrol between waypoints
    bt_sequence(
        bt_move_to(:patrol_target; speed=3.0),
        bt_wait(2.0),
        bt_set_bb(:patrol_target, next_waypoint)
    )
)

# Attach to entity
entity([
    ...,
    BehaviorTreeComponent(tree)
])`

const healthCode = `# Add health to an entity
entity([
    ...,
    HealthComponent(
        max_hp=100.0f0,
        armor=10.0f0,
        resistances=Dict(DAMAGE_FIRE => 0.5f0),  # 50% fire resist
        auto_despawn=true  # remove entity on death
    )
])

# Apply damage (respects armor + resistances)
apply_damage!(target, 25.0;
              source=attacker_eid,
              damage_type=DAMAGE_FIRE,
              knockback=Vec3d(0, 2, -5))

# Heal
heal!(target, 30.0; source=healer_eid)

# Query state
is_dead(eid)          # true if HP <= 0
get_hp(eid)           # current / max HP

# Events emitted automatically:
# DamageEvent, HealEvent, DeathEvent`

const inventoryCode = `# Add inventory to an entity
entity([
    ...,
    InventoryComponent(max_slots=20, max_weight=50.0f0)
])

# Register item definitions
register_item!(ItemDef(
    id=:health_potion,
    name="Health Potion",
    item_type=ITEM_CONSUMABLE,
    stackable=true,
    max_stack=10,
    weight=0.5f0,
    on_use=(eid) -> heal!(eid, 30.0)
))

# Place pickups in the world
entity([
    sphere_mesh(radius=0.2f0),
    MaterialComponent(color=RGB{Float32}(0.9, 0.1, 0.1)),
    transform(position=Vec3d(5, 0.5, 0)),
    PickupComponent(:health_potion; count=1, auto_pickup_radius=1.5f0)
])

# Events: ItemPickedUpEvent, ItemUsedEvent, ItemDroppedEvent`

const questsCode = `# Define a quest
register_quest!(QuestDef(
    id=:goblin_slayer,
    name="Goblin Slayer",
    description="Defeat 5 goblins",
    objectives=[
        ObjectiveDef(
            description="Kill goblins",
            type=OBJ_KILL,
            required=5
        )
    ]
))

# Start quest
start_quest!(:goblin_slayer)

# Advance objective progress (e.g., from a DeathEvent listener)
subscribe!(DeathEvent, event -> begin
    if is_quest_active(:goblin_slayer)
        advance_objective!(:goblin_slayer, 1)
    end
end)

# Query
is_quest_active(:goblin_slayer)     # true
is_quest_completed(:goblin_slayer)  # true when all objectives met
get_active_quest_ids()              # [:goblin_slayer, ...]

# Events: QuestStartedEvent, ObjectiveProgressEvent,
#          QuestCompletedEvent, QuestFailedEvent`

const dialogueCode = `# Build a dialogue tree
tree = DialogueTree(:npc_greeting, [
    DialogueNode(
        id=:start,
        speaker="Elder",
        text="Welcome, adventurer. Will you help us?",
        choices=[
            DialogueChoice("I'll help!", :accept),
            DialogueChoice("Not now.", :decline;
                on_select=() -> @info "Player declined")
        ]
    ),
    DialogueNode(
        id=:accept,
        speaker="Elder",
        text="Wonderful! Defeat the goblins in the east.",
        choices=[],
        on_enter=() -> start_quest!(:goblin_slayer)
    ),
    DialogueNode(
        id=:decline,
        speaker="Elder",
        text="Come back when you're ready.",
        choices=[]
    )
])

# Start dialogue (pauses gameplay)
start_dialogue!(tree)

# Engine handles input + rendering automatically:
# update_dialogue_input!(input)  — processes key/mouse
# render_dialogue!(ui_ctx)       — draws dialogue box

# Events: DialogueStartedEvent, DialogueChoiceEvent, DialogueEndedEvent`

const debugCode = `# Register custom debug commands
register_command!("heal", (args) -> begin
    heal!(player_eid[], parse(Float32, args[1]))
    return "Healed \$(args[1]) HP"
end; help="heal <amount> — restore HP")

register_command!("spawn_enemy", (args) -> begin
    pos = Vec3d(parse.(Float64, args[1:3])...)
    spawn_enemy!(pos)
    return "Enemy spawned"
end; help="spawn_enemy <x> <y> <z>")

# Add on-screen watches (always visible)
watch!("FPS", () -> round(1.0 / dt[]))
watch!("Enemies", () -> enemy_count[])
watch!("Player HP", () -> get_hp(player_eid[]))

# Toggle with backtick key
# Built-in commands: help, inspect, entities, components,
#                    fps, set, get, clear`

const sceneTransitionCode = `# Return a StateTransition from on_update! to switch states.
# Providing new_scene_defs rebuilds the scene entirely.

on_update!(state::MenuState, sc::Scene, dt::Float64, ctx::GameContext) = begin
    if start_pressed()
        # Switch to :play with a new scene
        return StateTransition(:play, build_game_scene())
    end
    return nothing
end

# Without new_scene_defs, the existing scene is preserved:
StateTransition(:pause)        # keep current scene
StateTransition(:play, defs)   # rebuild scene from defs`

const renderFsmCode = `# Launch the engine with an FSM-driven render loop
render(fsm;
    backend = OpenGLBackend(),
    width = 1280,
    height = 720,
    title = "My Game",
    post_process = PostProcessConfig(
        bloom_enabled=true,
        tone_mapping=TONEMAP_ACES
    )
)

# The render loop automatically runs each frame:
# 1. Config hot-reload check
# 2. Timers, coroutines, tweens, behavior trees
# 3. Health system, pickup collection
# 4. Dialogue + debug console input
# 5. on_update!(state) — check for StateTransition
# 6. Script lifecycle (on_start/on_update/on_destroy)
# 7. Physics, audio, particles, rendering
# 8. Deferred event flush + entity mutations`

const sections = [
  { id: 'fsm', title: 'Game State Machine' },
  { id: 'callbacks', title: 'State Callbacks' },
  { id: 'context', title: 'GameContext' },
  { id: 'prefab', title: 'Prefab System' },
  { id: 'eventbus', title: 'Event Bus' },
  { id: 'config', title: 'Game Config' },
  { id: 'timers', title: 'Timers' },
  { id: 'coroutines', title: 'Coroutines' },
  { id: 'tweens', title: 'Tweens & Easing' },
  { id: 'behavior-trees', title: 'Behavior Trees' },
  { id: 'health', title: 'Health & Damage' },
  { id: 'inventory', title: 'Inventory & Items' },
  { id: 'quests', title: 'Quests & Objectives' },
  { id: 'dialogue', title: 'Dialogue System' },
  { id: 'debug', title: 'Debug Console' },
  { id: 'transitions', title: 'Scene Switching' },
  { id: 'render', title: 'FSM Render Loop' },
]
</script>

<template>
  <div class="space-y-12">
    <div>
      <h1 class="text-3xl font-mono font-bold text-or-text">Gameplay Systems</h1>
      <p class="text-or-text-dim mt-3 leading-relaxed">
        OpenReality ships with a complete game logic toolkit: state machines, events, timers, coroutines,
        tweens, behavior trees, health/damage, inventory, quests, dialogue, config management, and
        a debug console. All systems integrate through the
        <code class="text-or-text-code bg-or-panel px-1.5 py-0.5 rounded text-sm">EventBus</code> and run
        automatically in the FSM render loop.
      </p>
    </div>

    <!-- Navigation -->
    <nav class="flex flex-wrap gap-2">
      <a
        v-for="s in sections"
        :key="s.id"
        :href="`#${s.id}`"
        class="px-2 py-1 text-xs font-mono rounded border border-or-border text-or-text-dim hover:text-or-green hover:border-or-green/50 transition-colors"
      >
        {{ s.title }}
      </a>
    </nav>

    <!-- GameStateMachine -->
    <section id="fsm" class="scroll-mt-20">
      <h2 class="text-xl font-mono font-bold text-or-text mb-4">
        <span class="text-or-green">#</span> Game State Machine
      </h2>
      <p class="text-or-text-dim mb-4 leading-relaxed">
        The FSM manages distinct game states (menu, playing, paused, etc.).
        Define concrete states by subtyping <code class="text-or-text-code bg-or-panel px-1.5 py-0.5 rounded text-sm">GameState</code>,
        register them with the machine, and let the render loop drive transitions.
        Transitions support optional guards and callbacks.
      </p>
      <CodeBlock :code="fsmCode" lang="julia" filename="state_machine.jl" />
    </section>

    <!-- State Callbacks -->
    <section id="callbacks" class="scroll-mt-20">
      <h2 class="text-xl font-mono font-bold text-or-text mb-4">
        <span class="text-or-green">#</span> State Callbacks
      </h2>
      <p class="text-or-text-dim mb-4 leading-relaxed">
        Each state type can override four lifecycle hooks. Only override the ones you need &mdash;
        defaults are no-ops that return <code class="text-or-text-code bg-or-panel px-1.5 py-0.5 rounded text-sm">nothing</code>.
      </p>
      <CodeBlock :code="stateCallbacksCode" lang="julia" filename="state_callbacks.jl" />
    </section>

    <!-- GameContext -->
    <section id="context" class="scroll-mt-20">
      <h2 class="text-xl font-mono font-bold text-or-text mb-4">
        <span class="text-or-green">#</span> GameContext
      </h2>
      <p class="text-or-text-dim mb-4 leading-relaxed">
        <code class="text-or-text-code bg-or-panel px-1.5 py-0.5 rounded text-sm">GameContext</code>
        provides a command buffer for deferred entity spawning and despawning. Scripts call
        <code class="text-or-text-code bg-or-panel px-1.5 py-0.5 rounded text-sm">spawn!</code> and
        <code class="text-or-text-code bg-or-panel px-1.5 py-0.5 rounded text-sm">despawn!</code> during
        the frame, and the engine flushes all mutations at once via
        <code class="text-or-text-code bg-or-panel px-1.5 py-0.5 rounded text-sm">apply_mutations!</code>.
      </p>
      <CodeBlock :code="contextCode" lang="julia" filename="game_context.jl" />
    </section>

    <!-- Prefab -->
    <section id="prefab" class="scroll-mt-20">
      <h2 class="text-xl font-mono font-bold text-or-text mb-4">
        <span class="text-or-green">#</span> Prefab System
      </h2>
      <p class="text-or-text-dim mb-4 leading-relaxed">
        A <code class="text-or-text-code bg-or-panel px-1.5 py-0.5 rounded text-sm">Prefab</code> wraps
        a factory function that returns an <code class="text-or-text-code bg-or-panel px-1.5 py-0.5 rounded text-sm">EntityDef</code>.
        Use <code class="text-or-text-code bg-or-panel px-1.5 py-0.5 rounded text-sm">instantiate</code> to create
        entity definitions with optional parameter overrides, or
        <code class="text-or-text-code bg-or-panel px-1.5 py-0.5 rounded text-sm">spawn!</code> to instantiate
        and enqueue in one step.
      </p>
      <CodeBlock :code="prefabCode" lang="julia" filename="prefab.jl" />
    </section>

    <!-- EventBus -->
    <section id="eventbus" class="scroll-mt-20">
      <h2 class="text-xl font-mono font-bold text-or-text mb-4">
        <span class="text-or-green">#</span> Event Bus
      </h2>
      <p class="text-or-text-dim mb-4 leading-relaxed">
        The <code class="text-or-text-code bg-or-panel px-1.5 py-0.5 rounded text-sm">EventBus</code> is a global
        pub/sub system with priority ordering, one-shot listeners, deferred events, listener filters,
        and event cancellation. Define event types by subtyping
        <code class="text-or-text-code bg-or-panel px-1.5 py-0.5 rounded text-sm">GameEvent</code>.
      </p>
      <CodeBlock :code="eventBusCode" lang="julia" filename="event_bus.jl" />
    </section>

    <!-- Config -->
    <section id="config" class="scroll-mt-20">
      <h2 class="text-xl font-mono font-bold text-or-text mb-4">
        <span class="text-or-green">#</span> Game Config
      </h2>
      <p class="text-or-text-dim mb-4 leading-relaxed">
        A global key-value store for runtime configuration. Supports typed retrieval, difficulty presets,
        TOML file loading, and hot-reload during development.
      </p>
      <CodeBlock :code="configCode" lang="julia" filename="config.jl" />
    </section>

    <!-- Timers -->
    <section id="timers" class="scroll-mt-20">
      <h2 class="text-xl font-mono font-bold text-or-text mb-4">
        <span class="text-or-green">#</span> Timers
      </h2>
      <p class="text-or-text-dim mb-4 leading-relaxed">
        One-shot and repeating timers with pause/resume. Entity-scoped timers automatically cancel
        when the owning entity is despawned.
      </p>
      <CodeBlock :code="timersCode" lang="julia" filename="timers.jl" />
    </section>

    <!-- Coroutines -->
    <section id="coroutines" class="scroll-mt-20">
      <h2 class="text-xl font-mono font-bold text-or-text mb-4">
        <span class="text-or-green">#</span> Coroutines
      </h2>
      <p class="text-or-text-dim mb-4 leading-relaxed">
        Cooperative coroutines for writing sequential game logic that spans multiple frames. Yield by
        time, frame count, or arbitrary condition. Entity-scoped coroutines auto-cancel on despawn.
      </p>
      <CodeBlock :code="coroutinesCode" lang="julia" filename="coroutines.jl" />
    </section>

    <!-- Tweens -->
    <section id="tweens" class="scroll-mt-20">
      <h2 class="text-xl font-mono font-bold text-or-text mb-4">
        <span class="text-or-green">#</span> Tweens &amp; Easing
      </h2>
      <p class="text-or-text-dim mb-4 leading-relaxed">
        Animate entity properties (position, scale, rotation, color, opacity) with configurable easing curves.
        Supports looping, ping-pong, chaining, and completion callbacks. 18 built-in easing functions.
      </p>
      <CodeBlock :code="tweensCode" lang="julia" filename="tweens.jl" />
    </section>

    <!-- Behavior Trees -->
    <section id="behavior-trees" class="scroll-mt-20">
      <h2 class="text-xl font-mono font-bold text-or-text mb-4">
        <span class="text-or-green">#</span> Behavior Trees
      </h2>
      <p class="text-or-text-dim mb-4 leading-relaxed">
        Composable AI behavior trees with selector, sequence, parallel, decorator, and action nodes.
        Each entity gets a per-entity <code class="text-or-text-code bg-or-panel px-1.5 py-0.5 rounded text-sm">Blackboard</code>
        for shared state between nodes. Built-in helpers for common patterns like move-to and wait.
      </p>
      <CodeBlock :code="behaviorTreeCode" lang="julia" filename="behavior_tree.jl" />
    </section>

    <!-- Health & Damage -->
    <section id="health" class="scroll-mt-20">
      <h2 class="text-xl font-mono font-bold text-or-text mb-4">
        <span class="text-or-green">#</span> Health &amp; Damage
      </h2>
      <p class="text-or-text-dim mb-4 leading-relaxed">
        <code class="text-or-text-code bg-or-panel px-1.5 py-0.5 rounded text-sm">HealthComponent</code> provides
        HP tracking, armor, typed damage resistances, knockback, and auto-despawn on death.
        All damage/heal/death events flow through the EventBus.
      </p>
      <CodeBlock :code="healthCode" lang="julia" filename="health.jl" />
    </section>

    <!-- Inventory & Items -->
    <section id="inventory" class="scroll-mt-20">
      <h2 class="text-xl font-mono font-bold text-or-text mb-4">
        <span class="text-or-green">#</span> Inventory &amp; Items
      </h2>
      <p class="text-or-text-dim mb-4 leading-relaxed">
        A slot-based inventory with a global item registry. Register item definitions once, then place
        <code class="text-or-text-code bg-or-panel px-1.5 py-0.5 rounded text-sm">PickupComponent</code> entities in the world.
        The pickup system handles auto-collection within radius and stacking.
      </p>
      <CodeBlock :code="inventoryCode" lang="julia" filename="inventory.jl" />
    </section>

    <!-- Quests -->
    <section id="quests" class="scroll-mt-20">
      <h2 class="text-xl font-mono font-bold text-or-text mb-4">
        <span class="text-or-green">#</span> Quests &amp; Objectives
      </h2>
      <p class="text-or-text-dim mb-4 leading-relaxed">
        Define quests with typed objectives (kill, collect, reach location, interact, custom). Progress
        tracking integrates with the EventBus for automatic advancement. Supports rewards and failure states.
      </p>
      <CodeBlock :code="questsCode" lang="julia" filename="quests.jl" />
    </section>

    <!-- Dialogue -->
    <section id="dialogue" class="scroll-mt-20">
      <h2 class="text-xl font-mono font-bold text-or-text mb-4">
        <span class="text-or-green">#</span> Dialogue System
      </h2>
      <p class="text-or-text-dim mb-4 leading-relaxed">
        Branching dialogue trees with per-choice conditions, callbacks, and auto-advance nodes.
        The engine handles input processing and UI rendering. Integrates with quests and events.
      </p>
      <CodeBlock :code="dialogueCode" lang="julia" filename="dialogue.jl" />
    </section>

    <!-- Debug Console -->
    <section id="debug" class="scroll-mt-20">
      <h2 class="text-xl font-mono font-bold text-or-text mb-4">
        <span class="text-or-green">#</span> Debug Console
      </h2>
      <p class="text-or-text-dim mb-4 leading-relaxed">
        An in-game console toggled with the backtick key. Register custom commands, add on-screen watches
        for real-time values, and use built-in commands for entity inspection and config editing.
      </p>
      <CodeBlock :code="debugCode" lang="julia" filename="debug_console.jl" />
    </section>

    <!-- Scene Switching -->
    <section id="transitions" class="scroll-mt-20">
      <h2 class="text-xl font-mono font-bold text-or-text mb-4">
        <span class="text-or-green">#</span> Scene Switching
      </h2>
      <p class="text-or-text-dim mb-4 leading-relaxed">
        Return a <code class="text-or-text-code bg-or-panel px-1.5 py-0.5 rounded text-sm">StateTransition</code>
        from <code class="text-or-text-code bg-or-panel px-1.5 py-0.5 rounded text-sm">on_update!</code> to switch
        states. Providing <code class="text-or-text-code bg-or-panel px-1.5 py-0.5 rounded text-sm">new_scene_defs</code>
        rebuilds the entire scene; omitting it preserves the current scene.
      </p>
      <CodeBlock :code="sceneTransitionCode" lang="julia" filename="scene_transition.jl" />
    </section>

    <!-- FSM-driven Render -->
    <section id="render" class="scroll-mt-20">
      <h2 class="text-xl font-mono font-bold text-or-text mb-4">
        <span class="text-or-green">#</span> FSM Render Loop
      </h2>
      <p class="text-or-text-dim mb-4 leading-relaxed">
        Pass the <code class="text-or-text-code bg-or-panel px-1.5 py-0.5 rounded text-sm">GameStateMachine</code>
        to <code class="text-or-text-code bg-or-panel px-1.5 py-0.5 rounded text-sm">render</code> to launch the
        engine with automatic state management, scene rebuilding, and all gameplay systems
        running each frame.
      </p>
      <CodeBlock :code="renderFsmCode" lang="julia" filename="render_fsm.jl" />
    </section>
  </div>
</template>
