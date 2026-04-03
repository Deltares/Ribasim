from typing import Any

from ribasim.input_base import TableModel
from ribasim.schemas import (
    LevelDemandStaticSchema,
    LevelDemandTimeSchema,
)

__all__ = ["Static", "Time"]


class Static(TableModel[LevelDemandStaticSchema]):
    def __init__(self, **kwargs: Any) -> None:
        super().__init__(**kwargs)


class Time(TableModel[LevelDemandTimeSchema]):
    def __init__(self, **kwargs: Any) -> None:
        super().__init__(**kwargs)
