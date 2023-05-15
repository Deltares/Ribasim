import pandera as pa
from pandera.engines.pandas_engine import PydanticModel
from pandera.typing import DataFrame
from pydantic import BaseModel

from ribasim import models
from ribasim.input_base import InputMixin

__all__ = ("LinearLevelConnection",)


class StaticSchema(pa.SchemaModel):
    class Config:
        """Config with dataframe-level data type."""

        dtype = PydanticModel(models.LinearLevelConnectionStatic)


class LinearLevelConnection(InputMixin, BaseModel):
    """
    Flow through this connection linearly depends on the level difference
    between the two connected basins.

    Parameters
    ----------
    static: pd.DataFrame

        With columns:

        * node_id
        * conductance

    """

    _input_type = "LinearLevelConnection"
    static: DataFrame[StaticSchema]

    class Config:
        validate_assignment = True
