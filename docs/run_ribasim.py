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

import re
from pathlib import Path

from juliacall import Main as jl

jl.seval("import Ribasim")

# Run Ribasim while capturing all of its terminal output into a single buffer.
# Letting juliacall stream straight to stdout causes blank lines in the rendered
# Quarto HTML: each line arrives as a separate Jupyter stream message, and
# Quarto adds a blank line after every line that contains ANSI color codes.
# Capturing the output and printing it once, with the ANSI codes stripped,
# avoids both problems.
_run_captured = jl.seval("""
function (toml_path)
    pipe = Pipe()
    Base.link_pipe!(pipe; reader_supports_async = true, writer_supports_async = true)
    buffer = IOBuffer()
    reader = @async write(buffer, pipe)
    retcode = redirect_stdout(pipe) do
        redirect_stderr(pipe) do
            Ribasim.main(toml_path)
        end
    end
    close(pipe.in)
    wait(reader)
    return String(take!(buffer)), retcode
end
""")

# Matches ANSI escape sequences (colors, cursor movement, etc.).
_ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")


def run_ribasim(toml_path: str | Path) -> None:
    """Run a Ribasim simulation via juliacall."""
    output, retcode = _run_captured(str(toml_path))
    print(_ANSI_RE.sub("", str(output)), end="")
    assert int(retcode) == 0, f"Simulation failed: {toml_path}"
