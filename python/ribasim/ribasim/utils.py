import re

import pandas as pd
from pandera.dtypes import Int32
from pandera.typing import Series


def _pascal_to_snake(pascal_str):
    # Insert a '_' before all uppercase letters that are not at the start of the string
    # and convert the string to lowercase
    return re.sub(r"(?<!^)(?=[A-Z])", "_", pascal_str).lower()


class MissingOptionalModule:
    """Presents a clear error for optional modules."""

    def __init__(self, name, suggestion="all"):
        self.name = name
        self.suggestion = suggestion

    def __getattr__(
        self,
        _,
    ):
        raise ImportError(
            f"{self.name} is required for this functionality. You can get it using `pip install ribasim[{self.suggestion}]`."
        )


def _node_lookup(df) -> Series[Int32]:
    """Create a lookup table from from (node_type, node_id) to the node dimension index.

    Used when adding data onto the nodes of an xugrid dataset.
    """
    return df.reset_index(names="node_index").set_index(["node_type", "node_id"])[
        "node_index"
    ]


def _edge_lookup(uds) -> Series[Int32]:
    """Create a lookup table from edge_id to the edge dimension index.

    Used when adding data onto the edges of an xugrid dataset.
    """

    return pd.Series(
        index=uds["edge_id"],
        data=uds[uds.grid.edge_dimension],
        name="edge_index",
    )


def _time_in_ns(df) -> None:
    """Convert the time column to datetime64[ns] dtype."""
    # datetime64[ms] gives trouble; https://github.com/pydata/xarray/issues/6318
    df["time"] = df["time"].astype("datetime64[ns]")
