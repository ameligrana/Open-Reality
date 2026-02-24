use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

/// What kind of project we are operating in.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ProjectKind {
    /// Inside the OpenReality engine repo itself (has src/OpenReality.jl)
    EngineDev,
    /// A user game project with .openreality/config.toml
    UserProject,
}

/// Configuration read from .openreality/config.toml
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectConfig {
    pub engine_path: String,
    #[serde(default)]
    pub default_backend: Option<String>,
}

/// The resolved project context.
#[derive(Debug, Clone)]
#[allow(dead_code)]
pub struct ProjectContext {
    /// The root of the project (where Project.toml lives)
    pub project_root: PathBuf,
    /// What kind of project this is
    pub kind: ProjectKind,
    /// Path to the OpenReality engine source.
    /// For EngineDev: same as project_root.
    /// For UserProject: resolved from config.toml's engine_path.
    pub engine_path: PathBuf,
    /// Config from .openreality/config.toml (None for engine dev)
    pub config: Option<ProjectConfig>,
}

/// Detect project context from the current directory, walking up.
pub fn detect_project_context() -> anyhow::Result<ProjectContext> {
    detect_project_context_from(&std::env::current_dir()?)
}

/// Detect project context starting from a specific directory, walking up.
pub fn detect_project_context_from(start: &Path) -> anyhow::Result<ProjectContext> {
    let mut dir = start.to_path_buf();
    loop {
        // Check for engine dev: Project.toml + src/OpenReality.jl
        if dir.join("Project.toml").exists() && dir.join("src").join("OpenReality.jl").exists() {
            return Ok(ProjectContext {
                project_root: dir.clone(),
                kind: ProjectKind::EngineDev,
                engine_path: dir,
                config: None,
            });
        }
        // Check for user project: .openreality/config.toml
        let config_path = dir.join(".openreality").join("config.toml");
        if config_path.exists() {
            let content = std::fs::read_to_string(&config_path)?;
            let config: ProjectConfig = toml::from_str(&content)?;
            let engine_path = dir.join(&config.engine_path);
            return Ok(ProjectContext {
                project_root: dir,
                kind: ProjectKind::UserProject,
                engine_path,
                config: Some(config),
            });
        }
        if !dir.pop() {
            anyhow::bail!(
                "Could not find an OpenReality project.\n\
                 Run `orcli` from within the OpenReality repo or a project created with `orcli init`.\n\
                 To create a new project: orcli init <project-name>"
            );
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_detect_engine_dev() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(dir.path().join("Project.toml"), "[deps]").unwrap();
        let src_dir = dir.path().join("src");
        std::fs::create_dir(&src_dir).unwrap();
        std::fs::write(src_dir.join("OpenReality.jl"), "module OpenReality end").unwrap();

        let ctx = detect_project_context_from(dir.path()).unwrap();
        assert_eq!(ctx.kind, ProjectKind::EngineDev);
        assert_eq!(ctx.project_root, dir.path());
        assert!(ctx.config.is_none());
    }

    #[test]
    fn test_detect_user_project() {
        let dir = tempfile::tempdir().unwrap();
        let config_dir = dir.path().join(".openreality");
        std::fs::create_dir(&config_dir).unwrap();
        std::fs::write(
            config_dir.join("config.toml"),
            "engine_path = \"/opt/openreality\"\n",
        )
        .unwrap();

        let ctx = detect_project_context_from(dir.path()).unwrap();
        assert_eq!(ctx.kind, ProjectKind::UserProject);
        assert!(ctx.config.is_some());
        assert_eq!(ctx.config.unwrap().engine_path, "/opt/openreality");
    }

    #[test]
    fn test_detect_no_project() {
        let dir = tempfile::tempdir().unwrap();
        // Create a nested dir so pop() hits the tempdir root, not filesystem root
        let nested = dir.path().join("a/b/c");
        std::fs::create_dir_all(&nested).unwrap();
        let result = detect_project_context_from(&nested);
        assert!(result.is_err());
    }
}
