from typing import Any

from ribasim.input_base import TableModel
from ribasim.schemas import (
    LevelBoundaryConcentrationSchema,
    LevelBoundaryStaticSchema,
    LevelBoundaryTimeSchema,
)

__all__ = ["Concentration", "Static", "Time"]


class Static(TableModel[LevelBoundaryStaticSchema]):
    def __init__(self, **kwargs: Any) -> None:
        super().__init__(**kwargs)


class Time(TableModel[LevelBoundaryTimeSchema]):
    def __init__(self, **kwargs: Any) -> None:
        super().__init__(**kwargs)


class Concentration(TableModel[LevelBoundaryConcentrationSchema]):
    def __init__(self, **kwargs: Any) -> None:
        super().__init__(**kwargs)
