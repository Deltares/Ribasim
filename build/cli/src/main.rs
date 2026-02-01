use std::{
    env::{self, consts::OS},
    ffi::CString,
    io::{self, Write},
    path::PathBuf,
};

use clap::Parser;
use libloading::{Library, Symbol};
use std::process::ExitCode;

#[derive(Parser)]
#[command(version)]
struct Cli {
    /// Path to the TOML file
    toml_path: Option<PathBuf>,

    /// Number of threads to use
    #[arg(short='t', long="threads", value_name="#THREADS", help="Number of threads to use.", default_value = "1", hide=true)]
    threads: String,
}

fn main() -> ExitCode {
    // Get the path to the directory containing the current executable
    let exe_dir = env::current_exe().unwrap().parent().unwrap().to_owned();

    // Parse command line arguments
    let cli = Cli::parse();

    let no_args_provided = env::args_os().len() == 1;

    let mut used_file_picker = false;

    let toml_path = match cli.toml_path {
        Some(path) => path,
        None if no_args_provided => {
            let picked = rfd::FileDialog::new()
                .add_filter("TOML", &["toml"])
                .set_title("Select a Ribasim model to run")
                .pick_file();

            match picked {
                Some(path) => {
                    used_file_picker = true;
                    path
                }
                None => return ExitCode::FAILURE,
            }
        }
        None => {
            eprintln!("Missing TOML file path");
            return ExitCode::FAILURE;
        }
    };

    if !toml_path.is_file() {
        eprintln!("File not found {:?}", toml_path);
        return ExitCode::FAILURE;
    }

    // Set JULIA_NUM_THREADS to the value from CLI
    env::set_var("JULIA_NUM_THREADS", &cli.threads);

    let shared_lib_path = match OS {
        "windows" => exe_dir.join("libribasim.dll"),
        "linux" => exe_dir.join("../lib/libribasim.so"),
        "macos" => exe_dir.join("../lib/libribasim.dylib"),
        _ => unimplemented!("Your OS is not supported yet."),
    };
    let exit_code = unsafe {
        // Load the library
        let lib = match Library::new(&shared_lib_path) {
            Ok(lib) => lib,
            Err(e) => {
                eprintln!("Failed to load libribasim from {:?}", shared_lib_path);
                eprintln!("Error: {:?}", e);
                return ExitCode::FAILURE;
            }
        };

        // Execute
        let execute: Symbol<unsafe extern "C" fn(*const libc::c_char) -> i32> =
            lib.get(b"execute").unwrap();
        let toml_path_c = CString::new(toml_path.to_str().unwrap()).unwrap();
        execute(toml_path_c.as_ptr())
    };

    if used_file_picker {
        eprintln!("Press Enter to close...");
        let _ = io::stdout().flush();
        let mut input = String::new();
        let _ = io::stdin().read_line(&mut input);
    }

    // Return with same exit code as `execute` did
    ExitCode::from(exit_code as u8)
}
