import numpy as np
import pandera as pa
from pandera.typing import Index, Series
from pandera.typing.geopandas import GeoSeries
from shapely.geometry import MultiPolygon, Polygon

from .base import _GeoBaseSchema


class BasinAreaSchema(_GeoBaseSchema):
    _node_id_relation: str = "subset"
    fid: Index[np.int32] = pa.Field(default=0, check_name=True)
    node_id: Series[np.int32] = pa.Field(nullable=False, default=0)
    geometry: GeoSeries[MultiPolygon] = pa.Field(default=None, nullable=True)

    @pa.parser("geometry")
    def convert_to_multi(cls, series):
        return series.apply(
            lambda geom: MultiPolygon([geom]) if isinstance(geom, Polygon) else geom
        )


class FlowBoundaryAreaSchema(_GeoBaseSchema):
    _node_id_relation: str = "subset"
    fid: Index[np.int32] = pa.Field(default=0, check_name=True)
    node_id: Series[np.int32] = pa.Field(nullable=False, default=0)
    geometry: GeoSeries[MultiPolygon] = pa.Field(default=None, nullable=True)

    @pa.parser("geometry")
    def convert_to_multi(cls, series):
        return series.apply(
            lambda geom: MultiPolygon([geom]) if isinstance(geom, Polygon) else geom
        )
