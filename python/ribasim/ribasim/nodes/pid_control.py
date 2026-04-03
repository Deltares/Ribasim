from typing import Any

from ribasim.input_base import TableModel
from ribasim.schemas import PidControlStaticSchema, PidControlTimeSchema

__all__ = ["Static", "Time"]


class Static(TableModel[PidControlStaticSchema]):
    def __init__(self, **kwargs: Any) -> None:
        super().__init__(**kwargs)


class Time(TableModel[PidControlTimeSchema]):
    def __init__(self, **kwargs: Any) -> None:
        super().__init__(**kwargs)
