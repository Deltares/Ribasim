from collections.abc import Callable
from datetime import datetime

import geopandas as gpd
import pandas as pd
from ribasim import Model
from ribasim.config import Experimental, Results
from ribasim.geometry.node import NodeModel

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

# Larger than the number of nodes and links of any component
ID_OFFSET = 1000
# Distance between the components in the map
X_OFFSET = 1000.0
CRS = "EPSG:28992"


def _shift(df: pd.DataFrame, k: int, columns: list[str]) -> pd.DataFrame:
    df = df.copy()
    for column in columns:
        if column in df.columns:
            df[column] = df[column] + k * ID_OFFSET
    if isinstance(df, gpd.GeoDataFrame):
        # The coordinates of the test models are arbitrary, so overriding the CRS is fine
        df = df.set_crs(CRS, allow_override=True)
        df.geometry = df.geometry.translate(xoff=k * X_OFFSET)
    return df


def _concat(dfs: list[pd.DataFrame]) -> pd.DataFrame:
    df = pd.concat(dfs)
    return gpd.GeoDataFrame(df, crs=CRS) if isinstance(dfs[0], gpd.GeoDataFrame) else df


def _node_df(model: Model) -> gpd.GeoDataFrame:
    df = model.node.df
    assert df is not None
    return df


def _merge(components: list[Model], model: Model) -> Model:
    """
    Add the components to the model as separate parts of the network.

    Node, link and subgrid IDs are offset by a multiple of `ID_OFFSET` per component, and
    the subnetworks get new IDs, starting at 2.
    """
    nodes, links = [], []
    tables: dict[tuple[str, str], list[pd.DataFrame]] = {}
    next_subnetwork_id = 2
    for k, component in enumerate(components):
        node = _shift(_node_df(component), k, [])
        node.index = node.index + k * ID_OFFSET
        subnetwork_ids = sorted(node["subnetwork_id"].dropna().unique())
        mapping = {s: next_subnetwork_id + i for i, s in enumerate(subnetwork_ids)}
        next_subnetwork_id += len(mapping)
        node["subnetwork_id"] = node["subnetwork_id"].map(mapping).astype("Int32")
        nodes.append(node)

        assert component.link.df is not None
        link = _shift(component.link.df, k, ["from_node_id", "to_node_id"])
        link.index = link.index + k * ID_OFFSET
        links.append(link)

        for field in component._fields():
            node_model = getattr(component, field)
            if not isinstance(node_model, NodeModel):
                continue
            for table_field in node_model._fields():
                table = getattr(node_model, table_field)
                if table_field == "node" or getattr(table, "df", None) is None:
                    continue
                df = _shift(table.df, k, ["node_id", "listen_node_id", "subgrid_id"])
                tables.setdefault((field, table_field), []).append(
                    df.reset_index(drop=True)
                )

    with model.node._no_validate():
        model.node.df = _concat(nodes)  # ty: ignore[invalid-assignment]
    model.node._update_used_ids()
    with model.link._no_validate():
        model.link.df = _concat(links)  # ty: ignore[invalid-assignment]
    model.link._update_used_ids()
    for (field, table_field), dfs in tables.items():
        df = _concat(dfs).reset_index(drop=True)
        df.index.name = "fid"
        getattr(getattr(model, field), table_field).df = df

    return model


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
    return _merge(components, model)


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
    return _merge(components, model)
