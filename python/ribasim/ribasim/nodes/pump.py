from ribasim.input_base import TableModel
from ribasim.schemas import (
    PumpStaticSchema,
)

__all__ = ["Static"]


class Static(TableModel[PumpStaticSchema]):
    pass
