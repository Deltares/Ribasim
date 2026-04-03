from typing import Any

from ribasim.input_base import TableModel
from ribasim.schemas import PumpStaticSchema, PumpTimeSchema

__all__ = ["Static", "Time"]


class Static(TableModel[PumpStaticSchema]):
    def __init__(self, **kwargs: Any) -> None:
        super().__init__(**kwargs)


class Time(TableModel[PumpTimeSchema]):
    def __init__(self, **kwargs: Any) -> None:
        super().__init__(**kwargs)
