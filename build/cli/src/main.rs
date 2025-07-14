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
}

fn main() -> ExitCode {
    // Get the path to the directory containing the current executable
    let exe_dir = env::current_exe().unwrap().parent().unwrap().to_owned();

    // Set the appropriate environment variable for the current platform
    if OS == "windows" {
        env::set_var(
            "PATH",
            format!(
                "{};{}",
                exe_dir.join("bin").display(),
                env::var("PATH").unwrap_or_default()
            ),
        );
    }

    // TODO: Do we need to set LD_LIBRARY_PATH on linux?

    // Parse command line arguments
    let cli = Cli::parse();

    if !cli.toml_path.is_file() {
        eprintln!("File not found {:?}", cli.toml_path);
        return ExitCode::FAILURE;
    }

    let shared_lib_path = match OS {
        "windows" => exe_dir.join("bin/libribasim.dll"),
        "linux" => exe_dir.join("lib/libribasim.so"),
        "macos" => exe_dir.join("lib/libribasim.dylib"),
        _ => unimplemented!("Your OS is not supported yet."),
    };
    unsafe {
        // Load the library
        let lib = Library::new(shared_lib_path).unwrap();

        // Execute
        let execute: Symbol<unsafe extern "C" fn(*const libc::c_char) -> i32> =
            lib.get(b"execute").unwrap();
        let toml_path_c = CString::new(cli.toml_path.to_str().unwrap()).unwrap();
        let exit_code = execute(toml_path_c.as_ptr());

        // Return with same exit code as `execute` did
        ExitCode::from(exit_code as u8)
    }
}
