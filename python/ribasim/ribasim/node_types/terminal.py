from pandera.typing import DataFrame

from ribasim.input_base import TableModel
from ribasim.schemas import TerminalStaticSchema  # type: ignore

__all__ = ("Terminal",)


class Terminal(TableModel):
    """
    Water sink without state or properties.

    Parameters
    ----------
    static : pd.DataFrame
        Table with only node IDs of this type.
    """

    static: DataFrame[TerminalStaticSchema]
