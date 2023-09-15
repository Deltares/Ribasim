from typing import Any, Dict, Union

import geopandas as gpd
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import pandera as pa
from geopandas import GeoDataFrame
from pandera.typing import DataFrame, Series
from pandera.typing.geopandas import GeoSeries

from ribasim.input_base import TableModel
from ribasim.types import FilePath

__all__ = ("Node",)


class StaticSchema(pa.SchemaModel):
    type: Series[str]
    geometry: GeoSeries[Any]


class Node(TableModel):
    """
    The Ribasim nodes as Point geometries.

    Parameters
    ----------
    static : geopandas.GeoDataFrame
        Table with node ID, type and geometry.
    """

    static: DataFrame[StaticSchema]

    class Config:
        validate_assignment = True

    @classmethod
    def _layername(cls, field) -> str:
        return cls.get_input_type()

    @classmethod
    def hasfid(cls):
        return True

    @staticmethod
    def get_node_ids_and_types(*nodes):
        data_types = {"node_id": int, "node_type": str}
        node_type = pd.DataFrame(
            {col: pd.Series(dtype=dtype) for col, dtype in data_types.items()}
        )

        for node in nodes:
            if not node:
                continue

            for table_type in ["static", "time", "condition"]:
                if hasattr(node, table_type):
                    table = getattr(node, table_type)
                    if table is not None:
                        node_type_table = pd.DataFrame(
                            data={
                                "node_id": table.node_id,
                                "node_type": len(table) * [node.get_input_type()],
                            }
                        )
                        node_type = node_type._append(node_type_table)

        node_type = node_type.drop_duplicates(subset="node_id")
        node_type = node_type.sort_values("node_id")

        node_id = node_type.node_id.tolist()
        node_type = node_type.node_type.tolist()

        return node_id, node_type

    def write_layer(self, path: FilePath) -> None:
        """
        Write the contents of the input to a GeoPackage.

        Parameters
        ----------
        path : FilePath
        """
        self.sort()
        dataframe = self.static
        name = self._layername(dataframe)

        gdf = gpd.GeoDataFrame(data=dataframe)
        gdf = gdf.set_geometry("geometry")

        gdf.to_file(path, layer=name, driver="GPKG")

        return

    @classmethod
    def _kwargs_from_geopackage(
        cls, path: FilePath
    ) -> Dict[str, Union[GeoDataFrame, DataFrame[Any], None]]:
        kwargs = {}

        field = "static"
        layername = cls._layername(field)
        df = gpd.read_file(path, layer=layername, engine="pyogrio", fid_as_index=True)
        kwargs[field] = df

        return kwargs

    def plot(self, ax=None, zorder=None) -> Any:
        """
        Plot the nodes. Each node type is given a separate marker.

        Parameters
        ----------
        ax : Optional
            The axis on which the nodes will be plotted.

        Returns
        -------
        None
        """
        if ax is None:
            _, ax = plt.subplots()
            ax.axis("off")

        MARKERS = {
            "Basin": "o",
            "FractionalFlow": "^",
            "LevelBoundary": "o",
            "LinearResistance": "^",
            "ManningResistance": "D",
            "TabulatedRatingCurve": "D",
            "Pump": "h",
            "Outlet": "h",
            "Terminal": "s",
            "FlowBoundary": "h",
            "DiscreteControl": "*",
            "PidControl": "x",
            "User": "s",
            "": "o",
        }

        COLORS = {
            "Basin": "b",
            "FractionalFlow": "r",
            "LevelBoundary": "g",
            "LinearResistance": "g",
            "ManningResistance": "r",
            "TabulatedRatingCurve": "g",
            "Pump": "0.5",  # grayscale level
            "Outlet": "g",
            "Terminal": "m",
            "FlowBoundary": "m",
            "DiscreteControl": "k",
            "PidControl": "k",
            "User": "g",
            "": "k",
        }

        for nodetype, df in self.static.groupby("type"):
            assert isinstance(nodetype, str)
            marker = MARKERS[nodetype]
            color = COLORS[nodetype]
            ax.scatter(
                df.geometry.x,
                df.geometry.y,
                marker=marker,
                color=color,
                zorder=zorder,
                label=nodetype,
            )

        geometry = self.static["geometry"]
        for text, xy in zip(
            self.static.index, np.column_stack((geometry.x, geometry.y))
        ):
            ax.annotate(text=text, xy=xy, xytext=(2.0, 2.0), textcoords="offset points")

        return ax

    def sort(self):
        self.static = self.static.sort_index()
