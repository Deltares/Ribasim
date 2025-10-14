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
    #[arg(short='t', long="threads", value_name="#THREADS", help="Number of threads to use. Defaults to the JULIA_NUM_THREADS environment variable, and when unset, to using the physical CPU count.")]
    threads: Option<String>,
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

    // Set JULIA_NUM_THREADS if the user explicitly set `--threads`
    // or if the environment variable is not yet set.
    if let Some(threads) = cli.threads {
        env::set_var("JULIA_NUM_THREADS", threads);
    } else if env::var("JULIA_NUM_THREADS").is_err() {
        // If no --threads specified and JULIA_NUM_THREADS not set, use physical CPU count
        env::set_var("JULIA_NUM_THREADS", num_cpus::get_physical().to_string());
    }

    let shared_lib_path = match OS {
        "windows" => "bin/libribasim.dll",
        "linux" => "lib/libribasim.so",
        "macos" => "lib/libribasim.dylib",
        _ => unimplemented!("Your OS is not supported yet."),
    };
    let full_shared_lib_path = exe_dir.join(shared_lib_path);
    unsafe {
        // Load the library
        let lib = Library::new(full_shared_lib_path).unwrap();

        // Init Julia
        let jl_init_with_image_file: Symbol<unsafe extern "C" fn(*const libc::c_char, *const libc::c_char) -> i32> =
            lib.get(b"jl_init_with_image_file").unwrap();

        let julia_bindir = CString::new(exe_dir.to_str().unwrap()).unwrap();
        let image_path = CString::new(shared_lib_path).unwrap();
        jl_init_with_image_file(julia_bindir.as_ptr(), image_path.as_ptr());

        // Execute
        let execute: Symbol<unsafe extern "C" fn(*const libc::c_char) -> i32> =
            lib.get(b"execute").unwrap();
        let toml_path_c = CString::new(cli.toml_path.to_str().unwrap()).unwrap();
        let exit_code = execute(toml_path_c.as_ptr());

        // Return with same exit code as `execute` did
        ExitCode::from(exit_code as u8)
    }
}
