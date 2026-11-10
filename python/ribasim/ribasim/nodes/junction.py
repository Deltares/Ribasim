from ribasim.input_base import TableModel
from ribasim.schemas import JunctionStaticSchema

__all__ = ["Static"]


class Static(TableModel[JunctionStaticSchema]):
    pass
