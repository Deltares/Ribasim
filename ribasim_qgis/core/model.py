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
    with open(path, "rb") as f:
        input_dir = Path(tomllib.load(f)["input_dir"])
    # The .joinpath method (/) of pathlib.Path will take care of an absolute input_dir.
    # No need to check it ourselves!
    return str((Path(path).parent / input_dir / "database.gpkg").resolve())


def get_property_from_model_file(path: str, property: str) -> Any:
    with open(path, "rb") as f:
        return tomllib.load(f)[property]
