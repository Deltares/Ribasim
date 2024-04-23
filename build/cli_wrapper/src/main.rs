use std::{env, path::PathBuf};

use clap::{CommandFactory, Parser};
use std::process::ExitCode;

#[derive(Parser)]
#[command(version)]
struct Cli {
    /// Path to the TOML file
    toml_path: PathBuf,
}

fn main() -> ExitCode {
    // Get the path to the directory containing the current executable
    let exe_dir = env::current_exe().unwrap().parent().unwrap().to_owned();

    // Set the appropriate environment variable for the current platform
    if std::env::consts::OS == "windows" {
        env::set_var(
            "PATH",
            format!(
                "{};{}",
                exe_dir.join("bin").display(),
                env::var("PATH").unwrap_or_default()
            ),
        );
    }

    // TODO: Do I need to set LD_LIBRARY_PATH on linux?

    // Parse command line arguments
    let cli = Cli::parse();

    if !cli.toml_path.is_file() {
        eprintln!("File not found {:?}", cli.toml_path);
        return ExitCode::FAILURE;
    }

    // Call ribasim shared library and check for errors
    todo!()
}
