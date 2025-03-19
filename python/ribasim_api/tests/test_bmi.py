import re
from pathlib import Path

import numpy as np
import pytest
import tomli
from numpy.testing import assert_array_almost_equal
from xmipy.errors import XMIError


def test_initialize(libribasim, basic, tmp_path):
    basic.write(tmp_path / "ribasim.toml")
    config_file = str(tmp_path / "ribasim.toml")
    libribasim.initialize(config_file)


def test_get_start_time(libribasim, basic, tmp_path):
    basic.write(tmp_path / "ribasim.toml")
    config_file = str(tmp_path / "ribasim.toml")
    libribasim.initialize(config_file)
    time = libribasim.get_start_time()
    assert time == pytest.approx(0.0)


def test_get_current_time(libribasim, basic, tmp_path):
    basic.write(tmp_path / "ribasim.toml")
    config_file = str(tmp_path / "ribasim.toml")
    libribasim.initialize(config_file)
    assert libribasim.get_current_time() == pytest.approx(libribasim.get_start_time())


def test_get_end_time(libribasim, basic, tmp_path):
    basic.write(tmp_path / "ribasim.toml")
    config_file = str(tmp_path / "ribasim.toml")
    libribasim.initialize(config_file)
    actual_end_time = libribasim.get_end_time()
    excepted_end_time = (basic.endtime - basic.starttime).total_seconds()
    assert actual_end_time == pytest.approx(excepted_end_time)


def test_update(libribasim, basic, tmp_path):
    basic.write(tmp_path / "ribasim.toml")
    config_file = str(tmp_path / "ribasim.toml")
    libribasim.initialize(config_file)
    libribasim.update()
    time = libribasim.get_current_time()
    assert time > 0.0


def test_update_until(libribasim, basic, tmp_path):
    basic.write(tmp_path / "ribasim.toml")
    config_file = str(tmp_path / "ribasim.toml")
    libribasim.initialize(config_file)
    expected_time = 60.0
    libribasim.update_until(expected_time)
    actual_time = libribasim.get_current_time()
    assert actual_time == pytest.approx(expected_time)


def test_update_subgrid_level(libribasim, basic, tmp_path):
    basic.write(tmp_path / "ribasim.toml")
    config_file = str(tmp_path / "ribasim.toml")
    libribasim.initialize(config_file)
    libribasim.update_subgrid_level()
    level = libribasim.get_value_ptr("basin.subgrid_level")
    # The subgrid levels are initialized with NaN.
    # After calling update, they should have regular values.
    assert np.isfinite(level).all()


def test_get_var_type(libribasim, basic, tmp_path):
    basic.write(tmp_path / "ribasim.toml")
    config_file = str(tmp_path / "ribasim.toml")
    libribasim.initialize(config_file)
    var_type = libribasim.get_var_type("basin.storage")
    assert var_type == "double"


def test_get_var_rank(libribasim, basic, tmp_path):
    basic.write(tmp_path / "ribasim.toml")
    config_file = str(tmp_path / "ribasim.toml")
    libribasim.initialize(config_file)
    actual_rank = libribasim.get_var_rank("basin.storage")
    expected_rank = 1
    assert_array_almost_equal(actual_rank, expected_rank)


def test_get_var_shape(libribasim, basic, tmp_path):
    basic.write(tmp_path / "ribasim.toml")
    config_file = str(tmp_path / "ribasim.toml")
    libribasim.initialize(config_file)
    actual_shape = libribasim.get_var_shape("basin.storage")
    expected_shape = np.array([4])
    assert_array_almost_equal(actual_shape, expected_shape)


def test_get_value_ptr_basin(libribasim, basic, tmp_path):
    basic.write(tmp_path / "ribasim.toml")
    config_file = str(tmp_path / "ribasim.toml")
    libribasim.initialize(config_file)

    # Storage
    actual_volume = libribasim.get_value_ptr("basin.storage")
    expected_volume = np.array([1.0, 1.0, 1.0, 1.0])
    assert_array_almost_equal(actual_volume, expected_volume)

    # Level
    actual_level = libribasim.get_value_ptr("basin.level")
    expected_level = np.array(4 * [0.04471158417652035])
    assert_array_almost_equal(actual_level, expected_level)


def test_get_value_ptr_subgrid(libribasim, two_basin, tmp_path):
    two_basin.write(tmp_path / "ribasim.toml")
    config_file = str(tmp_path / "ribasim.toml")
    libribasim.initialize(config_file)

    # Run model until subgrid level is updated
    libribasim.update_until(86400.0)

    # Subgrid level
    libribasim.update_subgrid_level()
    actual_subgrid_level = libribasim.get_value_ptr("basin.subgrid_level")
    expected_subgrid_level = np.array([2.17, 0.006142])
    assert_array_almost_equal(actual_subgrid_level, expected_subgrid_level)


def test_get_value_ptr_basin_forcing(libribasim, leaky_bucket, tmp_path):
    leaky_bucket.write(tmp_path / "ribasim.toml")
    config_file = str(tmp_path / "ribasim.toml")
    libribasim.initialize(config_file)

    # Infiltration (instantaneous)
    actual_infiltration = libribasim.get_value_ptr("basin.infiltration")
    expected_infiltration = np.array([0.0])
    assert_array_almost_equal(actual_infiltration, expected_infiltration)

    # Drainage (instantaneous)
    actual_drainage = libribasim.get_value_ptr("basin.drainage")
    expected_drainage = np.array([0.003])
    assert_array_almost_equal(actual_drainage, expected_drainage)

    # Run model for a while to build up integrated forcing
    libribasim.update_until(60.0)

    # Cumulative infiltration
    actual_infiltration = libribasim.get_value_ptr("basin.cumulative_infiltration")
    expected_infiltration = np.array([0.0])
    assert_array_almost_equal(actual_infiltration, expected_infiltration)

    # Cumulative drainage
    actual_drainage = libribasim.get_value_ptr("basin.cumulative_drainage")
    expected_drainage = np.array([0.003 * 60.0])
    assert_array_almost_equal(actual_drainage, expected_drainage)


def test_get_value_ptr_allocation(libribasim, user_demand, tmp_path):
    user_demand.write(tmp_path / "ribasim.toml")
    config_file = str(tmp_path / "ribasim.toml")
    libribasim.initialize(config_file)

    # Demand
    actual_demand = libribasim.get_value_ptr("user_demand.demand")
    expected_demand = np.array([1e-4, 0.0, 0.0])
    assert_array_almost_equal(actual_demand, expected_demand)

    # Run model for a while to build up realized
    libribasim.update_until(60.0)

    # Realized inflow
    actual_inflow = libribasim.get_value_ptr("user_demand.cumulative_inflow")
    expected_inflow = np.array([1e-4 * 60.0, 0.0, 0.0])
    assert_array_almost_equal(actual_inflow, expected_inflow)


def test_err_unknown_var(libribasim, basic, tmp_path):
    """
    Unknown or invalid variable address.

    Should trigger Python Exception, print the kernel error, and not crash the library.
    """
    basic.write(tmp_path / "ribasim.toml")
    config_file = str(tmp_path / "ribasim.toml")
    libribasim.initialize(config_file)

    variable_name = "unknown_node.unknown_variable"
    error_message = re.escape(
        f"BMI exception in get_var_type (for variable {variable_name}):"
        " Message from Ribasim "
        f"'Unknown variable {variable_name}'"
    )
    with pytest.raises(XMIError, match=error_message):
        libribasim.get_var_type(variable_name)


def test_get_component_name(libribasim):
    assert libribasim.get_component_name() == "Ribasim"


def test_get_version(libribasim):
    toml_path = Path(__file__).parents[3] / "core" / "Project.toml"
    with open(toml_path, mode="rb") as fp:
        config = tomli.load(fp)

    assert libribasim.get_version() == config["version"]


def test_execute(libribasim, basic, tmp_path):
    basic.write(tmp_path / "ribasim.toml")
    config_file = str(tmp_path / "ribasim.toml")
    libribasim.execute(config_file)
