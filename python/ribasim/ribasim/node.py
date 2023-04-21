from pathlib import Path
from typing import Any, Dict, Type, TypeVar

import geopandas as gpd
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import pandera as pa
from pandera.typing import DataFrame, Series
from pandera.typing.geopandas import GeoSeries
from pydantic import BaseModel

from ribasim.input_base import InputMixin
from ribasim.types import FilePath

T = TypeVar("T")

__all__ = ("Node",)

_MARKERS = {
    "Basin": "o",
    "FractionalFlow": "^",
    "LevelControl": "*",
    "LinearLevelConnection": "^",
    "TabulatedRatingCurve": "D",
    "Pump": "h",
    "": "o",
}


class StaticSchema(pa.SchemaModel):
    type: Series[str]
    geometry: GeoSeries


class Node(InputMixin, BaseModel):
    """
    The Ribasim nodes as Point geometries.

    Parameters
    ----------
    static: geopandas.GeoDataFrame

        With columns:

        * type
        * geometry

    """

    _input_type = "Node"
    static: DataFrame[StaticSchema]

    class Config:
        validate_assignment = True

    def __init__(self, static: pd.DataFrame):
        super().__init__(**locals())

    @classmethod
    def _layername(cls, field) -> str:
        return f"{cls._input_type}"

    def write(self, directory: FilePath, modelname: str) -> None:
        """
        Write the contents of the input to a GeoPackage.

        The Geopackage will be written in ``directory`` and will be be named
        ``{modelname}.gpkg``.

        Parameters
        ----------
        directory: FilePath
        modelname: str
        """
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
    def _kwargs_from_geopackage(cls: Type[T], path: FilePath) -> Dict:
        kwargs = {}

        field = "static"
        layername = cls._layername(field)
        df = gpd.read_file(path, layer=layername, engine="pyogrio", fid_as_index=True)
        kwargs[field] = df

        return kwargs

    def plot(self, **kwargs) -> Any:
        """
        Plot the nodes. Each node type is given a separate marker.

        Parameters
        ----------
        **kwargs: optional
            Keyword arguments forwarded to GeoDataFrame.plot.

        Returns
        -------
        None
        """
        kwargs = kwargs.copy()
        ax = kwargs.get("ax", None)
        if ax is None:
            _, ax = plt.subplots()
            ax.axis("off")
            kwargs["ax"] = ax

        for nodetype, df in self.static.groupby("type"):
            marker = _MARKERS[nodetype]
            kwargs["marker"] = marker
            df.plot(**kwargs)

        geometry = self.static["geometry"]
        for text, xy in zip(
            self.static.index, np.column_stack((geometry.x, geometry.y))
        ):
            ax.annotate(text=text, xy=xy, xytext=(2.0, 2.0), textcoords="offset points")

        return ax
