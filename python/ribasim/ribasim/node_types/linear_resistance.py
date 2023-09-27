from pandera.typing import DataFrame

from ribasim.input_base import TableModel
from ribasim.schemas import LinearResistanceStaticSchema  # type: ignore

__all__ = ("LinearResistance",)


class LinearResistance(TableModel):
    """
    Flow through this connection linearly depends on the level difference
    between the two connected basins.

    Parameters
    ----------
    static : pd.DataFrame
        Table with the constant resistances.
    """

    static: DataFrame[LinearResistanceStaticSchema]
