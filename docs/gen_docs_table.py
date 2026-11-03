"""
Python interface to `utils/gen_docs_table.jl` for generating input table documentation.

QMD files using the julia engine can include `utils/gen_docs_table.jl` directly.
QMD files using the jupyter engine, for instance because they contain a lot of Python code,
can include this script using `%run path/to/gen_docs_table.py`.
This will start a Julia session, import Ribasim, and define the `table_from_schema` function.

We don't use Python code cells in QMD files with the julia engine, since the code of such cells
is shown as a plain code block, which ignores options like `code-fold`.
"""

from pathlib import Path

from IPython.display import Markdown
from juliacall import Main as jl

jl.seval("import Ribasim")
jl.include(str(Path(__file__).parents[1] / "utils" / "gen_docs_table.jl"))


def _symbol_dict(d: dict[str, str] | None):
    """Convert a Python dict with string keys to a Julia `Dict{Symbol, String}`."""
    out = jl.Dict[jl.Symbol, jl.String]()
    for key, value in (d or {}).items():
        out[jl.Symbol(key)] = value
    return out


def table_from_schema(
    schema: str,
    *,
    units_override: dict[str, str] | None = None,
    restrictions: dict[str, str] | None = None,
    defaults_override: dict[str, str] | None = None,
) -> Markdown:
    """
    Create a markdown table documenting the columns of an input table schema.

    The schema is given by its name relative to `Ribasim.Schema`, e.g. "Basin.Static".
    See `table_from_schema` in `utils/gen_docs_table.jl` for the keyword arguments.
    """
    table = jl.table_from_schema(
        jl.seval(f"Ribasim.Schema.{schema}"),
        units_override=_symbol_dict(units_override),
        restrictions=_symbol_dict(restrictions),
        defaults_override=_symbol_dict(defaults_override),
        output=jl.String,
    )
    return Markdown(str(table))
