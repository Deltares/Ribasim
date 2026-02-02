from pathlib import Path

from qgis.testing import unittest

from ribasim_qgis.core.model import (
    get_database_path_from_model_file,
    get_directory_path_from_model_file,
)


class TestModel(unittest.TestCase):
    tests_folder_path = Path(__file__).parent.resolve()
    data_folder_path = tests_folder_path / "data"

    def test_get_directory_path_from_model_file(self):
        """Tests that get_directory_path_from_model_file() can resolve paths from a toml file."""
        for test_case in [("input_dir", "."), ("results_dir", "results")]:
            with self.subTest(property=test_case[0], value=test_case[1]):
                path = get_directory_path_from_model_file(
                    self.data_folder_path / "simple_valid.toml",
                    property=test_case[0],
                )
                self.assertTrue(path.is_absolute(), msg=f"{path} is not absolute")
                self.assertTrue(
                    path.is_relative_to(self.tests_folder_path),
                    msg=f"Path '{path}' is not relative to {self.tests_folder_path}",
                )
                self.assertEqual(path, self.data_folder_path / test_case[1])

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
