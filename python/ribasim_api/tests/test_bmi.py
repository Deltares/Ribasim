import re

import numpy as np
import pytest
from numpy.testing import assert_array_almost_equal
from xmipy.errors import XMIError


def test_initialize(libribasim, basic, tmp_path):
    basic.write(tmp_path)
    config_file = str(tmp_path / f"{basic.modelname}.toml")
    libribasim.initialize(config_file)


def test_get_current_time(libribasim, basic, tmp_path):
    basic.write(tmp_path)
    config_file = str(tmp_path / f"{basic.modelname}.toml")
    libribasim.initialize(config_file)
    time = libribasim.get_current_time()
    assert time == 0.0


def test_update(libribasim, basic, tmp_path):
    basic.write(tmp_path)
    config_file = str(tmp_path / f"{basic.modelname}.toml")
    libribasim.initialize(config_file)
    libribasim.update()
    time = libribasim.get_current_time()
    assert time > 0.0


@pytest.mark.skip(
    reason="update_until not in xmipy, see https://github.com/Deltares/xmipy/issues/92"
)
def test_update_until(libribasim, basic, tmp_path):
    basic.write(tmp_path)
    config_file = str(tmp_path / f"{basic.modelname}.toml")
    libribasim.initialize(config_file)
    expected_time = 60.0
    libribasim.update_until(expected_time)
    actual_time = libribasim.get_current_time()
    assert actual_time == expected_time


def test_get_var_type(libribasim, basic, tmp_path):
    basic.write(tmp_path)
    config_file = str(tmp_path / f"{basic.modelname}.toml")
    libribasim.initialize(config_file)
    var_type = libribasim.get_var_type("volume")
    assert var_type == "double"


@pytest.mark.skip(reason="get_value_ptr doesn't work yet")
def test_get_value_ptr(libribasim, basic, tmp_path):
    basic.write(tmp_path)
    config_file = str(tmp_path / f"{basic.modelname}.toml")
    libribasim.initialize(config_file)
    actual_volume = libribasim.get_value_ptr("volume")
    expected_volume = np.array([1.0, 1.0, 1.0])
    assert_array_almost_equal(actual_volume, expected_volume)


def test_err_unknown_var(libribasim, basic, tmp_path):
    """Unknown or invalid variable address should trigger Python Exception,
    print the kernel error, and not crash the library"""
    basic.write(tmp_path)
    config_file = str(tmp_path / f"{basic.modelname}.toml")
    libribasim.initialize(config_file)

    variable_name = "var-that-does-not-exist"
    error_message = re.escape(
        f"BMI exception in get_var_type (for variable {variable_name}):"
        " Message from Ribasim '"
        f"Unknown variable {variable_name}'"
    )
    with pytest.raises(XMIError, match=error_message):
        libribasim.get_var_type(variable_name)


def test_get_component_name(libribasim):
    assert libribasim.get_component_name() == "Ribasim"
