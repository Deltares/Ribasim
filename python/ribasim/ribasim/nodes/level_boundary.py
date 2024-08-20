from ribasim.input_base import TableModel
from ribasim.schemas import (
    LevelBoundaryConcentrationSchema,
    LevelBoundaryStaticSchema,
    LevelBoundaryTimeSchema,
)

__all__ = ["Static", "Time", "Concentration"]


class Static(TableModel[LevelBoundaryStaticSchema]):
    pass


class Time(TableModel[LevelBoundaryTimeSchema]):
    pass


class Concentration(TableModel[LevelBoundaryConcentrationSchema]):
    pass
