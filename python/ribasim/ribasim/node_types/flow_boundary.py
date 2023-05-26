import pandera as pa
from pandera.engines.pandas_engine import PydanticModel
from pandera.typing import DataFrame
from pydantic import BaseModel

from ribasim import models
from ribasim.input_base import InputMixin

__all__ = ("FlowBoundary",)


class StaticSchema(pa.SchemaModel):
    class Config:
        """Config with dataframe-level data type."""

        dtype = PydanticModel(models.FlowBoundaryStatic)


class FlowBoundary(InputMixin, BaseModel):
    """
    Sets a precribed flow like a one-sided pump.

    Parameters
    ----------
    static : pandas.DataFrame
        Table with the constant flows.
    """

    static: DataFrame[StaticSchema]

    class Config:
        validate_assignment = True
