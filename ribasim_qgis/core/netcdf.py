"""
Read Ribasim NetCDF result files using the GDAL Multidimensional Raster API.

Produces pandas DataFrames with a DatetimeIndex, matching the format
previously produced by Arrow postprocessing.
"""

from datetime import datetime, timedelta
from pathlib import Path

import numpy as np
import pandas as pd
from osgeo import gdal


def _read_time(root_group) -> pd.DatetimeIndex:
    """Read the time coordinate variable and decode to DatetimeIndex.

    Ribasim NetCDF files encode time as float64 with
    ``units = "days since 1900-01-01 00:00:00"`` (CF conventions).
    """
    time_arr = root_group.OpenMDArray("time")
    values = time_arr.ReadAsArray()

    units_attr = time_arr.GetAttribute("units")
    if units_attr is not None:
        units_str = units_attr.ReadAsString()
        # Parse "days since YYYY-MM-DD HH:MM:SS"
        _, _, ref = units_str.partition("since ")
        base = datetime.fromisoformat(ref.strip())
    else:
        # Fallback: assume days since 1900-01-01
        base = datetime(1900, 1, 1)

    timestamps = [base + timedelta(days=float(d)) for d in values]
    return pd.DatetimeIndex(timestamps, name="time")


def _open_netcdf(path: Path):
    """Open a NetCDF file with GDAL multidimensional API. Returns root group or None."""
    ds = gdal.OpenEx(str(path), gdal.OF_MULTIDIM_RASTER)
    if ds is None:
        return None
    return ds.GetRootGroup()


# Variables that are coordinate/auxiliary and should not be treated as result columns.
_SKIP_VARS = {
    "time",
    "node_id",
    "link_id",
    "from_node_id",
    "to_node_id",
    "substance",
    "subgrid_id",
}


def _read_units(root_group, variable_names: list[str]) -> dict[str, str]:
    """Read units for each variable via MDArray.GetUnit()."""
    units: dict[str, str] = {}
    for name in variable_names:
        arr = root_group.OpenMDArray(name)
        u = arr.GetUnit()
        if u:
            units[name] = u
    return units


def _read_2d_nc(path: Path, id_name: str) -> tuple[pd.DataFrame, dict[str, str]] | None:
    """Read a 2-D NetCDF result file (time x id) into a long-format DataFrame.

    Works for both basin.nc (id_name="node_id") and flow.nc (id_name="link_id").
    """
    root = _open_netcdf(path)
    if root is None:
        return None

    time_index = _read_time(root)
    ids = root.OpenMDArray(id_name).ReadAsArray()
    n_times = len(time_index)
    n_ids = len(ids)

    data_vars = [
        v
        for v in root.GetMDArrayNames()
        if v not in _SKIP_VARS and root.OpenMDArray(v).GetDimensionCount() == 2
    ]

    records: dict[str, np.ndarray] = {id_name: np.tile(ids, n_times)}
    for var in data_vars:
        records[var] = root.OpenMDArray(var).ReadAsArray().ravel()

    repeat_time = np.repeat(np.arange(n_times), n_ids)
    df = pd.DataFrame(records, index=time_index[repeat_time])
    units = _read_units(root, data_vars)
    return df, units


def read_basin_nc(path: Path) -> tuple[pd.DataFrame, dict[str, str]] | None:
    """Read basin.nc → DataFrame with DatetimeIndex.

    Columns: node_id, level, storage, inflow_rate, outflow_rate, …
    Index: DatetimeIndex (one row per time x node_id combination).
    """
    return _read_2d_nc(path, "node_id")


def read_flow_nc(path: Path) -> tuple[pd.DataFrame, dict[str, str]] | None:
    """Read flow.nc → DataFrame with DatetimeIndex.

    Columns: link_id, flow_rate, convergence
    Index: DatetimeIndex (one row per time x link_id combination).
    """
    return _read_2d_nc(path, "link_id")


def read_concentration_nc(path: Path) -> tuple[pd.DataFrame, dict[str, str]] | None:
    """Read concentration.nc → wide-format DataFrame.

    The raw data has shape (time, node_id, substance).
    This pivots to wide format with substance names as columns.

    Columns: node_id, <substance_1>, <substance_2>, …
    Index: DatetimeIndex.
    """
    root = _open_netcdf(path)
    if root is None:
        return None

    time_index = _read_time(root)
    node_ids = root.OpenMDArray("node_id").ReadAsArray()
    n_times = len(time_index)
    n_nodes = len(node_ids)

    # Read substance names (string array — use Read() instead of ReadAsArray())
    substances = root.OpenMDArray("substance").Read()

    # Read concentration: shape (time, node_id, substance)
    conc = root.OpenMDArray("concentration").ReadAsArray()

    records: dict[str, np.ndarray] = {"node_id": np.tile(node_ids, n_times)}
    for i, sub in enumerate(substances):
        records[sub] = conc[:, :, i].ravel()

    repeat_time = np.repeat(np.arange(n_times), n_nodes)
    df = pd.DataFrame(records, index=time_index[repeat_time])
    conc_unit = root.OpenMDArray("concentration").GetUnit()
    units = dict.fromkeys(substances, conc_unit) if conc_unit else {}
    return df, units
