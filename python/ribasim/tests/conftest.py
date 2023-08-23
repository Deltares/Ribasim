from pathlib import Path

import pytest
import ribasim
from ribasim_testmodels import (
    backwater_model,
    basic_model,
    basic_transient_model,
    bucket_model,
    discrete_control_of_pid_control_model,
    flow_boundary_time_model,
    flow_condition_model,
    invalid_discrete_control_model,
    invalid_edge_types_model,
    invalid_fractional_flow_model,
    invalid_qh_model,
    level_setpoint_with_minmax_model,
    linear_resistance_model,
    manning_resistance_model,
    misc_nodes_model,
    pid_control_equation_model,
    pid_control_model,
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
    basic_transient_model(basic_model()).write(datadir / "basic_transient")
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
    pid_control_model().write(datadir / "pid_control")
    misc_nodes_model().write(datadir / "misc_nodes")
    invalid_qh_model().write(datadir / "invalid_qh")
    invalid_fractional_flow_model().write(datadir / "invalid_fractional_flow")
    flow_boundary_time_model().write(datadir / "flow_boundary_time")
    level_setpoint_with_minmax_model().write(datadir / "level_setpoint_with_minmax")
    pid_control_equation_model().write(datadir / "pid_control_equation")
    invalid_discrete_control_model().write(datadir / "invalid_discrete_control")
    invalid_edge_types_model().write(datadir / "invalid_edge_types")
    discrete_control_of_pid_control_model().write(
        datadir / "discrete_control_of_pid_control"
    )
