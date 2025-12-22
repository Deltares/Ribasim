import warnings

from geopandas import GeoDataFrame
from pandas import DataFrame

# On each breaking change, increment the __schema_version__


def _rename_column(df, from_colname, to_colname):
    """Rename a column, ensuring we don't end up with two of the same name."""
    # If a column has a default value, or is nullable, they are always added.
    # Remove that column first, then rename the old column.
    if to_colname in df.columns and from_colname not in df.columns:
        warnings.warn(
            "Already migrated, your model (version) might be inconsistent.", UserWarning
        )
        return df

    if from_colname not in df.columns:
        return df

    df.drop(columns=to_colname, inplace=True, errors="ignore")
    df.rename(columns={from_colname: to_colname}, inplace=True, errors="raise")
    return df


def check_inactive(df: DataFrame, name: str):
    """Check that inactive nodes are not present in the series, as removing them would alter model behavior."""
    if "active" not in df.columns:
        return
    nodes = df["node_id"][~df["active"].isin([True, None])].tolist()
    if len(nodes) > 0:
        raise ValueError(
            f"Inactive node(s) with node_id {nodes} in {name} cannot be migrated automatically, and should either be removed, or the respective attribute set to zero in the case of flows, or infinity in the case of resistance."
        )


def nodeschema_migration(gdf: GeoDataFrame, schema_version: int) -> GeoDataFrame:
    if schema_version == 0 and "node_id" in gdf.columns:
        warnings.warn("Migrating outdated Node table.", UserWarning)
        assert gdf["node_id"].is_unique, "Node IDs have to be unique."
        gdf.set_index("node_id", inplace=True)
    if schema_version < 10:
        warnings.warn("Migrating outdated Node table.", UserWarning)
        _rename_column(gdf, "source_priority", "route_priority")

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
    if schema_version < 7 and "surface_runoff" not in df.columns:
        warnings.warn("Migrating outdated Basin / static table.", UserWarning)
        df["surface_runoff"] = None
    return df


def basintimeschema_migration(df: DataFrame, schema_version: int) -> DataFrame:
    if schema_version == 0:
        warnings.warn("Migrating outdated Basin / time table.", UserWarning)
        df.drop(columns="urban_runoff", inplace=True, errors="ignore")
    if schema_version < 7 and "surface_runoff" not in df.columns:
        warnings.warn("Migrating outdated Basin / static table.", UserWarning)
        df["surface_runoff"] = None

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
    if schema_version < 9:
        warnings.warn("Migrating outdated PidControl / static table.", UserWarning)
        check_inactive(df, name="PidControl / static")
        df.drop(columns="active", inplace=True, errors="ignore")
    return df


def outletstaticschema_migration(df: DataFrame, schema_version: int) -> DataFrame:
    if schema_version < 2:
        warnings.warn("Migrating outdated Outlet / static table.", UserWarning)
        _rename_column(df, "min_crest_level", "min_upstream_level")
    if schema_version < 9:
        warnings.warn("Migrating outdated Outlet / static table.", UserWarning)
        check_inactive(df, name="Outlet / static")
        df.drop(columns="active", inplace=True, errors="ignore")
    return df


for node_type in ["UserDemand", "LevelDemand", "FlowDemand"]:
    for table_type in ["static", "time"]:
        if table_type == "static" and node_type == "UserDemand":
            continue  # see below

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
        df["time"] = None
        df["condition_id"] = range(1, n_rows + 1)
    if schema_version < 8:
        warnings.warn(
            "Migrating outdated DiscreteControl / condition table.", UserWarning
        )
        df["threshold_low"] = None
        df.rename(columns={"greater_than": "threshold_high"}, inplace=True)
    return df


def basinprofileschema_migration(df: DataFrame, schema_version: int) -> DataFrame:
    if schema_version < 6:
        warnings.warn("Migrating outdated Basin / profile table.", UserWarning)
        df["storage"] = None
    return df


def pumpstaticschema_migration(df: DataFrame, schema_version: int) -> DataFrame:
    if schema_version < 9:
        warnings.warn("Migrating outdated Pump / static table.", UserWarning)
        check_inactive(df, name="Pump / static")
        df.drop(columns="active", inplace=True, errors="ignore")
    return df


def levelboundarystaticschema_migration(
    df: DataFrame, schema_version: int
) -> DataFrame:
    if schema_version < 9:
        warnings.warn("Migrating outdated LevelBoundary / static table.", UserWarning)
        check_inactive(df, name="LevelBoundary / static")
        df.drop(columns="active", inplace=True, errors="ignore")
    return df


def flowboundarystaticschema_migration(df: DataFrame, schema_version: int) -> DataFrame:
    if schema_version < 9:
        warnings.warn("Migrating outdated FlowBoundary / static table.", UserWarning)
        check_inactive(df, name="FlowBoundary / static")
        df.drop(columns="active", inplace=True, errors="ignore")
    return df


def linearresistancestaticschema_migration(
    df: DataFrame, schema_version: int
) -> DataFrame:
    if schema_version < 9:
        warnings.warn(
            "Migrating outdated LinearResistance / static table.", UserWarning
        )
        check_inactive(df, name="LinearResistance / static")
        df.drop(columns="active", inplace=True, errors="ignore")
    return df


def manningresistancestaticschema_migration(
    df: DataFrame, schema_version: int
) -> DataFrame:
    if schema_version < 9:
        warnings.warn(
            "Migrating outdated ManningResistance / static table.", UserWarning
        )
        check_inactive(df, name="ManningResistance / static")
        df.drop(columns="active", inplace=True, errors="ignore")
    return df


def tabulatedratingcurvestaticschema_migration(
    df: DataFrame, schema_version: int
) -> DataFrame:
    if schema_version < 9:
        warnings.warn(
            "Migrating outdated TabulatedRatingCurve / static table.", UserWarning
        )
        check_inactive(df, name="TabulatedRatingCurve / static")
        df.drop(columns="active", inplace=True, errors="ignore")
    return df


def userdemandstaticschema_migration(df: DataFrame, schema_version: int) -> DataFrame:
    if schema_version < 4:
        warnings.warn(
            f"Migrating outdated {node_type} / {table_type} table.", UserWarning
        )
        df.rename(columns={"priority": "demand_priority"}, inplace=True)
    if schema_version < 9:
        warnings.warn(
            "Migrating outdated TabulatedRatingCurve / static table.", UserWarning
        )
        check_inactive(df, name="UserDemand / static")
        df.drop(columns="active", inplace=True, errors="ignore")
    return df
