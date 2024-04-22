use std::env;

fn main() {
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

    // Get the command line arguments
    let args: Vec<String> = std::env::args().skip(1).collect();

    // Parse command line arguments
    todo!();

    // Call ribasim shared library and check for errors
    todo!()
}
