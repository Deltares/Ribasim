from collections.abc import Callable
from datetime import datetime

import geopandas as gpd
import pandas as pd
from ribasim import Model
from ribasim.config import Experimental, Results
from ribasim.merge import _merge_models

from ribasim_testmodels.allocation import (
    cyclic_demand_model,
    flow_demand_model,
    level_demand_model,
    polder_management_model,
)
from ribasim_testmodels.basic import (
    basic_basin_both_area_and_storage_model,
    basic_model,
    tabulated_rating_curve_model,
)
from ribasim_testmodels.continuous_control import outlet_continuous_control_model
from ribasim_testmodels.discrete_control import (
    concentration_condition_model,
    connector_node_flow_condition_model,
    level_range_model,
    storage_condition_model,
    transient_condition_model,
)
from ribasim_testmodels.junction import junction_combined
from ribasim_testmodels.observation import observation_model
from ribasim_testmodels.pid_control import (
    discrete_control_of_pid_control_model,
    pid_control_model,
)
from ribasim_testmodels.time import transient_pump_outlet_model
from ribasim_testmodels.two_basin import two_basin_model

# Together these cover all node types and input tables, except the NetCDF inputs
PHYSICAL_COMPONENTS: list[Callable[[], Model]] = [
    basic_model,
    basic_basin_both_area_and_storage_model,
    tabulated_rating_curve_model,
    two_basin_model,
    junction_combined,
    observation_model,
    pid_control_model,
    discrete_control_of_pid_control_model,
    level_range_model,
    storage_condition_model,
    concentration_condition_model,
    connector_node_flow_condition_model,
    transient_condition_model,
    outlet_continuous_control_model,
    transient_pump_outlet_model,
]

# Each with subnetworks without a primary network, since a model with a primary network
# can't have other subnetworks that are not connected to it. Primary and secondary
# networks are covered by also running medium_primary_secondary_network in the workload.
ALLOCATION_COMPONENTS: list[Callable[[], Model]] = [
    cyclic_demand_model,
    level_demand_model,
    flow_demand_model,
    polder_management_model,
]

CRS = "EPSG:28992"


def _node_df(model: Model) -> gpd.GeoDataFrame:
    df = model.node.df
    assert df is not None
    return df


def precompile_workload_model() -> Model:
    """
    Model that runs in the precompile workload of Ribasim, without allocation.

    Code that is compiled while running this model is cached, and reused for other
    models. Therefore it combines many test models as separate parts of one network, to
    cover all node types and input tables, with the default solver and interpolation
    settings.
    """
    components = [f() for f in PHYSICAL_COMPONENTS]
    for component in components:
        _node_df(component)["subnetwork_id"] = pd.NA
    model = Model(
        starttime=datetime(2020, 1, 1),
        endtime=datetime(2020, 1, 20),
        crs=CRS,
        experimental=Experimental(concentration=True),
        results=Results(subgrid=True),
    )
    return _merge_models(components, model)


def precompile_workload_allocation_model() -> Model:
    """
    Model that runs in the precompile workload of Ribasim, with allocation.

    Like `precompile_workload_model`, but it combines test models with all demand node
    types in allocation subnetworks.
    """
    components = [f() for f in ALLOCATION_COMPONENTS]
    for component in components:
        # Nodes without a subnetwork ID are in the primary network, make it a subnetwork
        node = _node_df(component)
        node["subnetwork_id"] = node["subnetwork_id"].fillna(1).astype("Int32")
    model = Model(
        starttime=datetime(2020, 1, 1),
        endtime=datetime(2020, 1, 20),
        crs=CRS,
        experimental=Experimental(concentration=True, allocation=True),
    )
    return _merge_models(components, model)
