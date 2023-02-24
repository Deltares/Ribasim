from pydantic import BaseModel

from ribasim.input_base import ArrowInputMixin
from ribasim.types import DataFrame


class Basin(BaseModel, ArrowInputMixin):
    _input_type = "Basin"
    dataframe: DataFrame


class BasinState(BaseModel, ArrowInputMixin):
    _input_type = "Basin / state"
    dataframe: DataFrame


class BasinProfile(BaseModel, ArrowInputMixin):
    _input_type = "Basin / profile"
    dataframe: DataFrame


class BasinForcing(BaseModel, ArrowInputMixin):
    _input_type = "Basin / forcing"
    dataframe: DataFrame
