from typing import Any

from ribasim.geometry import FlowBoundaryAreaSchema
from ribasim.input_base import SpatialTableModel, TableModel
from ribasim.schemas import (
    FlowBoundaryConcentrationSchema,
    FlowBoundaryStaticSchema,
    FlowBoundaryTimeSchema,
)

__all__ = ["Concentration", "Static", "Time"]


class Static(TableModel[FlowBoundaryStaticSchema]):
    def __init__(self, **kwargs: Any) -> None:
        super().__init__(**kwargs)


class Time(TableModel[FlowBoundaryTimeSchema]):
    def __init__(self, **kwargs: Any) -> None:
        super().__init__(**kwargs)


class Concentration(TableModel[FlowBoundaryConcentrationSchema]):
    def __init__(self, **kwargs: Any) -> None:
        super().__init__(**kwargs)


class Area(SpatialTableModel[FlowBoundaryAreaSchema]):
    def __init__(self, **kwargs: Any) -> None:
        super().__init__(**kwargs)
