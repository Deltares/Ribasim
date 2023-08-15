from pathlib import Path

import pytest
import ribasim
from ribasim_testmodels import (
    backwater_model,
    basic_model,
    basic_transient_model,
    bucket_model,
    dutch_waterways_model,
    flow_boundary_time_model,
    flow_condition_model,
    invalid_control_states_model,
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

    models = [
        model_generator()
        for model_generator in (
            backwater_model,
            basic_model,
            bucket_model,
            dutch_waterways_model,
            flow_boundary_time_model,
            flow_condition_model,
            invalid_control_states_model,
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
    ]

    for model in models:
        model.write(datadir / model.modelname)

        if model.modelname == "basic":
            model = basic_transient_model(model)
            model.write(datadir / model.modelname)
