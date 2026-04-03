from typing import Any

from ribasim.input_base import TableModel
from ribasim.schemas import OutletStaticSchema, OutletTimeSchema

__all__ = ["Static", "Time"]


class Static(TableModel[OutletStaticSchema]):
    def __init__(self, **kwargs: Any) -> None:
        super().__init__(**kwargs)


class Time(TableModel[OutletTimeSchema]):
    def __init__(self, **kwargs: Any) -> None:
        super().__init__(**kwargs)
