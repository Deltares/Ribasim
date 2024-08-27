"""
This module forms the high level DockWidget.

It ensures the underlying widgets can talk to each other.  It also manages the
connection to the QGIS Layers Panel, and ensures there is a group for the
Ribasim layers there.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any, cast

from PyQt5.QtWidgets import QTabWidget, QVBoxLayout, QWidget
from qgis.core import (
    Qgis,
    QgsAbstractVectorLayerLabeling,
    QgsCoordinateReferenceSystem,
    QgsLayerTreeGroup,
    QgsMapLayer,
    QgsProject,
    QgsVectorLayer,
)
from qgis.gui import QgisInterface

from ribasim_qgis.core.nodes import Input
from ribasim_qgis.widgets.dataset_widget import DatasetWidget
from ribasim_qgis.widgets.nodes_widget import NodesWidget

PYQT_DELETED_ERROR = "wrapped C/C++ object of type QgsLayerTreeGroup has been deleted"


class RibasimWidget(QWidget):
    def __init__(self, parent: QWidget, iface: QgisInterface):
        super().__init__(parent)

        self.iface = iface
        self.message_bar = self.iface.messageBar()

        self.__dataset_widget = DatasetWidget(self)
        self.__nodes_widget = NodesWidget(self)

        # Layout
        layout = QVBoxLayout()
        self.tabwidget = QTabWidget()
        layout.addWidget(self.tabwidget)
        self.tabwidget.addTab(self.__dataset_widget, "Model")
        self.tabwidget.addTab(self.__nodes_widget, "Nodes")
        self.setLayout(layout)

        # QGIS Layers Panel groups
        self.group: QgsLayerTreeGroup | None = None
        self.groups: dict[str, QgsLayerTreeGroup] = {}

        return

    # Inter-widget communication
    # --------------------------
    @property
    def path(self) -> Path:
        return self.__dataset_widget.path

    @property
    def node_layer(self) -> QgsVectorLayer | None:
        return self.__dataset_widget.node_layer

    @property
    def edge_layer(self) -> QgsVectorLayer | None:
        return self.__dataset_widget.edge_layer

    @property
    def crs(self) -> QgsCoordinateReferenceSystem:
        """Returns coordinate reference system of current mapview"""
        map_canvas = self.iface.mapCanvas()
        assert map_canvas is not None
        map_settings = map_canvas.mapSettings()
        assert map_settings is not None
        return map_settings.destinationCrs()

    def add_node_layer(self, element: Input):
        self.__dataset_widget.add_node_layer(element)

    def toggle_node_buttons(self, state: bool) -> None:
        self.__nodes_widget.toggle_node_buttons(state)

    def selection_names(self):
        return self.__dataset_widget.selection_names()

    # QGIS layers
    # -----------
    def create_subgroup(self, name: str, part: str) -> None:
        try:
            assert self.group is not None
            value = self.group.addGroup(f"{name}-{part}")
            assert value is not None
            self.groups[part] = value
        except RuntimeError as e:
            if e.args[0] == PYQT_DELETED_ERROR:
                # This means the main group has been deleted: recreate
                # everything.
                self.create_groups(name)

    def create_groups(self, name: str) -> None:
        """Create an empty legend group in the QGIS Layers Panel."""
        project = QgsProject.instance()
        assert project is not None
        root = project.layerTreeRoot()
        assert root is not None
        self.group = root.addGroup(name)
        self.create_subgroup(name, "Ribasim Input")

    def add_to_group(self, maplayer: Any, destination: str, on_top: bool):
        """
        Try to add to a group; it might have been deleted. In that case, we add
        as many groups as required.
        """
        group = self.groups[destination]
        try:
            if on_top:
                group.insertLayer(0, maplayer)
            else:
                group.addLayer(maplayer)
        except RuntimeError as e:
            if e.args[0] == PYQT_DELETED_ERROR:
                # Then re-create groups and try again
                name = str(Path(self.path).stem)
                self.create_subgroup(name, destination)
                self.add_to_group(maplayer, destination, on_top)
            else:
                raise e

    def add_layer(
        self,
        layer: QgsVectorLayer,
        destination: str,
        suppress: bool | None = None,
        on_top: bool = False,
        labels: QgsAbstractVectorLayerLabeling | None = None,
    ) -> QgsMapLayer | None:
        """
        Add a layer to the Layers Panel

        Parameters
        ----------
        layer:
            QGIS map layer, raster or vector layer
        destination:
            Legend group
        suppress:
            optional, bool. Default value is None.
            This controls whether attribute form popup is suppressed or not.
            Only relevant for vector (input) layers.
        on_top: optional, bool. Default value is False.
            Whether to place the layer on top in the destination legend group.
            Handy for transparent layers such as contours.
        labels: optional
            Whether to place labels, based on which column, styling, etc.

        Returns
        -------
        maplayer: QgsMapLayer or None
        """
        if layer is None:
            return None
        add_to_legend = self.group is None
        project = QgsProject.instance()
        assert project is not None
        maplayer = cast(QgsVectorLayer, project.addMapLayer(layer, add_to_legend))
        assert maplayer is not None
        if suppress is not None:
            config = maplayer.editFormConfig()
            config.setSuppress(
                Qgis.AttributeFormSuppression.On
                if suppress
                else Qgis.AttributeFormSuppression.Default
            )
            maplayer.setEditFormConfig(config)
        if labels is not None:
            layer.setLabeling(labels)
            layer.setLabelsEnabled(True)
        if destination is not None:
            self.add_to_group(maplayer, destination, on_top)

        return maplayer
