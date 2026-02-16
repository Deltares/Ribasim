"""
Read Ribasim NetCDF result files using the GDAL Multidimensional Raster API.

Return lightweight ``NetCDFResult`` dataclasses that keep data in their
natural 2-D NumPy shape (n_times x n_ids).
"""

from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path

import numpy as np
import pandas as pd
from osgeo import gdal


@dataclass
class NetCDFResult:
    """Container for a single NetCDF result file.

    Attributes
    ----------
    time:
        DatetimeIndex of shape (n_times,).
    ids:
        1-D array of node_id or link_id values, shape (n_ids,).
    variables:
        Mapping from variable name to its 2-D array (n_times, n_ids).
    units:
        Mapping from variable name to its unit string.
    """

    time: pd.DatetimeIndex
    ids: np.ndarray
    variables: dict[str, np.ndarray]
    units: dict[str, str]


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
    """Open a NetCDF file with GDAL multidimensional API. Return root group or None."""
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


def _read_2d_nc(path: Path, id_name: str) -> NetCDFResult | None:
    """Read a 2-D NetCDF result file (time x id) into a NetCDFResult.

    Works for both basin.nc (id_name="node_id") and flow.nc (id_name="link_id").
    """
    root = _open_netcdf(path)
    if root is None:
        return None

    time_index = _read_time(root)
    ids = root.OpenMDArray(id_name).ReadAsArray()

    data_vars = [
        v
        for v in root.GetMDArrayNames()
        if v not in _SKIP_VARS and root.OpenMDArray(v).GetDimensionCount() == 2
    ]

    variables: dict[str, np.ndarray] = {}
    for var in data_vars:
        variables[var] = root.OpenMDArray(var).ReadAsArray()  # (n_times, n_ids)

    units = _read_units(root, data_vars)
    return NetCDFResult(time=time_index, ids=ids, variables=variables, units=units)


def read_basin_nc(path: Path) -> NetCDFResult | None:
    """Read basin.nc into a NetCDFResult.

    Shape per variable: (n_times, n_node_ids).
    """
    return _read_2d_nc(path, "node_id")


def read_flow_nc(path: Path) -> NetCDFResult | None:
    """Read flow.nc into a NetCDFResult.

    Shape per variable: (n_times, n_link_ids).
    """
    return _read_2d_nc(path, "link_id")


def read_concentration_nc(path: Path) -> NetCDFResult | None:
    """Read concentration.nc into a NetCDFResult.

    The raw data has shape (time, node_id, substance).
    Each substance becomes a separate variable with shape (n_times, n_node_ids).
    """
    root = _open_netcdf(path)
    if root is None:
        return None

    time_index = _read_time(root)
    node_ids = root.OpenMDArray("node_id").ReadAsArray()

    # Read substance names (string array — use Read() instead of ReadAsArray())
    substances: list[str] = root.OpenMDArray("substance").Read()

    # Read concentration: shape (time, node_id, substance)
    conc = root.OpenMDArray("concentration").ReadAsArray()

    variables: dict[str, np.ndarray] = {}
    for i, sub in enumerate(substances):
        variables[sub] = conc[:, :, i]  # (n_times, n_node_ids) — no copy needed

    conc_unit = root.OpenMDArray("concentration").GetUnit()
    units = dict.fromkeys(substances, conc_unit) if conc_unit else {}
    return NetCDFResult(time=time_index, ids=node_ids, variables=variables, units=units)
