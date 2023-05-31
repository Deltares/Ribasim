from pathlib import Path
from typing import Dict

import geopandas as gpd
import matplotlib.pyplot as plt
import numpy as np
import pandera as pa
import shapely
from matplotlib.axes import Axes
from pandera.typing import DataFrame, Series
from pandera.typing.geopandas import GeoSeries

from ribasim.input_base import TableModel
from ribasim.types import FilePath

__all__ = ("Edge",)


class StaticSchema(pa.SchemaModel):
    from_node_id: Series[int] = pa.Field(coerce=True)
    to_node_id: Series[int] = pa.Field(coerce=True)
    geometry: GeoSeries


class Edge(TableModel):
    """
    Defines the connections between nodes.

    Parameters
    ----------
    static : pandas.DataFrame
        Table describing the flow connections.
    """

    static: DataFrame[StaticSchema]

    class Config:
        validate_assignment = True

    @classmethod
    def _layername(cls, field) -> str:
        return cls.get_input_type()

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
        if "geometry" in gdf.columns:
            gdf = gdf.set_geometry("geometry")
        else:
            gdf["geometry"] = None
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

    def plot(self, **kwargs) -> Axes:
        ax = kwargs.get("ax", None)
        color = kwargs.get("color", None)
        if ax is None:
            _, ax = plt.subplots()
            ax.axis("off")
            kwargs["ax"] = ax
        if color is None:
            color = "#3690c0"  # lightblue
            kwargs["color"] = color

        self.static.plot(**kwargs)

        # Determine the angle for every caret marker and where to place it.
        coords = shapely.get_coordinates(self.static.geometry).reshape(-1, 2, 2)
        x, y = np.mean(coords, axis=1).T
        dx, dy = np.diff(coords, axis=1)[:, 0, :].T
        angle = np.degrees(np.arctan2(dy, dx)) - 90

        # A faster alternative may be ax.quiver(). However, getting the scaling
        # right is tedious.
        for m_x, m_y, m_angle in zip(x, y, angle):
            ax.plot(
                m_x,
                m_y,
                marker=(3, 0, m_angle),
                markersize=5,
                linestyle="None",
                color=color,
            )

        return ax

    def sort(self):
        self.static = self.static.sort_index()
