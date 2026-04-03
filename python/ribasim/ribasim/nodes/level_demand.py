from ribasim.input_base import TableModel
from ribasim.schemas import (
    LevelDemandStaticSchema,
    LevelDemandTimeSchema,
)

__all__ = ["Static", "Time"]


class Static(TableModel[LevelDemandStaticSchema]):
    pass


class Time(TableModel[LevelDemandTimeSchema]):
    pass
