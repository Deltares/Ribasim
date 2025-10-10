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

    def nodetype(self):
        return self.input_type.split("/")[0].strip()

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
