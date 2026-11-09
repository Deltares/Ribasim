"""Private helpers to merge models into one model. Not part of the public API."""

import geopandas as gpd
import pandas as pd

from ribasim.geometry.node import NodeModel
from ribasim.model import Model


def _shift(
    df: pd.DataFrame,
    k: int,
    columns: list[str],
    crs: str,
    id_offset: int,
    x_offset: float,
) -> pd.DataFrame:
    df = df.copy()
    for column in columns:
        if column in df.columns:
            df[column] = df[column] + k * id_offset
    if isinstance(df, gpd.GeoDataFrame):
        # The coordinates of the merged models are assumed to be arbitrary,
        # so overriding the CRS is fine
        df = df.set_crs(crs, allow_override=True)
        df.geometry = df.geometry.translate(xoff=k * x_offset)
    return df


def _concat(dfs: list[pd.DataFrame], crs: str) -> pd.DataFrame:
    df = pd.concat(dfs)
    return gpd.GeoDataFrame(df, crs=crs) if isinstance(dfs[0], gpd.GeoDataFrame) else df


def _merge_models(
    components: list[Model],
    model: Model,
    id_offset: int = 1000,
    x_offset: float = 1000.0,
) -> Model:
    """
    Add the components to the model as separate parts of the network.

    Node, link and subgrid IDs are offset by a multiple of `id_offset` per component,
    so `id_offset` must be larger than the IDs in any component. The geometries are
    translated by a multiple of `x_offset` per component, and get the CRS of `model`.
    The subnetworks get new IDs, starting at 2.
    """
    crs = model.crs
    nodes, links = [], []
    tables: dict[tuple[str, str], list[pd.DataFrame]] = {}
    next_subnetwork_id = 2
    for k, component in enumerate(components):
        node = _shift(component.node.df, k, [], crs, id_offset, x_offset)
        node.index = node.index + k * id_offset
        subnetwork_ids = sorted(node["subnetwork_id"].dropna().unique())
        mapping = {s: next_subnetwork_id + i for i, s in enumerate(subnetwork_ids)}
        next_subnetwork_id += len(mapping)
        node["subnetwork_id"] = node["subnetwork_id"].map(mapping).astype("Int32")
        nodes.append(node)

        link = _shift(
            component.link.df,
            k,
            ["from_node_id", "to_node_id"],
            crs,
            id_offset,
            x_offset,
        )
        link.index = link.index + k * id_offset
        links.append(link)

        for field in component._fields():
            node_model = getattr(component, field)
            if not isinstance(node_model, NodeModel):
                continue
            for table_field in node_model._fields():
                table = getattr(node_model, table_field)
                if table_field == "node" or getattr(table, "df", None) is None:
                    continue
                df = _shift(
                    table.df,
                    k,
                    ["node_id", "listen_node_id", "subgrid_id"],
                    crs,
                    id_offset,
                    x_offset,
                )
                tables.setdefault((field, table_field), []).append(
                    df.reset_index(drop=True)
                )

    with model.node._no_validate():
        model.node.df = _concat(nodes, crs)  # ty: ignore[invalid-assignment]
    model.node._update_used_ids()
    with model.link._no_validate():
        model.link.df = _concat(links, crs)  # ty: ignore[invalid-assignment]
    model.link._update_used_ids()
    for (field, table_field), dfs in tables.items():
        df = _concat(dfs, crs).reset_index(drop=True)
        df.index.name = "fid"
        getattr(getattr(model, field), table_field).df = df

    return model
