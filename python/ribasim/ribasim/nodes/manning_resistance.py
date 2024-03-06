from pandera.typing import DataFrame

from ribasim.schemas import (
    ManningResistanceStaticSchema,
)

__all__ = ["Static"]


class Static(DataFrame[ManningResistanceStaticSchema]):
    def __init__(self, **kwargs):
        super().__init__(data=dict(**kwargs))
