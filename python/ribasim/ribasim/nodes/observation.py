from typing import Any

from ribasim.input_base import TableModel
from ribasim.schemas import ObservationTimeSchema

__all__ = ["Time"]


class Time(TableModel[ObservationTimeSchema]):
    def __init__(self, **kwargs: Any) -> None:
        super().__init__(**kwargs)
