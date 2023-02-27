import pandas as pd
import pandera as pa
from pandera.typing import DataFrame, Series
from pandera.typing.geopandas import GeoSeries
from pydantic import BaseModel

from ribasim.input_base import InputMixin

__all__ = ("Node",)


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

    def __init__(self, static: pd.DataFrame):
        super().__init__(**locals())
