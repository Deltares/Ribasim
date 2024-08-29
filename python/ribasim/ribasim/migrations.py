import warnings

from geopandas import GeoDataFrame
from pandas import DataFrame


def nodeschema_migration(gdf: GeoDataFrame) -> GeoDataFrame:
    if "node_id" in gdf.columns:
        warnings.warn("Migrating outdated Node table.", UserWarning)
        assert gdf["node_id"].is_unique, "Node IDs have to be unique."
        gdf.set_index("node_id", inplace=True)

    return gdf


def edgeschema_migration(gdf: GeoDataFrame) -> GeoDataFrame:
    if "from_node_type" in gdf.columns:
        warnings.warn("Migrating outdated Edge table.", UserWarning)
        gdf.drop("from_node_type", inplace=True, axis=1)
    if "to_node_type" in gdf.columns:
        warnings.warn("Migrating outdated Edge table.", UserWarning)
        gdf.drop("to_node_type", inplace=True, axis=1)
    if "edge_id" in gdf.columns:
        warnings.warn("Migrating outdated Edge table.", UserWarning)
        gdf.set_index("edge_id", inplace=True)

    return gdf


def basinstaticschema_migration(df: DataFrame) -> DataFrame:
    if "urban_runoff" in df.columns:
        warnings.warn("Migrating outdated Basin / Static table.", UserWarning)
        df.drop("urban_runoff", inplace=True, axis=1)

    return df


def basintimeschema_migration(df: DataFrame) -> DataFrame:
    if "urban_runoff" in df.columns:
        warnings.warn("Migrating outdated Basin / Time table.", UserWarning)
        df.drop("urban_runoff", inplace=True, axis=1)

    return df


def continuouscontrolvariableschema_migration(df: DataFrame) -> DataFrame:
    if "listen_node_type" in df.columns:
        warnings.warn(
            "Migrating outdated ContinuousControl / Variable table.", UserWarning
        )
        df.drop("listen_node_type", inplace=True, axis=1)

    return df


def discretecontrolvariableschema_migration(df: DataFrame) -> DataFrame:
    if "listen_node_type" in df.columns:
        warnings.warn(
            "Migrating outdated DiscreteControl / Variable table.", UserWarning
        )
        df.drop("listen_node_type", inplace=True, axis=1)

    return df


def pidcontrolstaticschema_migration(df: DataFrame) -> DataFrame:
    if "listen_node_type" in df.columns:
        warnings.warn("Migrating outdated PidControl / Static table.", UserWarning)
        df.drop("listen_node_type", inplace=True, axis=1)

    return df
