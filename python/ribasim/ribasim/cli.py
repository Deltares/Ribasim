"""Command-line interface utilities for running Ribasim."""

import shutil
import subprocess
from pathlib import Path


def _find_cli() -> Path:
    """Find the Ribasim CLI executable on PATH.

    Returns
    -------
    Path
        Path to the Ribasim CLI executable.

    Raises
    ------
    FileNotFoundError
        If the Ribasim CLI is not found on PATH.
    """
    cli_path = shutil.which("ribasim")

    if cli_path is not None:
        return Path(cli_path)

    raise FileNotFoundError(
        "Ribasim CLI executable 'ribasim' not found on PATH. "
        "Please ensure Ribasim is installed and available on your PATH."
    )


def _is_notebook() -> bool:
    """Check if we're running in a notebook.

    The stdout/stderr of ribasim.exe gets sent to the Jupyter server rather than the cell output
    with `subprocess.run("ribasim --version")`. We want this to go to the cell output,
    and we want to avoid many print lines with the progress bar as it runs.
    So we detect if we run in a notebook, and use IPython display and display_update to avoid that.
    """
    try:
        import marimo

        if marimo.running_in_notebook():
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
            return False  # Terminal running IPython
        else:
            return False  # Other type
    except (NameError, ImportError):
        return False  # Standard Python interpreter


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
        If the Ribasim CLI is not found on PATH (when cli_path is not provided).
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
    else:
        cli = Path(cli_path)

    # Build command arguments
    args = []

    if threads is not None:
        args.extend(["--threads", str(threads)])

    if version:
        args.append("--version")
    elif toml_path is not None:
        args.append(toml_path)
    else:
        raise ValueError("Provide a toml_path, or set version=True")

    in_notebook = _is_notebook()

    if in_notebook:
        # In notebook: use IPython display for better progress bar handling
        from IPython.display import HTML, display, update_display

        progress_display_id = "ribasim_progress"
        progress_displayed = False

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
            raise subprocess.CalledProcessError(proc.returncode, [cli, *args])
    else:
        # In terminal: direct forwarding preserves colors and formatting
        result = subprocess.run([cli, *args])
        result.check_returncode()
