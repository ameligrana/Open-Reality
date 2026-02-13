use wasm_bindgen::prelude::*;
use web_sys::HtmlCanvasElement;

use crate::scene::LoadedScene;
use crate::input::InputState;
use crate::animation;
use crate::transform;
use crate::skinning;

/// Main application state for the WASM runtime.
#[wasm_bindgen]
pub struct App {
    scene: LoadedScene,
    input: InputState,
    last_time: f64,
    canvas: HtmlCanvasElement,
    // Renderer will be added in Phase 6
}

#[wasm_bindgen]
impl App {
    /// Create a new App from canvas ID and ORSB scene data.
    pub async fn new(canvas_id: &str, scene_data: &[u8]) -> Result<App, JsValue> {
        let window = web_sys::window().ok_or("No window")?;
        let document = window.document().ok_or("No document")?;
        let canvas = document
            .get_element_by_id(canvas_id)
            .ok_or("Canvas not found")?
            .dyn_into::<HtmlCanvasElement>()
            .map_err(|_| "Element is not a canvas")?;

        // Parse ORSB scene
        let scene = LoadedScene::from_orsb(scene_data)
            .map_err(|e| JsValue::from_str(&format!("Failed to load scene: {e}")))?;

        log::info!(
            "Loaded scene: {} entities, {} meshes, {} textures",
            scene.num_entities(),
            scene.num_meshes(),
            scene.num_textures(),
        );

        Ok(App {
            scene,
            input: InputState::new(),
            last_time: 0.0,
            canvas,
        })
    }

    /// Run one frame of the game loop. Called from requestAnimationFrame.
    pub fn frame(&mut self, time: f64) {
        let dt = if self.last_time > 0.0 {
            (time - self.last_time) / 1000.0
        } else {
            0.016 // ~60fps first frame
        };
        self.last_time = time;

        // Update systems
        self.input.update();
        animation::update_animations(&mut self.scene, dt as f32);
        transform::compute_world_transforms(&mut self.scene);
        skinning::update_skinned_meshes(&mut self.scene);

        // Rendering will be done here in Phase 6
        // For now, just tick the systems
    }

    /// Get the canvas width.
    pub fn width(&self) -> u32 {
        self.canvas.width()
    }

    /// Get the canvas height.
    pub fn height(&self) -> u32 {
        self.canvas.height()
    }
}
