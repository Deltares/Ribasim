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
from qgis.core import (
    QgsCategorizedSymbolRenderer,
    QgsEditorWidgetSetup,
    QgsField,
    QgsLineSymbol,
    QgsMarkerSymbol,
    QgsPalLayerSettings,
    QgsRendererCategory,
    QgsSimpleMarkerSymbolLayerBase,
    QgsSingleSymbolRenderer,
    QgsVectorLayer,
    QgsVectorLayerSimpleLabeling,
)
from ribasim_qgis.core import geopackage


class Input(abc.ABC):
    """
    Abstract base class for Ribasim input layers.
    """

    def __init__(self, path: str):
        self.name = self.input_type
        self.path = path
        self.layer = None

    @classmethod
    def create(cls, path: str, crs: Any, names: List[str]) -> "Input":
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


class Node(Input):
    input_type = "Node"
    geometry_type = "Point"
    attributes = (QgsField("Node", QVariant.String),)

    def write(self) -> None:
        """
        Special the Basin layer write because it needs to generate a new file.
        """
        self.layer = geopackage.write_layer(
            self.path, self.layer, self.name, newfile=True
        )
        self.set_defaults()
        return

    def set_editor_widget(self) -> None:
        layer = self.layer
        index = layer.fields().indexFromName("Node")
        setup = QgsEditorWidgetSetup(
            "ValueMap",
            {
                "map": {
                    "Basin": "Basin",
                    "FractionalFlow": "FractionalFlow",
                    "TabulatedRatingCurve": "TabulatedRatingCurve",
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
            "Basin": (QColor("blue"), "Basin", shape.Circle),
            "FractionalFlow": (QColor("red"), "FractionalFlow", shape.Triangle),
            "TabulatedRatingCurve": (
                QColor("green"),
                "TabulatedRatingCurve",
                shape.Diamond,
            ),
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

        renderer = QgsCategorizedSymbolRenderer(attrName="Node", categories=categories)
        return renderer

    @property
    def labels(self) -> Any:
        pal_layer = QgsPalLayerSettings()
        pal_layer.fieldName = "fid"
        pal_layer.enabled = True
        pal_layer.dist = 2.0
        labels = QgsVectorLayerSimpleLabeling(pal_layer)
        return labels


class Edge(Input):
    input_type = "Edge"
    geometry_type = "Linestring"
    attributes = [
        QgsField("from_node_id", QVariant.Int),
        QgsField("to_node_id", QVariant.Int),
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


class BasinProfile(Input):
    input_type = "Basin / profile"
    geometry_type = "No Geometry"
    attributes = [
        QgsField("node_id", QVariant.Int),
        QgsField("storage", QVariant.Double),
        QgsField("area", QVariant.Double),
        QgsField("level", QVariant.Double),
    ]


class Basin(Input):
    input_type = "Basin"
    geometry_type = "No geometry"
    attributes = [
        QgsField("node_id", QVariant.Int),
        QgsField("drainage", QVariant.Double),
        QgsField("potential_evaporation", QVariant.Double),
        QgsField("infiltration", QVariant.Double),
        QgsField("precipitation", QVariant.Double),
        QgsField("urban_runoff", QVariant.Double),
    ]


class BasinForcing(Input):
    input_type = "Basin / forcing"
    geometry_type = "No Geometry"
    attributes = [
        QgsField("time", QVariant.DateTime),
        QgsField("node_id", QVariant.Int),
        QgsField("drainage", QVariant.Double),
        QgsField("potential_evaporation", QVariant.Double),
        QgsField("infiltration", QVariant.Double),
        QgsField("precipitation", QVariant.Double),
        QgsField("urban_runoff", QVariant.Double),
    ]


class BasinState(Input):
    input_type = "LSW / state"
    geometry_type = "No Geometry"
    attributes = [
        QgsField("node_id", QVariant.Int),
        QgsField("storage", QVariant.Double),
        QgsField("concentration", QVariant.Double),
    ]


class TabulatedRatingCurve(Input):
    input_type = "TabulatedRatingCurve"
    geometry_type = "No Geometry"
    attributes = [
        QgsField("node_id", QVariant.Int),
        QgsField("level", QVariant.Double),
        QgsField("discharge", QVariant.Double),
    ]


class FractionalFlow(Input):
    input_type = "FractionalFlow"
    geometry_type = "No Geometry"
    attributes = [
        QgsField("node_id", QVariant.Int),
        QgsField("fraction", QVariant.Double),
    ]


class LevelControl(Input):
    input_type = "LevelControl"
    geometry_type = "No Geometry"
    attributes = [
        QgsField("node_id", QVariant.Int),
        QgsField("target_level", QVariant.Double),
    ]


NODES = {
    "Node": Node,
    "Edge": Edge,
    "Basin": Basin,
    "Basin / state": BasinState,
    "Basin / profile": BasinProfile,
    "Basin / forcing": BasinForcing,
    "TabulatedRatingCurve": TabulatedRatingCurve,
    "FractionalFlow": FractionalFlow,
    "LevelControl": LevelControl,
}


def load_nodes_from_geopackage(path: str) -> Dict[str, Input]:
    # List the names in the geopackage
    gpkg_names = geopackage.layers(path)
    nodes = {}
    for layername in gpkg_names:
        nodes[layername] = NODES[layername](path)

    return nodes
