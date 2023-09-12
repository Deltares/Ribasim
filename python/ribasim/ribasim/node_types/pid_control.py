from typing import Optional

from pandera.typing import DataFrame

from ribasim.input_base import TableModel
from ribasim.schemas import PidControlStaticSchema, PidControlTimeSchema  # type: ignore

__all__ = ("PidControl",)


class PidControl(TableModel):
    """
    Controller based on PID (Proportional, integral, derivative) which
    controls the level of a single basin with a pump.

    Parameters
    ----------
    static: pandas.DataFrame
        Table with data for this node type.
    time : pandas.DataFrame, optional
        Table with time-varying data for this node type.
    """

    static: Optional[DataFrame[PidControlStaticSchema]] = None
    time: Optional[DataFrame[PidControlTimeSchema]] = None

    class Config:
        validate_assignment = True
