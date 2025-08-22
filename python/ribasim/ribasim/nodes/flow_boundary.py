from ribasim.geometry import FlowBoundaryAreaSchema
from ribasim.input_base import SpatialTableModel, TableModel
from ribasim.schemas import (
    FlowBoundaryConcentrationSchema,
    FlowBoundaryStaticSchema,
    FlowBoundaryTimeSchema,
)

__all__ = ["Static", "Time", "Concentration"]


class Static(TableModel[FlowBoundaryStaticSchema]):
    pass


class Time(TableModel[FlowBoundaryTimeSchema]):
    pass


class Concentration(TableModel[FlowBoundaryConcentrationSchema]):
    pass


class Area(SpatialTableModel[FlowBoundaryAreaSchema]):
    pass
