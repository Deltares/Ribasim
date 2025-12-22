"""Command-line interface utilities for running Ribasim."""

import os
import shutil
import subprocess
import sys
import warnings
from enum import Enum
from pathlib import Path


class SubprocessHandling(Enum):
    """Method for handling subprocess output streams."""

    DISPLAY = "display"  # Jupyter/IPython notebooks using display/update_display
    SPYDER = "spyder"  # Spyder IDE using \r carriage returns
    FORWARD = "forward"  # Terminal with direct forwarding


def _resolve_executable(executable: str | Path, error_msg: str = "") -> Path:
    """Resolve an executable using shutil.which().

    This allows users to specify "path/to/ribasim" instead of "path/to/ribasim.exe".

    Parameters
    ----------
    executable : str | Path
        If a Path, searches for the executable name in the parent directory.
        If a str, searches for the executable name in the system PATH.
    error_msg : str
        Custom error message to raise if executable is not found.

    Returns
    -------
    Path
        Path to the resolved executable.

    Raises
    ------
    FileNotFoundError
        If the executable is not found.
    """
    if isinstance(executable, Path):
        name = executable.name
        search_path = executable.parent
    else:
        name = executable
        search_path = None

    cli = shutil.which(name, path=search_path)
    if cli is None:
        raise FileNotFoundError(error_msg)
    return Path(cli)


def _find_cli(ribasim_exe: str | Path | None = None) -> Path:
    """Find the Ribasim CLI executable on ribasim_exe or the PATH.

    Parameters
    ----------
    ribasim_exe : str | Path | None, optional
        Path to the Ribasim CLI executable. If None, first checks the RIBASIM_EXE
        environment variable, then searches the PATH.

    Returns
    -------
    Path
        Path to the Ribasim CLI executable.

    Raises
    ------
    FileNotFoundError
        If the Ribasim CLI is not found via RIBASIM_EXE or on the PATH (when ribasim_exe is None),
        or if the executable is not found at the specified ribasim_exe.
    """
    if ribasim_exe is not None:
        # Use ribasim_exe argument if provided
        ribasim_exe = Path(ribasim_exe)
        return _resolve_executable(
            ribasim_exe,
            f"Ribasim CLI executable not found at '{ribasim_exe.resolve()}'. "
            "Please ensure the path is correct.",
        )
    else:
        # Else check RIBASIM_EXE environment variable
        if (ribasim_exe_env := os.environ.get("RIBASIM_EXE")) is not None:
            ribasim_exe = Path(ribasim_exe_env)

            return _resolve_executable(
                ribasim_exe,
                f"Ribasim CLI executable not found at RIBASIM_EXE='{ribasim_exe.resolve()}'. "
                "Please ensure the path is correct.",
            )
        else:
            # Fall back to searching the PATH
            return _resolve_executable(
                "ribasim",
                "Ribasim CLI executable 'ribasim' not found. "
                "Please ensure Ribasim is installed and available on your PATH, "
                "or set the RIBASIM_EXE environment variable.",
            )


def _subprocess_handling() -> SubprocessHandling:
    """Determine how to handle subprocess output streams.

    Returns
    -------
    SubprocessHandling
        The method to use for handling subprocess output.
        - DISPLAY: Jupyter/IPython notebooks using display/update_display
        - SPYDER: Spyder IDE using carriage returns for progress bars
        - FORWARD: Terminal with direct forwarding (preserves colors)
    """
    # Check for Marimo first
    try:
        import marimo

        if marimo.running_in_notebook():
            return SubprocessHandling.DISPLAY
    except ImportError:
        pass

    # Check for Jupyter/IPython/Spyder
    try:
        # Try to get IPython instance
        from IPython.core.getipython import get_ipython

        ipy = get_ipython()
        if ipy is None:
            return SubprocessHandling.FORWARD

        # Check the shell type
        shell = ipy.__class__.__name__
        if shell == "ZMQInteractiveShell":
            return SubprocessHandling.DISPLAY  # Jupyter notebook or qtconsole
        elif shell == "SpyderShell":
            # See: https://github.com/spyder-ide/qtconsole/issues/471#issuecomment-787856716
            return SubprocessHandling.SPYDER  # Spyder IDE
        elif shell == "TerminalInteractiveShell":
            return SubprocessHandling.FORWARD  # Terminal running IPython
        else:
            return SubprocessHandling.FORWARD  # Other type
    except (NameError, ImportError):
        return SubprocessHandling.FORWARD  # Standard Python interpreter


def run_ribasim(
    toml_path: str | Path | None = None,
    *,
    ribasim_exe: str | Path | None = None,
    cli_path: str | Path | None = None,
    version: bool = False,
    threads: int | None = None,
) -> None:
    """Run the Ribasim CLI executable.

    Parameters
    ----------
    toml_path : str | Path | None, optional
        Path to the TOML file.
        Required unless version=True.
    ribasim_exe : str | Path | None, optional
        Path to the Ribasim CLI executable. If not provided, first checks the
        RIBASIM_EXE environment variable, then searches PATH.
    cli_path : str | Path | None, optional
        Deprecated alias for ribasim_exe. Use ribasim_exe instead.
    version : bool, default False
        Print version
    threads : int | None, optional
        Number of threads to use. If not specified, defaults to the
        JULIA_NUM_THREADS environment variable, and when unset, to using the physical CPU count.

    Raises
    ------
    FileNotFoundError
        If the Ribasim CLI is not found via RIBASIM_EXE or on PATH (when ribasim_exe is not provided),
        or the toml_path does not exist.
    ValueError
        If neither toml_path nor version is provided.
    subprocess.CalledProcessError
        If the Ribasim CLI returns a non-zero exit code.

    Examples
    --------
    >>> run_ribasim("model.toml")
    >>> run_ribasim("model.toml", threads=4)
    >>> run_ribasim("model.toml", ribasim_exe="/path/to/ribasim")
    >>> run_ribasim(version=True)
    """
    # Handle deprecated cli_path parameter
    if cli_path is not None:
        if ribasim_exe is not None:
            raise ValueError(
                "Cannot specify both 'ribasim_exe' and deprecated 'cli_path'. "
                "Use 'ribasim_exe' only."
            )
        warnings.warn(
            "The 'cli_path' parameter is deprecated. Use 'ribasim_exe' instead.",
            DeprecationWarning,
            stacklevel=2,
        )
        ribasim_exe = cli_path

    # Build command arguments
    args: list[str | Path] = []

    if threads is not None:
        args.extend(["--threads", str(threads)])

    if version:
        args.append("--version")
    elif toml_path is not None:
        toml_path = Path(toml_path)
        if not toml_path.exists():
            raise FileNotFoundError(
                f"TOML file not found at '{toml_path}'. "
                "Please ensure the path is correct."
            )
        args.append(toml_path)
    else:
        raise ValueError("Provide a toml_path, or set version=True")

    cli = _find_cli(ribasim_exe)
    handling = _subprocess_handling()

    if handling == SubprocessHandling.FORWARD:
        # In terminal: direct forwarding preserves colors and formatting
        result = subprocess.run([cli, *args])
        result.check_returncode()
    else:
        # For DISPLAY and SPYDER: capture output and handle progress bars
        _run_with_progress_handling(cli, args, handling)


def _run_with_progress_handling(
    cli: Path, args: list[str | Path], handling: SubprocessHandling
) -> None:
    """Run subprocess with special handling for progress bars.

    Parameters
    ----------
    cli : Path
        Path to the Ribasim CLI executable.
    args : list[str | Path]
        Command-line arguments.
    handling : SubprocessHandling
        The output handling method (DISPLAY or SPYDER).
    """
    if handling == SubprocessHandling.DISPLAY:
        from IPython.display import HTML, display, update_display

    progress_display_id = "ribasim_progress"
    progress_displayed = False

    term_width = (
        shutil.get_terminal_size((80, 20)).columns
        if handling == SubprocessHandling.SPYDER
        else 0
    )

    with subprocess.Popen(
        [cli, *args],
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
                    # This is a progress bar line - update in place
                    if handling == SubprocessHandling.DISPLAY:
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
                    else:  # SPYDER
                        if not progress_displayed:
                            print("", end="\r")
                            progress_displayed = True
                        print("\r" + " " * term_width, end="\r")  # Clear current line
                        print(line, end="\r")  # Keep progress bar on one line
                        sys.stdout.flush()
                else:
                    # Regular output line
                    if handling == SubprocessHandling.SPYDER and progress_displayed:
                        print()  # New line after progress bar
                        progress_displayed = False
                    print(line)
                    if handling == SubprocessHandling.SPYDER:
                        sys.stdout.flush()

    if proc.returncode != 0:
        raise subprocess.CalledProcessError(proc.returncode, [cli, *args])
