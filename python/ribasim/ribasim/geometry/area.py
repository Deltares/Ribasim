from typing import Any

import pandera as pa
from pandera.typing import Series
from pandera.typing.geopandas import GeoSeries

from ribasim.schemas import _BaseSchema


class BasinAreaSchema(_BaseSchema):
    node_id: Series[int] = pa.Field(nullable=False, default=0)
    geometry: GeoSeries[Any] = pa.Field(default=None, nullable=True)
