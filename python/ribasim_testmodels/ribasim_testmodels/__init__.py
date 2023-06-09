__version__ = "0.1.1"

from ribasim_testmodels.basic import (
    basic_model,
    basic_transient_model,
    tabulated_rating_curve_model,
)
from ribasim_testmodels.trivial import trivial_model

__all__ = [
    "basic_model",
    "basic_transient_model",
    "tabulated_rating_curve_model",
    "trivial_model",
]
