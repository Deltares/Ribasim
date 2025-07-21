"""
Julia interface setup for Ribasim simulations.

In QMD files using the jupyter engine, this script can be included using
`%run path/to/run_ribasim.py`. This will start a Julia session,
import Ribasim, and define the `run_ribasim` function.

In a file where multiple simulations are run this has the benefit
of only needing to start Julia once, compared to `subprocess.run`.
"""

from pathlib import Path

from juliacall import Main as jl

jl.seval("import Ribasim")


def run_ribasim(toml_path: str | Path) -> None:
    """Run a Ribasim simulation via juliacall."""
    retcode = jl.Ribasim.main(str(toml_path))
    assert retcode == 0, f"Simulation failed: {toml_path}"
