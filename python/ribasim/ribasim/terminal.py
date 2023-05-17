import pandera as pa
from pandera.typing import DataFrame, Series
from pydantic import BaseModel

from ribasim.input_base import InputMixin

__all__ = ("Terminal",)


class StaticSchema(pa.SchemaModel):
    node_id: Series[int] = pa.Field(coerce=True)


class Terminal(InputMixin, BaseModel):
    """
    Water sink without state or properties.

    Parameters
    ----------
    static : pd.DataFrame
        Table with only node IDs of this type.
    """

    _input_type = "Terminal"
    static: DataFrame[StaticSchema]

    class Config:
        validate_assignment = True
