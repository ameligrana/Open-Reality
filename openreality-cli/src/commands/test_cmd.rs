use crate::project::ProjectContext;

pub async fn run(ctx: ProjectContext) -> anyhow::Result<()> {
    let project_dir = ctx.engine_path;

    println!("Running test suite in {}...", project_dir.display());

    let status = tokio::process::Command::new("julia")
        .args(["--project=.", "-e", "using Pkg; Pkg.test()"])
        .current_dir(&project_dir)
        .stdin(std::process::Stdio::inherit())
        .stdout(std::process::Stdio::inherit())
        .stderr(std::process::Stdio::inherit())
        .status()
        .await?;

    std::process::exit(status.code().unwrap_or(1));
}
