from pathlib import Path

import pytest
import ribasim
from ribasim_testmodels import (
    PID_control_model_1,
    backwater_model,
    basic_model,
    basic_transient_model,
    bucket_model,
    pump_control_model,
    tabulated_rating_curve_model,
    trivial_model,
)


# we can't call fixtures directly, so we keep separate versions
@pytest.fixture()
def basic() -> ribasim.Model:
    return basic_model()


@pytest.fixture()
def basic_transient(basic) -> ribasim.Model:
    return basic_transient_model(basic)


@pytest.fixture()
def tabulated_rating_curve() -> ribasim.Model:
    return tabulated_rating_curve_model()


@pytest.fixture()
def backwater() -> ribasim.Model:
    return backwater_model()


# write models to disk for Julia tests to use
if __name__ == "__main__":
    datadir = Path("data")
    trivial_model().write(datadir / "trivial")
    bucket_model().write(datadir / "bucket")
    basic_model().write(datadir / "basic")
    basic_transient_model(basic_model()).write(datadir / "basic-transient")
    tabulated_rating_curve_model().write(datadir / "tabulated_rating_curve")
    pump_control_model().write(datadir / "pump_control")
    backwater_model().write(datadir / "backwater")
    PID_control_model_1().write(datadir / "pid_1")
