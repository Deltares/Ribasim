import tomllib
from pathlib import Path

import pytest

from ribasim_qgis.core.model import (
    get_database_path_from_model_file,
    get_directory_path_from_model_file,
)
from ribasim_qgis.core.nodes import get_external_input_files

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


def test_get_database_path_from_model_file():
    """Tests that get_database_path_from_model_file() can find the input directory and appends the database.gpkg to it."""
    path = get_database_path_from_model_file(data_folder_path / "simple_valid.toml")
    assert path.is_absolute(), f"{path} is not absolute"
    assert path.is_relative_to(tests_folder_path), (
        f"Path '{path}' is not relative to {tests_folder_path}"
    )
    assert path == data_folder_path / "database.gpkg"


def test_get_external_input_files():
    """Tests that get_external_input_files() returns empty dict for model without external files."""
    model_path = data_folder_path / "simple_valid.toml"
    with model_path.open("rb") as f:
        toml_data = tomllib.load(f)

    external_files = get_external_input_files(toml_data)
    assert isinstance(external_files, dict)
    assert len(external_files) == 0


def test_get_external_input_files_with_netcdf():
    """Tests that get_external_input_files() correctly identifies NetCDF files from TOML."""
    model_path = data_folder_path / "with_netcdf.toml"
    with model_path.open("rb") as f:
        toml_data = tomllib.load(f)

    external_files = get_external_input_files(toml_data)
    assert isinstance(external_files, dict)
    assert external_files["Basin / profile"] == "basin_profile.nc"
    assert external_files["FlowBoundary / time"] == "flow_boundary_time.nc"
