__version__ = "2024.4.0"

from collections.abc import Callable

from ribasim.model import Model

import ribasim_testmodels
from ribasim_testmodels.allocation import (
    allocation_control_model,
    allocation_example_model,
    allocation_off_flow_demand_model,
    allocation_training_model,
    bommelerwaard_model,
    cyclic_demand_model,
    drain_surplus_model,
    fair_distribution_model,
    flow_demand_model,
    invalid_infeasible_model,
    level_demand_model,
    linear_resistance_demand_model,
    looped_subnetwork_model,
    minimal_subnetwork_model,
    multi_level_demand_model,
    multi_priority_flow_demand_model,
    multiple_source_priorities_model,
    primary_and_secondary_subnetworks_model,
    secondary_networks_with_sources_model,
    small_primary_secondary_network_model,
    small_primary_secondary_network_verification_model,
    subnetwork_model,
    user_demand_model,
)
from ribasim_testmodels.backwater import backwater_model
from ribasim_testmodels.basic import (
    basic_arrow_model,
    basic_basin_both_area_and_storage_model,
    basic_basin_only_area_model,
    basic_basin_only_storage_model,
    basic_model,
    basic_transient_model,
    cyclic_time_model,
    drought_model,
    flow_boundary_interpolation_model,
    outlet_model,
    tabulated_rating_curve_model,
)
from ribasim_testmodels.bucket import bucket_model, leaky_bucket_model
from ribasim_testmodels.continuous_control import outlet_continuous_control_model
from ribasim_testmodels.discrete_control import (
    circular_flow_model,
    compound_variable_condition_model,
    concentration_condition_model,
    connector_node_flow_condition_model,
    continuous_concentration_condition_model,
    flow_condition_model,
    level_boundary_condition_model,
    level_range_model,
    pump_discrete_control_model,
    storage_condition_model,
    tabulated_rating_curve_control_model,
    transient_condition_model,
)
from ribasim_testmodels.doc_example import local_pidcontrolled_cascade_model
from ribasim_testmodels.equations import (
    linear_resistance_model,
    manning_resistance_model,
    misc_nodes_model,
    pid_control_equation_model,
    rating_curve_between_basins_model,
    rating_curve_model,
)
from ribasim_testmodels.invalid import (
    invalid_discrete_control_model,
    invalid_link_types_model,
    invalid_no_basin_model,
    invalid_priorities_model,
    invalid_qh_model,
    invalid_unstable_model,
)
from ribasim_testmodels.junction import (
    junction_chained,
    junction_combined,
)
from ribasim_testmodels.pid_control import (
    discrete_control_of_pid_control_model,
    pid_control_model,
)
from ribasim_testmodels.time import (
    flow_boundary_time_model,
    transient_pump_outlet_model,
)
from ribasim_testmodels.trivial import trivial_model
from ribasim_testmodels.two_basin import two_basin_model

__all__ = [
    "allocation_control_model",
    "allocation_training_model",
    "allocation_example_model",
    "allocation_off_flow_demand_model",
    "backwater_model",
    "basic_arrow_model",
    "basic_model",
    "basic_basin_only_area_model",
    "basic_basin_only_storage_model",
    "basic_basin_both_area_and_storage_model",
    "basic_transient_model",
    "bommelerwaard_model",
    "bucket_model",
    "circular_flow_model",
    "compound_variable_condition_model",
    "concentration_condition_model",
    "continuous_concentration_condition_model",
    "connector_node_flow_condition_model",
    "cyclic_demand_model",
    "cyclic_time_model",
    "discrete_control_of_pid_control_model",
    "drain_surplus_model",
    "drought_model",
    "fair_distribution_model",
    "flow_boundary_interpolation_model",
    "flow_boundary_time_model",
    "flow_condition_model",
    "flow_demand_model",
    "invalid_infeasible_model",
    "invalid_discrete_control_model",
    "invalid_link_types_model",
    "invalid_no_basin_model",
    "invalid_priorities_model",
    "invalid_qh_model",
    "invalid_unstable_model",
    "junction_combined",
    "junction_chained",
    "leaky_bucket_model",
    "level_boundary_condition_model",
    "level_demand_model",
    "level_range_model",
    "linear_resistance_demand_model",
    "linear_resistance_model",
    "local_pidcontrolled_cascade_model",
    "looped_subnetwork_model",
    "primary_and_secondary_subnetworks_model",
    "manning_resistance_model",
    "minimal_subnetwork_model",
    "misc_nodes_model",
    "multiple_source_priorities_model",
    "multi_level_demand_model",
    "multi_priority_flow_demand_model",
    "outlet_continuous_control_model",
    "outlet_model",
    "pid_control_equation_model",
    "pid_control_model",
    "pump_discrete_control_model",
    "rating_curve_model",
    "rating_curve_between_basins_model",
    "secondary_networks_with_sources_model",
    "small_primary_secondary_network_model",
    "small_primary_secondary_network_verification_model",
    "storage_condition_model",
    "subnetwork_model",
    "tabulated_rating_curve_control_model",
    "tabulated_rating_curve_model",
    "transient_condition_model",
    "transient_pump_outlet_model",
    "trivial_model",
    "two_basin_model",
    "user_demand_model",
]

# provide a mapping from model name to its constructor, so we can iterate over all models
constructors: dict[str, Callable[[], Model]] = {}
for model_name_model in __all__:
    model_name = model_name_model.removesuffix("_model")
    model_constructor = getattr(ribasim_testmodels, model_name_model)
    constructors[model_name] = model_constructor
