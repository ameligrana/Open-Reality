use crate::project::ProjectContext;
use crate::state::Backend;

pub async fn run(backend_str: String, ctx: ProjectContext) -> anyhow::Result<()> {
    let backend = parse_backend(&backend_str)?;

    if !backend.needs_build() {
        println!("{} requires no build step.", backend.label());
        return Ok(());
    }

    let (program, args, cwd) = match backend {
        Backend::Metal => (
            "swift",
            vec!["build", "-c", "release"],
            ctx.engine_path.join("metal_bridge"),
        ),
        Backend::WebGPU => (
            "cargo",
            vec!["build", "--release"],
            ctx.engine_path.join("openreality-wgpu"),
        ),
        Backend::WasmExport => (
            "wasm-pack",
            vec!["build", "--target", "web", "--release"],
            ctx.engine_path.join("openreality-web"),
        ),
        _ => unreachable!(),
    };

    println!(
        "Building {} in {}...",
        backend.label(),
        cwd.display()
    );

    let status = tokio::process::Command::new(program)
        .args(&args)
        .current_dir(&cwd)
        .stdin(std::process::Stdio::inherit())
        .stdout(std::process::Stdio::inherit())
        .stderr(std::process::Stdio::inherit())
        .status()
        .await?;

    std::process::exit(status.code().unwrap_or(1));
}

fn parse_backend(s: &str) -> anyhow::Result<Backend> {
    match s.to_lowercase().as_str() {
        "metal" => Ok(Backend::Metal),
        "webgpu" | "wgpu" => Ok(Backend::WebGPU),
        "wasm" | "wasm-export" => Ok(Backend::WasmExport),
        "opengl" | "gl" => Ok(Backend::OpenGL),
        "vulkan" | "vk" => Ok(Backend::Vulkan),
        _ => anyhow::bail!("Unknown backend: {s}. Options: opengl, metal, vulkan, webgpu, wasm"),
    }
}
