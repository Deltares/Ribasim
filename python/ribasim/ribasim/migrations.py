import warnings

from geopandas import GeoDataFrame
from pandas import DataFrame

# On each breaking change, increment the __schema_version__ by one.
# Do the same for write_schema_version in ribasim_qgis/core/geopackage.py


def _rename_column(df, from_colname, to_colname):
    """Rename a column, ensuring we don't end up with two of the same name."""
    # If a column has a default value, or is nullable, they are always added.
    # Remove that column first, then rename the old column.
    if to_colname in df.columns and from_colname not in df.columns:
        warnings.warn(
            "Already migrated, your model (version) might be inconsistent.", UserWarning
        )
        return df

    df.drop(columns=to_colname, inplace=True, errors="ignore")
    df.rename(columns={from_colname: to_colname}, inplace=True, errors="raise")
    return df


def nodeschema_migration(gdf: GeoDataFrame, schema_version: int) -> GeoDataFrame:
    if schema_version == 0 and "node_id" in gdf.columns:
        warnings.warn("Migrating outdated Node table.", UserWarning)
        assert gdf["node_id"].is_unique, "Node IDs have to be unique."
        gdf.set_index("node_id", inplace=True)

    return gdf


def linkschema_migration(gdf: GeoDataFrame, schema_version: int) -> GeoDataFrame:
    if schema_version == 0:
        warnings.warn("Migrating outdated Link table.", UserWarning)
        gdf.drop(columns="from_node_type", inplace=True, errors="ignore")
    if schema_version == 0:
        warnings.warn("Migrating outdated Link table.", UserWarning)
        gdf.drop(columns="to_node_type", inplace=True, errors="ignore")
    if "edge_id" in gdf.columns and schema_version == 0:
        warnings.warn("Migrating outdated Link table.", UserWarning)
        assert gdf["edge_id"].is_unique, "Link IDs have to be unique."
        gdf.set_index("edge_id", inplace=True)
    if schema_version < 3 and "subnetwork_id" in gdf.columns:
        warnings.warn("Migrating outdated Link table.", UserWarning)
        gdf.drop(columns="subnetwork_id", inplace=True, errors="ignore")
    if schema_version < 4 and gdf.index.name == "edge_id":
        warnings.warn("Migrating outdated Link table.", UserWarning)
        gdf.index.rename("link_id", inplace=True)
    if schema_version < 4 and "edge_type" in gdf.columns:
        warnings.warn("Migrating outdated Link table.", UserWarning)
        _rename_column(gdf, "edge_type", "link_type")

    return gdf


def basinstaticschema_migration(df: DataFrame, schema_version: int) -> DataFrame:
    if schema_version == 0:
        warnings.warn("Migrating outdated Basin / static table.", UserWarning)
        df.drop(columns="urban_runoff", inplace=True, errors="ignore")

    return df


def basintimeschema_migration(df: DataFrame, schema_version: int) -> DataFrame:
    if schema_version == 0:
        warnings.warn("Migrating outdated Basin / time table.", UserWarning)
        df.drop(columns="urban_runoff", inplace=True, errors="ignore")

    return df


def continuouscontrolvariableschema_migration(
    df: DataFrame, schema_version: int
) -> DataFrame:
    if schema_version == 0:
        warnings.warn(
            "Migrating outdated ContinuousControl / variable table.", UserWarning
        )
        df.drop(columns="listen_node_type", inplace=True, errors="ignore")

    return df


def discretecontrolvariableschema_migration(
    df: DataFrame, schema_version: int
) -> DataFrame:
    if schema_version == 0:
        warnings.warn(
            "Migrating outdated DiscreteControl / variable table.", UserWarning
        )
        df.drop(columns="listen_node_type", inplace=True, errors="ignore")

    return df


def pidcontrolstaticschema_migration(df: DataFrame, schema_version: int) -> DataFrame:
    if schema_version == 0:
        warnings.warn("Migrating outdated PidControl / static table.", UserWarning)
        df.drop(columns="listen_node_type", inplace=True, errors="ignore")

    return df


def outletstaticschema_migration(df: DataFrame, schema_version: int) -> DataFrame:
    if schema_version < 2:
        warnings.warn("Migrating outdated Outlet / static table.", UserWarning)
        _rename_column(df, "min_crest_level", "min_upstream_level")

    return df


for node_type in ["UserDemand", "LevelDemand", "FlowDemand"]:
    for table_type in ["static", "time"]:

        def migration_func(
            df: DataFrame,
            schema_version: int,
            node_type: str = node_type,
            table_type: str = table_type,
        ) -> DataFrame:
            if schema_version < 4:
                warnings.warn(
                    f"Migrating outdated {node_type} / {table_type} table.", UserWarning
                )
                df.rename(columns={"priority": "demand_priority"}, inplace=True)
            return df

        globals()[f"{node_type.lower()}{table_type}schema_migration"] = migration_func


def discretecontrolconditionschema_migration(
    df: DataFrame, schema_version: int
) -> DataFrame:
    if schema_version < 5:
        warnings.warn(
            "Migrating outdated DiscreteControl / condition table.", UserWarning
        )
        n_rows = len(df)
        df["time"] = [None] * n_rows
        df["condition_id"] = range(1, n_rows + 1)
    return df
