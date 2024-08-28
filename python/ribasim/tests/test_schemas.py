from unittest.mock import patch

import pytest
from pydantic import ValidationError
from ribasim import Model
from ribasim.db_utils import _set_db_schema_version
from ribasim.nodes import basin
from ribasim.schemas import BasinProfileSchema
from shapely.geometry import Point


def test_config_inheritance():
    assert BasinProfileSchema.__config__.add_missing_columns
    assert BasinProfileSchema.__config__.coerce


@patch("ribasim.schemas.migrations.nodeschema_migration")
def test_migration(migration, basic, tmp_path):
    toml_path = tmp_path / "basic.toml"
    db_path = tmp_path / "database.gpkg"
    basic.write(toml_path)

    # Fake old schema that needs migration
    _set_db_schema_version(db_path, 0)

    Model.read(toml_path)
    assert migration.called


def test_geometry_validation():
    with pytest.raises(
        ValidationError,
        match="Column 'geometry' failed element-wise validator number 0: <Check is_correct_geometry_type> failure cases",
    ):
        basin.Area(geometry=[Point([1.0, 2.0])])
