from pathlib import Path

import pytest
import ribasim
from ribasim_testmodels import (
    backwater_model,
    basic_model,
    basic_transient_model,
    bucket_model,
    conditions_on_discrete_flow_model,
    crossing_specific_control_model,
    flow_boundary_time_model,
    flow_condition_model,
    invalid_qh_model,
    linear_resistance_model,
    manning_resistance_model,
    miscellaneous_nodes_model,
    pid_control_model_1,
    pump_discrete_control_model,
    rating_curve_model,
    tabulated_rating_curve_control_model,
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
    tabulated_rating_curve_control_model().write(
        datadir / "tabulated_rating_curve_control"
    )
    pump_discrete_control_model().write(datadir / "pump_discrete_control")
    flow_condition_model().write(datadir / "flow_condition")
    backwater_model().write(datadir / "backwater")
    linear_resistance_model().write(datadir / "linear_resistance")
    rating_curve_model().write(datadir / "rating_curve")
    manning_resistance_model().write(datadir / "manning_resistance")
    pid_control_model_1().write(datadir / "pid_1")
    miscellaneous_nodes_model().write(datadir / "misc_nodes")
    invalid_qh_model().write(datadir / "invalid_qh")
    flow_boundary_time_model().write(datadir / "flow_boundary_time")
    crossing_specific_control_model().write(datadir / "crossing_specific_control")
    conditions_on_discrete_flow_model().write(datadir / "conditions_on_discrete_flow")
