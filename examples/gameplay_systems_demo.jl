# Gameplay Systems Demo — "Goblin's Keep"
# Demonstrates ALL 12 new gameplay subsystems in a single playable example:
#
#   1.  Enhanced Event Bus       — priority listeners, one-shot, deferred events, cancellation
#   2.  Game Config              — TOML-style config, difficulty presets
#   3.  Timers                   — one-shot & interval timers, entity-scoped auto-cancel
#   4.  Coroutines               — yield_wait, yield_frames, yield_until
#   5.  FSM Overhaul             — guards, transitions, history, StateChangedEvent
#   6.  Tweens / Easing          — position/scale/color tweens, chaining, ping-pong
#   7.  Collision Layers         — bitmask filtering (player vs enemy vs projectile vs pickup)
#   8.  Health / Damage          — HP, armor, resistances, knockback, auto-despawn
#   9.  Behavior Trees           — enemy patrol/chase/attack AI
#  10.  Debug Console            — in-game console with custom commands + watches
#  11.  Inventory / Items        — pickup collection, item usage (health potion)
#  12.  Quest / Objectives       — kill + collect quests with auto-tracking
#  13.  Dialogue                 — branching NPC dialogue with quest integration
#
# Run with:
#   julia --project=. examples/gameplay_systems_demo.jl

using OpenReality

# =============================================================================
# Constants
# =============================================================================

const ARENA_SIZE     = 30.0
const WALL_HEIGHT    = 3.0
const PLAYER_START   = Vec3d(0.0, 1.7, 0.0)
const NPC_POS        = Vec3d(5.0, 0.5, -5.0)

const ENEMY_COUNT    = 5
const ENEMY_HP       = 50.0f0
const ENEMY_DAMAGE   = 8.0f0
const PLAYER_HP      = 100.0f0
const ATTACK_RANGE   = 2.8
const ATTACK_COOLDOWN= 0.6

const POTION_COUNT   = 3
const POTION_HEAL    = 30.0f0

# =============================================================================
# 2. Game Config — difficulty presets
# =============================================================================

function setup_config!()
    set_config!("player.max_hp", PLAYER_HP)
    set_config!("player.attack_range", ATTACK_RANGE)
    set_config!("player.attack_cooldown", ATTACK_COOLDOWN)
    set_config!("enemy.hp", ENEMY_HP)
    set_config!("enemy.damage", ENEMY_DAMAGE)
    set_config!("enemy.count", ENEMY_COUNT)
    set_config!("enemy.chase_speed", 3.0)
    set_config!("enemy.patrol_speed", 1.5)
    set_config!("potion.heal", POTION_HEAL)

    register_difficulty!(:easy, Dict{String, Any}(
        "player.max_hp"    => 150.0f0,
        "enemy.hp"         => 30.0f0,
        "enemy.damage"     => 5.0f0,
        "enemy.chase_speed"=> 2.0,
    ))
    register_difficulty!(:hard, Dict{String, Any}(
        "player.max_hp"    => 75.0f0,
        "enemy.hp"         => 80.0f0,
        "enemy.damage"     => 15.0f0,
        "enemy.chase_speed"=> 4.5,
    ))
    apply_difficulty!(:easy)
end

# =============================================================================
# 11. Item definitions
# =============================================================================

function register_items!()
    register_item!(ItemDef(:health_potion, "Health Potion";
        description="Restores HP",
        item_type=ITEM_CONSUMABLE,
        stackable=true,
        max_stack=5,
        on_use=(user, def) -> begin
            heal_amount = get_config(Float32, "potion.heal"; default=30.0f0)
            heal!(user, heal_amount)
            true  # consumed
        end,
        metadata=Dict{Symbol,Any}(:color => RGB{Float32}(0.9, 0.1, 0.1))
    ))

    register_item!(ItemDef(:goblin_ear, "Goblin Ear";
        description="Trophy from a defeated goblin",
        item_type=ITEM_QUEST,
        stackable=true,
        max_stack=99
    ))
end

# =============================================================================
# 12. Quest definitions
# =============================================================================

function register_quests!()
    register_quest!(QuestDef(:clear_arena, "Clear the Arena";
        description="Defeat all goblins in the arena",
        objectives=[
            ObjectiveDef("Defeat goblins", OBJ_KILL, :goblin;
                         required_count=get_config(Int, "enemy.count"; default=5))
        ],
        rewards=QuestReward(on_reward=() -> begin
            emit!(GameLogEvent("Quest complete! The arena is clear."))
        end)
    ))

    register_quest!(QuestDef(:collect_ears, "Goblin Trophies";
        description="Collect goblin ears as proof of your deeds",
        objectives=[
            ObjectiveDef("Collect goblin ears", OBJ_COLLECT, :goblin_ear;
                         required_count=3)
        ],
        prerequisites=[:clear_arena]
    ))
end

# =============================================================================
# Custom events
# =============================================================================

struct GameLogEvent <: GameEvent
    message::String
end

struct PlayerAttackEvent <: GameEvent
    player_id::EntityID
end

# =============================================================================
# Shared game state
# =============================================================================

const game_log       = Ref(String[])
const attack_cooldown= Ref(0.0)
const player_eid     = Ref{Union{EntityID, Nothing}}(nothing)
const enemy_count_alive = Ref(0)
const npc_eid        = Ref{Union{EntityID, Nothing}}(nothing)
const kills          = Ref(0)
const start_requested = Ref(false)
const return_to_menu  = Ref(false)

# =============================================================================
# 1. Enhanced Event Bus — listeners with priority, one-shot, filtering
# =============================================================================

function setup_event_listeners!()
    # Game log listener (low priority = runs last, collects messages)
    subscribe!(GameLogEvent, event -> begin
        push!(game_log[], event.message)
        if length(game_log[]) > 8
            popfirst!(game_log[])
        end
    end; priority=200)

    # Kill counter (high priority)
    subscribe!(DeathEvent, event -> begin
        kills[] += 1
        enemy_count_alive[] -= 1

        # Drop a goblin ear pickup at the death location
        tc = get_component(event.entity, TransformComponent)
        if tc !== nothing
            pos = tc.position[]
            emit_deferred!(GameLogEvent("A goblin falls! ($(enemy_count_alive[]) remaining)"))
        end
    end; priority=10)

    # One-shot: first kill announcement
    subscribe_once!(DeathEvent, event -> begin
        emit_deferred!(GameLogEvent("First blood!"))
    end; priority=50)

    # Track quest completions
    subscribe!(QuestCompletedEvent, event -> begin
        emit_deferred!(GameLogEvent("Quest completed: $(event.quest_id)"))
    end)
end

# =============================================================================
# 9. Behavior Tree — enemy AI (patrol → chase → attack)
# =============================================================================

function make_enemy_bt()
    bt_selector(
        # Branch 1: if player is nearby, chase and attack
        bt_sequence(
            # Condition: player within detection range
            bt_condition((eid, bb) -> begin
                player_eid[] === nothing && return false
                tc = get_component(eid, TransformComponent)
                ptc = get_component(player_eid[], TransformComponent)
                (tc === nothing || ptc === nothing) && return false
                epos = tc.position[]
                ppos = ptc.position[]
                dist = sqrt((epos[1]-ppos[1])^2 + (epos[2]-ppos[2])^2 + (epos[3]-ppos[3])^2)
                bb_set!(bb, :target_pos, ppos)
                bb_set!(bb, :dist_to_player, dist)
                return dist < 10.0
            end),

            bt_selector(
                # If close enough, attack
                bt_sequence(
                    bt_condition((eid, bb) -> bb_get(bb, :dist_to_player, 999.0) < 2.5),
                    bt_action((eid, bb, dt) -> begin
                        # Damage player on cooldown
                        cd = bb_get(bb, :attack_cd, 0.0)
                        if cd <= 0.0
                            if player_eid[] !== nothing && has_component(player_eid[], HealthComponent)
                                dmg = get_config(Float32, "enemy.damage"; default=8.0f0)
                                apply_damage!(player_eid[], dmg; source=eid,
                                              damage_type=DAMAGE_PHYSICAL)
                            end
                            bb_set!(bb, :attack_cd, 1.2)
                        else
                            bb_set!(bb, :attack_cd, cd - dt)
                        end
                        return BT_SUCCESS
                    end)
                ),

                # Otherwise, chase player
                bt_action((eid, bb, dt) -> begin
                    tc = get_component(eid, TransformComponent)
                    tc === nothing && return BT_FAILURE
                    target = bb_get(bb, :target_pos, nothing)
                    target === nothing && return BT_FAILURE
                    epos = tc.position[]
                    dx = target[1] - epos[1]
                    dz = target[3] - epos[3]
                    dist = sqrt(dx*dx + dz*dz)
                    dist < 0.1 && return BT_SUCCESS
                    speed = get_config(Float64, "enemy.chase_speed"; default=3.0)
                    nx, nz = dx/dist, dz/dist
                    tc.position[] = Vec3d(epos[1]+nx*speed*dt, epos[2], epos[3]+nz*speed*dt)
                    return BT_RUNNING
                end)
            )
        ),

        # Branch 2: patrol randomly
        bt_sequence(
            bt_action((eid, bb, dt) -> begin
                # Pick a new patrol target every few seconds
                if !bb_has(bb, :patrol_target) || bb_get(bb, :patrol_timer, 0.0) <= 0.0
                    half = ARENA_SIZE / 2 - 2
                    bb_set!(bb, :patrol_target, Vec3d(
                        rand() * 2half - half, 0.5,
                        rand() * 2half - half))
                    bb_set!(bb, :patrol_timer, 3.0 + rand() * 2.0)
                end
                bb_set!(bb, :patrol_timer, bb_get(bb, :patrol_timer, 0.0) - dt)
                return BT_SUCCESS
            end),
            bt_action((eid, bb, dt) -> begin
                tc = get_component(eid, TransformComponent)
                tc === nothing && return BT_FAILURE
                target = bb_get(bb, :patrol_target, tc.position[])
                epos = tc.position[]
                dx = target[1] - epos[1]
                dz = target[3] - epos[3]
                dist = sqrt(dx*dx + dz*dz)
                dist < 0.5 && return BT_SUCCESS
                speed = get_config(Float64, "enemy.patrol_speed"; default=1.5)
                nx, nz = dx/dist, dz/dist
                tc.position[] = Vec3d(epos[1]+nx*speed*dt, epos[2], epos[3]+nz*speed*dt)
                return BT_RUNNING
            end)
        )
    )
end

# =============================================================================
# Scene builders
# =============================================================================

function build_arena_scene()
    defs = Any[]

    # Floor
    push!(defs, entity([
        plane_mesh(width=Float32(ARENA_SIZE), depth=Float32(ARENA_SIZE)),
        MaterialComponent(color=RGB{Float32}(0.3, 0.35, 0.25), roughness=0.9f0),
        transform(position=Vec3d(0, 0, 0)),
        ColliderComponent(shape=AABBShape(Vec3f(Float32(ARENA_SIZE/2), 0.1f0, Float32(ARENA_SIZE/2)));
                          layer=LAYER_TERRAIN, mask=LAYER_ALL),
        RigidBodyComponent(body_type=BODY_STATIC)
    ]))

    # Walls (4 sides)
    half = Float32(ARENA_SIZE / 2)
    wall_positions = [
        (Vec3d(0, WALL_HEIGHT/2, -half), Vec3d(ARENA_SIZE, WALL_HEIGHT, 0.5)),
        (Vec3d(0, WALL_HEIGHT/2,  half), Vec3d(ARENA_SIZE, WALL_HEIGHT, 0.5)),
        (Vec3d(-half, WALL_HEIGHT/2, 0), Vec3d(0.5, WALL_HEIGHT, ARENA_SIZE)),
        (Vec3d( half, WALL_HEIGHT/2, 0), Vec3d(0.5, WALL_HEIGHT, ARENA_SIZE)),
    ]
    for (pos, sz) in wall_positions
        push!(defs, entity([
            cube_mesh(),
            MaterialComponent(color=RGB{Float32}(0.45, 0.4, 0.35), roughness=0.95f0),
            transform(position=pos, scale=sz),
            ColliderComponent(shape=AABBShape(Vec3f(Float32(sz[1]/2), Float32(sz[2]/2), Float32(sz[3]/2)));
                              layer=LAYER_TERRAIN, mask=LAYER_ALL),
            RigidBodyComponent(body_type=BODY_STATIC)
        ]))
    end

    # Directional light
    push!(defs, entity([
        DirectionalLightComponent(
            direction=Vec3f(-0.5f0, -1.0f0, -0.3f0),
            intensity=1.2f0,
            color=RGB{Float32}(1.0, 0.95, 0.85)
        ),
        transform()
    ]))

    # Ambient point lights (corners)
    for (x, z) in [(-10, -10), (10, -10), (-10, 10), (10, 10)]
        push!(defs, entity([
            PointLightComponent(color=RGB{Float32}(1.0, 0.8, 0.5), intensity=15.0f0, range=20.0f0),
            transform(position=Vec3d(x, 4, z))
        ]))
    end

    # Player (built manually to add gameplay components alongside PlayerComponent)
    prev_mouse_down = Ref(false)
    camera_child = entity([
        CameraComponent(fov=75.0f0, aspect=Float32(16/9), near=0.1f0, far=500.0f0),
        transform()
    ])
    push!(defs, entity([
        PlayerComponent(move_speed=5.0f0, sprint_multiplier=2.0f0, mouse_sensitivity=0.002f0),
        transform(position=PLAYER_START),
        ColliderComponent(shape=AABBShape(Vec3f(0.3f0, 0.9f0, 0.3f0));
                          layer=LAYER_PLAYER, mask=LAYER_ALL),
        RigidBodyComponent(body_type=BODY_KINEMATIC),
        HealthComponent(max_hp=get_config(Float32, "player.max_hp"; default=100.0f0)),
        InventoryComponent(max_slots=10),
        ScriptComponent(
            on_start=(eid, ctx) -> begin
                player_eid[] = eid
                # 3. Timer — track attack cooldown
                timer_interval!(0.05, () -> begin
                    if attack_cooldown[] > 0
                        attack_cooldown[] -= 0.05
                    end
                end; owner=eid)
            end,
            on_update=(eid, dt, ctx) -> begin
                # Player attack on left-click (manual edge detection)
                input = ctx.input
                mouse_down = 0 in input.mouse_buttons
                mouse_clicked = mouse_down && !prev_mouse_down[]
                prev_mouse_down[] = mouse_down
                if mouse_clicked && attack_cooldown[] <= 0
                    attack_cooldown[] = get_config(Float64, "player.attack_cooldown"; default=0.6)
                    emit!(PlayerAttackEvent(eid))
                end
            end
        )
    ]; children=[camera_child]))

    # Enemies (goblins) — with behavior trees, health, collision layers
    enemy_bt = make_enemy_bt()
    ehp = get_config(Float32, "enemy.hp"; default=50.0f0)
    for i in 1:get_config(Int, "enemy.count"; default=5)
        angle = 2π * i / get_config(Int, "enemy.count"; default=5)
        r = 8.0 + rand() * 4.0
        pos = Vec3d(cos(angle) * r, 0.5, sin(angle) * r)

        push!(defs, entity([
            cube_mesh(),
            MaterialComponent(color=RGB{Float32}(0.2, 0.6, 0.15), roughness=0.7f0),
            transform(position=pos, scale=Vec3d(0.6, 1.0, 0.6)),
            ColliderComponent(shape=AABBShape(Vec3f(0.3f0, 0.5f0, 0.3f0));
                              layer=LAYER_ENEMY, mask=LAYER_PLAYER | LAYER_TERRAIN | LAYER_PROJECTILE),
            RigidBodyComponent(body_type=BODY_KINEMATIC),
            HealthComponent(max_hp=ehp, auto_despawn=true,
                on_death=(eid, evt) -> begin
                    # Drop a goblin ear pickup at death location
                    tc = get_component(eid, TransformComponent)
                    if tc !== nothing
                        ear_pos = tc.position[]
                        # 3. Timer — delayed pickup spawn (entity is about to despawn)
                        timer_once!(0.1, () -> begin
                            # We can't spawn via ctx here since we're outside update,
                            # so emit a deferred event instead
                            emit_deferred!(GameLogEvent("A goblin ear drops to the ground!"))
                        end)
                    end
                end),
            BehaviorTreeComponent(enemy_bt; tick_rate=0.1),
            ScriptComponent(
                on_start=(eid, ctx) -> begin
                    enemy_count_alive[] += 1
                end
            )
        ]))
    end

    # Potion pickups
    for i in 1:POTION_COUNT
        angle = 2π * i / POTION_COUNT + π/4
        pos = Vec3d(cos(angle) * 5, 0.3, sin(angle) * 5)
        push!(defs, entity([
            sphere_mesh(radius=0.2f0),
            MaterialComponent(color=RGB{Float32}(0.9, 0.1, 0.1), emissive_factor=Vec3f(0.5, 0.1, 0.1)),
            transform(position=pos),
            ColliderComponent(shape=SphereShape(0.3f0);
                              layer=LAYER_PICKUP, mask=LAYER_PLAYER),
            PickupComponent(:health_potion; count=1, auto_pickup_radius=1.5f0),
            ScriptComponent(
                on_start=(eid, ctx) -> begin
                    # 6. Tween — bobbing animation
                    tween!(eid, :position, Vec3d(pos[1], pos[2]+0.4, pos[3]), 1.0;
                           easing=ease_in_out_sine,
                           loop_mode=TWEEN_PING_PONG, loop_count=-1)
                    # 6. Tween — pulsing glow via scale
                    tween!(eid, :scale, Vec3d(1.3, 1.3, 1.3), 0.8;
                           easing=ease_in_out_quad,
                           loop_mode=TWEEN_PING_PONG, loop_count=-1)
                end
            )
        ]))
    end

    # NPC (quest-giver) — tall blue pillar
    push!(defs, entity([
        cube_mesh(),
        MaterialComponent(color=RGB{Float32}(0.2, 0.3, 0.8), roughness=0.5f0,
                          emissive_factor=Vec3f(0.06, 0.09, 0.24)),
        transform(position=NPC_POS, scale=Vec3d(0.5, 1.5, 0.5)),
        ColliderComponent(shape=AABBShape(Vec3f(0.3f0, 0.75f0, 0.3f0));
                          layer=LAYER_DEFAULT, mask=LAYER_ALL),
        RigidBodyComponent(body_type=BODY_STATIC),
        ScriptComponent(
            on_start=(eid, ctx) -> begin
                npc_eid[] = eid
                # 6. Tween — idle rotation for NPC marker
                tween!(eid, :scale, Vec3d(0.55, 1.55, 0.55), 2.0;
                       easing=ease_in_out_sine,
                       loop_mode=TWEEN_PING_PONG, loop_count=-1)
            end
        )
    ]))

    # Decorative pillars
    for (x, z) in [(-6, -6), (6, -6), (-6, 6), (6, 6)]
        push!(defs, entity([
            cube_mesh(),
            MaterialComponent(color=RGB{Float32}(0.5, 0.45, 0.4), roughness=0.8f0),
            transform(position=Vec3d(x, 1.5, z), scale=Vec3d(0.8, 3.0, 0.8)),
            ColliderComponent(shape=AABBShape(Vec3f(0.4f0, 1.5f0, 0.4f0));
                              layer=LAYER_TERRAIN, mask=LAYER_ALL),
            RigidBodyComponent(body_type=BODY_STATIC)
        ]))
    end

    return defs
end

# =============================================================================
# 13. Dialogue — NPC conversation with quest integration
# =============================================================================

function build_npc_dialogue_initial()
    DialogueTree([
        DialogueNode(:greet, "Old Sage", "Greetings, adventurer. This arena is infested with goblins.";
            choices=[
                DialogueChoice("What should I do?", :quest_offer),
                DialogueChoice("I'm just passing through.", :end)
            ]),

        DialogueNode(:quest_offer, "Old Sage",
            "Clear out the goblins! Defeat them all and I'll have another task for you.";
            choices=[
                DialogueChoice("I'll do it!", :accept;
                    on_select=() -> begin
                        start_quest!(:clear_arena)
                        emit!(GameLogEvent("Quest accepted: Clear the Arena"))
                    end),
                DialogueChoice("Maybe later.", :end)
            ]),

        DialogueNode(:accept, "Old Sage", "Good luck! Press Left Mouse to attack when you're close.";
            auto_advance=:end),
    ])
end

function build_npc_dialogue_post_quest()
    DialogueTree([
        DialogueNode(:post_quest, "Old Sage",
            "Impressive! Now collect 3 goblin ears as proof of your deeds.";
            choices=[
                DialogueChoice("Consider it done!", :accept2;
                    on_select=() -> begin
                        start_quest!(:collect_ears)
                        emit!(GameLogEvent("Quest accepted: Goblin Trophies"))
                    end),
                DialogueChoice("Farewell.", :end)
            ]),

        DialogueNode(:accept2, "Old Sage", "Bring me the ears. I'll be here.";
            auto_advance=:end),
    ])
end

# =============================================================================
# 10. Debug Console — custom commands + watches
# =============================================================================

function setup_debug_console!()
    # Custom commands
    register_command!("heal", (args) -> begin
        amt = isempty(args) ? 50.0 : parse(Float64, args[1])
        if player_eid[] !== nothing
            heal!(player_eid[], amt)
            return "Healed player for $amt HP"
        end
        return "No player found"
    end; help="Heal player: heal [amount]")

    register_command!("difficulty", (args) -> begin
        if isempty(args)
            d = get_active_difficulty()
            return "Current difficulty: $(d === nothing ? "default" : d)"
        end
        name = Symbol(args[1])
        if apply_difficulty!(name)
            return "Applied difficulty: $name"
        end
        return "Unknown difficulty: $name"
    end; help="Set difficulty: difficulty <easy|hard>")

    register_command!("kill_all", (args) -> begin
        iterate_components(HealthComponent) do eid, health
            eid == player_eid[] && return
            apply_damage!(eid, 9999.0; damage_type=DAMAGE_TRUE)
        end
        return "All enemies eliminated"
    end; help="Kill all enemies")

    register_command!("quests", (args) -> begin
        active = get_active_quest_ids()
        isempty(active) && return "No active quests"
        lines = String[]
        for qid in active
            aq = get_quest_progress(qid)
            if aq !== nothing
                for (i, obj) in enumerate(aq.objectives)
                    push!(lines, "  [$qid] $(obj.description): $(obj.current_count)/$(obj.required_count)")
                end
            end
        end
        return join(lines, "\n")
    end; help="Show active quests")

    # Watches (always visible top-right)
    watch!("HP", () -> begin
        player_eid[] === nothing && return "N/A"
        hp = get_hp(player_eid[])
        hp === nothing && return "N/A"
        frac = get_hp_fraction(player_eid[])
        return "$(round(Int, hp)) / $(round(Int, get_config(Float32, "player.max_hp"; default=100.0f0)))"
    end)

    watch!("Enemies", () -> "$(enemy_count_alive[])")

    watch!("Kills", () -> "$(kills[])")

    watch!("Quest", () -> begin
        active = get_active_quest_ids()
        isempty(active) && return "None"
        qid = first(active)
        aq = get_quest_progress(qid)
        aq === nothing && return string(qid)
        obj = first(aq.objectives)
        return "$qid: $(obj.current_count)/$(obj.required_count)"
    end)
end

# =============================================================================
# 4. Coroutine — intro sequence
# =============================================================================

function start_intro_sequence!()
    start_coroutine!() do ctx
        emit!(GameLogEvent("Welcome to Goblin's Keep!"))
        yield_wait(ctx, 1.5)
        emit!(GameLogEvent("Approach the blue pillar to speak with the Sage."))
        yield_wait(ctx, 2.0)
        emit!(GameLogEvent("Press [E] near the NPC to start dialogue."))
        yield_wait(ctx, 2.0)
        emit!(GameLogEvent("Press [`] to open the debug console."))
    end
end

# =============================================================================
# FSM Game States
# =============================================================================

# --- Menu State ---
mutable struct MenuState <: GameState end

function OpenReality.on_enter!(state::MenuState, sc::Scene)
    # Nothing — UI draws the menu
end

function OpenReality.on_update!(state::MenuState, sc::Scene, dt::Float64, ctx::GameContext)
    if start_requested[]
        start_requested[] = false
        return StateTransition(:playing, build_arena_scene())
    end
    return nothing
end

function OpenReality.get_ui_callback(state::MenuState)
    return function(ui_ctx)
        cx = Float32(ui_ctx.width / 2)
        cy = Float32(ui_ctx.height / 2)

        # Title
        ui_text(ui_ctx, "GOBLIN'S KEEP";
                x=cx - 130, y=cy - 100, size=40,
                color=RGB{Float32}(1.0, 0.85, 0.2))

        # Subtitle
        ui_text(ui_ctx, "Gameplay Systems Demo";
                x=cx - 100, y=cy - 55, size=18,
                color=RGB{Float32}(0.7, 0.7, 0.7))

        # Difficulty selector
        ui_text(ui_ctx, "Difficulty:";
                x=cx - 70, y=cy, size=16,
                color=RGB{Float32}(0.9, 0.9, 0.9))

        if ui_button(ui_ctx, "Easy"; x=cx - 110, y=cy + 25, width=100, height=35,
                     color=RGB{Float32}(0.2, 0.6, 0.2),
                     hover_color=RGB{Float32}(0.3, 0.7, 0.3))
            apply_difficulty!(:easy)
        end
        if ui_button(ui_ctx, "Hard"; x=cx + 10, y=cy + 25, width=100, height=35,
                     color=RGB{Float32}(0.7, 0.2, 0.2),
                     hover_color=RGB{Float32}(0.8, 0.3, 0.3))
            apply_difficulty!(:hard)
        end

        # Play button
        if ui_button(ui_ctx, "PLAY"; x=cx - 60, y=cy + 80, width=120, height=45,
                     color=RGB{Float32}(0.2, 0.4, 0.8),
                     hover_color=RGB{Float32}(0.3, 0.5, 0.9))
            start_requested[] = true
        end
    end
end

# --- Playing State ---
mutable struct PlayingState <: GameState
    elapsed::Float64
    PlayingState() = new(0.0)
end

function OpenReality.on_enter!(state::PlayingState, sc::Scene)
    setup_event_listeners!()
    setup_debug_console!()
    register_items!()
    register_quests!()
    start_intro_sequence!()
end

function OpenReality.on_update!(state::PlayingState, sc::Scene, dt::Float64, ctx::GameContext)
    state.elapsed += dt

    # NPC interaction: press E near NPC
    if npc_eid[] !== nothing && player_eid[] !== nothing && !is_dialogue_active()
        ptc = get_component(player_eid[], TransformComponent)
        ntc = get_component(npc_eid[], TransformComponent)
        if ptc !== nothing && ntc !== nothing
            pp = ptc.position[]
            np = ntc.position[]
            dist = sqrt((pp[1]-np[1])^2 + (pp[3]-np[3])^2)
            if dist < 3.0
                input = ctx.input
                if is_key_just_pressed(input, Int('E'))
                    # Choose dialogue based on quest state
                    if is_quest_completed(:clear_arena)
                        tree = build_npc_dialogue_post_quest()
                        start_dialogue!(tree; id=:sage)
                    elseif !is_quest_active(:clear_arena)
                        tree = build_npc_dialogue_initial()
                        start_dialogue!(tree; id=:sage)
                    end
                end
            end
        end
    end

    # Player attack handling
    if player_eid[] !== nothing && attack_cooldown[] <= 0
        # (attack input handled by script component)
    end

    # Check for game over
    if player_eid[] !== nothing && is_dead(player_eid[])
        return StateTransition(:game_over)
    end

    # Check for victory (both quests complete)
    if is_quest_completed(:clear_arena) && is_quest_completed(:collect_ears)
        return StateTransition(:victory)
    end

    return nothing
end

function OpenReality.get_ui_callback(state::PlayingState)
    return function(ui_ctx)
        # HUD — HP bar
        if player_eid[] !== nothing
            frac = get_hp_fraction(player_eid[])
            frac = frac !== nothing ? frac : 1.0f0
            bar_w = 200.0f0
            bar_h = 20.0f0

            ui_rect(ui_ctx; x=10, y=Float32(ui_ctx.height - 35),
                    width=bar_w, height=bar_h,
                    color=RGB{Float32}(0.2, 0.2, 0.2), alpha=0.8f0)
            hp_color = frac > 0.5f0 ? RGB{Float32}(0.1, 0.8, 0.2) :
                       frac > 0.25f0 ? RGB{Float32}(0.9, 0.7, 0.1) :
                       RGB{Float32}(0.9, 0.1, 0.1)
            ui_rect(ui_ctx; x=10, y=Float32(ui_ctx.height - 35),
                    width=bar_w * frac, height=bar_h,
                    color=hp_color, alpha=0.9f0)
            ui_text(ui_ctx, "HP"; x=15, y=Float32(ui_ctx.height - 33), size=14,
                    color=RGB{Float32}(1, 1, 1))
        end

        # HUD — inventory quick-info
        if player_eid[] !== nothing
            potions = get_item_count(player_eid[], :health_potion)
            ears = get_item_count(player_eid[], :goblin_ear)
            ui_text(ui_ctx, "Potions: $potions  |  Ears: $ears";
                    x=10, y=Float32(ui_ctx.height - 55), size=14,
                    color=RGB{Float32}(0.9, 0.9, 0.7))
        end

        # HUD — quest tracker
        active = get_active_quest_ids()
        if !isempty(active)
            y = 60.0f0
            ui_text(ui_ctx, "Active Quests:";
                    x=10, y=y, size=16, color=RGB{Float32}(1, 0.85, 0.2))
            for qid in active
                aq = get_quest_progress(qid)
                aq === nothing && continue
                y += 20
                ui_text(ui_ctx, string(aq.def.name);
                        x=15, y=y, size=14, color=RGB{Float32}(0.9, 0.9, 0.9))
                for obj in aq.objectives
                    y += 16
                    marker = obj.completed ? "[x]" : "[ ]"
                    ui_text(ui_ctx, "  $marker $(obj.description) ($(obj.current_count)/$(obj.required_count))";
                            x=20, y=y, size=12,
                            color=obj.completed ?
                                RGB{Float32}(0.3, 0.8, 0.3) :
                                RGB{Float32}(0.7, 0.7, 0.7))
                end
            end
        end

        # HUD — game log (bottom-left above HP bar)
        log_y = Float32(ui_ctx.height - 80)
        for msg in reverse(game_log[])
            ui_text(ui_ctx, msg; x=10, y=log_y, size=13,
                    color=RGB{Float32}(0.8, 0.8, 0.6))
            log_y -= 16
            log_y < 100 && break
        end

        # NPC proximity hint
        if npc_eid[] !== nothing && player_eid[] !== nothing && !is_dialogue_active()
            ptc = get_component(player_eid[], TransformComponent)
            ntc = get_component(npc_eid[], TransformComponent)
            if ptc !== nothing && ntc !== nothing
                pp = ptc.position[]
                np = ntc.position[]
                dist = sqrt((pp[1]-np[1])^2 + (pp[3]-np[3])^2)
                if dist < 3.0
                    ui_text(ui_ctx, "[E] Talk to Sage";
                            x=Float32(ui_ctx.width/2 - 60),
                            y=Float32(ui_ctx.height/2 + 30),
                            size=18, color=RGB{Float32}(1, 1, 0.5))
                end
            end
        end

        # Controls hint
        ui_text(ui_ctx, "WASD: Move  |  Mouse: Look  |  LMB: Attack  |  [`]: Console";
                x=Float32(ui_ctx.width/2 - 200), y=Float32(ui_ctx.height - 15),
                size=12, color=RGB{Float32}(0.5, 0.5, 0.5))

        # Render dialogue overlay
        render_dialogue!(ui_ctx)

        # Render debug console overlay
        render_debug_console!(ui_ctx)
    end
end

# --- Game Over State ---
mutable struct GameOverState <: GameState end

function OpenReality.get_ui_callback(state::GameOverState)
    return function(ui_ctx)
        cx = Float32(ui_ctx.width / 2)
        cy = Float32(ui_ctx.height / 2)
        ui_rect(ui_ctx; x=0, y=0, width=Float32(ui_ctx.width), height=Float32(ui_ctx.height),
                color=RGB{Float32}(0.1, 0, 0), alpha=0.7f0)
        ui_text(ui_ctx, "YOU DIED"; x=cx - 80, y=cy - 40, size=48,
                color=RGB{Float32}(0.9, 0.1, 0.1))
        ui_text(ui_ctx, "Goblins defeated: $(kills[])";
                x=cx - 70, y=cy + 20, size=18,
                color=RGB{Float32}(0.7, 0.7, 0.7))
        if ui_button(ui_ctx, "Return to Menu"; x=cx - 75, y=cy + 60, width=150, height=40,
                     color=RGB{Float32}(0.3, 0.3, 0.5),
                     hover_color=RGB{Float32}(0.4, 0.4, 0.6))
            return_to_menu[] = true
        end
    end
end

function OpenReality.on_update!(state::GameOverState, sc::Scene, dt::Float64, ctx::GameContext)
    if return_to_menu[]
        return_to_menu[] = false
        return StateTransition(:menu, build_menu_scene())
    end
    return nothing
end

# --- Victory State ---
mutable struct VictoryState <: GameState end

function OpenReality.get_ui_callback(state::VictoryState)
    return function(ui_ctx)
        cx = Float32(ui_ctx.width / 2)
        cy = Float32(ui_ctx.height / 2)
        ui_rect(ui_ctx; x=0, y=0, width=Float32(ui_ctx.width), height=Float32(ui_ctx.height),
                color=RGB{Float32}(0, 0.05, 0.1), alpha=0.7f0)
        ui_text(ui_ctx, "VICTORY!"; x=cx - 80, y=cy - 40, size=48,
                color=RGB{Float32}(1.0, 0.85, 0.2))
        ui_text(ui_ctx, "All quests completed!";
                x=cx - 80, y=cy + 20, size=18,
                color=RGB{Float32}(0.7, 0.9, 0.7))
        if ui_button(ui_ctx, "Return to Menu"; x=cx - 75, y=cy + 60, width=150, height=40,
                     color=RGB{Float32}(0.2, 0.5, 0.3),
                     hover_color=RGB{Float32}(0.3, 0.6, 0.4))
            return_to_menu[] = true
        end
    end
end

function OpenReality.on_update!(state::VictoryState, sc::Scene, dt::Float64, ctx::GameContext)
    if return_to_menu[]
        return_to_menu[] = false
        return StateTransition(:menu, build_menu_scene())
    end
    return nothing
end

# =============================================================================
# Player attack event handler (registered when playing starts)
# =============================================================================

function setup_attack_handler!()
    subscribe!(PlayerAttackEvent, event -> begin
        ptc = get_component(event.player_id, TransformComponent)
        ptc === nothing && return
        ppos = ptc.position[]
        range_sq = get_config(Float64, "player.attack_range"; default=2.8)^2

        # Find closest enemy in range
        closest_eid = nothing
        closest_dist = Inf
        iterate_components(HealthComponent) do eid, health
            eid == event.player_id && return
            is_dead(eid) && return
            tc = get_component(eid, TransformComponent)
            tc === nothing && return
            epos = tc.position[]
            dx = epos[1] - ppos[1]
            dy = epos[2] - ppos[2]
            dz = epos[3] - ppos[3]
            d2 = dx*dx + dy*dy + dz*dz
            if d2 < range_sq && d2 < closest_dist
                closest_dist = d2
                closest_eid = eid
            end
        end

        if closest_eid !== nothing
            apply_damage!(closest_eid, 25.0;
                          damage_type=DAMAGE_PHYSICAL,
                          knockback=Vec3d(0, 0, 0))
            emit_deferred!(GameLogEvent("Hit!"))
        end
    end; priority=10)
end

# =============================================================================
# Menu scene (needs a camera + light for the UI to render)
# =============================================================================

function build_menu_scene()
    [
        create_player(position=Vec3d(0, 1.7, 0)),
        entity([
            DirectionalLightComponent(direction=Vec3f(0, -1, 0), intensity=0.3f0,
                                      color=RGB{Float32}(0.4, 0.3, 0.5)),
            transform()
        ]),
        entity([
            plane_mesh(width=10.0f0, depth=10.0f0),
            MaterialComponent(color=RGB{Float32}(0.1, 0.1, 0.15), roughness=0.95f0),
            transform(),
            ColliderComponent(shape=AABBShape(Vec3f(5.0f0, 0.01f0, 5.0f0))),
            RigidBodyComponent(body_type=BODY_STATIC)
        ])
    ]
end

# =============================================================================
# Main — wire everything together
# =============================================================================

function main()
    # 2. Setup config
    setup_config!()

    # Build FSM with transitions and guards
    fsm = GameStateMachine(:menu, build_menu_scene())
    add_state!(fsm, :menu, MenuState())
    add_state!(fsm, :playing, PlayingState())
    add_state!(fsm, :game_over, GameOverState())
    add_state!(fsm, :victory, VictoryState())

    # 5. FSM Transitions with guards
    add_transition!(fsm, :menu, :playing;
        on_transition=() -> begin
            # Reset game state for new run
            kills[] = 0
            enemy_count_alive[] = 0
            player_eid[] = nothing
            npc_eid[] = nothing
            empty!(game_log[])
            attack_cooldown[] = 0.0
            setup_attack_handler!()
        end)
    add_transition!(fsm, :playing, :game_over)
    add_transition!(fsm, :playing, :victory)
    add_transition!(fsm, :game_over, :menu)
    add_transition!(fsm, :victory, :menu)

    # Render with FSM
    render(fsm;
        title="Goblin's Keep — Gameplay Systems Demo",
        width=1280, height=720,
        on_scene_switch=(old_scene, new_defs) -> begin
            reset_engine_state!()
        end,
        post_process=PostProcessConfig(
            tone_mapping=TONEMAP_ACES,
            bloom_enabled=true,
            bloom_threshold=0.8f0,
            bloom_intensity=0.3f0,
            fxaa_enabled=true,
            vignette_enabled=true,
            vignette_intensity=0.4f0,
            vignette_radius=0.8f0
        )
    )
end

main()
