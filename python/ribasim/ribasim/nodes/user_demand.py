from typing import Any

from ribasim.input_base import TableModel
from ribasim.schemas import (
    UserDemandConcentrationSchema,
    UserDemandStaticSchema,
    UserDemandTimeSchema,
)

__all__ = ["Static", "Time"]


class Static(TableModel[UserDemandStaticSchema]):
    def __init__(self, **kwargs: Any) -> None:
        super().__init__(**kwargs)


class Time(TableModel[UserDemandTimeSchema]):
    def __init__(self, **kwargs: Any) -> None:
        super().__init__(**kwargs)


class Concentration(TableModel[UserDemandConcentrationSchema]):
    def __init__(self, **kwargs: Any) -> None:
        super().__init__(**kwargs)
