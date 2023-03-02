use std::env;
use std::process::Command;

fn main() {
    // Get the path to the directory containing the compiled executable
    let bin_path = env::current_exe().unwrap().parent().unwrap().join("bin");

    // Set the appropriate environment variable for the current platform
    match std::env::consts::OS {
        "windows" => env::set_var(
            "PATH",
            format!(
                "{};{}",
                bin_path.display(),
                env::var("PATH").unwrap_or_default()
            ),
        ),
        _ => env::set_var(
            "LD_LIBRARY_PATH",
            format!(
                "{}:{}",
                bin_path.display(),
                env::var("LD_LIBRARY_PATH").unwrap_or_default()
            ),
        ),
    };

    // Get the command line arguments
    let args: Vec<String> = std::env::args().skip(1).collect();

    // Run the ribasim executable with the command line arguments
    let status = Command::new(bin_path.join("ribasim.exe"))
        .args(args)
        .status()
        .expect("Failed to execute ribasim");

    // Exit the Rust program with the same exit status as the child process
    std::process::exit(status.code().unwrap_or(1));
}
