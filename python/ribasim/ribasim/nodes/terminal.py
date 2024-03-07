from pandas import DataFrame

from ribasim.input_base import TableModel
from ribasim.schemas import (
    TerminalStaticSchema,
)

__all__ = ["Static"]


class Static(TableModel[TerminalStaticSchema]):
    def __init__(self, **kwargs):
        super().__init__(df=DataFrame(dict(**kwargs)))
