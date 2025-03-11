from ribasim.input_base import TableModel
from ribasim.schemas import PumpStaticSchema, PumpTimeSchema

__all__ = ["Static", "Time"]


class Static(TableModel[PumpStaticSchema]):
    pass


class Time(TableModel[PumpTimeSchema]):
    pass
