import pandas as pd
import pandera as pa
from pandera.typing import DataFrame, Series
from pydantic import BaseModel

from ribasim.input_base import InputMixin


class StaticSchema(pd.SchemaModel):
    type: Series[str] = pa.Field()


class Node(BaseModel, InputMixin):
    _input_type = "Node"
    static: DataFrame[StaticSchema]
