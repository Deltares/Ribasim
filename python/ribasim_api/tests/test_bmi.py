import numpy as np
import pytest
from numpy.testing import assert_array_almost_equal


def test_initialize(ribasim_basic):
    libribasim, config_file = ribasim_basic
    libribasim.initialize(config_file)


def test_get_current_time(ribasim_basic):
    libribasim, config_file = ribasim_basic
    libribasim.initialize(config_file)
    time = libribasim.get_current_time()
    assert time == 0.0


def test_update(ribasim_basic):
    libribasim, config_file = ribasim_basic
    libribasim.initialize(config_file)
    libribasim.update()
    time = libribasim.get_current_time()
    assert time > 0.0


@pytest.mark.skip(
    reason="update_until not in xmipy, see https://github.com/Deltares/xmipy/issues/92"
)
def test_update_until(ribasim_basic):
    libribasim, config_file = ribasim_basic
    libribasim.initialize(config_file)
    expected_time = 60.0
    libribasim.update_until(expected_time)
    actual_time = libribasim.get_current_time()
    assert actual_time == expected_time


def test_get_var_type(ribasim_basic):
    libribasim, config_file = ribasim_basic
    libribasim.initialize(config_file)
    var_type = libribasim.get_var_type("volume")
    assert var_type == "double"


@pytest.mark.skip(reason="get_value_ptr doesn't work yet")
def test_get_value_ptr(ribasim_basic):
    libribasim, config_file = ribasim_basic
    libribasim.initialize(config_file)
    actual_volume = libribasim.get_value_ptr("volume")
    expected_volume = np.array([1.0, 1.0, 1.0])
    assert_array_almost_equal(actual_volume, expected_volume)
