from ribasim.input_base import TableModel
from ribasim.schemas import (
    FlowDemandStaticSchema,
    FlowDemandTimeSchema,
)

__all__ = ["Static", "Time"]


class Static(TableModel[FlowDemandStaticSchema]):
    pass


class Time(TableModel[FlowDemandTimeSchema]):
    pass
