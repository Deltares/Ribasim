from pathlib import Path

import pytest
import ribasim
from ribasim_testmodels import (
    backwater_model,
    basic_model,
    basic_transient_model,
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

    model = trivial_model()
    model.write(datadir / "trivial")

    model = basic_model()
    model.write(datadir / "basic")

    model = basic_transient_model(model)
    model.write(datadir / "basic-transient")

    model = tabulated_rating_curve_model()
    model.write(datadir / "tabulated_rating_curve")

    model = pump_control_model()
    model.write(datadir / "pump_control")

    model = backwater_model()
    model.write(datadir / "backwater")