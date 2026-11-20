use std::{
    env::{self, consts::OS},
    ffi::{CString, c_char},
    path::PathBuf,
    process::ExitCode,
};

use clap::Parser;
use libloading::{Library, Symbol};

#[derive(Parser)]
#[command(version)]
struct Cli {
    /// Path to the TOML file
    toml_path: PathBuf,

    /// Number of threads to use
    #[arg(short, long, value_name = "#THREADS", default_value = "1")]
    threads: i32,
}

fn main() -> ExitCode {
    let cli = Cli::parse();
    match run(&cli) {
        Ok(exit_code) => exit_code,
        Err(message) => {
            eprintln!("{message}");
            ExitCode::FAILURE
        }
    }
}

fn run(cli: &Cli) -> Result<ExitCode, String> {
    if !cli.toml_path.is_file() {
        return Err(format!("File not found {:?}", cli.toml_path));
    }
    let toml_path = cli
        .toml_path
        .to_str()
        .ok_or_else(|| format!("Path is not valid UTF-8 {:?}", cli.toml_path))?;
    let toml_path = CString::new(toml_path)
        .map_err(|_| format!("Path contains a null byte {:?}", cli.toml_path))?;

    let exe_path =
        env::current_exe().map_err(|error| format!("Failed to locate ribasim: {error}"))?;
    let exe_dir = exe_path
        .parent()
        .ok_or_else(|| format!("Failed to locate the directory of {exe_path:?}"))?;
    let shared_lib_path = match OS {
        "windows" => exe_dir.join("libribasim.dll"),
        "linux" => exe_dir.join("../lib/libribasim.so"),
        "macos" => exe_dir.join("../lib/libribasim.dylib"),
        _ => return Err(format!("Your OS ({OS}) is not supported yet.")),
    };

    unsafe {
        let lib = Library::new(&shared_lib_path).map_err(|error| {
            format!("Failed to load libribasim from {shared_lib_path:?}\nError: {error:?}")
        })?;

        // Configure Julia before the first Julia entrypoint initializes the runtime.
        let set_threads: Symbol<unsafe extern "C" fn(i32) -> i32> = lib
            .get(b"ribasim_set_julia_threads")
            .map_err(|error| format!("Failed to find the Julia thread configurator: {error}"))?;
        match set_threads(cli.threads) {
            0 => {}
            1 => return Err("Julia was initialized before its thread count was configured".into()),
            2 => {
                return Err(format!(
                    "Julia thread count must be between 1 and {}",
                    i16::MAX
                ));
            }
            code => {
                return Err(format!(
                    "Failed to configure Julia threads (error code {code})"
                ));
            }
        }

        // Let Julia handle Ctrl-C, such that the results are written before stopping.
        let enable_signal_handlers: Symbol<unsafe extern "C" fn() -> i32> = lib
            .get(b"ribasim_enable_julia_signal_handlers")
            .map_err(|error| {
                format!("Failed to find the Julia signal handler configurator: {error}")
            })?;
        match enable_signal_handlers() {
            0 => {}
            1 => {
                return Err(
                    "Julia was initialized before its signal handlers were configured".into(),
                );
            }
            code => {
                return Err(format!(
                    "Failed to configure Julia signal handlers (error code {code})"
                ));
            }
        }

        let execute: Symbol<unsafe extern "C" fn(*const c_char) -> i32> = lib
            .get(b"execute")
            .map_err(|error| format!("Failed to find the execute function: {error}"))?;
        let exit_code = execute(toml_path.as_ptr());

        // Never unload libribasim: Julia threads may still be running, and unloading their
        // code from under them can crash the process on exit.
        std::mem::forget(lib);

        // Return with same exit code as `execute` did
        Ok(u8::try_from(exit_code).map_or(ExitCode::FAILURE, ExitCode::from))
    }
}
