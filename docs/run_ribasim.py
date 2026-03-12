"""
Julia interface setup for Ribasim simulations.

In QMD files using the jupyter engine, this script can be included using
`%run path/to/run_ribasim.py`. This will start a Julia session,
import Ribasim, and define the `run_ribasim` function.

In a file where multiple simulations are run this has the benefit
of only needing to start Julia once, compared to `subprocess.run`.

Since Ribasim Python also has `run_ribasim`, we can include this script
in a hidden evaluated cell, after `from ribasim import run_ribasim`.
That way we can run this version on CI but it looks like we run the Ribasim Python version.
"""

import os
import re
import sys
import tempfile
from pathlib import Path

from juliacall import Main as jl

jl.seval("import Ribasim")

_ANSI_RE = re.compile(r"\x1b\[[0-9;]*[a-zA-Z]")


def _filter_output(raw: str) -> str:
    """Remove blank lines and progress bar repetitions from Ribasim output."""
    lines = raw.splitlines()
    filtered = []
    for line in lines:
        plain = _ANSI_RE.sub("", line)
        # Skip lines that are only whitespace or invisible braille blanks (U+2800)
        if all(c in " \t\u2800" for c in plain):
            continue
        # Skip progress bar log lines from OrdinaryDiffEqCore
        if "@ OrdinaryDiffEqCore" in plain:
            continue
        if plain.lstrip().startswith("\u250c") and "Simulating" in plain:
            continue
        filtered.append(line)
    return "\n".join(filtered)


def run_ribasim(toml_path: str | Path) -> None:
    """Run a Ribasim simulation via juliacall."""
    # Redirect stderr at the fd level to capture Julia output
    # (logo, log messages, progress bar) which all go to stderr.
    sys.stderr.flush()
    old_fd = os.dup(2)
    try:
        with tempfile.TemporaryFile(mode="w+b") as tmp:
            os.dup2(tmp.fileno(), 2)
            try:
                retcode = jl.Ribasim.main(str(toml_path))
            finally:
                os.dup2(old_fd, 2)
            tmp.seek(0)
            raw = tmp.read().decode("utf-8", errors="replace")
    finally:
        os.close(old_fd)

    output = _filter_output(raw)
    if output:
        print(output, file=sys.stderr)

    assert retcode == 0, f"Simulation failed: {toml_path}"
