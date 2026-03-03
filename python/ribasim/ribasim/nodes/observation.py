from ribasim.input_base import TableModel
from ribasim.schemas import ObservationTimeSchema

__all__ = ["Time"]


class Time(TableModel[ObservationTimeSchema]):
    pass
