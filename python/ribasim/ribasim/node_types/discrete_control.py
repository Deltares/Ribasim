from pandera.typing import DataFrame

from ribasim.input_base import TableModel
from ribasim.schemas import (  # type: ignore
    DiscreteControlConditionSchema,
    DiscreteControlLogicSchema,
)

__all__ = ("DiscreteControl",)


class DiscreteControl(TableModel):
    """
    Defines the control logic.

    Parameters
    ----------
    condition : pandas.DataFrame
        Table with the information of control conditions.
    logic : pandas.Dataframe
        Table with the information of truth state to control state mapping.
    """

    condition: DataFrame[DiscreteControlConditionSchema]
    logic: DataFrame[DiscreteControlLogicSchema]
