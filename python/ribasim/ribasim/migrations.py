import warnings

from geopandas import GeoDataFrame
from pandas import DataFrame


def nodeschemamigration(gdf: GeoDataFrame) -> GeoDataFrame:
    warnings.warn("Migrating outdated Node table.", UserWarning)
    if "node_id" in gdf.columns:
        assert gdf["node_id"].is_unique, "Node IDs have to be unique."
        gdf.set_index("node_id", inplace=True)

    return gdf


def edgeschemamigration(gdf: GeoDataFrame) -> GeoDataFrame:
    warnings.warn("Migrating outdated Edge table.", UserWarning)
    if "from_node_type" in gdf.columns:
        gdf.drop("from_node_type", inplace=True, axis=1)
    if "to_node_type" in gdf.columns:
        gdf.drop("to_node_type", inplace=True, axis=1)
    if "edge_id" in gdf.columns:
        gdf.set_index("edge_id", inplace=True)

    return gdf


def basinstaticschemamigration(df: DataFrame) -> DataFrame:
    warnings.warn("Migrating outdated Basin / Static table.", UserWarning)
    if "urban_runoff" in df.columns:
        print(df)
        df.drop("urban_runoff", inplace=True, axis=1)

    return df


def basintimeschemamigration(df: DataFrame) -> DataFrame:
    warnings.warn("Migrating outdated Basin / Time table.", UserWarning)
    if "urban_runoff" in df.columns:
        df.drop("urban_runoff", inplace=True, axis=1)

    return df
