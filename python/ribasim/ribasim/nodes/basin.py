from ribasim.geometry.area import BasinAreaSchema
from ribasim.input_base import SpatialTableModel, TableModel
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
    "Area",
    "Concentration",
    "Profile",
    "State",
    "Static",
    "Subgrid",
    "Time",
]


class Static(TableModel[BasinStaticSchema]):
    pass


class Time(TableModel[BasinTimeSchema]):
    pass


class State(TableModel[BasinStateSchema]):
    pass


class Profile(TableModel[BasinProfileSchema]):
    pass


class Subgrid(TableModel[BasinSubgridSchema]):
    pass


class Area(SpatialTableModel[BasinAreaSchema]):
    pass


class Concentration(TableModel[BasinConcentrationSchema]):
    pass


class ConcentrationExternal(TableModel[BasinConcentrationExternalSchema]):
    pass


class ConcentrationState(TableModel[BasinConcentrationStateSchema]):
    pass
