use crate::handle::HandleStore;
use std::sync::Arc;

/// GPU mesh with vertex and index buffers.
pub struct GPUMesh {
    pub vertex_buffer: wgpu::Buffer,
    pub normal_buffer: wgpu::Buffer,
    pub uv_buffer: wgpu::Buffer,
    pub index_buffer: wgpu::Buffer,
    pub index_count: u32,
}

/// GPU texture with associated view and sampler.
pub struct GPUTexture {
    pub texture: wgpu::Texture,
    pub view: wgpu::TextureView,
    pub sampler: wgpu::Sampler,
    pub width: u32,
    pub height: u32,
    pub channels: u32,
}

/// Render target (framebuffer equivalent).
pub struct RenderTarget {
    pub color_texture: wgpu::Texture,
    pub color_view: wgpu::TextureView,
    pub depth_texture: Option<wgpu::Texture>,
    pub depth_view: Option<wgpu::TextureView>,
    pub width: u32,
    pub height: u32,
}

/// G-Buffer with multiple render targets for deferred shading.
pub struct GBuffer {
    /// RGB = albedo, A = metallic
    pub albedo_metallic: wgpu::Texture,
    pub albedo_metallic_view: wgpu::TextureView,
    /// RGB = encoded normal, A = roughness
    pub normal_roughness: wgpu::Texture,
    pub normal_roughness_view: wgpu::TextureView,
    /// RGB = emissive, A = AO
    pub emissive_ao: wgpu::Texture,
    pub emissive_ao_view: wgpu::TextureView,
    /// R = clearcoat, G = subsurface, BA = reserved
    pub advanced: wgpu::Texture,
    pub advanced_view: wgpu::TextureView,
    /// Depth buffer
    pub depth: wgpu::Texture,
    pub depth_view: wgpu::TextureView,
    pub width: u32,
    pub height: u32,
}

/// Cascaded shadow map.
pub struct CascadedShadowMap {
    pub depth_textures: Vec<wgpu::Texture>,
    pub depth_views: Vec<wgpu::TextureView>,
    pub sampler: wgpu::Sampler,
    pub num_cascades: u32,
    pub resolution: u32,
}

/// Post-processing pipeline state.
pub struct PostProcessPipeline {
    pub bloom_extract_pipeline: wgpu::RenderPipeline,
    pub bloom_blur_pipeline: wgpu::RenderPipeline,
    pub bloom_composite_pipeline: wgpu::RenderPipeline,
    pub fxaa_pipeline: Option<wgpu::RenderPipeline>,
    pub bloom_targets: Vec<RenderTarget>,
    pub params_buffer: wgpu::Buffer,
    pub params_bind_group_layout: wgpu::BindGroupLayout,
}

/// SSAO pass state.
pub struct SSAOPass {
    pub pipeline: wgpu::RenderPipeline,
    pub blur_pipeline: wgpu::RenderPipeline,
    pub target: RenderTarget,
    pub blur_target: RenderTarget,
    pub noise_texture: GPUTexture,
    pub params_buffer: wgpu::Buffer,
    pub bind_group_layout: wgpu::BindGroupLayout,
}

/// SSR pass state.
pub struct SSRPass {
    pub pipeline: wgpu::RenderPipeline,
    pub target: RenderTarget,
    pub params_buffer: wgpu::Buffer,
    pub bind_group_layout: wgpu::BindGroupLayout,
}

/// TAA pass state.
pub struct TAAPass {
    pub pipeline: wgpu::RenderPipeline,
    pub history_texture: wgpu::Texture,
    pub history_view: wgpu::TextureView,
    pub target: RenderTarget,
    pub params_buffer: wgpu::Buffer,
    pub bind_group_layout: wgpu::BindGroupLayout,
    pub first_frame: bool,
}

/// Main backend state — owns all wgpu resources.
pub struct WGPUBackendState {
    pub instance: wgpu::Instance,
    pub adapter: wgpu::Adapter,
    pub device: wgpu::Device,
    pub queue: wgpu::Queue,
    pub surface: wgpu::Surface<'static>,
    pub surface_config: wgpu::SurfaceConfiguration,
    pub width: u32,
    pub height: u32,

    // Resource stores (Julia holds opaque u64 handles into these)
    pub meshes: HandleStore<GPUMesh>,
    pub textures: HandleStore<GPUTexture>,
    pub framebuffers: HandleStore<RenderTarget>,

    // Deferred pipeline resources
    pub gbuffer: Option<GBuffer>,
    pub lighting_target: Option<RenderTarget>,
    pub csm: Option<CascadedShadowMap>,

    // Screen-space effects
    pub ssao: Option<SSAOPass>,
    pub ssr: Option<SSRPass>,
    pub taa: Option<TAAPass>,
    pub post_process: Option<PostProcessPipeline>,

    // Shared GPU resources
    pub per_frame_buffer: wgpu::Buffer,
    pub per_frame_bind_group_layout: wgpu::BindGroupLayout,
    pub per_object_buffer: wgpu::Buffer,
    pub material_bind_group_layout: wgpu::BindGroupLayout,
    pub light_buffer: wgpu::Buffer,
    pub default_sampler: wgpu::Sampler,

    // Error state
    pub last_error: Option<String>,
}

impl WGPUBackendState {
    /// Create a new backend state from a raw window handle.
    pub fn new(
        window: impl raw_window_handle::HasWindowHandle + raw_window_handle::HasDisplayHandle + Send + Sync + 'static,
        width: u32,
        height: u32,
    ) -> Result<Self, String> {
        use openreality_gpu_shared::uniforms::*;

        let instance = wgpu::Instance::new(wgpu::InstanceDescriptor {
            backends: wgpu::Backends::all(),
            ..Default::default()
        });

        let surface = instance
            .create_surface(window)
            .map_err(|e| format!("Failed to create surface: {e}"))?;

        let adapter = pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
            power_preference: wgpu::PowerPreference::HighPerformance,
            compatible_surface: Some(&surface),
            force_fallback_adapter: false,
        }))
        .ok_or("Failed to find suitable GPU adapter")?;

        let (device, queue) = pollster::block_on(adapter.request_device(
            &wgpu::DeviceDescriptor {
                label: Some("OpenReality WebGPU Device"),
                required_features: wgpu::Features::empty(),
                required_limits: wgpu::Limits::default(),
                memory_hints: wgpu::MemoryHints::default(),
            },
            None,
        ))
        .map_err(|e| format!("Failed to create device: {e}"))?;

        let surface_caps = surface.get_capabilities(&adapter);
        let surface_format = surface_caps
            .formats
            .iter()
            .find(|f| f.is_srgb())
            .copied()
            .unwrap_or(surface_caps.formats[0]);

        let surface_config = wgpu::SurfaceConfiguration {
            usage: wgpu::TextureUsages::RENDER_ATTACHMENT,
            format: surface_format,
            width,
            height,
            present_mode: wgpu::PresentMode::Fifo,
            alpha_mode: surface_caps.alpha_modes[0],
            view_formats: vec![],
            desired_maximum_frame_latency: 2,
        };
        surface.configure(&device, &surface_config);

        // Create per-frame uniform buffer
        let per_frame_buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("Per-Frame Uniforms"),
            size: std::mem::size_of::<PerFrameUniforms>() as u64,
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        let per_frame_bind_group_layout =
            device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
                label: Some("Per-Frame Bind Group Layout"),
                entries: &[wgpu::BindGroupLayoutEntry {
                    binding: 0,
                    visibility: wgpu::ShaderStages::VERTEX | wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Uniform,
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                }],
            });

        // Per-object uniform buffer
        let per_object_buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("Per-Object Uniforms"),
            size: std::mem::size_of::<PerObjectUniforms>() as u64,
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        // Material bind group layout
        let material_bind_group_layout =
            device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
                label: Some("Material Bind Group Layout"),
                entries: &[
                    // binding 0: MaterialUBO
                    wgpu::BindGroupLayoutEntry {
                        binding: 0,
                        visibility: wgpu::ShaderStages::FRAGMENT,
                        ty: wgpu::BindingType::Buffer {
                            ty: wgpu::BufferBindingType::Uniform,
                            has_dynamic_offset: false,
                            min_binding_size: None,
                        },
                        count: None,
                    },
                    // bindings 1-6: texture maps
                    wgpu::BindGroupLayoutEntry {
                        binding: 1,
                        visibility: wgpu::ShaderStages::FRAGMENT,
                        ty: wgpu::BindingType::Texture {
                            sample_type: wgpu::TextureSampleType::Float { filterable: true },
                            view_dimension: wgpu::TextureViewDimension::D2,
                            multisampled: false,
                        },
                        count: None,
                    },
                    wgpu::BindGroupLayoutEntry {
                        binding: 2,
                        visibility: wgpu::ShaderStages::FRAGMENT,
                        ty: wgpu::BindingType::Texture {
                            sample_type: wgpu::TextureSampleType::Float { filterable: true },
                            view_dimension: wgpu::TextureViewDimension::D2,
                            multisampled: false,
                        },
                        count: None,
                    },
                    wgpu::BindGroupLayoutEntry {
                        binding: 3,
                        visibility: wgpu::ShaderStages::FRAGMENT,
                        ty: wgpu::BindingType::Texture {
                            sample_type: wgpu::TextureSampleType::Float { filterable: true },
                            view_dimension: wgpu::TextureViewDimension::D2,
                            multisampled: false,
                        },
                        count: None,
                    },
                    wgpu::BindGroupLayoutEntry {
                        binding: 4,
                        visibility: wgpu::ShaderStages::FRAGMENT,
                        ty: wgpu::BindingType::Texture {
                            sample_type: wgpu::TextureSampleType::Float { filterable: true },
                            view_dimension: wgpu::TextureViewDimension::D2,
                            multisampled: false,
                        },
                        count: None,
                    },
                    wgpu::BindGroupLayoutEntry {
                        binding: 5,
                        visibility: wgpu::ShaderStages::FRAGMENT,
                        ty: wgpu::BindingType::Texture {
                            sample_type: wgpu::TextureSampleType::Float { filterable: true },
                            view_dimension: wgpu::TextureViewDimension::D2,
                            multisampled: false,
                        },
                        count: None,
                    },
                    wgpu::BindGroupLayoutEntry {
                        binding: 6,
                        visibility: wgpu::ShaderStages::FRAGMENT,
                        ty: wgpu::BindingType::Texture {
                            sample_type: wgpu::TextureSampleType::Float { filterable: true },
                            view_dimension: wgpu::TextureViewDimension::D2,
                            multisampled: false,
                        },
                        count: None,
                    },
                    // binding 7: sampler
                    wgpu::BindGroupLayoutEntry {
                        binding: 7,
                        visibility: wgpu::ShaderStages::FRAGMENT,
                        ty: wgpu::BindingType::Sampler(wgpu::SamplerBindingType::Filtering),
                        count: None,
                    },
                ],
            });

        // Light uniform buffer
        let light_buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("Light Uniforms"),
            size: std::mem::size_of::<LightUniforms>() as u64,
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        // Default sampler
        let default_sampler = device.create_sampler(&wgpu::SamplerDescriptor {
            label: Some("Default Sampler"),
            address_mode_u: wgpu::AddressMode::Repeat,
            address_mode_v: wgpu::AddressMode::Repeat,
            address_mode_w: wgpu::AddressMode::Repeat,
            mag_filter: wgpu::FilterMode::Linear,
            min_filter: wgpu::FilterMode::Linear,
            mipmap_filter: wgpu::FilterMode::Linear,
            ..Default::default()
        });

        log::info!(
            "WebGPU backend initialized: {} ({})",
            adapter.get_info().name,
            adapter.get_info().backend.to_str()
        );

        Ok(Self {
            instance,
            adapter,
            device,
            queue,
            surface,
            surface_config,
            width,
            height,
            meshes: HandleStore::new(),
            textures: HandleStore::new(),
            framebuffers: HandleStore::new(),
            gbuffer: None,
            lighting_target: None,
            csm: None,
            ssao: None,
            ssr: None,
            taa: None,
            post_process: None,
            per_frame_buffer,
            per_frame_bind_group_layout,
            per_object_buffer,
            material_bind_group_layout,
            light_buffer,
            default_sampler,
            last_error: None,
        })
    }

    /// Resize the surface and recreate dependent resources.
    pub fn resize(&mut self, width: u32, height: u32) {
        if width > 0 && height > 0 {
            self.width = width;
            self.height = height;
            self.surface_config.width = width;
            self.surface_config.height = height;
            self.surface.configure(&self.device, &self.surface_config);
        }
    }

    /// Render a frame that just clears to a color (bootstrap pass).
    pub fn render_clear(&mut self, r: f64, g: f64, b: f64) -> Result<(), String> {
        let output = self
            .surface
            .get_current_texture()
            .map_err(|e| format!("Surface texture error: {e}"))?;

        let view = output
            .texture
            .create_view(&wgpu::TextureViewDescriptor::default());

        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("Clear Encoder"),
            });

        {
            let _render_pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("Clear Pass"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: &view,
                    resolve_target: None,
                    ops: wgpu::Operations {
                        load: wgpu::LoadOp::Clear(wgpu::Color {
                            r,
                            g,
                            b,
                            a: 1.0,
                        }),
                        store: wgpu::StoreOp::Store,
                    },
                })],
                depth_stencil_attachment: None,
                ..Default::default()
            });
        }

        self.queue.submit(std::iter::once(encoder.finish()));
        output.present();

        Ok(())
    }

    /// Upload mesh data to GPU buffers.
    pub fn upload_mesh(
        &mut self,
        positions: &[f32],
        normals: &[f32],
        uvs: &[f32],
        indices: &[u32],
    ) -> u64 {
        use wgpu::util::DeviceExt;

        let vertex_buffer = self
            .device
            .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                label: Some("Vertex Position Buffer"),
                contents: bytemuck::cast_slice(positions),
                usage: wgpu::BufferUsages::VERTEX,
            });

        let normal_buffer = self
            .device
            .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                label: Some("Vertex Normal Buffer"),
                contents: bytemuck::cast_slice(normals),
                usage: wgpu::BufferUsages::VERTEX,
            });

        let uv_buffer = self
            .device
            .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                label: Some("Vertex UV Buffer"),
                contents: bytemuck::cast_slice(uvs),
                usage: wgpu::BufferUsages::VERTEX,
            });

        let index_buffer = self
            .device
            .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                label: Some("Index Buffer"),
                contents: bytemuck::cast_slice(indices),
                usage: wgpu::BufferUsages::INDEX,
            });

        let mesh = GPUMesh {
            vertex_buffer,
            normal_buffer,
            uv_buffer,
            index_buffer,
            index_count: indices.len() as u32,
        };

        self.meshes.insert(mesh)
    }

    /// Upload texture data to GPU.
    pub fn upload_texture(
        &mut self,
        pixels: &[u8],
        width: u32,
        height: u32,
        channels: u32,
    ) -> u64 {
        use wgpu::util::DeviceExt;

        // Convert to RGBA if needed
        let rgba_data: Vec<u8>;
        let data = if channels == 4 {
            pixels
        } else if channels == 3 {
            rgba_data = pixels
                .chunks(3)
                .flat_map(|rgb| [rgb[0], rgb[1], rgb[2], 255])
                .collect();
            &rgba_data
        } else if channels == 1 {
            rgba_data = pixels
                .iter()
                .flat_map(|&g| [g, g, g, 255])
                .collect();
            &rgba_data
        } else {
            self.last_error = Some(format!("Unsupported channel count: {channels}"));
            return 0;
        };

        let texture_size = wgpu::Extent3d {
            width,
            height,
            depth_or_array_layers: 1,
        };

        let texture = self.device.create_texture(&wgpu::TextureDescriptor {
            label: Some("Uploaded Texture"),
            size: texture_size,
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format: wgpu::TextureFormat::Rgba8UnormSrgb,
            usage: wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST,
            view_formats: &[],
        });

        self.queue.write_texture(
            wgpu::ImageCopyTexture {
                texture: &texture,
                mip_level: 0,
                origin: wgpu::Origin3d::ZERO,
                aspect: wgpu::TextureAspect::All,
            },
            data,
            wgpu::ImageDataLayout {
                offset: 0,
                bytes_per_row: Some(4 * width),
                rows_per_image: Some(height),
            },
            texture_size,
        );

        let view = texture.create_view(&wgpu::TextureViewDescriptor::default());

        let sampler = self.device.create_sampler(&wgpu::SamplerDescriptor {
            label: Some("Texture Sampler"),
            address_mode_u: wgpu::AddressMode::Repeat,
            address_mode_v: wgpu::AddressMode::Repeat,
            mag_filter: wgpu::FilterMode::Linear,
            min_filter: wgpu::FilterMode::Linear,
            mipmap_filter: wgpu::FilterMode::Linear,
            ..Default::default()
        });

        let gpu_texture = GPUTexture {
            texture,
            view,
            sampler,
            width,
            height,
            channels,
        };

        self.textures.insert(gpu_texture)
    }

    /// Destroy a mesh by handle.
    pub fn destroy_mesh(&mut self, handle: u64) {
        self.meshes.remove(handle);
    }

    /// Destroy a texture by handle.
    pub fn destroy_texture(&mut self, handle: u64) {
        self.textures.remove(handle);
    }
}
