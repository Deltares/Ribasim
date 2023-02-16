"""
This module contains the classes to represent the Ribasim ndoe layers.

The classes specify:

* The (unabbreviated) name
* The type of geometry (No geometry, point, linestring, polygon)
* The required attributes of the attribute table

Each node layer is (optionally) represented in multiple places:

* It always lives in a GeoPackage.
* While a geopackage is active within plugin, it is always represented in a
  Dataset Tree: the Dataset Tree provides a direct look at the state of the
  GeoPackage. In this tree, steady and transient input are on the same row.
  Associated input is, to potentially enable transient associated data later
  on (like a building pit with changing head top boundary).
* It can be added to the Layers Panel in QGIS. This enables a user to visualize
  and edit its data.

"""

import abc
from typing import Any, List, Tuple

from PyQt5.QtCore import QVariant
from PyQt5.QtWidgets import (
    QDialog,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QPushButton,
    QVBoxLayout,
)
from qgis.core import (
    QgsDefaultValue,
    QgsFeature,
    QgsField,
    QgsFillSymbol,
    QgsGeometry,
    QgsLineSymbol,
    QgsPointXY,
    QgsSingleSymbolRenderer,
    QgsVectorLayer,
)
from ribasim_qgis.core import geopackage


class NameDialog(QDialog):
    def __init__(self, parent=None):
        super(NameDialog, self).__init__(parent)
        self.name_line_edit = QLineEdit()
        self.ok_button = QPushButton("OK")
        self.cancel_button = QPushButton("Cancel")
        self.ok_button.clicked.connect(self.accept)
        self.cancel_button.clicked.connect(self.reject)
        first_row = QHBoxLayout()
        first_row.addWidget(QLabel("Layer name"))
        first_row.addWidget(self.name_line_edit)
        second_row = QHBoxLayout()
        second_row.addStretch()
        second_row.addWidget(self.ok_button)
        second_row.addWidget(self.cancel_button)
        layout = QVBoxLayout()
        layout.addLayout(first_row)
        layout.addLayout(second_row)
        self.setLayout(layout)


class RibasimInput(abc.ABC):
    """
    Abstract base class for Ribasim input layers.
    """

    element_type = None
    geometry_type = None
    attributes = []

    def _initialize_default(self, path, name):
        """Things to always initialize for every input layer."""
        self.name = name
        self.path = path
        self.ribasim_name = f"Ribasim {self.element_type}:{name}"
        self.layer = None

    @abc.abstractmethod
    def _initialize(self, path, name):
        pass

    def __init__(self, path: str, name: str):
        self._initialize_default(path, name)
        self._initialize()

    @staticmethod
    def dialog(
        path: str, crs: Any, iface: Any, klass: type, names: List[str]
    ) -> Tuple[Any]:
        dialog = NameDialog()
        dialog.show()
        ok = dialog.exec_()
        if not ok:
            return

        name = dialog.name_line_edit.text()
        if name in names:
            raise ValueError(f"Name already exists in geopackage: {name}")

        instance = klass(path, name)
        instance.create_layers(crs)
        return instance

    def new_layer(self, crs: Any, geometry_type: str, name: str, attributes: List):
        layer = QgsVectorLayer(geometry_type, name, "memory")
        provider = layer.dataProvider()
        provider.addAttributes(attributes)
        layer.updateFields()
        layer.setCrs(crs)
        self.layer = layer
        return

    def renderer(self):
        return

    def layer_from_geopackage(self) -> QgsVectorLayer:
        self.timml_layer = QgsVectorLayer(
            f"{self.path}|layername={self.ribasim_name}", self.ribasim_name
        )
        return

    def from_geopackage(self):
        self.layer_from_geopackage()
        return (self.layer, self.renderer())

    def write(self):
        self.layer = geopackage.write_layer(self.path, self.layer, self.ribasim_name)
        return

    def remove_from_geopackage(self):
        geopackage.remove_layer(self.path, self.ribasim_name)


class Edges(RibasimInput):
    def _initialize(self):
        self.element_type = "edge"
        self.geometry_type = "Linestring"
        self.attributes = [
            QgsField("from_id", QVariant.Int),
            QgsField("from_node", QVariant.String),
            QgsField("to_id", QVariant.Int),
            QgsField("to_node", QVariant.String),
        ]


class Lsw(RibasimInput):
    def _initialize(self):
        self.element_type = "node"
        self.geometry_type = "Point"
        self.attributes = [
            QgsField("id", QVariant.Int),
        ]


class LswLookup(RibasimInput):
    def _initialize(self):
        self.element_type = "lookup_LSW"
        self.geometry_type = "No Geometry"
        self.attributes = [
            QgsField("id", QVariant.Int),
            QgsField("volume", QVariant.Double),
            QgsField("area", QVariant.Double),
            QgsField("level", QVariant.Double),
        ]


class OutflowTableLookup(RibasimInput):
    def _initialize(self):
        self.element_type = "lookup_OutflowTable"
        self.geometry_type = "No Geometry"
        self.attributes = [
            QgsField("id", QVariant.Int),
            QgsField("level", QVariant.Double),
            QgsField("discharge", QVariant.Double),
        ]


class Bifurcation(RibasimInput):
    def _initialize(self):
        self.element_type = "static_Bifurcation"
        self.geometry_type = "No Geometry"
        self.attributes = [
            QgsField("id", QVariant.Int),
            QgsField("fraction_1", QVariant.Double),
            QgsField("fraction_2", QVariant.Double),
        ]


class LevelControl(RibasimInput):
    def _initialize(self):
        self.element_type = "static_LevelControl"
        self.geometry_type = "No Geometry"
        self.attributes = [
            QgsField("id", QVariant.Int),
            QgsField("target_volume", QVariant.Double),
        ]


class LswState(RibasimInput):
    def _initialize(self):
        self.element_type = "state_LSW"
        self.geometry_type = "No Geometry"
        self.attributes = [
            QgsField("id", QVariant.Int),
            QgsField("S", QVariant.Double),
            QgsField("C", QVariant.Double),
        ]


class LswForcing(RibasimInput):
    def _initialize(self):
        self.element_type = "forcing_LSW"
        self.geometry_type = "No Geometry"
        self.attributes = [
            QgsField("id", QVariant.Int),
            QgsField("time", QVariant.QDateTime),
            QgsField("P", QVariant.Double),
            QgsField("ET", QVariant.Double),
        ]


NODES = {
    "Edges": Edges,
    "LSW": Lsw,
    "lookup LSW": LswLookup,
    "lookup OutflowTable": OutflowTableLookup,
    "static Bifurcation": Bifurcation,
    "static LevelControl": LevelControl,
}


def parse_name(layername: str) -> Tuple[str, str]:
    """
    Based on the layer name find out:

    * whether it's a Ribasim input layer;
    * which element type it is;
    * what the user provided name is.

    For example:
    parse_name("Ribasim Edges: network") -> ("Edges", "network")
    """
    values = layername.split("_")
    if len(values) == 2:
        _, kind = values
        nodetype = None
    elif len(values) == 3:
        _, kind, nodetype = values
    else:
        raise ValueError(
            'Expected layer name of "ribasim_{kind}_{nodetype}", '
            f'"ribasim_node", "ribasim_edge". Received {layername}'
        )
    return kind, nodetype


def load_nodes_from_geopackage(path: str) -> List[RibasimInput]:
    # List the names in the geopackage
    gpkg_names = geopackage.layers(path)

    # Group them on the basis of name
    nodes = []
    for layername in gpkg_names:
        if layername.startswith("ribasim_"):
            kind, nodetype = parse_name(layername)
            if kind in ("node", "edge"):
                key = kind
            else:
                key = f"{kind} {nodetype}"
            nodes.append(NODES[key](path))

    return nodes
