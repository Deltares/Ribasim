from pydantic import BaseModel

from ribasim.input_base import ArrowInputMixin
from ribasim.types import DataFrame


class LevelControl(BaseModel, ArrowInputMixin):
    _input_type = "LevelControl"
    dataframe: DataFrame


class LevelControlForcing(BaseModel, ArrowInputMixin):
    _input_type = "LevelControl / forcing"
    dataframe: DataFrame
