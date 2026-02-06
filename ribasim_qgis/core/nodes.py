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


def get_external_input_files(model_path: Path) -> list[dict[str, str]]:
    """Get list of external input files (NetCDF or Arrow) from TOML.

    Parameters
    ----------
    model_path : Path
        Path to the model (.toml) file.

    Returns
    -------
    list[dict[str, str]]
        List of dictionaries with 'node_type', 'table', 'filepath', and 'table_name' keys.
    """
    import tomllib

    external_files = []

    with model_path.open("rb") as f:
        toml_data = tomllib.load(f)

    # List of node types that might have external input files
    node_types = [
        "basin",
        "continuous_control",
        "discrete_control",
        "flow_boundary",
        "flow_demand",
        "level_boundary",
        "level_demand",
        "linear_resistance",
        "manning_resistance",
        "outlet",
        "pid_control",
        "pump",
        "tabulated_rating_curve",
        "user_demand",
    ]

    for node_type in node_types:
        if node_type not in toml_data:
            continue

        node_config = toml_data[node_type]
        if not isinstance(node_config, dict):
            continue

        # Check each key in the node config for external files
        for table_key, value in node_config.items():
            if isinstance(value, str) and (
                value.endswith(".nc") or value.endswith(".arrow")
            ):
                # Convert snake_case to PascalCase for display name
                display_node_type = "".join(
                    word.capitalize() for word in node_type.split("_")
                )
                table_name = f"{display_node_type} / {table_key}"

                external_files.append(
                    {
                        "node_type": node_type,
                        "table": table_key,
                        "filepath": value,
                        "table_name": table_name,
                    }
                )

    return external_files


def load_external_input_layer(
    model_path: Path,
    filepath: str,
    layer_name: str,
) -> QgsVectorLayer | None:
    """Load an external input file (NetCDF or Arrow) as a QGIS layer.

    Parameters
    ----------
    model_path : Path
        Path to the model (.toml) file.
    filepath : str
        Relative path to the external file from the model directory.
    layer_name : str
        Name for the layer in QGIS.

    Returns
    -------
    QgsVectorLayer | None
        The loaded layer, or None if loading failed.
    """
    import tomllib

    import pandas as pd
    from osgeo import ogr
    from PyQt5.QtCore import QMetaType
    from qgis.core import QgsFeature, QgsField, edit

    with model_path.open("rb") as f:
        toml_data = tomllib.load(f)

    input_dir = toml_data.get("input_dir", "")
    full_path = (model_path.parent / input_dir / filepath).resolve()

    if not full_path.exists():
        return None

    # Try to open with OGR (supports both Arrow and NetCDF)
    try:
        if filepath.endswith(".arrow"):
            # Arrow files can be loaded directly with OGR
            dataset = ogr.Open(str(full_path))
            if dataset is None:
                return None

            # Get stream and convert to pandas
            ogr_layer = dataset.GetLayer(0)
            if ogr_layer is None:
                return None

            # Read Arrow data as pandas DataFrame
            stream = ogr_layer.GetArrowStreamAsNumPy()
            dfs = []
            while (batch := stream.GetNextRecordBatch()) is not None:
                df = pd.DataFrame(batch)
                dfs.append(df)

            if not dfs:
                return None

            df = pd.concat(dfs, ignore_index=True)

            # Convert bytes columns to strings
            import contextlib

            for column in df.columns:
                if df.dtypes[column] == object:  # noqa: E721
                    with contextlib.suppress(AttributeError, UnicodeDecodeError):
                        df[column] = df[column].str.decode("utf-8")

            # Create a memory layer with the data
            layer = QgsVectorLayer("None", layer_name, "memory")

            # Add fields based on DataFrame columns
            fields = []
            for col in df.columns:
                dtype = df[col].dtype
                if dtype in ["int32", "int64", "int"]:
                    fields.append(QgsField(col, QMetaType.Type.Int))
                elif dtype in ["float32", "float64", "float"]:
                    fields.append(QgsField(col, QMetaType.Type.Double))
                else:
                    fields.append(QgsField(col, QMetaType.Type.QString))

            with edit(layer):
                layer.dataProvider().addAttributes(fields)
            layer.updateFields()

            # Add features
            features = []
            for _, row in df.iterrows():
                feature = QgsFeature(layer.fields())
                for col in df.columns:
                    value = row[col]
                    # Handle pandas NA/NaT
                    if pd.isna(value):
                        value = None
                    feature.setAttribute(col, value)
                features.append(feature)

            with edit(layer):
                layer.dataProvider().addFeatures(features)
            layer.updateExtents()

        elif filepath.endswith(".nc"):
            # NetCDF files: load via pandas/xarray and create memory layer
            try:
                import xarray as xr
            except ImportError:
                print(
                    "xarray is required to load NetCDF files. Install it with: pip install xarray netCDF4"
                )
                return None

            # Open NetCDF with xarray
            ds = xr.open_dataset(full_path)
            df = ds.to_dataframe().reset_index()
            ds.close()

            # Create a memory layer
            layer = QgsVectorLayer("None", layer_name, "memory")

            # Add fields based on DataFrame columns
            fields = []
            for col in df.columns:
                dtype = df[col].dtype
                if dtype in ["int32", "int64", "int"]:
                    fields.append(QgsField(col, QMetaType.Type.Int))
                elif dtype in ["float32", "float64", "float"]:
                    fields.append(QgsField(col, QMetaType.Type.Double))
                elif dtype == "datetime64[ns]":
                    fields.append(QgsField(col, QMetaType.Type.QDateTime))
                else:
                    fields.append(QgsField(col, QMetaType.Type.QString))

            with edit(layer):
                layer.dataProvider().addAttributes(fields)
            layer.updateFields()

            # Add features
            features = []
            for _, row in df.iterrows():
                feature = QgsFeature(layer.fields())
                for col in df.columns:
                    value = row[col]
                    # Handle pandas NA/NaT
                    if pd.isna(value):
                        value = None
                    elif isinstance(value, pd.Timestamp):
                        # Convert pandas Timestamp to string for QGIS
                        value = str(value)
                    feature.setAttribute(col, value)
                features.append(feature)

            with edit(layer):
                layer.dataProvider().addFeatures(features)
            layer.updateExtents()
        else:
            return None

        if not layer.isValid():
            return None

        # Mark layer as read-only
        layer.setReadOnly(True)

        return layer

    except Exception as e:
        # Return None if loading fails
        print(f"Error loading external input file: {e}")
        return None
