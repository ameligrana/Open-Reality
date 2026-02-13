/// Browser input state — keyboard, mouse, and touch events.
pub struct InputState {
    pub keys_down: [bool; 256],
    pub mouse_x: f64,
    pub mouse_y: f64,
    pub mouse_dx: f64,
    pub mouse_dy: f64,
    pub mouse_buttons: [bool; 3],
}

impl InputState {
    pub fn new() -> Self {
        Self {
            keys_down: [false; 256],
            mouse_x: 0.0,
            mouse_y: 0.0,
            mouse_dx: 0.0,
            mouse_dy: 0.0,
            mouse_buttons: [false; 3],
        }
    }

    /// Reset per-frame deltas.
    pub fn update(&mut self) {
        self.mouse_dx = 0.0;
        self.mouse_dy = 0.0;
    }

    pub fn is_key_down(&self, key_code: u8) -> bool {
        self.keys_down[key_code as usize]
    }
}
