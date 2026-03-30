from pathlib import Path

import pytest

from ribasim_qgis.core.model import (
    get_database_path_from_model_file,
    get_directory_path_from_model_file,
)

tests_folder_path = Path(__file__).parent.resolve()
data_folder_path = tests_folder_path / "data"


@pytest.mark.parametrize(
    ("prop", "expected"),
    [("input_dir", "."), ("results_dir", "results")],
)
def test_get_directory_path_from_model_file(prop, expected):
    """Tests that get_directory_path_from_model_file() can resolve paths from a toml file."""
    path = get_directory_path_from_model_file(
        data_folder_path / "simple_valid.toml",
        property=prop,
    )
    assert path.is_absolute(), f"{path} is not absolute"
    assert path.is_relative_to(tests_folder_path), (
        f"Path '{path}' is not relative to {tests_folder_path}"
    )
    assert path == data_folder_path / expected


def test_get_database_path_from_model_file(self):
    """Tests that get_database_path_from_model_file() can find the input directory and appends the database.gpkg to it."""
    path = get_database_path_from_model_file(
        self.data_folder_path / "simple_valid.toml"
    )
    self.assertTrue(path.is_absolute(), msg=f"{path} is not absolute")
    self.assertTrue(
        path.is_relative_to(self.tests_folder_path),
        msg=f"Path '{path}' is not relative to {self.tests_folder_path}",
    )
    self.assertEqual(path, self.data_folder_path / "database.gpkg")
