from pydantic import BaseModel

from ribasim.input_base import ArrowInputMixin
from ribasim.types import DataFrame


class TabulatedRatingCurve(BaseModel, ArrowInputMixin):
    _input_type = "TabulatedRatingCurve"
    dataframe: DataFrame
