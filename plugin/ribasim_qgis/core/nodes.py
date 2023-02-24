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
from typing import Any, Dict, List, Tuple

from PyQt5.QtCore import QVariant
from PyQt5.QtGui import QColor
from PyQt5.QtWidgets import (
    QDialog,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QPushButton,
    QVBoxLayout,
)
from qgis.core import (
    QgsCategorizedSymbolRenderer,
    QgsDefaultValue,
    QgsEditorWidgetSetup,
    QgsFeature,
    QgsField,
    QgsFillSymbol,
    QgsGeometry,
    QgsLineSymbol,
    QgsMarkerSymbol,
    QgsPalLayerSettings,
    QgsPointXY,
    QgsRendererCategory,
    QgsSimpleMarkerSymbolLayerBase,
    QgsSingleSymbolRenderer,
    QgsVectorLayer,
    QgsVectorLayerSimpleLabeling,
)
from ribasim_qgis.core import geopackage


class RibasimInput(abc.ABC):
    """
    Abstract base class for Ribasim input layers.
    """

    def __init__(self, path: str):
        self.name = f"ribasim_{self.input_type}"
        self.path = path
        self.layer = None

    @classmethod
    def create(cls, path: str, crs: Any, names: List[str]) -> "RibasimInput":
        instance = cls(path)
        if instance.name in names:
            raise ValueError(f"Name already exists in geopackage: {instance.name}")
        instance.layer = instance.new_layer(crs)
        return instance

    def new_layer(self, crs: Any) -> Any:
        """
        Separate creation of the instance with creating the layer, since the
        layer might also come from an existing geopackage.
        """
        layer = QgsVectorLayer(self.geometry_type, self.name, "memory")
        provider = layer.dataProvider()
        provider.addAttributes(self.attributes)
        layer.updateFields()
        layer.setCrs(crs)
        return layer

    def set_defaults(self):
        layer = self.layer
        defaults = getattr(self, "defaults", None)
        if layer is None or defaults is None:
            return
        fields = layer.fields()
        for name, definition in defaults.items():
            index = fields.indexFromName(name)
            layer.setDefaultValueDefinition(index, definition)
        return

    def set_read_only(self) -> None:
        return

    @property
    def renderer(self) -> None:
        return

    @property
    def labels(self) -> None:
        return

    def layer_from_geopackage(self) -> QgsVectorLayer:
        self.layer = QgsVectorLayer(f"{self.path}|layername={self.name}", self.name)
        return

    def from_geopackage(self) -> Tuple[Any, Any]:
        self.layer_from_geopackage()
        return (self.layer, self.renderer, self.labels)

    def write(self) -> None:
        self.layer = geopackage.write_layer(self.path, self.layer, self.name)
        self.set_defaults()
        return

    def remove_from_geopackage(self) -> None:
        geopackage.remove_layer(self.path, self.name)
        return

    def set_editor_widget(self) -> None:
        """Calling during new_layer doesn't have any effect..."""
        return


class Basin(RibasimInput):
    input_type = "node"
    geometry_type = "Point"
    attributes = [
        # TODO: node should be a ComboBox?
        QgsField("node", QVariant.String),  # TODO discuss
    ]

    def write(self) -> None:
        """
        Special the LSW layer write because it needs to generate a new file.
        """
        self.layer = geopackage.write_layer(
            self.path, self.layer, self.name, newfile=True
        )
        self.set_defaults()
        return

    def set_editor_widget(self) -> None:
        layer = self.layer
        index = layer.fields().indexFromName("node")
        setup = QgsEditorWidgetSetup(
            "ValueMap",
            {
                "map": {
                    "LSW": "LSW",
                    "Bifurcation": "Bifurcation",
                    "OutflowTable": "OutflowTable",
                    "LevelControl": "LevelControl",
                },
            },
        )
        layer.setEditorWidgetSetup(index, setup)

        layer_form_config = layer.editFormConfig()
        layer_form_config.setReuseLastValue(1, True)
        layer.setEditFormConfig(layer_form_config)

        return

    @property
    def renderer(self) -> QgsCategorizedSymbolRenderer:
        shape = QgsSimpleMarkerSymbolLayerBase
        markers = {
            "LSW": (QColor("blue"), "LSW", shape.Circle),
            "Bifurcation": (QColor("red"), "Bifurcation", shape.Triangle),
            "OutflowTable": (QColor("green"), "OutflowTable", shape.Diamond),
            "LevelControl": (QColor("blue"), "LevelControl", shape.Star),
            "": (
                QColor("white"),
                "",
                shape.Circle,
            ),  # All other nodes, or incomplete input
        }

        categories = []
        for value, (colour, label, shape) in markers.items():
            symbol = QgsMarkerSymbol()
            symbol.symbolLayer(0).setShape(shape)
            symbol.setColor(QColor(colour))
            symbol.setSize(4)
            category = QgsRendererCategory(value, symbol, label, shape)
            categories.append(category)

        renderer = QgsCategorizedSymbolRenderer(attrName="node", categories=categories)
        return renderer

    @property
    def labels(self) -> Any:
        pal_layer = QgsPalLayerSettings()
        pal_layer.fieldName = "fid"
        pal_layer.enabled = True
        pal_layer.dist = 2.0
        labels = QgsVectorLayerSimpleLabeling(pal_layer)
        return labels


class Edges(RibasimInput):
    input_type = "edge"
    geometry_type = "Linestring"
    attributes = [
        QgsField("from_node_fid", QVariant.Int),
        QgsField("to_node_fid", QVariant.Int),
    ]

    @property
    def renderer(self) -> QgsSingleSymbolRenderer:
        symbol = QgsLineSymbol.createSimple(
            {
                "color": "#3690c0",  # lighter blue
                "width": "0.5",
            }
        )
        return QgsSingleSymbolRenderer(symbol)

    def set_read_only(self) -> None:
        layer = self.layer
        config = layer.editFormConfig()
        for index in range(len(layer.fields())):
            config.setReadOnly(index, True)
        layer.setEditFormConfig(config)
        return


class BasinLookup(RibasimInput):
    input_type = "lookup_LSW"
    geometry_type = "No Geometry"
    attributes = [
        QgsField("node_fid", QVariant.Int),
        QgsField("volume", QVariant.Double),
        QgsField("area", QVariant.Double),
        QgsField("level", QVariant.Double),
    ]


class OutflowTableLookup(RibasimInput):
    input_type = "lookup_OutflowTable"
    geometry_type = "No Geometry"
    attributes = [
        QgsField("node_fid", QVariant.Int),
        QgsField("level", QVariant.Double),
        QgsField("discharge", QVariant.Double),
    ]


class Bifurcation(RibasimInput):
    input_type = "static_Bifurcation"
    geometry_type = "No Geometry"
    attributes = [
        QgsField("node_fid", QVariant.Int),
        QgsField("fraction_1", QVariant.Double),
        QgsField("fraction_2", QVariant.Double),
    ]


class LevelControl(RibasimInput):
    input_type = "static_LevelControl"
    geometry_type = "No Geometry"
    attributes = [
        QgsField("node_fid", QVariant.Int),
        QgsField("target_volume", QVariant.Double),
    ]


class BasinState(RibasimInput):
    input_type = "state_LSW"
    geometry_type = "No Geometry"
    attributes = [
        QgsField("node_fid", QVariant.Int),
        QgsField("S", QVariant.Double),
        QgsField("C", QVariant.Double),
    ]


class BasinForcing(RibasimInput):
    input_type = "forcing_LSW"
    geometry_type = "No Geometry"
    attributes = [
        QgsField("time", QVariant.DateTime),
        QgsField("node_fid", QVariant.Int),
        QgsField("demand", QVariant.Double),
        QgsField("drainage", QVariant.Double),
        QgsField("E_pot", QVariant.Double),
        QgsField("infiltration", QVariant.Double),
        QgsField("P", QVariant.Double),
        QgsField("priority", QVariant.Double),
        QgsField("urban_runoff", QVariant.Double),
    ]


NODES = {
    "node": Basin,
    "edge": Edges,
    "lookup_LSW": BasinLookup,
    "lookup_OutflowTable": OutflowTableLookup,
    "static_Bifurcation": Bifurcation,
    "static_LevelControl": LevelControl,
    "forcing_LSW": BasinForcing,
}


def parse_name(layername: str) -> Tuple[str, str]:
    """
    Based on the layer name find out which type it is.

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


def load_nodes_from_geopackage(path: str) -> Dict[str, RibasimInput]:
    # List the names in the geopackage
    gpkg_names = geopackage.layers(path)
    nodes = {}
    for layername in gpkg_names:
        if layername.startswith("ribasim_"):
            kind, nodetype = parse_name(layername)
            if kind in ("node", "edge"):
                key = kind
            else:
                key = f"{kind}_{nodetype}"
            nodes[key] = NODES[key](path)

    return nodes
