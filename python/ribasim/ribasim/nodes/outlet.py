from ribasim.input_base import TableModel
from ribasim.schemas import OutletStaticSchema, OutletTimeSchema

__all__ = ["Static", "Time"]


class Static(TableModel[OutletStaticSchema]):
    pass


class Time(TableModel[OutletTimeSchema]):
    pass
