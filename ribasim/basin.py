from pydantic import BaseModel

from ribasim.input_base import ArrowInputMixin
from ribasim.types import DataFrame


class BasinState(BaseModel, ArrowInputMixin):
    _input_type = "state_Basin"
    dataframe: DataFrame


class BasinLookup(BaseModel, ArrowInputMixin):
    _input_type = "lookup_Basin"
    dataframe: DataFrame
