from typing import Any, get_type_hints

import pandera as pa
from pandera.typing import Series
from pandera.typing.geopandas import GeoDataFrame, GeoSeries

from ribasim.schemas import _BaseSchema


class _GeoBaseSchema(_BaseSchema):
    @pa.check("geometry")
    def is_correct_geometry_type(cls, geoseries: GeoSeries[Any]) -> Series[bool]:
        T = get_type_hints(cls)["geometry"].__args__[0]
        return geoseries.map(lambda geom: isinstance(geom, T))

    @pa.check_types
    def force_2d(cls, gdf: GeoDataFrame[Any]) -> GeoDataFrame[Any]:
        gdf.geometry = gdf.geometry.force_2d()
        return gdf
