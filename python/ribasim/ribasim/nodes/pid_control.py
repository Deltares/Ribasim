from ribasim.input_base import TableModel
from ribasim.schemas import PidControlStaticSchema, PidControlTimeSchema

__all__ = ["Static", "Time"]


class Static(TableModel[PidControlStaticSchema]):
    pass


class Time(TableModel[PidControlTimeSchema]):
    pass
