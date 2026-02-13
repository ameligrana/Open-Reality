/// Embedded WGSL shader source strings for the WebGPU rendering pipeline.
/// These are shared between the native FFI backend and the WASM web runtime.

pub const FULLSCREEN_QUAD_VERT: &str = include_str!("../shaders/fullscreen_quad.wgsl");
pub const GBUFFER_VERT: &str = include_str!("../shaders/gbuffer_vert.wgsl");
pub const GBUFFER_FRAG: &str = include_str!("../shaders/gbuffer_frag.wgsl");
pub const DEFERRED_LIGHTING_FRAG: &str = include_str!("../shaders/deferred_lighting.wgsl");
pub const SHADOW_DEPTH_VERT: &str = include_str!("../shaders/shadow_depth.wgsl");
pub const SSAO_FRAG: &str = include_str!("../shaders/ssao.wgsl");
pub const SSAO_BLUR_FRAG: &str = include_str!("../shaders/ssao_blur.wgsl");
pub const SSR_FRAG: &str = include_str!("../shaders/ssr.wgsl");
pub const TAA_FRAG: &str = include_str!("../shaders/taa.wgsl");
pub const BLOOM_EXTRACT_FRAG: &str = include_str!("../shaders/bloom_extract.wgsl");
pub const BLOOM_BLUR_FRAG: &str = include_str!("../shaders/bloom_blur.wgsl");
pub const BLOOM_COMPOSITE_FRAG: &str = include_str!("../shaders/bloom_composite.wgsl");
pub const FXAA_FRAG: &str = include_str!("../shaders/fxaa.wgsl");
pub const PRESENT_FRAG: &str = include_str!("../shaders/present.wgsl");
