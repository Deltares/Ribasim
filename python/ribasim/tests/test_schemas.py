import subprocess
import sys
import textwrap
from unittest.mock import patch

import pandas as pd
import pytest
import ribasim
from pandas.testing import assert_frame_equal
from pydantic import ValidationError
from ribasim import Model
from ribasim.db_utils import _get_db_schema_version, _set_db_schema_version
from ribasim.migrations import _rename_column
from ribasim.nodes import basin
from ribasim.schemas import BasinProfileSchema
from shapely.geometry import Point


def test_config_inheritance():
    assert BasinProfileSchema.__config__.add_missing_columns
    assert BasinProfileSchema.__config__.coerce


@patch("ribasim.schemas.migrations.nodeschema_migration")
def test_migration(migration, basic, tmp_path):
    toml_path = tmp_path / "basic.toml"
    db_path = tmp_path / "input/database.gpkg"
    basic.write(toml_path)

    # Migration is not needed on default model
    Model.read(toml_path)
    assert not migration.called

    # Fake old schema that needs migration
    _set_db_schema_version(db_path, 0)
    Model.read(toml_path)
    assert migration.called


def test_model_schema(basic, tmp_path):
    toml_path = tmp_path / "basic.toml"
    db_path = tmp_path / "input/database.gpkg"
    basic.write(toml_path)

    assert _get_db_schema_version(db_path) == ribasim.__schema_version__
    _set_db_schema_version(db_path, 0)
    assert _get_db_schema_version(db_path) == 0


def test_geometry_validation():
    with pytest.raises(
        ValidationError,
        match="Column 'geometry' failed element-wise validator number 0: <Check is_correct_geometry_type> failure cases",
    ):
        basin.Area(geometry=[Point([1.0, 2.0])])


def test_column_rename():
    df = pd.DataFrame({"edge_type": [1], "link_type": [2]})
    _rename_column(df, "edge_type", "link_type")
    assert_frame_equal(df, pd.DataFrame({"link_type": [1]}))
    df = pd.DataFrame({"edge_type": [1]})
    _rename_column(df, "edge_type", "link_type")
    assert_frame_equal(df, pd.DataFrame({"link_type": [1]}))
    df = pd.DataFrame({"link_type": [2]})
    assert_frame_equal(df, _rename_column(df, "edge_type", "link_type"))


def test_df_accepts_plain_dataframe(basic):
    """Assigning a pd.DataFrame (e.g. from pd.concat) to a TableModel.df should work."""
    static = basic.manning_resistance.static
    original_df = static.df
    assert original_df is not None

    # pd.concat returns a plain pd.DataFrame, not a pandera DataFrame
    new_df = pd.concat([original_df], ignore_index=True)
    assert type(new_df) is pd.DataFrame

    static.df = new_df
    assert static.df is not None
    assert len(static.df) == len(original_df)

    # Pandera validation must still run: missing columns are added, index is coerced
    assert "control_state" in static.df.columns
    assert static.df.index.dtype == "int32"


def test_df_accepts_plain_dataframe_typing(tmp_path):
    """Pyrefly should not report bad-assignment when assigning pd.DataFrame to TableModel.df."""
    snippet = tmp_path / "check_df_typing.py"
    snippet.write_text(
        textwrap.dedent("""\
            import pandas as pd
            from ribasim.input_base import TableModel
            from ribasim.schemas import ManningResistanceStaticSchema

            table = TableModel[ManningResistanceStaticSchema]()
            table.df = pd.DataFrame()
        """),
        encoding="utf-8",
    )
    result = subprocess.run(
        [sys.executable, "-m", "pyrefly", "check", str(snippet)],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    assert "bad-assignment" not in result.stdout, result.stdout
    assert "bad-assignment" not in result.stderr, result.stderr
