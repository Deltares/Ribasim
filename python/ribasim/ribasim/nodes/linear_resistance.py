from ribasim.input_base import TableModel
from ribasim.schemas import (
    LinearResistanceStaticSchema,
)

__all__ = ["Static"]


class Static(TableModel[LinearResistanceStaticSchema]):
    pass
