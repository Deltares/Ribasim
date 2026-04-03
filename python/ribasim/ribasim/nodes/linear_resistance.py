from typing import Any

from ribasim.input_base import TableModel
from ribasim.schemas import (
    LinearResistanceStaticSchema,
)

__all__ = ["Static"]


class Static(TableModel[LinearResistanceStaticSchema]):
    def __init__(self, **kwargs: Any) -> None:
        super().__init__(**kwargs)
