# New Features Showcase
# Demonstrates: Audio, UI/HUD, Skeletal Animation, and Particle System
#
# Run with:
#   julia --project=. examples/features_showcase.jl

using OpenReality

reset_entity_counter!()
reset_component_stores!()

# ============================================================================
# Scene Setup
# ============================================================================

s = scene([
    # FPS Player with audio listener
    create_player(position=Vec3d(0, 2.0, 12)),

    # Attach AudioListenerComponent to the camera entity
    # (create_player makes a camera child; we add audio to a separate entity
    # that follows the same position for simplicity)
    entity([
        transform(position=Vec3d(0, 2.0, 12)),
        AudioListenerComponent(gain=1.0f0)
    ]),

    # ====== Lighting ======

    # Sun
    entity([
        DirectionalLightComponent(
            direction=Vec3f(0.4, -1.0, -0.3),
            intensity=3.0f0,
            color=RGB{Float32}(1.0, 0.95, 0.85)
        )
    ]),

    # Warm fill light
    entity([
        PointLightComponent(
            color=RGB{Float32}(1.0, 0.6, 0.3),
            intensity=15.0f0,
            range=20.0f0
        ),
        transform(position=Vec3d(-5, 4, 3))
    ]),

    # Cool fill light
    entity([
        PointLightComponent(
            color=RGB{Float32}(0.3, 0.5, 1.0),
            intensity=15.0f0,
            range=20.0f0
        ),
        transform(position=Vec3d(5, 4, 3))
    ]),

    # ====== Ground ======

    entity([
        transform(scale=Vec3d(30, 1, 30)),
        plane_mesh(width=1.0f0, depth=1.0f0),
        MaterialComponent(
            color=RGB{Float32}(0.3, 0.35, 0.3),
            metallic=0.0f0,
            roughness=0.9f0
        ),
        ColliderComponent(shape=AABBShape(Vec3f(15.0f0, 0.01f0, 15.0f0))),
        RigidBodyComponent(body_type=BODY_STATIC)
    ]),

    # ====== Feature 1: Skeletal Animation ======
    # A simple "robot arm" with two bones — the upper arm and forearm rotate
    # via programmatic animation channels. The mesh entity has a
    # SkinnedMeshComponent that references the bone entities.

    # Upper arm bone (root)
    entity([
        transform(position=Vec3d(-4, 1, 0)),
        BoneComponent(
            inverse_bind_matrix=Mat4f(
                1, 0, 0, 0,
                0, 1, 0, 0,
                0, 0, 1, 0,
                4, -1, 0, 1   # inverse of bind position
            ),
            bone_index=0,
            name="upper_arm"
        ),
        cube_mesh(size=0.3f0),
        MaterialComponent(
            color=RGB{Float32}(0.8, 0.2, 0.2),
            metallic=0.7f0,
            roughness=0.3f0
        )
    ], children=[
        # Forearm bone (child)
        entity([
            transform(position=Vec3d(0, 1.5, 0)),
            BoneComponent(
                inverse_bind_matrix=Mat4f(
                    1, 0, 0, 0,
                    0, 1, 0, 0,
                    0, 0, 1, 0,
                    4, -2.5, 0, 1
                ),
                bone_index=1,
                name="forearm"
            ),
            cube_mesh(size=0.25f0),
            MaterialComponent(
                color=RGB{Float32}(0.9, 0.3, 0.3),
                metallic=0.7f0,
                roughness=0.3f0
            )
        ])
    ]),

    # Label for skeletal animation
    entity([
        transform(position=Vec3d(-4, 0.1, 1.5)),
        plane_mesh(width=2.5f0, depth=0.5f0),
        MaterialComponent(
            color=RGB{Float32}(0.15, 0.15, 0.15),
            metallic=0.0f0,
            roughness=1.0f0
        )
    ]),

    # ====== Feature 2: Particle System — Fire ======

    entity([
        transform(position=Vec3d(0, 0.5, 0)),
        ParticleSystemComponent(
            max_particles=300,
            emission_rate=80.0f0,
            lifetime_min=0.4f0,
            lifetime_max=1.2f0,
            velocity_min=Vec3f(-0.3f0, 1.5f0, -0.3f0),
            velocity_max=Vec3f(0.3f0, 3.5f0, 0.3f0),
            gravity_modifier=0.0f0,    # fire rises, no gravity
            damping=0.3f0,
            start_size_min=0.15f0,
            start_size_max=0.35f0,
            end_size=0.05f0,
            start_color=RGB{Float32}(1.0, 0.6, 0.1),   # orange
            end_color=RGB{Float32}(1.0, 0.1, 0.0),      # red
            start_alpha=0.9f0,
            end_alpha=0.0f0,
            additive=true
        ),
        # A small dark pedestal underneath
        cube_mesh(size=0.6f0),
        MaterialComponent(
            color=RGB{Float32}(0.1, 0.1, 0.1),
            metallic=0.0f0,
            roughness=0.95f0
        )
    ]),

    # Fire label
    entity([
        transform(position=Vec3d(0, 0.1, 1.5)),
        plane_mesh(width=1.5f0, depth=0.5f0),
        MaterialComponent(
            color=RGB{Float32}(0.15, 0.15, 0.15),
            metallic=0.0f0,
            roughness=1.0f0
        )
    ]),

    # ====== Feature 2b: Particle System — Sparks ======

    entity([
        transform(position=Vec3d(4, 2.5, 0)),
        ParticleSystemComponent(
            max_particles=200,
            emission_rate=40.0f0,
            burst_count=30,
            lifetime_min=0.5f0,
            lifetime_max=2.0f0,
            velocity_min=Vec3f(-2.0f0, -1.0f0, -2.0f0),
            velocity_max=Vec3f(2.0f0, 4.0f0, 2.0f0),
            gravity_modifier=1.0f0,    # sparks fall
            damping=0.05f0,
            start_size_min=0.03f0,
            start_size_max=0.08f0,
            end_size=0.01f0,
            start_color=RGB{Float32}(1.0, 0.9, 0.5),   # bright yellow
            end_color=RGB{Float32}(1.0, 0.3, 0.0),      # orange fade
            start_alpha=1.0f0,
            end_alpha=0.0f0,
            additive=true
        ),
        sphere_mesh(radius=0.2f0, segments=16, rings=8),
        MaterialComponent(
            color=RGB{Float32}(0.5, 0.5, 0.5),
            metallic=0.9f0,
            roughness=0.2f0
        )
    ]),

    # Sparks label
    entity([
        transform(position=Vec3d(4, 0.1, 1.5)),
        plane_mesh(width=1.5f0, depth=0.5f0),
        MaterialComponent(
            color=RGB{Float32}(0.15, 0.15, 0.15),
            metallic=0.0f0,
            roughness=1.0f0
        )
    ]),

    # ====== Feature 3: Audio Source ======
    # A pulsing sphere that represents a spatial audio emitter.
    # (Audio will play if a .wav file is provided)

    entity([
        transform(position=Vec3d(-4, 1.5, -4)),
        sphere_mesh(radius=0.4f0),
        MaterialComponent(
            color=RGB{Float32}(0.2, 0.5, 1.0),
            metallic=0.3f0,
            roughness=0.5f0,
            emissive_factor=Vec3f(0.2f0, 0.4f0, 0.8f0)
        ),
        AudioSourceComponent(
            audio_path="",        # Set to a .wav path to hear audio
            playing=false,
            looping=true,
            gain=0.8f0,
            spatial=true,
            reference_distance=2.0f0,
            max_distance=50.0f0
        )
    ]),

    # Audio label
    entity([
        transform(position=Vec3d(-4, 0.1, -2.5)),
        plane_mesh(width=2.0f0, depth=0.5f0),
        MaterialComponent(
            color=RGB{Float32}(0.15, 0.15, 0.15),
            metallic=0.0f0,
            roughness=1.0f0
        )
    ]),

    # ====== Decorative objects ======

    # Metallic sphere
    entity([
        transform(position=Vec3d(4, 1, -4)),
        sphere_mesh(radius=0.7f0),
        MaterialComponent(
            color=RGB{Float32}(0.95, 0.95, 0.95),
            metallic=1.0f0,
            roughness=0.1f0
        )
    ]),

    # Wooden cube
    entity([
        transform(position=Vec3d(0, 0.75, -6)),
        cube_mesh(size=1.5f0),
        MaterialComponent(
            color=RGB{Float32}(0.55, 0.35, 0.18),
            metallic=0.0f0,
            roughness=0.8f0
        )
    ]),
])

# ============================================================================
# Feature 4: UI/HUD Overlay
# ============================================================================
# The UI callback is called every frame to build immediate-mode UI elements.

frame_count = Ref(0)

ui_callback = function(ctx::UIContext)
    frame_count[] += 1

    # ---- Title bar ----
    ui_rect(ctx, x=0, y=0, width=ctx.width, height=50,
            color=RGB{Float32}(0.0, 0.0, 0.0), alpha=0.6f0)
    ui_text(ctx, "OpenReality — New Features Showcase", x=15, y=12, size=28,
            color=RGB{Float32}(1.0, 1.0, 1.0))

    # ---- Feature status panel (bottom-left) ----
    panel_x = 10
    panel_y = ctx.height - 180
    panel_w = 280
    panel_h = 170

    ui_rect(ctx, x=panel_x, y=panel_y, width=panel_w, height=panel_h,
            color=RGB{Float32}(0.05, 0.05, 0.1), alpha=0.75f0)

    ui_text(ctx, "Feature Status", x=panel_x+10, y=panel_y+8, size=22,
            color=RGB{Float32}(0.9, 0.9, 0.2))

    features = [
        ("Audio System", RGB{Float32}(0.3, 0.8, 1.0)),
        ("UI / HUD", RGB{Float32}(0.3, 1.0, 0.4)),
        ("Skeletal Animation", RGB{Float32}(1.0, 0.4, 0.4)),
        ("Particle System", RGB{Float32}(1.0, 0.7, 0.2)),
    ]

    for (i, (name, color)) in enumerate(features)
        y_off = panel_y + 30 + i * 30
        ui_text(ctx, "* $name", x=panel_x+15, y=y_off, size=18, color=color)
    end

    # ---- Particle stats (top-right) ----
    stats_w = 220
    stats_x = ctx.width - stats_w - 10
    stats_y = 60

    total_particles = sum(pool.alive_count for (_, pool) in PARTICLE_POOLS; init=0)

    ui_rect(ctx, x=stats_x, y=stats_y, width=stats_w, height=80,
            color=RGB{Float32}(0.05, 0.05, 0.1), alpha=0.75f0)
    ui_text(ctx, "Particles: $total_particles", x=stats_x+10, y=stats_y+8, size=20,
            color=RGB{Float32}(1.0, 0.8, 0.3))
    ui_text(ctx, "Emitters: $(length(PARTICLE_POOLS))", x=stats_x+10, y=stats_y+35, size=18,
            color=RGB{Float32}(0.8, 0.8, 0.8))

    # ---- Animated progress bar (demo) ----
    progress = Float32((sin(frame_count[] * 0.02) + 1.0) / 2.0)
    bar_y = ctx.height - 40
    ui_progress_bar(ctx, progress, x=ctx.width-310, y=bar_y, width=300, height=25,
                    color=RGB{Float32}(0.2, 0.8, 0.4))

    # ---- Controls hint (bottom-right) ----
    ui_text(ctx, "WASD: Move  |  Mouse: Look  |  Shift: Sprint  |  Esc: Release cursor",
            x=ctx.width-550, y=ctx.height-15, size=14,
            color=RGB{Float32}(0.6, 0.6, 0.6))
end

# ============================================================================
# Render
# ============================================================================

println("Starting OpenReality Features Showcase...")
println("Controls: WASD to move, mouse to look, Shift to sprint, Escape to release cursor")
println()
println("Features demonstrated:")
println("  1. Audio System    — spatial audio source (blue sphere, back-left)")
println("  2. UI / HUD        — overlay text, panels, progress bar, stats")
println("  3. Skeletal Anim   — bone hierarchy (red cubes, left)")
println("  4. Particle System — fire (center) + sparks (right)")

render(s, ui=ui_callback, title="OpenReality — Features Showcase")
