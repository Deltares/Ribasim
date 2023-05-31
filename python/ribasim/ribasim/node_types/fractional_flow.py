import pandera as pa
from pandera.engines.pandas_engine import PydanticModel
from pandera.typing import DataFrame

from ribasim import models
from ribasim.input_base import TableModel

__all__ = ("FractionalFlow",)


class StaticSchema(pa.SchemaModel):
    class Config:
        """Config with dataframe-level data type."""

        dtype = PydanticModel(models.FractionalFlowStatic)


class FractionalFlow(TableModel):
    """
    Receives a fraction of the flow. The fractions must sum to 1.0 for a furcation.

    Parameters
    ----------
    static : pandas.DataFrame
        Table with the constant flow fractions.
    """

    static: DataFrame[StaticSchema]

    class Config:
        validate_assignment = True

    def sort(self):
        self.static = self.static.sort_values("node_id", ignore_index=True)
