"""Shared fixtures for QGIS plugin tests."""

from pathlib import Path

import netCDF4 as nc4
import numpy as np
import pytest


@pytest.fixture
def results_dir(tmp_path: Path) -> Path:
    """Create a temporary results directory with minimal NetCDF result files.

    Files created:
    - basin.nc   (time x node_id)   with variables: level, storage
    - flow.nc    (time x link_id)   with variable: flow_rate
    - concentration.nc  (time x node_id x substance) with substances: Cl, tracer
    """
    _create_basin_nc(tmp_path / "basin.nc")
    _create_flow_nc(tmp_path / "flow.nc")
    _create_concentration_nc(tmp_path / "concentration.nc")
    return tmp_path


# --- Helpers ---

_N_TIMES = 4
_NODE_IDS = np.array([1, 3, 6], dtype=np.int32)
_LINK_IDS = np.array([10, 20], dtype=np.int32)
# Days since 1900-01-01: corresponds to 2020-01-01 through 2020-01-04
_TIME_VALUES = np.array([43831.0, 43832.0, 43833.0, 43834.0], dtype=np.float64)
_TIME_UNITS = "days since 1900-01-01 00:00:00"


def _create_basin_nc(path: Path) -> None:
    with nc4.Dataset(str(path), "w") as ds:
        ds.createDimension("time", _N_TIMES)
        ds.createDimension("node_id", len(_NODE_IDS))

        t = ds.createVariable("time", "f8", ("time",))
        t[:] = _TIME_VALUES
        t.units = _TIME_UNITS

        nid = ds.createVariable("node_id", "i4", ("node_id",))
        nid[:] = _NODE_IDS

        level = ds.createVariable("level", "f8", ("time", "node_id"))
        level[:] = np.arange(_N_TIMES * len(_NODE_IDS), dtype=np.float64).reshape(
            _N_TIMES, len(_NODE_IDS)
        )
        level.units = "m"

        storage = ds.createVariable("storage", "f8", ("time", "node_id"))
        storage[:] = np.ones((_N_TIMES, len(_NODE_IDS)), dtype=np.float64) * 100.0
        storage.units = "m3"


def _create_flow_nc(path: Path) -> None:
    with nc4.Dataset(str(path), "w") as ds:
        ds.createDimension("time", _N_TIMES)
        ds.createDimension("link_id", len(_LINK_IDS))

        t = ds.createVariable("time", "f8", ("time",))
        t[:] = _TIME_VALUES
        t.units = _TIME_UNITS

        lid = ds.createVariable("link_id", "i4", ("link_id",))
        lid[:] = _LINK_IDS

        fr = ds.createVariable("flow_rate", "f8", ("time", "link_id"))
        fr[:] = np.full((_N_TIMES, len(_LINK_IDS)), 5.0)
        fr.units = "m3 s-1"


def _create_concentration_nc(path: Path) -> None:
    substances = ["Cl", "tracer"]
    with nc4.Dataset(str(path), "w") as ds:
        ds.createDimension("time", _N_TIMES)
        ds.createDimension("node_id", len(_NODE_IDS))
        ds.createDimension("substance", len(substances))

        t = ds.createVariable("time", "f8", ("time",))
        t[:] = _TIME_VALUES
        t.units = _TIME_UNITS

        nid = ds.createVariable("node_id", "i4", ("node_id",))
        nid[:] = _NODE_IDS

        sub = ds.createVariable("substance", str, ("substance",))
        for i, name in enumerate(substances):
            sub[i] = name

        conc = ds.createVariable(
            "concentration", "f8", ("time", "node_id", "substance")
        )
        conc[:] = np.arange(
            _N_TIMES * len(_NODE_IDS) * len(substances), dtype=np.float64
        ).reshape(_N_TIMES, len(_NODE_IDS), len(substances))
        conc.units = "mg L-1"
