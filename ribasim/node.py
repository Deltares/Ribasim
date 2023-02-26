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
    _input_type = "Node"
    static: DataFrame[StaticSchema]
