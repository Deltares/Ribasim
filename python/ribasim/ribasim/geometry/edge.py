from pathlib import Path
from typing import Any, Dict, Union

import geopandas as gpd
import matplotlib.pyplot as plt
import numpy as np
import pandera as pa
import shapely
from geopandas import GeoDataFrame
from matplotlib.axes import Axes
from numpy.typing import NDArray
from pandera.typing import DataFrame, Series
from pandera.typing.geopandas import GeoSeries

from ribasim.input_base import TableModel
from ribasim.types import FilePath

__all__ = ("Edge",)


class StaticSchema(pa.SchemaModel):
    from_node_id: Series[int] = pa.Field(coerce=True)
    to_node_id: Series[int] = pa.Field(coerce=True)
    geometry: GeoSeries[Any]


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
        gdf.to_file(directory / f"{modelname}.gpkg", layer=name, driver="GPKG")

        return

    @classmethod
    def _kwargs_from_geopackage(
        cls, path: FilePath
    ) -> Dict[str, Union[DataFrame[Any], GeoDataFrame, None]]:
        kwargs = {}

        field = "static"
        layername = cls._layername(field)
        df = gpd.read_file(path, layer=layername, engine="pyogrio", fid_as_index=True)
        kwargs[field] = df

        return kwargs

    def get_where_edge_type(self, edge_type: str) -> NDArray[np.bool_]:
        return (self.static.edge_type == edge_type).to_numpy()

    def plot(self, **kwargs) -> Axes:
        ax = kwargs.get("ax", None)
        color_flow = kwargs.get("color_flow", None)
        color_control = kwargs.get("color_control", None)

        if ax is None:
            _, ax = plt.subplots()
            ax.axis("off")
            kwargs["ax"] = ax

        kwargs_flow = kwargs.copy()
        kwargs_control = kwargs.copy()

        if color_flow is None:
            color_flow = "#3690c0"  # lightblue
            kwargs_flow["color"] = color_flow
            kwargs_flow["label"] = "Flow Edge"
        else:
            color_flow = kwargs["color_flow"]
            del kwargs_flow["color_flow"], kwargs_control["color_flow"]

        if color_control is None:
            color_control = "grey"
            kwargs_control["color"] = color_control
            kwargs_control["label"] = "Affect Edge"
        else:
            color_control = kwargs["color_flow"]
            del kwargs_flow["color_control"], kwargs_control["color_control"]

        where_flow = self.get_where_edge_type("flow")
        where_control = self.get_where_edge_type("control")

        self.static[where_flow].plot(**kwargs_flow)

        if where_control.any():
            self.static[where_control].plot(**kwargs_control)

        # Determine the angle for every caret marker and where to place it.
        coords = shapely.get_coordinates(self.static.geometry).reshape(-1, 2, 2)
        x, y = np.mean(coords, axis=1).T
        dx, dy = np.diff(coords, axis=1)[:, 0, :].T
        angle = np.degrees(np.arctan2(dy, dx)) - 90

        # A faster alternative may be ax.quiver(). However, getting the scaling
        # right is tedious.
        color = []

        for i in range(len(self.static)):
            if where_flow[i]:
                color.append(color_flow)
            elif where_control[i]:
                color.append(color_control)
            else:
                color.append("k")

        for m_x, m_y, m_angle, c in zip(x, y, angle, color):
            ax.plot(
                m_x,
                m_y,
                marker=(3, 0, m_angle),
                markersize=5,
                linestyle="None",
                c=c,
            )

        return ax

    def sort(self):
        self.static = self.static.sort_index()
