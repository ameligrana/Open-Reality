use crate::project::ProjectContext;

pub async fn run(file: String, ctx: ProjectContext) -> anyhow::Result<()> {
    let status = tokio::process::Command::new("julia")
        .args(["--project=.", &file])
        .current_dir(&ctx.project_root)
        .stdin(std::process::Stdio::inherit())
        .stdout(std::process::Stdio::inherit())
        .stderr(std::process::Stdio::inherit())
        .status()
        .await?;

    std::process::exit(status.code().unwrap_or(1));
}
