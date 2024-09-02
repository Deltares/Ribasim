import warnings

from geopandas import GeoDataFrame
from pandas import DataFrame

# On each breaking change, increment the __schema_version__ by one.
# Do the same for write_schema_version in ribasim_qgis/core/geopackage.py


def nodeschema_migration(gdf: GeoDataFrame, schema_version: int) -> GeoDataFrame:
    if "node_id" in gdf.columns and schema_version == 0:
        warnings.warn("Migrating outdated Node table.", UserWarning)
        assert gdf["node_id"].is_unique, "Node IDs have to be unique."
        gdf.set_index("node_id", inplace=True)

    return gdf


def edgeschema_migration(gdf: GeoDataFrame, schema_version: int) -> GeoDataFrame:
    if "from_node_type" in gdf.columns and schema_version == 0:
        warnings.warn("Migrating outdated Edge table.", UserWarning)
        gdf.drop("from_node_type", inplace=True, axis=1)
    if "to_node_type" in gdf.columns and schema_version == 0:
        warnings.warn("Migrating outdated Edge table.", UserWarning)
        gdf.drop("to_node_type", inplace=True, axis=1)
    if "edge_id" in gdf.columns and schema_version == 0:
        warnings.warn("Migrating outdated Edge table.", UserWarning)
        gdf.set_index("edge_id", inplace=True)

    return gdf


def basinstaticschema_migration(df: DataFrame, schema_version: int) -> DataFrame:
    if "urban_runoff" in df.columns and schema_version == 0:
        warnings.warn("Migrating outdated Basin / static table.", UserWarning)
        df.drop("urban_runoff", inplace=True, axis=1)

    return df


def basintimeschema_migration(df: DataFrame, schema_version: int) -> DataFrame:
    if "urban_runoff" in df.columns and schema_version == 0:
        warnings.warn("Migrating outdated Basin / time table.", UserWarning)
        df.drop("urban_runoff", inplace=True, axis=1)

    return df


def continuouscontrolvariableschema_migration(
    df: DataFrame, schema_version: int
) -> DataFrame:
    if "listen_node_type" in df.columns and schema_version == 0:
        warnings.warn(
            "Migrating outdated ContinuousControl / variable table.", UserWarning
        )
        df.drop("listen_node_type", inplace=True, axis=1)

    return df


def discretecontrolvariableschema_migration(
    df: DataFrame, schema_version: int
) -> DataFrame:
    if "listen_node_type" in df.columns and schema_version == 0:
        warnings.warn(
            "Migrating outdated DiscreteControl / variable table.", UserWarning
        )
        df.drop("listen_node_type", inplace=True, axis=1)

    return df


def pidcontrolstaticschema_migration(df: DataFrame, schema_version: int) -> DataFrame:
    if "listen_node_type" in df.columns and schema_version == 0:
        warnings.warn("Migrating outdated PidControl / static table.", UserWarning)
        df.drop("listen_node_type", inplace=True, axis=1)

    return df


def outletstaticschema_migration(df: DataFrame, schema_version: int) -> DataFrame:
    if schema_version == 1:
        warnings.warn("Migrating outdated Outlet / static table.", UserWarning)
        df.rename(columns={"min_crest_level": "min_upstream_level"}, inplace=True)

    return df
