"""Tests for ribasim_qgis.core.netcdf — reading Ribasim NetCDF result files."""

import numpy as np
import pandas as pd

from ribasim_qgis.core.netcdf import (
    NetCDFResult,
    read_basin_nc,
    read_concentration_nc,
    read_flow_nc,
)

# --- read_basin_nc ---


def test_read_basin_nc_returns_result(results_dir):
    result = read_basin_nc(results_dir / "basin.nc")
    assert isinstance(result, NetCDFResult)


def test_read_basin_nc_time(results_dir):
    result = read_basin_nc(results_dir / "basin.nc")
    assert isinstance(result.time, pd.DatetimeIndex)
    assert len(result.time) == 4
    assert result.time[0] == pd.Timestamp("2020-01-03")
    assert result.time[-1] == pd.Timestamp("2020-01-06")


def test_read_basin_nc_ids(results_dir):
    result = read_basin_nc(results_dir / "basin.nc")
    np.testing.assert_array_equal(result.ids, [1, 3, 6])


def test_read_basin_nc_variables(results_dir):
    result = read_basin_nc(results_dir / "basin.nc")
    assert set(result.variables.keys()) == {"level", "storage"}
    assert result.variables["level"].shape == (4, 3)
    assert result.variables["storage"].shape == (4, 3)
    np.testing.assert_allclose(result.variables["storage"], 100.0)


def test_read_basin_nc_units(results_dir):
    result = read_basin_nc(results_dir / "basin.nc")
    assert result.units["level"] == "m"
    assert result.units["storage"] == "m3"


# --- read_flow_nc ---


def test_read_flow_nc_returns_result(results_dir):
    result = read_flow_nc(results_dir / "flow.nc")
    assert isinstance(result, NetCDFResult)


def test_read_flow_nc_ids(results_dir):
    result = read_flow_nc(results_dir / "flow.nc")
    np.testing.assert_array_equal(result.ids, [10, 20])


def test_read_flow_nc_variables(results_dir):
    result = read_flow_nc(results_dir / "flow.nc")
    assert "flow_rate" in result.variables
    assert result.variables["flow_rate"].shape == (4, 2)
    np.testing.assert_allclose(result.variables["flow_rate"], 5.0)


def test_read_flow_nc_units(results_dir):
    result = read_flow_nc(results_dir / "flow.nc")
    assert result.units["flow_rate"] == "m3 s-1"


# --- read_concentration_nc ---


def test_read_concentration_nc_returns_result(results_dir):
    result = read_concentration_nc(results_dir / "concentration.nc")
    assert isinstance(result, NetCDFResult)


def test_read_concentration_nc_substances(results_dir):
    result = read_concentration_nc(results_dir / "concentration.nc")
    assert set(result.variables.keys()) == {"Cl", "tracer"}


def test_read_concentration_nc_shape(results_dir):
    result = read_concentration_nc(results_dir / "concentration.nc")
    for var in result.variables.values():
        assert var.shape == (4, 3)  # (n_times, n_node_ids)


def test_read_concentration_nc_ids(results_dir):
    result = read_concentration_nc(results_dir / "concentration.nc")
    np.testing.assert_array_equal(result.ids, [1, 3, 6])


def test_read_concentration_nc_units(results_dir):
    result = read_concentration_nc(results_dir / "concentration.nc")
    assert result.units["Cl"] == "mg L-1"
    assert result.units["tracer"] == "mg L-1"


# --- Missing / invalid files ---


def test_read_basin_nc_missing_file(tmp_path):
    assert read_basin_nc(tmp_path / "nonexistent.nc") is None


def test_read_flow_nc_missing_file(tmp_path):
    assert read_flow_nc(tmp_path / "nonexistent.nc") is None


def test_read_concentration_nc_missing_file(tmp_path):
    assert read_concentration_nc(tmp_path / "nonexistent.nc") is None
