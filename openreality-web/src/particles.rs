use glam::Vec3;

/// Configuration for a particle emitter (matches Julia's ParticleSystemComponent).
pub struct ParticleConfig {
    pub max_particles: usize,
    pub emission_rate: f32,
    pub burst_count: i32,
    pub lifetime_min: f32,
    pub lifetime_max: f32,
    pub velocity_min: Vec3,
    pub velocity_max: Vec3,
    pub gravity_modifier: f32,
    pub damping: f32,
    pub start_size_min: f32,
    pub start_size_max: f32,
    pub end_size: f32,
    pub start_color: [f32; 3],
    pub end_color: [f32; 3],
    pub start_alpha: f32,
    pub end_alpha: f32,
    pub additive: bool,
}

impl Default for ParticleConfig {
    fn default() -> Self {
        Self {
            max_particles: 256,
            emission_rate: 20.0,
            burst_count: 0,
            lifetime_min: 1.0,
            lifetime_max: 2.0,
            velocity_min: Vec3::new(-0.5, 1.0, -0.5),
            velocity_max: Vec3::new(0.5, 3.0, 0.5),
            gravity_modifier: 1.0,
            damping: 0.0,
            start_size_min: 0.1,
            start_size_max: 0.3,
            end_size: 0.0,
            start_color: [1.0, 1.0, 1.0],
            end_color: [1.0, 1.0, 1.0],
            start_alpha: 1.0,
            end_alpha: 0.0,
            additive: false,
        }
    }
}

struct Particle {
    position: Vec3,
    velocity: Vec3,
    lifetime: f32,
    max_lifetime: f32,
    size: f32,
    alive: bool,
}

const GRAVITY: Vec3 = Vec3::new(0.0, -9.81, 0.0);

/// A particle pool for one emitter. Manages particle simulation and billboard vertex generation.
pub struct ParticlePool {
    particles: Vec<Particle>,
    emit_accumulator: f32,
    /// Flat vertex data: 6 vertices per particle, 9 floats per vertex (pos3 + uv2 + rgba4).
    pub vertex_data: Vec<f32>,
    pub vertex_count: usize,
    pub alive_count: usize,
}

impl ParticlePool {
    pub fn new(max_particles: usize) -> Self {
        let mut particles = Vec::with_capacity(max_particles);
        for _ in 0..max_particles {
            particles.push(Particle {
                position: Vec3::ZERO,
                velocity: Vec3::ZERO,
                lifetime: 0.0,
                max_lifetime: 1.0,
                size: 0.0,
                alive: false,
            });
        }
        Self {
            particles,
            emit_accumulator: 0.0,
            vertex_data: vec![0.0; max_particles * 6 * 9],
            vertex_count: 0,
            alive_count: 0,
        }
    }

    /// Resize the pool if max_particles changed.
    pub fn resize(&mut self, max_particles: usize) {
        if self.particles.len() != max_particles {
            self.particles.resize_with(max_particles, || Particle {
                position: Vec3::ZERO,
                velocity: Vec3::ZERO,
                lifetime: 0.0,
                max_lifetime: 1.0,
                size: 0.0,
                alive: false,
            });
            self.vertex_data.resize(max_particles * 6 * 9, 0.0);
        }
    }

    /// Emit a single particle at the given origin.
    fn emit(&mut self, origin: Vec3, config: &ParticleConfig) -> bool {
        for p in &mut self.particles {
            if !p.alive {
                p.position = origin;
                p.velocity = Vec3::new(
                    rand_range(config.velocity_min.x, config.velocity_max.x),
                    rand_range(config.velocity_min.y, config.velocity_max.y),
                    rand_range(config.velocity_min.z, config.velocity_max.z),
                );
                p.max_lifetime = rand_range(config.lifetime_min, config.lifetime_max);
                p.lifetime = p.max_lifetime;
                p.size = rand_range(config.start_size_min, config.start_size_max);
                p.alive = true;
                return true;
            }
        }
        false
    }

    /// Simulate physics for all alive particles.
    fn simulate(&mut self, dt: f32, gravity_modifier: f32, damping: f32) {
        let mut alive = 0;
        for p in &mut self.particles {
            if !p.alive {
                continue;
            }
            p.lifetime -= dt;
            if p.lifetime <= 0.0 {
                p.alive = false;
                continue;
            }
            p.velocity += GRAVITY * gravity_modifier * dt;
            p.velocity *= 1.0 - damping * dt;
            p.position += p.velocity * dt;
            alive += 1;
        }
        self.alive_count = alive;
    }

    /// Sort alive particles back-to-front relative to camera.
    fn sort_back_to_front(&mut self, cam_pos: Vec3) {
        // Partition alive to front
        let n = self.particles.len();
        let mut write = 0;
        for i in 0..n {
            if self.particles[i].alive {
                if i != write {
                    self.particles.swap(i, write);
                }
                write += 1;
            }
        }
        // Sort alive slice by -distance^2 (farthest first)
        let alive_slice = &mut self.particles[..write];
        alive_slice.sort_by(|a, b| {
            let da = (a.position - cam_pos).length_squared();
            let db = (b.position - cam_pos).length_squared();
            db.partial_cmp(&da).unwrap_or(core::cmp::Ordering::Equal)
        });
    }

    /// Build billboard vertex data for rendering.
    fn build_billboards(
        &mut self,
        config: &ParticleConfig,
        cam_right: Vec3,
        cam_up: Vec3,
    ) {
        let mut offset = 0;
        let mut vert_count = 0;

        for p in &self.particles {
            if !p.alive {
                continue;
            }

            let t = 1.0 - (p.lifetime / p.max_lifetime).clamp(0.0, 1.0);
            let size = lerp(p.size, config.end_size, t);
            let half = size * 0.5;

            let r = lerp(config.start_color[0], config.end_color[0], t);
            let g = lerp(config.start_color[1], config.end_color[1], t);
            let b = lerp(config.start_color[2], config.end_color[2], t);
            let a = lerp(config.start_alpha, config.end_alpha, t);

            let right = cam_right * half;
            let up = cam_up * half;

            let bl = p.position - right - up;
            let br = p.position + right - up;
            let tr = p.position + right + up;
            let tl = p.position - right + up;

            // Two triangles: BL, BR, TR and BL, TR, TL
            let corners = [(bl, 0.0, 0.0), (br, 1.0, 0.0), (tr, 1.0, 1.0),
                           (bl, 0.0, 0.0), (tr, 1.0, 1.0), (tl, 0.0, 1.0)];

            for (pos, u, v) in corners {
                if offset + 9 <= self.vertex_data.len() {
                    self.vertex_data[offset]     = pos.x;
                    self.vertex_data[offset + 1] = pos.y;
                    self.vertex_data[offset + 2] = pos.z;
                    self.vertex_data[offset + 3] = u;
                    self.vertex_data[offset + 4] = v;
                    self.vertex_data[offset + 5] = r;
                    self.vertex_data[offset + 6] = g;
                    self.vertex_data[offset + 7] = b;
                    self.vertex_data[offset + 8] = a;
                    offset += 9;
                    vert_count += 1;
                }
            }
        }
        self.vertex_count = vert_count;
    }

    /// Full per-frame update: emit, simulate, sort, build billboards.
    pub fn update(
        &mut self,
        dt: f32,
        origin: Vec3,
        config: &mut ParticleConfig,
        cam_pos: Vec3,
        cam_right: Vec3,
        cam_up: Vec3,
    ) {
        self.resize(config.max_particles);

        // Burst emission
        if config.burst_count > 0 {
            for _ in 0..config.burst_count {
                if !self.emit(origin, config) { break; }
            }
            config.burst_count = 0;
        }

        // Continuous emission
        self.emit_accumulator += config.emission_rate * dt;
        while self.emit_accumulator >= 1.0 {
            if !self.emit(origin, config) { break; }
            self.emit_accumulator -= 1.0;
        }

        self.simulate(dt, config.gravity_modifier, config.damping);
        self.sort_back_to_front(cam_pos);
        self.build_billboards(config, cam_right, cam_up);
    }
}

fn lerp(a: f32, b: f32, t: f32) -> f32 {
    a + (b - a) * t
}

/// Simple deterministic-ish pseudo-random for WASM (no std rand).
/// Uses a global xorshift state.
static mut RAND_STATE: u32 = 12345;

fn rand_f32() -> f32 {
    unsafe {
        RAND_STATE ^= RAND_STATE << 13;
        RAND_STATE ^= RAND_STATE >> 17;
        RAND_STATE ^= RAND_STATE << 5;
        (RAND_STATE as f32) / (u32::MAX as f32)
    }
}

fn rand_range(lo: f32, hi: f32) -> f32 {
    lo + (hi - lo) * rand_f32()
}
