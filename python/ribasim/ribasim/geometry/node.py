from pathlib import Path
from typing import Any, Dict

import geopandas as gpd
import matplotlib.pyplot as plt
import numpy as np
import pandera as pa
from pandera.typing import DataFrame, Series
from pandera.typing.geopandas import GeoSeries

from ribasim.input_base import TableModel
from ribasim.types import FilePath

__all__ = ("Node",)


class StaticSchema(pa.SchemaModel):
    type: Series[str]
    geometry: GeoSeries


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

    def write(self, directory: FilePath, modelname: str) -> None:
        """
        Write the contents of the input to a GeoPackage.

        The Geopackage will be written in ``directory`` and will be be named
        ``{modelname}.gpkg``.

        Parameters
        ----------
        directory : FilePath
        modelname : str
        """
        self.sort()
        directory = Path(directory)
        dataframe = self.static
        name = self._layername(dataframe)

        gdf = gpd.GeoDataFrame(data=dataframe)
        gdf = gdf.set_geometry("geometry")

        gdf.to_file(directory / f"{modelname}.gpkg", layer=name)

        return

    @classmethod
    def _kwargs_from_geopackage(cls, path: FilePath) -> Dict:
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
            "Terminal": "s",
            "FlowBoundary": "h",
            "Control": "*",
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
            "Terminal": "m",
            "FlowBoundary": "m",
            "Control": "k",
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
