"""Command-line interface utilities for running Ribasim."""

import shutil
import subprocess
import sys
from enum import Enum
from pathlib import Path


class SubprocessHandling(Enum):
    """Method for handling subprocess output streams."""

    DISPLAY = "display"  # Jupyter/IPython notebooks using display/update_display
    SPYDER = "spyder"  # Spyder IDE using \r carriage returns
    FORWARD = "forward"  # Terminal with direct forwarding


def _find_cli() -> Path | None:
    """Find the Ribasim CLI executable on PATH.

    Returns
    -------
    Path | None
        Path to the Ribasim CLI executable, or None if not found.
    """
    cli_path = shutil.which("ribasim")

    if cli_path is not None:
        return Path(cli_path)

    return None


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
    cli_path : str | Path | None, optional
        Path to the Ribasim CLI executable. If not provided, searches PATH.
    version : bool, default False
        Print version
    threads : int | None, optional
        Number of threads to use. If not specified, defaults to the
        JULIA_NUM_THREADS environment variable, and when unset, to using the physical CPU count.

    Raises
    ------
    FileNotFoundError
        If the Ribasim CLI is not found on PATH (when cli_path is not provided),
        or the toml_path does not exist.
    ValueError
        If neither toml_path nor version is provided.
    subprocess.CalledProcessError
        If the Ribasim CLI returns a non-zero exit code.

    Examples
    --------
    >>> run_ribasim("model.toml")
    >>> run_ribasim("model.toml", threads=4)
    >>> run_ribasim("model.toml", cli_path="/path/to/ribasim")
    >>> run_ribasim(version=True)
    """
    if cli_path is None:
        cli = _find_cli()
        if cli is None:
            raise FileNotFoundError(
                "Ribasim CLI executable 'ribasim' not found on PATH. "
                "Please ensure Ribasim is installed and available on your PATH."
            )
    else:
        cli = Path(cli_path)
        if not cli.exists():
            raise FileNotFoundError(
                f"Ribasim CLI executable not found at '{cli_path}'. "
                "Please ensure the path is correct."
            )

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
