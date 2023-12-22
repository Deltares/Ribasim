from functools import reduce
from pathlib import Path
from typing import Any

from qgis.core import QgsVectorLayer

from .. import tomllib
from .nodes import NODES


def get_directory_path_from_model_file(
    model_path: Path, *properties: str, directory_key: str
) -> Path | None:
    """Generate database absolute full path from model .toml file.

    Args:
        model_path (Path): Path to model .toml file.
        properties (list[str]): The properties to retrieve from the model file and append to the path.
        directory_key (str): The key to use to get the directory path from the model file. Could be input_dir or results_dir.

    Returns_:
        Path: Full path to database Geopackage.
    """
    with open(model_path, "rb") as f:
        toml_file = tomllib.load(f)
    directory_path = toml_file[directory_key]
    found_path = __recursive_get(toml_file, *properties) if properties else "."
    if found_path != {}:
        # The .joinpath method (/) of pathlib.Path will take care of an absolute input_dir.
        # No need to check it ourselves!
        return (Path(model_path).parent / directory_path / found_path).resolve()
    else:
        return None


def get_database_path_from_model_file(model_path: Path) -> Path | None:
    """Get the database path database.gpkg based on the model file's input_dir.

    Args:
        model_path (Path): Path to the model (.toml) file.

    Returns_:
        Path: The full path to database.gpkg
    """
    input_dir = get_directory_path_from_model_file(
        model_path, directory_key="input_dir"
    )
    if input_dir is not None:
        return input_dir / "database.gpkg"
    else:
        return None


def get_arrow_layers_from_model(model_path: Path) -> list[QgsVectorLayer]:
    """Get the arrow layers from the model file.

    Args:
        model_path (Path): Path to the model (.toml) file.

    Returns_:
        list[QgsVectorLayer]: List of arrow layers.
    """
    return [
        layer
        for node_type in NODES.keys()
        if (layer := __create_arrow_layer_from_model(model_path, node_type)) is not None
    ]


def __create_arrow_layer_from_model(
    model_path: Path, node_type: str
) -> QgsVectorLayer | None:
    """Create an arrow layer from the model file.

    Args:
        model_path (Path): Path to the model (.toml) file.
        node_type (str):
            Node type to create the arrow layer for.
            Should come from the NODES list, contains a / to separate table from entry.
            See ribasim_qgis.core.nodes.NODES.

    Returns_:
        QgsVectorLayer: Arrow layer.
    """
    if "/" in node_type:
        table, node = node_type.lower().split(" / ", maxsplit=1)
        arrow_file_path = get_directory_path_from_model_file(
            model_path, table, node, directory_key="input_dir"
        )

        if arrow_file_path is not None and arrow_file_path.exists():
            return QgsVectorLayer(str(arrow_file_path), node_type, "ogr")

    return None


def __recursive_get(d: dict[Any, Any], *keys: Any) -> Any:
    return reduce(lambda c, k: c.get(k, {}), keys, d)
