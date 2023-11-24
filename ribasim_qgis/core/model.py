from pathlib import Path
from typing import Any

import ribasim_qgis.tomllib as tomllib


def get_database_path_from_model_file(path: str) -> str:
    """Generate database absolute full path from model .toml file.

    Args:
        path (str): Path to model .toml file.

    Returns_:
        str: Full path to database Geopackage.
    """
    model_filename = get_property_from_model_file(path, "database")
    return str(Path(path).parent.joinpath(model_filename))


def get_property_from_model_file(path: str, property: str) -> Any:
    with open(path, "rb") as f:
        return tomllib.load(f)[property]
