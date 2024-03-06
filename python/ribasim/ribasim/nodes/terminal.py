from pandera.typing import DataFrame

from ribasim.schemas import (
    TerminalStaticSchema,
)

__all__ = ["Static"]


class Static(DataFrame[TerminalStaticSchema]):
    def __init__(self, **kwargs):
        super().__init__(data=dict(**kwargs))
