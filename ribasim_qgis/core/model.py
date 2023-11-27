from pathlib import Path

import ribasim_qgis.tomllib as tomllib


def get_directory_path_from_model_file(model_path: Path, *, property: str) -> Path:
    """Generate database absolute full path from model .toml file.

    Args:
        path (Path): Path to model .toml file.
        property (str): The property to retrieve from the model file and append to the path.

    Returns_:
        Path: Full path to database Geopackage.
    """
    with open(model_path, "rb") as f:
        found_property = Path(tomllib.load(f)[property])
    # The .joinpath method (/) of pathlib.Path will take care of an absolute input_dir.
    # No need to check it ourselves!
    return (Path(model_path).parent / found_property).resolve()
