from geopandas import GeoDataFrame
from pandas import DataFrame

from ribasim.geometry.area import BasinAreaSchema
from ribasim.input_base import TableModel
from ribasim.schemas import (
    BasinConcentrationExternalSchema,
    BasinConcentrationSchema,
    BasinConcentrationStateSchema,
    BasinProfileSchema,
    BasinStateSchema,
    BasinStaticSchema,
    BasinSubgridSchema,
    BasinTimeSchema,
)

__all__ = [
    "Static",
    "Time",
    "State",
    "Profile",
    "Subgrid",
    "Area",
    "Concentration",
]


class Static(TableModel[BasinStaticSchema]):
    def __init__(self, **kwargs):
        super().__init__(df=DataFrame(dict(**kwargs)))


class Time(TableModel[BasinTimeSchema]):
    def __init__(self, **kwargs):
        super().__init__(df=DataFrame(dict(**kwargs)))


class State(TableModel[BasinStateSchema]):
    def __init__(self, **kwargs):
        super().__init__(df=DataFrame(dict(**kwargs)))


class Profile(TableModel[BasinProfileSchema]):
    def __init__(self, **kwargs):
        super().__init__(df=DataFrame(dict(**kwargs)))


class Subgrid(TableModel[BasinSubgridSchema]):
    def __init__(self, **kwargs):
        super().__init__(df=DataFrame(dict(**kwargs)))


class Area(TableModel[BasinAreaSchema]):
    def __init__(self, **kwargs):
        super().__init__(df=GeoDataFrame(dict(**kwargs)))


class Concentration(TableModel[BasinConcentrationSchema]):
    def __init__(self, **kwargs):
        super().__init__(df=GeoDataFrame(dict(**kwargs)))


class ConcentrationExternal(TableModel[BasinConcentrationExternalSchema]):
    def __init__(self, **kwargs):
        super().__init__(df=GeoDataFrame(dict(**kwargs)))


class ConcentrationState(TableModel[BasinConcentrationStateSchema]):
    def __init__(self, **kwargs):
        super().__init__(df=GeoDataFrame(dict(**kwargs)))
