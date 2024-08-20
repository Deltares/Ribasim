from ribasim.input_base import TableModel
from ribasim.schemas import (
    ManningResistanceStaticSchema,
)

__all__ = ["Static"]


class Static(TableModel[ManningResistanceStaticSchema]):
    pass
