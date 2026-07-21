use std::{
    env::{self, consts::OS},
    ffi::CString,
    path::PathBuf,
};

use clap::Parser;
use libloading::{Library, Symbol};
use std::process::ExitCode;

#[derive(Parser)]
#[command(version)]
struct Cli {
    /// Path to the TOML file
    toml_path: PathBuf,

    /// Number of threads to use
    #[arg(
        short = 't',
        long = "threads",
        value_name = "#THREADS",
        help = "Number of threads to use.",
        default_value = "1",
        hide = true
    )]
    threads: i32,
}

fn main() -> ExitCode {
    // Get the path to the directory containing the current executable
    let exe_dir = env::current_exe().unwrap().parent().unwrap().to_owned();

    // Parse command line arguments
    let cli = Cli::parse();

    if !cli.toml_path.is_file() {
        eprintln!("File not found {:?}", cli.toml_path);
        return ExitCode::FAILURE;
    }

    let shared_lib_path = match OS {
        "windows" => exe_dir.join("libribasim.dll"),
        "linux" => exe_dir.join("../lib/libribasim.so"),
        "macos" => exe_dir.join("../lib/libribasim.dylib"),
        _ => unimplemented!("Your OS is not supported yet."),
    };
    unsafe {
        // Load the library
        let lib = match Library::new(&shared_lib_path) {
            Ok(lib) => lib,
            Err(e) => {
                eprintln!("Failed to load libribasim from {:?}", shared_lib_path);
                eprintln!("Error: {:?}", e);
                return ExitCode::FAILURE;
            }
        };

        // Configure Julia before the first Julia entrypoint initializes the runtime.
        let set_threads: Symbol<unsafe extern "C" fn(i32) -> i32> =
            match lib.get(b"ribasim_set_julia_threads") {
                Ok(symbol) => symbol,
                Err(error) => {
                    eprintln!("Failed to find the Julia thread configurator: {error}");
                    return ExitCode::FAILURE;
                }
            };
        match set_threads(cli.threads) {
            0 => {}
            1 => {
                eprintln!("Julia was initialized before its thread count was configured");
                return ExitCode::FAILURE;
            }
            2 => {
                eprintln!("Julia thread count must be between 1 and {}", i16::MAX);
                return ExitCode::FAILURE;
            }
            code => {
                eprintln!("Failed to configure Julia threads (error code {code})");
                return ExitCode::FAILURE;
            }
        }

        // Execute
        let execute: Symbol<unsafe extern "C" fn(*const libc::c_char) -> i32> =
            lib.get(b"execute").unwrap();
        let toml_path_c = CString::new(cli.toml_path.to_str().unwrap()).unwrap();
        let exit_code = execute(toml_path_c.as_ptr());

        // Return with same exit code as `execute` did
        ExitCode::from(exit_code as u8)
    }
}
