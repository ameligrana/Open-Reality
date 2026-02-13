//! OpenReality WebGPU Backend — C FFI entry points.
//!
//! This crate is compiled as a cdylib and loaded by Julia via ccall.
//! All public functions use `extern "C"` ABI with `#[no_mangle]`.

mod backend;
mod handle;

use backend::WGPUBackendState;
use handle::HandleStore;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::sync::Mutex;

// Global store of backend instances (usually just one).
static BACKENDS: std::sync::LazyLock<Mutex<HandleStore<WGPUBackendState>>> =
    std::sync::LazyLock::new(|| Mutex::new(HandleStore::new()));

// ============================================================
// Window handle wrapper for raw-window-handle integration
// ============================================================

/// Wrapper that implements HasWindowHandle + HasDisplayHandle for X11.
#[cfg(target_os = "linux")]
struct X11WindowHandle {
    window: u64,
    display: *mut std::ffi::c_void,
}

#[cfg(target_os = "linux")]
unsafe impl Send for X11WindowHandle {}
#[cfg(target_os = "linux")]
unsafe impl Sync for X11WindowHandle {}

#[cfg(target_os = "linux")]
impl raw_window_handle::HasWindowHandle for X11WindowHandle {
    fn window_handle(&self) -> Result<raw_window_handle::WindowHandle<'_>, raw_window_handle::HandleError> {
        let raw = raw_window_handle::RawWindowHandle::Xlib(raw_window_handle::XlibWindowHandle::new(self.window as _));
        Ok(unsafe { raw_window_handle::WindowHandle::borrow_raw(raw) })
    }
}

#[cfg(target_os = "linux")]
impl raw_window_handle::HasDisplayHandle for X11WindowHandle {
    fn display_handle(&self) -> Result<raw_window_handle::DisplayHandle<'_>, raw_window_handle::HandleError> {
        let raw = raw_window_handle::RawDisplayHandle::Xlib(
            raw_window_handle::XlibDisplayHandle::new(
                std::ptr::NonNull::new(self.display),
                0,
            ),
        );
        Ok(unsafe { raw_window_handle::DisplayHandle::borrow_raw(raw) })
    }
}

/// Wrapper for Windows (Win32).
#[cfg(target_os = "windows")]
struct Win32WindowHandle {
    hwnd: *mut std::ffi::c_void,
}

#[cfg(target_os = "windows")]
unsafe impl Send for Win32WindowHandle {}
#[cfg(target_os = "windows")]
unsafe impl Sync for Win32WindowHandle {}

#[cfg(target_os = "windows")]
impl raw_window_handle::HasWindowHandle for Win32WindowHandle {
    fn window_handle(&self) -> Result<raw_window_handle::WindowHandle<'_>, raw_window_handle::HandleError> {
        let raw = raw_window_handle::RawWindowHandle::Win32(
            raw_window_handle::Win32WindowHandle::new(
                std::num::NonZeroIsize::new(self.hwnd as isize).unwrap(),
            ),
        );
        Ok(unsafe { raw_window_handle::WindowHandle::borrow_raw(raw) })
    }
}

#[cfg(target_os = "windows")]
impl raw_window_handle::HasDisplayHandle for Win32WindowHandle {
    fn display_handle(&self) -> Result<raw_window_handle::DisplayHandle<'_>, raw_window_handle::HandleError> {
        let raw = raw_window_handle::RawDisplayHandle::Windows(raw_window_handle::WindowsDisplayHandle::new());
        Ok(unsafe { raw_window_handle::DisplayHandle::borrow_raw(raw) })
    }
}

// ============================================================
// FFI: Lifecycle
// ============================================================

/// Initialize the WebGPU backend with a raw window handle.
///
/// On Linux: `window_handle` is the X11 Window (u64), `display_handle` is the X11 Display*.
/// On Windows: `window_handle` is the HWND, `display_handle` is unused.
///
/// Returns a backend handle (> 0) on success, 0 on failure.
#[no_mangle]
pub extern "C" fn or_wgpu_initialize(
    window_handle: u64,
    display_handle: *mut std::ffi::c_void,
    width: i32,
    height: i32,
) -> u64 {
    let _ = env_logger::try_init();

    let w = width as u32;
    let h = height as u32;

    #[cfg(target_os = "linux")]
    let result = {
        let handle = X11WindowHandle {
            window: window_handle,
            display: display_handle,
        };
        WGPUBackendState::new(handle, w, h)
    };

    #[cfg(target_os = "windows")]
    let result = {
        let handle = Win32WindowHandle {
            hwnd: window_handle as *mut std::ffi::c_void,
        };
        WGPUBackendState::new(handle, w, h)
    };

    #[cfg(not(any(target_os = "linux", target_os = "windows")))]
    let result: Result<WGPUBackendState, String> = Err("Unsupported platform".into());

    match result {
        Ok(state) => {
            let mut backends = BACKENDS.lock().unwrap();
            backends.insert(state)
        }
        Err(e) => {
            log::error!("WebGPU initialization failed: {e}");
            0
        }
    }
}

/// Shutdown the backend and release all GPU resources.
#[no_mangle]
pub extern "C" fn or_wgpu_shutdown(backend: u64) {
    let mut backends = BACKENDS.lock().unwrap();
    if let Some(state) = backends.remove(backend) {
        // Drop state — all wgpu resources are released
        drop(state);
        log::info!("WebGPU backend shut down");
    }
}

/// Resize the rendering surface.
#[no_mangle]
pub extern "C" fn or_wgpu_resize(backend: u64, width: i32, height: i32) {
    let mut backends = BACKENDS.lock().unwrap();
    if let Some(state) = backends.get_mut(backend) {
        state.resize(width as u32, height as u32);
    }
}

// ============================================================
// FFI: Simple rendering
// ============================================================

/// Render a frame that clears to the given color (bootstrap test).
#[no_mangle]
pub extern "C" fn or_wgpu_render_clear(backend: u64, r: f64, g: f64, b: f64) -> i32 {
    let mut backends = BACKENDS.lock().unwrap();
    if let Some(state) = backends.get_mut(backend) {
        match state.render_clear(r, g, b) {
            Ok(()) => 0,
            Err(e) => {
                state.last_error = Some(e);
                -1
            }
        }
    } else {
        -1
    }
}

// ============================================================
// FFI: Mesh operations
// ============================================================

/// Upload mesh data to GPU. Returns mesh handle (> 0) or 0 on failure.
#[no_mangle]
pub extern "C" fn or_wgpu_upload_mesh(
    backend: u64,
    positions: *const f32,
    num_vertices: u32,
    normals: *const f32,
    uvs: *const f32,
    indices: *const u32,
    num_indices: u32,
) -> u64 {
    let mut backends = BACKENDS.lock().unwrap();
    if let Some(state) = backends.get_mut(backend) {
        let pos_slice = unsafe { std::slice::from_raw_parts(positions, (num_vertices * 3) as usize) };
        let norm_slice = unsafe { std::slice::from_raw_parts(normals, (num_vertices * 3) as usize) };
        let uv_slice = unsafe { std::slice::from_raw_parts(uvs, (num_vertices * 2) as usize) };
        let idx_slice = unsafe { std::slice::from_raw_parts(indices, num_indices as usize) };
        state.upload_mesh(pos_slice, norm_slice, uv_slice, idx_slice)
    } else {
        0
    }
}

/// Destroy a mesh and free its GPU resources.
#[no_mangle]
pub extern "C" fn or_wgpu_destroy_mesh(backend: u64, mesh: u64) {
    let mut backends = BACKENDS.lock().unwrap();
    if let Some(state) = backends.get_mut(backend) {
        state.destroy_mesh(mesh);
    }
}

// ============================================================
// FFI: Texture operations
// ============================================================

/// Upload texture data to GPU. Returns texture handle (> 0) or 0 on failure.
#[no_mangle]
pub extern "C" fn or_wgpu_upload_texture(
    backend: u64,
    pixels: *const u8,
    width: i32,
    height: i32,
    channels: i32,
) -> u64 {
    let mut backends = BACKENDS.lock().unwrap();
    if let Some(state) = backends.get_mut(backend) {
        let data_len = (width * height * channels) as usize;
        let pixel_slice = unsafe { std::slice::from_raw_parts(pixels, data_len) };
        state.upload_texture(pixel_slice, width as u32, height as u32, channels as u32)
    } else {
        0
    }
}

/// Destroy a texture and free its GPU resources.
#[no_mangle]
pub extern "C" fn or_wgpu_destroy_texture(backend: u64, texture: u64) {
    let mut backends = BACKENDS.lock().unwrap();
    if let Some(state) = backends.get_mut(backend) {
        state.destroy_texture(texture);
    }
}

// ============================================================
// FFI: Error handling
// ============================================================

/// Get the last error message. Returns a C string (valid until next FFI call) or null.
#[no_mangle]
pub extern "C" fn or_wgpu_last_error(backend: u64) -> *const c_char {
    let backends = BACKENDS.lock().unwrap();
    if let Some(state) = backends.get(backend) {
        if let Some(ref err) = state.last_error {
            // Leak the CString so the pointer remains valid until next call
            let c_str = CString::new(err.as_str()).unwrap();
            c_str.into_raw() as *const c_char
        } else {
            std::ptr::null()
        }
    } else {
        std::ptr::null()
    }
}

// ============================================================
// FFI: Advanced resource creation (stubs for now)
// ============================================================

/// Create cascaded shadow maps. Returns CSM handle or 0.
#[no_mangle]
pub extern "C" fn or_wgpu_create_csm(
    backend: u64,
    num_cascades: i32,
    resolution: i32,
    _near: f32,
    _far: f32,
) -> u64 {
    let mut backends = BACKENDS.lock().unwrap();
    if let Some(state) = backends.get_mut(backend) {
        let res = resolution as u32;
        let n = num_cascades as u32;

        let sampler = state.device.create_sampler(&wgpu::SamplerDescriptor {
            label: Some("Shadow Sampler"),
            compare: Some(wgpu::CompareFunction::LessEqual),
            mag_filter: wgpu::FilterMode::Linear,
            min_filter: wgpu::FilterMode::Linear,
            ..Default::default()
        });

        let mut depth_textures = Vec::new();
        let mut depth_views = Vec::new();

        for i in 0..n {
            let texture = state.device.create_texture(&wgpu::TextureDescriptor {
                label: Some(&format!("Shadow Cascade {i}")),
                size: wgpu::Extent3d {
                    width: res,
                    height: res,
                    depth_or_array_layers: 1,
                },
                mip_level_count: 1,
                sample_count: 1,
                dimension: wgpu::TextureDimension::D2,
                format: wgpu::TextureFormat::Depth32Float,
                usage: wgpu::TextureUsages::RENDER_ATTACHMENT
                    | wgpu::TextureUsages::TEXTURE_BINDING,
                view_formats: &[],
            });
            let view = texture.create_view(&wgpu::TextureViewDescriptor::default());
            depth_textures.push(texture);
            depth_views.push(view);
        }

        state.csm = Some(backend::CascadedShadowMap {
            depth_textures,
            depth_views,
            sampler,
            num_cascades: n,
            resolution: res,
        });

        1 // Success (non-zero)
    } else {
        0
    }
}

/// Create post-processing pipeline. Returns handle or 0.
/// This is a stub — full implementation comes in Phase 4.
#[no_mangle]
pub extern "C" fn or_wgpu_create_post_process(
    _backend: u64,
    _width: i32,
    _height: i32,
    _bloom_threshold: f32,
    _bloom_intensity: f32,
    _gamma: f32,
    _tone_mapping_mode: i32,
    _fxaa_enabled: i32,
) -> u64 {
    // TODO: Implement in Phase 4
    1
}
