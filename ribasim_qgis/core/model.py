from pathlib import Path
from typing import Any

from qgis.core import qgsfunction

import ribasim_qgis.tomllib as tomllib


def get_directory_path_from_model_file(model_path: Path, *, property: str) -> Path:
    """Generate database absolute full path from model .toml file.

    Parameters
    ----------
    path : Path
        Path to model .toml file.
    property : str
        The property to retrieve from the model file and append to the path.

    Returns
    -------
    Path
        Full path to database Geopackage.
    """
    with open(model_path, "rb") as f:
        found_property = Path(tomllib.load(f)[property])
    # The .joinpath method (/) of pathlib.Path will take care of an absolute input_dir.
    # No need to check it ourselves!
    return (Path(model_path).parent / found_property).resolve()


def get_toml_dict(model_path: Path) -> dict[str, Any]:
    with open(model_path, "rb") as f:
        return tomllib.load(f)


def get_database_path_from_model_file(model_path: Path) -> Path:
    """Get the database path database.gpkg based on the model file's input_dir.

    Parameters
    ----------
    model_path : Path
        Path to the model (.toml) file.

    Returns
    -------
    Path
        The full path to database.gpkg
    """
    return (
        get_directory_path_from_model_file(model_path, property="input_dir")
        / "database.gpkg"
    )


@qgsfunction(args="auto", group="Custom", referenced_columns=[])  # type: ignore
def label_flow_rate(value: float) -> str:
    """
    Format the label for `flow_rate`.

    Above 1, show 2 decimals.
    Show 0 as 0.
    Between 0 and 1, and below 1, show scientific notation and 2 decimals.
    Example outputs: 0, 1.23e-06, 12345.68
    """
    if abs(value) >= 1:
        return f"{value:.2f}"
    if abs(value) == 0.0:
        return "0"
    else:
        return f"{value:.2e}"


@qgsfunction(args="auto", group="Custom", referenced_columns=[])  # type: ignore
def label_scientific(value: float) -> str:
    """
    Format the label for `concentration`.

    Uses scientific notation with 3 decimals.
    """
    return f"{value:.3e}"
