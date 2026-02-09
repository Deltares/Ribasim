"""
Classes to represent the Ribasim node layers.

The classes specify:

* The (unabbreviated) name
* The type of geometry ("No Geometry", "Point", "LineString", "Polygon")
* The required attributes of the attribute table

Each node layer is (optionally) represented in multiple places:

* It always lives in a GeoPackage.
* It can be added to the Layers Panel in QGIS. This enables a user to visualize
  and edit its data.

"""

from __future__ import annotations

from pathlib import Path
from typing import Any

from qgis.core import (
    QgsVectorLayer,
)

from ribasim_qgis.core import geopackage

STYLE_DIR = Path(__file__).parent / "styles"


class Table:
    """Base class for Ribasim input layers."""

    def __init__(self, input_type: str, path: Path):
        self.input_type = input_type
        self._path = path

    @property
    def labels(self) -> Any:
        return None

    def layer_from_geopackage(self) -> QgsVectorLayer:
        self.layer = QgsVectorLayer(
            f"{self._path}|layername={self.input_type}", self.input_type
        )
        # Load style from database if exists, otherwise load and save default qml style
        _, success = self.layer.loadDefaultStyle()
        if not success:
            self.load_default_style()
            self.save_style()

        return self.layer

    def from_geopackage(self) -> tuple[QgsVectorLayer, Any]:
        self.layer_from_geopackage()
        return (self.layer, self.labels)

    def stylename(self) -> str:
        return f"{self.input_type.replace(' / ', '_')}Style"

    def load_default_style(self):
        fn = STYLE_DIR / f"{self.stylename()}.qml"
        self.layer.loadNamedStyle(str(fn))

    def save_style(self):
        self.layer.saveStyleToDatabase(self.stylename(), "", True, "")


tables = {
    "Node",
    "Link",
    "Basin / concentration",
    "Basin / concentration_external",
    "Basin / concentration_state",
    "Basin / area",
    "Basin / profile",
    "Basin / state",
    "Basin / static",
    "Basin / subgrid",
    "Basin / subgrid_time",
    "Basin / time",
    "ContinuousControl / function",
    "ContinuousControl / variable",
    "DiscreteControl / condition",
    "DiscreteControl / logic",
    "DiscreteControl / variable",
    "FlowBoundary / concentration",
    "FlowBoundary / static",
    "FlowBoundary / time",
    "FlowBoundary / area",
    "FlowDemand / static",
    "FlowDemand / time",
    "LevelBoundary / concentration",
    "LevelBoundary / static",
    "LevelBoundary / time",
    "LevelDemand / static",
    "LevelDemand / time",
    "LinearResistance / static",
    "ManningResistance / static",
    "Outlet / static",
    "Outlet / time",
    "PidControl / static",
    "PidControl / time",
    "Pump / static",
    "Pump / time",
    "TabulatedRatingCurve / static",
    "TabulatedRatingCurve / time",
    "UserDemand / concentration",
    "UserDemand / static",
    "UserDemand / time",
}


def load_nodes_from_geopackage(path: Path) -> dict[str, Table]:
    # List the names in the geopackage
    gpkg_names = geopackage.layers(path)
    nodes = {}
    for layername in gpkg_names:
        if layername in tables:
            nodes[layername] = Table(layername, path)
    return nodes


def get_external_input_files(model_path: Path) -> dict[str, str]:
    """Get dictionary of external input files (NetCDF) from TOML.

    Parameters
    ----------
    model_path : Path
        Path to the model (.toml) file.

    Returns
    -------
    dict[str, str]
        Dictionary mapping table names (e.g., 'Basin / profile') to file paths.
    """
    import tomllib

    external_files = {}

    with model_path.open("rb") as f:
        toml_data = tomllib.load(f)

    # Derive node types from existing tables set
    # Extract unique node types (the part before ' / ')
    node_types = {table.split(" / ")[0] for table in tables if " / " in table}

    for node_type in node_types:
        # Convert PascalCase to snake_case for TOML lookup
        snake_case_type = "".join(
            ["_" + c.lower() if c.isupper() else c for c in node_type]
        ).lstrip("_")

        if snake_case_type not in toml_data:
            continue

        node_config = toml_data[snake_case_type]
        if not isinstance(node_config, dict):
            continue

        # Check each key in the node config for external files
        for table_key, value in node_config.items():
            if isinstance(value, str) and value.endswith(".nc"):
                table_name = f"{node_type} / {table_key}"
                # Only include if this table is in our known tables
                if table_name in tables:
                    external_files[table_name] = value

    return external_files


def load_external_input_tables(model_path: Path) -> dict[str, Table]:
    """Load external input files (NetCDF) as Table objects.

    Parameters
    ----------
    model_path : Path
        Path to the model (.toml) file.

    Returns
    -------
    dict[str, Table]
        Dictionary mapping table names to Table objects.
    """
    import tomllib

    external_files = get_external_input_files(model_path)

    if not external_files:
        return {}

    with model_path.open("rb") as f:
        toml_data = tomllib.load(f)

    input_dir = toml_data.get("input_dir", "")

    external_tables = {}
    for table_name, filepath in external_files.items():
        full_path = (model_path.parent / input_dir / filepath).resolve()

        if not full_path.exists():
            continue

        # Create a Table-like object for the external file
        table = ExternalTable(table_name, full_path)
        external_tables[table_name] = table

    return external_tables  # type: ignore[return-value]


class ExternalTable(Table):
    """Represents a table stored in an external NetCDF file."""

    def __init__(self, input_type: str, path: Path):
        super().__init__(input_type, path)

    def layer_from_geopackage(self) -> QgsVectorLayer:
        """Load the external NetCDF file as a QGIS vector layer.

        Uses QGIS/GDAL native support for NetCDF files.
        """
        # NetCDF can be loaded via GDAL NetCDF driver
        # GDAL NetCDF driver - use the format NETCDF:"filename":variable
        # For now, try loading the whole file
        uri = f"NETCDF:{self._path}"

        self.layer = QgsVectorLayer(uri, self.input_type, "ogr")

        # Fallback: try without NETCDF prefix if loading failed
        if not self.layer.isValid():
            self.layer = QgsVectorLayer(str(self._path), self.input_type, "ogr")

        # Mark as read-only since these are external files
        if self.layer.isValid():
            self.layer.setReadOnly(True)

        # Load style if available
        _, success = self.layer.loadDefaultStyle()
        if not success:
            self.load_default_style()
            # Don't save style to database for external files

        return self.layer
