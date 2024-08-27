from typing import Any

import pandera as pa
from pandera.dtypes import Int32
from pandera.typing import Index, Series
from pandera.typing.geopandas import GeoSeries

from ribasim.schemas import _BaseSchema


class BasinAreaSchema(_BaseSchema):
    fid: Index[Int32] = pa.Field(default=0, check_name=True)
    node_id: Series[Int32] = pa.Field(nullable=False, default=0)
    geometry: GeoSeries[Any] = pa.Field(default=None, nullable=True)
