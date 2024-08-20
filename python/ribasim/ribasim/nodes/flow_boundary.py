from ribasim.input_base import TableModel
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
