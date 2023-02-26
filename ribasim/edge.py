import pandera as pa
from pandera.typing import DataFrame, Series
from pandera.typing.geopandas import GeoSeries
from pydantic import BaseModel

from ribasim.input_base import InputMixin

__all__ = ("Edge",)


class StaticSchema(pa.SchemaModel):
    from_node_id: Series[int]
    to_node_id: Series[int]
    geometry: GeoSeries


class Edge(InputMixin, BaseModel):
    _input_type = "Edge"
    static: DataFrame[StaticSchema]
