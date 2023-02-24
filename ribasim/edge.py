import pandera as pa
from pandera.typing import DataFrame, GeoSeries, Series
from pydantic import BaseModel

from ribasim.input_base import InputMixin


class StaticSchema(pa.SchemaModel):
    from_node_id: Series[int]
    to_node_id: Series[int]
    geometry: GeoSeries


class Edge(BaseModel, InputMixin):
    _input_type = "Edge"
    static: DataFrame[StaticSchema]
