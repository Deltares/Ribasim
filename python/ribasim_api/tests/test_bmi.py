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


def test_update_until(ribasim_basic):
    libribasim, config_file = ribasim_basic
    libribasim.initialize(config_file)
    libribasim.update_until(60.0)
    time = libribasim.get_current_time()
    assert time == 60.0


def test_get_var_type(ribasim_basic):
    libribasim, config_file = ribasim_basic
    libribasim.initialize(config_file)
    var_type = libribasim.get_var_type("volume")
    assert var_type == "double"


def test_get_value_ptr(ribasim_basic):
    libribasim, config_file = ribasim_basic
    libribasim.initialize(config_file)
    actual_volume = libribasim.get_value_ptr("volume")
    expected_volume = np.array([1.0, 1.0, 1.0])
    assert_array_almost_equal(actual_volume, expected_volume)
