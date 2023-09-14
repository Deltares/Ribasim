from pandera.typing import DataFrame

from ribasim.input_base import TableModel
from ribasim.schemas import FractionalFlowStaticSchema  # type: ignore

__all__ = ("FractionalFlow",)


class FractionalFlow(TableModel):
    """
    Receives a fraction of the flow. The fractions must sum to 1.0 for a furcation.

    Parameters
    ----------
    static : pandas.DataFrame
        Table with the constant flow fractions.
    """

    static: DataFrame[FractionalFlowStaticSchema]
