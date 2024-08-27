import pytest
from pydantic import ValidationError
from ribasim.nodes import basin
from ribasim.schemas import BasinProfileSchema
from shapely.geometry import Point


def test_config_inheritance():
    assert BasinProfileSchema.__config__.add_missing_columns
    assert BasinProfileSchema.__config__.coerce


def test_geometry_validation():
    with pytest.raises(
        ValidationError,
        match="Column 'geometry' failed element-wise validator number 0: <Check is_correct_geometry_type> failure cases",
    ):
        basin.Area(geometry=[Point([1.0, 2.0])])
