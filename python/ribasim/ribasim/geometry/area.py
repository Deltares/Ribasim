from typing import Any

import pandera as pa
from pandera.dtypes import Int32
from pandera.typing import Series
from pandera.typing.geopandas import GeoSeries

from ribasim.schemas import _BaseSchema


class BasinAreaSchema(_BaseSchema):
    node_id: Series[Int32] = pa.Field(nullable=False, default=0)
    geometry: GeoSeries[Any] = pa.Field(default=None, nullable=True)
