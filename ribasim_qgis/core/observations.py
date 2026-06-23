"""
Read Ribasim Observation input data from the model GeoPackage.

Unlike the NetCDF readers in :mod:`ribasim_qgis.core.netcdf`, this module reads
*input* data: the ``Observation / time`` table holds user-provided observed
timeseries, keyed by ``node_id`` and ``variable``. These can be plotted
alongside the simulated results for comparison.
"""

from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
import pandas as pd

from ribasim_qgis.core.geopackage import sqlite3_cursor
from ribasim_qgis.core.netcdf import TIME_FORMAT

# Name of the observation timeseries table in the GeoPackage.
OBSERVATION_TABLE = "Observation / time"

# A single timeseries: (time strings, values).
ObservationSeries = tuple[np.ndarray, np.ndarray]


@dataclass
class Observations:
    """Observed timeseries read from the ``Observation / time`` table.

    Attributes
    ----------
    data:
        Mapping ``node_id -> variable -> (time_strings, values)``.
    variables:
        The set of all variable names present across all observation nodes.
    """

    data: dict[int, dict[str, ObservationSeries]] = field(default_factory=dict)
    variables: set[str] = field(default_factory=set)

    def series(self, node_id: int, variable: str) -> ObservationSeries | None:
        """Return the ``(time_strings, values)`` series, or None if absent."""
        return self.data.get(node_id, {}).get(variable)


def _table_exists(cursor, name: str) -> bool:
    cursor.execute(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
        (name,),
    )
    return cursor.fetchone() is not None


def read_observations(gpkg_path: Path) -> Observations | None:
    """Read the ``Observation / time`` table into an :class:`Observations`.

    Returns ``None`` if the GeoPackage has no observation table or it is empty.
    """
    if not gpkg_path.is_file():
        return None

    with sqlite3_cursor(gpkg_path) as cursor:
        if not _table_exists(cursor, OBSERVATION_TABLE):
            return None
        cursor.execute(
            'SELECT node_id, variable, time, value FROM "Observation / time" '
            "ORDER BY node_id, variable, time"
        )
        rows = cursor.fetchall()

    if not rows:
        return None

    df = pd.DataFrame(rows, columns=["node_id", "variable", "time", "value"])
    df["time"] = pd.to_datetime(df["time"])

    observations = Observations()
    # Build per (node_id, variable) series from the time-sorted frame.
    for node_id in df["node_id"].unique():
        node_frame = df[df["node_id"] == node_id]
        per_variable: dict[str, ObservationSeries] = {}
        for variable in node_frame["variable"].unique():
            var_frame = node_frame[node_frame["variable"] == variable]
            time_strings = var_frame["time"].dt.strftime(TIME_FORMAT).to_numpy()
            values = var_frame["value"].to_numpy(dtype=float)
            per_variable[str(variable)] = (time_strings, values)
            observations.variables.add(str(variable))
        observations.data[int(node_id)] = per_variable

    return observations
