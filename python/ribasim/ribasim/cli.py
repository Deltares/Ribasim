"""Command-line interface utilities for running Ribasim."""

import os
import platform
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path
from urllib.request import urlretrieve

from platformdirs import user_cache_dir

from ribasim import __version__


def _reporthook(block_num: int, block_size: int, total_size: int) -> None:
    """Report download progress.

    Parameters
    ----------
    block_num : int
        Current block number.
    block_size : int
        Size of each block in bytes.
    total_size : int
        Total file size in bytes.
    """
    downloaded = block_num * block_size
    if total_size > 0:
        percent = min(100, downloaded * 100 / total_size)
        downloaded_mb = downloaded / (1024 * 1024)
        total_mb = total_size / (1024 * 1024)
        bar_length = 40
        filled = int(bar_length * downloaded / total_size)
        bar = "=" * filled + "-" * (bar_length - filled)
        print(
            f"\rDownloading: [{bar}] {percent:.1f}% ({downloaded_mb:.1f}/{total_mb:.1f} MB)",
            end="",
            flush=True,
        )
        if downloaded >= total_size:
            print()  # New line after completion


def _get_cli_dir() -> Path:
    """Get the directory for storing downloaded Ribasim CLI executables.

    Returns
    -------
    Path
        The directory path where CLI executables are stored.
    """
    cli_dir = Path(user_cache_dir("ribasim", appauthor=False)) / "cli"
    cli_dir.mkdir(parents=True, exist_ok=True)
    return cli_dir


def _get_cli_version(cli_path: str | Path) -> str | None:
    """Get the version of a Ribasim CLI executable.

    Parameters
    ----------
    cli_path : str | Path
        Path to the Ribasim CLI executable.

    Returns
    -------
    str | None
        The version string if successful, None otherwise.
    """
    try:
        result = subprocess.run(
            [str(cli_path), "--version"],
            capture_output=True,
            encoding="utf-8",
            check=True,
        )
        # Parse output like "ribasim 2025.5.0" or "ribasim 2025.5.0-34-g678e1dc"
        output = result.stdout.strip()
        if output.startswith("ribasim "):
            cli_version = output.split()[1]
            # Extract the base version (before any '-' for dev versions)
            return cli_version.split("-")[0]
    except (subprocess.CalledProcessError, IndexError, FileNotFoundError):
        pass
    return None


def _download_cli() -> Path:
    """Download the Ribasim CLI executable for the current platform.

    Returns
    -------
    Path
        Path to the downloaded Ribasim CLI executable.

    Raises
    ------
    RuntimeError
        If the platform is not supported.
    """
    system = platform.system()
    machine = platform.machine()

    # Check platform support
    if system == "Windows" and machine == "AMD64":
        zip_name = "ribasim_windows.zip"
        exe_name = "ribasim.exe"
    elif system == "Linux" and machine == "x86_64":
        zip_name = "ribasim_linux.zip"
        exe_name = "ribasim"
    else:
        raise RuntimeError(
            f"Platform {system} {machine} is not supported. "
            "Ribasim CLI is only available for Windows x64 and Linux x64."
        )

    cli_dir = _get_cli_dir()
    version_dir = cli_dir / __version__
    exe_path = version_dir / "ribasim" / exe_name

    # Check if a compatible version already exists
    if exe_path.exists():
        existing_version = _get_cli_version(exe_path)
        if existing_version == __version__:
            return exe_path

    # Download the CLI
    print(
        f"Ribasim CLI v{__version__} not found. Downloading...",
        file=sys.stderr,
    )
    version_dir.mkdir(parents=True, exist_ok=True)
    url = f"https://github.com/Deltares/Ribasim/releases/download/v{__version__}/{zip_name}"
    zip_path = version_dir / zip_name

    urlretrieve(url, zip_path, reporthook=_reporthook)

    # Extract the zip file
    print("Extracting...", file=sys.stderr)
    with zipfile.ZipFile(zip_path, "r") as zip_ref:
        zip_ref.extractall(version_dir)

    # Remove the zip file
    zip_path.unlink()

    print(f"Ribasim CLI installed to {exe_path}", file=sys.stderr)
    return exe_path


def _find_cli() -> Path:
    """Find or download the Ribasim CLI executable.

    Returns
    -------
    Path
        Path to the Ribasim CLI executable.

    Raises
    ------
    RuntimeError
        If the platform is not supported and Ribasim CLI is not on PATH.
    """
    # First check if compatible CLI is on PATH (excluding the Python wrapper location)
    system = platform.system()
    exe_name = "ribasim.exe" if system == "Windows" else "ribasim"

    # Get the directory where the Python wrapper script would be installed
    if system == "Windows":
        python_scripts = Path(sys.prefix) / "Scripts"
    else:
        python_scripts = Path(sys.prefix) / "bin"

    # Filter PATH to exclude the Python scripts directory
    original_path = os.environ.get("PATH", "")
    path_dirs = [
        d
        for d in original_path.split(os.pathsep)
        if Path(d).resolve() != python_scripts.resolve()
    ]
    filtered_path = os.pathsep.join(path_dirs)

    # Search for ribasim with the filtered PATH
    which_ribasim = shutil.which(exe_name, path=filtered_path)

    if which_ribasim is not None:
        ribasim_path = Path(which_ribasim).resolve()
        # Check version compatibility
        version = _get_cli_version(ribasim_path)
        if version == __version__:
            return ribasim_path

    # Not on PATH or incompatible version, download it
    return _download_cli()


def _is_notebook() -> bool:
    """Check if we're running in a Jupyter or Marimo notebook (not IPython terminal)."""
    # Check for Marimo first
    try:
        import marimo as mo  # type: ignore

        if mo.running_in_notebook():
            return True
    except ImportError:
        pass

    # Check for Jupyter/IPython
    try:
        # Try to get IPython instance
        from IPython.core.getipython import get_ipython

        ipy = get_ipython()
        if ipy is None:
            return False

        # Check the shell type
        shell = ipy.__class__.__name__
        if shell == "ZMQInteractiveShell":
            return True  # Jupyter notebook or qtconsole
        elif shell == "TerminalInteractiveShell":
            return False  # Terminal running IPython - display() doesn't work well here
        else:
            return False  # Other type
    except (NameError, ImportError):
        return False  # Standard Python interpreter


def run_ribasim(*args: str | Path) -> None:
    """Run the Ribasim CLI executable with the given arguments.

    Parameters
    ----------
    *args : str | Path
        Arguments to pass to the Ribasim CLI, such as the path to the TOML file.
        Pass '--help' to see all options.

    Raises
    ------
    RuntimeError
        If the platform is not supported and Ribasim CLI is not on PATH.
    subprocess.CalledProcessError
        If the Ribasim CLI returns a non-zero exit code.
    """
    cli_path = _find_cli()

    # Check if we're running in a Jupyter notebook (not IPython terminal)
    in_notebook = _is_notebook()

    if in_notebook:
        # In notebook: use IPython display for better progress bar handling
        from IPython.display import HTML, display, update_display

        progress_display_id = "ribasim_progress"
        progress_displayed = False

        with subprocess.Popen(
            [str(cli_path), *args],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            universal_newlines=True,
            encoding="utf-8",
            bufsize=1,
        ) as proc:
            if proc.stdout:
                for line in proc.stdout:
                    line = line.rstrip()
                    if line.startswith("Simulating"):
                        # This is a progress bar line - use display for smooth updates
                        if not progress_displayed:
                            display(
                                HTML(f"<pre>{line}</pre>"),
                                display_id=progress_display_id,
                            )
                            progress_displayed = True
                        else:
                            update_display(
                                HTML(f"<pre>{line}</pre>"),
                                display_id=progress_display_id,
                            )
                    else:
                        print(line)

        if proc.returncode != 0:
            raise subprocess.CalledProcessError(proc.returncode, [str(cli_path), *args])
    else:
        # In terminal: direct forwarding preserves colors and formatting
        result = subprocess.run([str(cli_path), *args])
        result.check_returncode()


def main() -> None:
    """Serve as the main entry point for the ribasim CLI script."""
    # Pass all arguments after the script name to ribasim
    run_ribasim(*sys.argv[1:])
