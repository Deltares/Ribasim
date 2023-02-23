from pydantic import BaseModel

from ribasim.input_base import ArrowInputMixin
from ribasim.types import DataFrame


class OutflowTable(BaseModel, ArrowInputMixin):
    _input_type = "lookup_OutflowTable"
    dataframe: DataFrame
