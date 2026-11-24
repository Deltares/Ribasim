from ribasim.input_base import TableModel
from ribasim.schemas import (
    UserDemandStaticSchema,
    UserDemandTimeSchema,
)

__all__ = ["Static", "Time"]


class Static(TableModel[UserDemandStaticSchema]):
    pass


class Time(TableModel[UserDemandTimeSchema]):
    pass
