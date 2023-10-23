__version__ = "0.2.0"

from typing import Callable, Dict

import ribasim

import ribasim_testmodels
from ribasim_testmodels.allocation import (
    # looped_subnetwork_model,
    user_model,
)
from ribasim_testmodels.backwater import backwater_model
from ribasim_testmodels.basic import (
    basic_model,
    basic_transient_model,
    outlet_model,
    tabulated_rating_curve_model,
)
from ribasim_testmodels.bucket import bucket_model
from ribasim_testmodels.discrete_control import (
    flow_condition_model,
    level_boundary_condition_model,
    level_setpoint_with_minmax_model,
    pump_discrete_control_model,
    tabulated_rating_curve_control_model,
)
from ribasim_testmodels.dutch_waterways import dutch_waterways_model
from ribasim_testmodels.equations import (
    linear_resistance_model,
    manning_resistance_model,
    misc_nodes_model,
    pid_control_equation_model,
    rating_curve_model,
)
from ribasim_testmodels.invalid import (
    invalid_discrete_control_model,
    invalid_edge_types_model,
    invalid_fractional_flow_model,
    invalid_qh_model,
)
from ribasim_testmodels.pid_control import (
    discrete_control_of_pid_control_model,
    pid_control_model,
)
from ribasim_testmodels.time import flow_boundary_time_model
from ribasim_testmodels.trivial import trivial_model

__all__ = [
    "backwater_model",
    "basic_model",
    "basic_transient_model",
    "bucket_model",
    "pump_discrete_control_model",
    "flow_condition_model",
    "tabulated_rating_curve_model",
    "trivial_model",
    "linear_resistance_model",
    "rating_curve_model",
    "manning_resistance_model",
    "pid_control_model",
    "misc_nodes_model",
    "tabulated_rating_curve_control_model",
    "dutch_waterways_model",
    "invalid_qh_model",
    "flow_boundary_time_model",
    "pid_control_equation_model",
    "invalid_fractional_flow_model",
    "invalid_discrete_control_model",
    "level_setpoint_with_minmax_model",
    "invalid_edge_types_model",
    "discrete_control_of_pid_control_model",
    "level_boundary_condition_model",
    "outlet_model",
    "user_model",
    # Disable until this issue is resolved:
    # https://github.com/Deltares/Ribasim/issues/692
    # "looped_subnetwork_model",
]

# provide a mapping from model name to its constructor, so we can iterate over all models
constructors: Dict[str, Callable[[], ribasim.Model]] = {}
for model_name_model in __all__:
    model_name = model_name_model.removesuffix("_model")
    model_constructor = getattr(ribasim_testmodels, model_name_model)
    constructors[model_name] = model_constructor
