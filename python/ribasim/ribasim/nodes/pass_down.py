from ribasim.input_base import TableModel
from ribasim.schemas import PassDownStaticSchema

__all__ = ["Static"]


class Static(TableModel[PassDownStaticSchema]):
    pass
