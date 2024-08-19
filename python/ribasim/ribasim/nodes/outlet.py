from ribasim.input_base import TableModel
from ribasim.schemas import (
    OutletStaticSchema,
)

__all__ = ["Static"]


class Static(TableModel[OutletStaticSchema]):
    pass
