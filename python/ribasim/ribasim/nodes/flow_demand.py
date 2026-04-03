from typing import Any

from ribasim.input_base import TableModel
from ribasim.schemas import (
    FlowDemandStaticSchema,
    FlowDemandTimeSchema,
)

__all__ = ["Static", "Time"]


class Static(TableModel[FlowDemandStaticSchema]):
    def __init__(self, **kwargs: Any) -> None:
        super().__init__(**kwargs)


class Time(TableModel[FlowDemandTimeSchema]):
    def __init__(self, **kwargs: Any) -> None:
        super().__init__(**kwargs)
