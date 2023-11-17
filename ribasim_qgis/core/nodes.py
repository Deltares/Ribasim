"""
This module contains the classes to represent the Ribasim node layers.

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
from typing import Any

from PyQt5.QtCore import Qt, QVariant
from PyQt5.QtGui import QColor
from qgis.core import (
    Qgis,
    QgsCategorizedSymbolRenderer,
    QgsEditorWidgetSetup,
    QgsField,
    QgsLineSymbol,
    QgsMarkerLineSymbolLayer,
    QgsMarkerSymbol,
    QgsPalLayerSettings,
    QgsRendererCategory,
    QgsSimpleMarkerSymbolLayer,
    QgsSimpleMarkerSymbolLayerBase,
    QgsVectorLayer,
    QgsVectorLayerSimpleLabeling,
)

from ribasim_qgis.core import geopackage


class Input(abc.ABC):
    """Abstract base class for Ribasim input layers."""

    input_type = ""

    def __init__(self, path: str):
        self.name = self.input_type
        self.path = path
        self.layer = None

    @classmethod
    def is_spatial(cls):
        return False

    @classmethod
    def nodetype(cls):
        return cls.input_type.split("/")[0].strip()

    @classmethod
    def create(cls, path: str, crs: Any, names: list[str]) -> "Input":
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

    def from_geopackage(self) -> tuple[Any, Any]:
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
        # Calling during new_layer doesn't have any effect...
        return


class Node(Input):
    input_type = "Node"
    geometry_type = "Point"
    attributes = (
        QgsField("name", QVariant.String),
        QgsField("type", QVariant.String),
    )

    @classmethod
    def is_spatial(cls):
        return True

    def write(self) -> None:
        # Special case the Node layer write because it needs to generate a new file.

        self.layer = geopackage.write_layer(
            self.path, self.layer, self.name, newfile=True
        )
        self.set_defaults()
        return

    def set_editor_widget(self) -> None:
        layer = self.layer
        index = layer.fields().indexFromName("type")
        setup = QgsEditorWidgetSetup(
            "ValueMap",
            {"map": {node: node for node in NONSPATIALNODETYPES}},
        )
        layer.setEditorWidgetSetup(index, setup)

        layer_form_config = layer.editFormConfig()
        layer_form_config.setReuseLastValue(1, True)
        layer.setEditFormConfig(layer_form_config)

        return

    @property
    def renderer(self) -> QgsCategorizedSymbolRenderer:
        shape = QgsSimpleMarkerSymbolLayerBase
        MARKERS = {
            "Basin": (QColor("blue"), "Basin", shape.Circle),
            "FractionalFlow": (QColor("red"), "FractionalFlow", shape.Triangle),
            "LinearResistance": (
                QColor("green"),
                "LinearResistance",
                shape.Triangle,
            ),
            "TabulatedRatingCurve": (
                QColor("green"),
                "TabulatedRatingCurve",
                shape.Diamond,
            ),
            "LevelBoundary": (QColor("green"), "LevelBoundary", shape.Circle),
            "FlowBoundary": (QColor("purple"), "FlowBoundary", shape.Hexagon),
            "Pump": (QColor("gray"), "Pump", shape.Hexagon),
            "Outlet": (QColor("green"), "Outlet", shape.Hexagon),
            "ManningResistance": (QColor("red"), "ManningResistance", shape.Diamond),
            "Terminal": (QColor("purple"), "Terminal", shape.Square),
            "DiscreteControl": (QColor("black"), "DiscreteControl", shape.Star),
            "PidControl": (QColor("black"), "PidControl", shape.Cross2),
            "User": (QColor("green"), "User", shape.Square),
            "": (
                QColor("white"),
                "",
                shape.Circle,
            ),  # All other nodes, or incomplete input
        }

        categories = []
        for value, (colour, label, shape) in MARKERS.items():
            symbol = QgsMarkerSymbol()
            symbol.symbolLayer(0).setShape(shape)
            symbol.setColor(QColor(colour))
            symbol.setSize(4)
            category = QgsRendererCategory(value, symbol, label, shape)
            category.setRenderState(True)
            categories.append(category)

        renderer = QgsCategorizedSymbolRenderer(attrName="type", categories=categories)
        return renderer

    @property
    def labels(self) -> Any:
        pal_layer = QgsPalLayerSettings()
        pal_layer.fieldName = """concat("name", ' #', "fid")"""
        pal_layer.isExpression = True
        pal_layer.enabled = True
        pal_layer.dist = 2.0
        labels = QgsVectorLayerSimpleLabeling(pal_layer)
        return labels


class Edge(Input):
    input_type = "Edge"
    geometry_type = "Linestring"
    attributes = [
        QgsField("name", QVariant.String),
        QgsField("from_node_id", QVariant.Int),
        QgsField("to_node_id", QVariant.Int),
        QgsField("edge_type", QVariant.String),
    ]

    @classmethod
    def is_spatial(cls):
        return True

    def set_editor_widget(self) -> None:
        layer = self.layer
        index = layer.fields().indexFromName("edge_type")
        setup = QgsEditorWidgetSetup(
            "ValueMap",
            {"map": {node: node for node in EDGETYPES}},
        )
        layer.setEditorWidgetSetup(index, setup)

        layer_form_config = layer.editFormConfig()
        layer_form_config.setReuseLastValue(1, True)
        layer.setEditFormConfig(layer_form_config)

        return

    @property
    def renderer(self) -> QgsCategorizedSymbolRenderer:
        MARKERS = {
            "flow": (QColor("#3690c0"), "flow"),  # lightblue
            "control": (QColor("gray"), "control"),
            "": (QColor("black"), ""),  # All other edges, or incomplete input
        }

        categories = []
        for value, (colour, label) in MARKERS.items():
            # Create line
            symbol = QgsLineSymbol()
            symbol.setColor(QColor(colour))
            symbol.setWidth(0.5)

            # Create an arrow marker to indicate directionality
            arrow_marker = QgsSimpleMarkerSymbolLayer()
            arrow_marker.setShape(QgsSimpleMarkerSymbolLayer.ArrowHeadFilled)
            arrow_marker.setColor(QColor(colour))
            arrow_marker.setSize(3)
            arrow_marker.setStrokeStyle(Qt.PenStyle(Qt.NoPen))

            # Add marker to line
            marker_symbol = QgsMarkerSymbol()
            marker_symbol.changeSymbolLayer(0, arrow_marker)
            marker_line_symbol_layer = QgsMarkerLineSymbolLayer.create(
                {"placements": "SegmentCenter"}
            )
            marker_line_symbol_layer.setSubSymbol(marker_symbol)
            symbol.appendSymbolLayer(marker_line_symbol_layer)

            category = QgsRendererCategory(value, symbol, label)
            category.setRenderState(True)
            categories.append(category)

        renderer = QgsCategorizedSymbolRenderer(
            attrName="edge_type", categories=categories
        )
        return renderer

    @property
    def labels(self) -> Any:
        pal_layer = QgsPalLayerSettings()
        pal_layer.fieldName = """concat("name", ' #', "fid")"""
        pal_layer.isExpression = True
        pal_layer.enabled = True
        pal_layer.placement = Qgis.LabelPlacement.Line
        pal_layer.dist = 1.0
        labels = QgsVectorLayerSimpleLabeling(pal_layer)
        return labels


class BasinProfile(Input):
    input_type = "Basin / profile"
    geometry_type = "No Geometry"
    attributes = [
        QgsField("node_id", QVariant.Int),
        QgsField("area", QVariant.Double),
        QgsField("level", QVariant.Double),
    ]


class BasinStatic(Input):
    input_type = "Basin / static"
    geometry_type = "No geometry"
    attributes = [
        QgsField("node_id", QVariant.Int),
        QgsField("drainage", QVariant.Double),
        QgsField("potential_evaporation", QVariant.Double),
        QgsField("infiltration", QVariant.Double),
        QgsField("precipitation", QVariant.Double),
        QgsField("urban_runoff", QVariant.Double),
    ]


class BasinTime(Input):
    input_type = "Basin / time"
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
    input_type = "Basin / state"
    geometry_type = "No Geometry"
    attributes = [
        QgsField("node_id", QVariant.Int),
        QgsField("level", QVariant.Double),
        QgsField("concentration", QVariant.Double),
    ]


class TabulatedRatingCurveStatic(Input):
    input_type = "TabulatedRatingCurve / static"
    geometry_type = "No Geometry"
    attributes = [
        QgsField("node_id", QVariant.Int),
        QgsField("active", QVariant.Bool),
        QgsField("level", QVariant.Double),
        QgsField("discharge", QVariant.Double),
        QgsField("control_state", QVariant.String),
    ]


class TabulatedRatingCurveTime(Input):
    input_type = "TabulatedRatingCurve / time"
    geometry_type = "No Geometry"
    attributes = [
        QgsField("time", QVariant.DateTime),
        QgsField("node_id", QVariant.Int),
        QgsField("level", QVariant.Double),
        QgsField("discharge", QVariant.Double),
    ]


class FractionalFlowStatic(Input):
    input_type = "FractionalFlow / static"
    geometry_type = "No Geometry"
    attributes = [
        QgsField("node_id", QVariant.Int),
        QgsField("fraction", QVariant.Double),
        QgsField("control_state", QVariant.String),
    ]


class LinearResistanceStatic(Input):
    input_type = "LinearResistance / static"
    geometry_type = "No Geometry"
    attributes = [
        QgsField("node_id", QVariant.Int),
        QgsField("active", QVariant.Bool),
        QgsField("resistance", QVariant.Double),
        QgsField("control_state", QVariant.String),
    ]


class ManningResistanceStatic(Input):
    input_type = "ManningResistance / static"
    geometry_type = "No Geometry"
    attributes = [
        QgsField("node_id", QVariant.Int),
        QgsField("active", QVariant.Bool),
        QgsField("length", QVariant.Double),
        QgsField("manning_n", QVariant.Double),
        QgsField("profile_width", QVariant.Double),
        QgsField("profile_slope", QVariant.Double),
        QgsField("control_state", QVariant.String),
    ]


class LevelBoundaryStatic(Input):
    input_type = "LevelBoundary / static"
    geometry_type = "No Geometry"
    attributes = [
        QgsField("node_id", QVariant.Int),
        QgsField("active", QVariant.Bool),
        QgsField("level", QVariant.Double),
    ]


class LevelBoundaryTime(Input):
    input_type = "LevelBoundary / time"
    geometry_type = "No Geometry"
    attributes = [
        QgsField("time", QVariant.DateTime),
        QgsField("node_id", QVariant.Int),
        QgsField("time", QVariant.DateTime),
        QgsField("level", QVariant.Double),
    ]


class PumpStatic(Input):
    input_type = "Pump / static"
    geometry_type = "No Geometry"
    attributes = [
        QgsField("node_id", QVariant.Int),
        QgsField("active", QVariant.Bool),
        QgsField("flow_rate", QVariant.Double),
        QgsField("min_flow_rate", QVariant.Double),
        QgsField("max_flow_rate", QVariant.Double),
        QgsField("control_state", QVariant.String),
    ]


class OutletStatic(Input):
    input_type = "Outlet / static"
    geometry_type = "No Geometry"
    attributes = [
        QgsField("node_id", QVariant.Int),
        QgsField("active", QVariant.Bool),
        QgsField("flow_rate", QVariant.Double),
        QgsField("min_flow_rate", QVariant.Double),
        QgsField("max_flow_rate", QVariant.Double),
        QgsField("min_crest_level", QVariant.Double),
        QgsField("control_state", QVariant.String),
    ]


class TerminalStatic(Input):
    input_type = "Terminal / static"
    geometry_type = "No Geometry"
    attributes = [QgsField("node_id", QVariant.Int)]


class FlowBoundaryStatic(Input):
    input_type = "FlowBoundary / static"
    geometry_type = "No Geometry"
    attributes = [
        QgsField("node_id", QVariant.Int),
        QgsField("active", QVariant.Bool),
        QgsField("flow_rate", QVariant.Double),
    ]


class FlowBoundaryTime(Input):
    input_type = "FlowBoundary / time"
    geometry_type = "No Geometry"
    attributes = [
        QgsField("time", QVariant.DateTime),
        QgsField("node_id", QVariant.Int),
        QgsField("flow_rate", QVariant.Double),
    ]


class DiscreteControlCondition(Input):
    input_type = "DiscreteControl / condition"
    geometry_type = "No Geometry"
    attributes = [
        QgsField("node_id", QVariant.Int),
        QgsField("listen_feature_id", QVariant.Int),
        QgsField("variable", QVariant.String),
        QgsField("greater_than", QVariant.Double),
    ]


class DiscreteControlLogic(Input):
    input_type = "DiscreteControl / logic"
    geometry_type = "LineString"
    attributes = [
        QgsField("node_id", QVariant.Int),
        QgsField("control_state", QVariant.String),
        QgsField("truth_state", QVariant.String),
    ]


class PidControlStatic(Input):
    input_type = "PidControl / static"
    geometry_type = "LineString"
    attributes = [
        QgsField("node_id", QVariant.Int),
        QgsField("active", QVariant.Bool),
        QgsField("listen_node_id", QVariant.Int),
        QgsField("target", QVariant.Double),
        QgsField("proportional", QVariant.Double),
        QgsField("integral", QVariant.Double),
        QgsField("derivative", QVariant.Double),
    ]


class PidControlTime(Input):
    input_type = "PidControl / time"
    geometry_type = "LineString"
    attributes = [
        QgsField("node_id", QVariant.Int),
        QgsField("listen_node_id", QVariant.Int),
        QgsField("time", QVariant.DateTime),
        QgsField("target", QVariant.Double),
        QgsField("proportional", QVariant.Double),
        QgsField("integral", QVariant.Double),
        QgsField("derivative", QVariant.Double),
    ]


class UserStatic(Input):
    input_type = "User / static"
    geometry_type = "No Geometry"
    attributes = [
        QgsField("node_id", QVariant.Int),
        QgsField("active", QVariant.Bool),
        QgsField("demand", QVariant.Double),
        QgsField("return_factor", QVariant.Double),
        QgsField("priority", QVariant.Int),
    ]


class UserTime(Input):
    input_type = "User / time"
    geometry_type = "No Geometry"
    attributes = [
        QgsField("node_id", QVariant.Int),
        QgsField("time", QVariant.DateTime),
        QgsField("demand", QVariant.Double),
        QgsField("return_factor", QVariant.Double),
        QgsField("priority", QVariant.Int),
    ]


NODES = {cls.input_type: cls for cls in Input.__subclasses__()}
NONSPATIALNODETYPES = {
    cls.nodetype() for cls in Input.__subclasses__() if not cls.is_spatial()
}
EDGETYPES = {"flow", "control"}


def load_nodes_from_geopackage(path: str) -> dict[str, Input]:
    # List the names in the geopackage
    gpkg_names = geopackage.layers(path)
    nodes = {}
    for layername in gpkg_names:
        nodes[layername] = NODES[layername](path)
    return nodes
