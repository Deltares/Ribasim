from pandera.typing import DataFrame

from ribasim.schemas import (
    LinearResistanceStaticSchema,
)

__all__ = ["Static"]


class Static(DataFrame[LinearResistanceStaticSchema]):
    def __init__(self, **kwargs):
        super().__init__(data=dict(**kwargs))
