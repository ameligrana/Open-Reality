use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(
    name = "orcli",
    about = "Open Reality game engine CLI",
    version,
    arg_required_else_help = false
)]
pub struct Cli {
    #[command(subcommand)]
    pub command: Option<Command>,
}

#[derive(Subcommand)]
pub enum Command {
    /// Initialize a new OpenReality project
    Init {
        /// Project name (directory to create)
        name: String,
        /// Clone for engine development instead of creating a user project
        #[arg(long)]
        engine_dev: bool,
        /// Git URL for the engine repo
        #[arg(
            long,
            default_value = "https://github.com/sinisterMage/Open-Reality.git"
        )]
        repo_url: String,
    },
    /// Generate new project files
    New {
        #[command(subcommand)]
        kind: NewKind,
    },
    /// Run a Julia scene/script
    Run {
        /// Path to the .jl file to run
        file: String,
    },
    /// Build a backend (metal, webgpu, wasm)
    Build {
        /// Backend to build
        backend: String,
    },
    /// Run the Julia test suite
    Test,
}

#[derive(Subcommand)]
pub enum NewKind {
    /// Generate a new scene file
    Scene {
        /// Name of the scene (used for filename)
        name: String,
    },
}
