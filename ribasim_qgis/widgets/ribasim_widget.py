"""
This module forms the high level DockWidget.

It ensures the underlying widgets can talk to each other.  It also manages the
connection to the QGIS Layers Panel, and ensures there is a group for the
Ribasim layers there.
"""
from pathlib import Path
from typing import Any

from PyQt5.QtWidgets import QTabWidget, QVBoxLayout, QWidget
from qgis.core import QgsEditFormConfig, QgsMapLayer, QgsProject

from ribasim_qgis.widgets.dataset_widget import DatasetWidget
from ribasim_qgis.widgets.nodes_widget import NodesWidget
from ribasim_qgis.widgets.results_widget import ResultsWidget

PYQT_DELETED_ERROR = "wrapped C/C++ object of type QgsLayerTreeGroup has been deleted"


class RibasimWidget(QWidget):
    def __init__(self, parent, iface):
        super().__init__(parent)

        self.iface = iface
        self.message_bar = self.iface.messageBar()

        self.dataset_widget = DatasetWidget(self)
        self.nodes_widget = NodesWidget(self)
        self.results_widget = ResultsWidget(self)

        # Layout
        self.layout = QVBoxLayout()
        self.tabwidget = QTabWidget()
        self.layout.addWidget(self.tabwidget)
        self.tabwidget.addTab(self.dataset_widget, "Model")
        self.tabwidget.addTab(self.nodes_widget, "Nodes")
        self.tabwidget.addTab(self.results_widget, "Results")
        self.setLayout(self.layout)

        # QGIS Layers Panel groups
        self.group = None
        self.groups = {}

        return

    # Inter-widget communication
    # --------------------------
    @property
    def path(self) -> str:
        return self.dataset_widget.path

    @property
    def crs(self) -> Any:
        """Returns coordinate reference system of current mapview"""
        return self.iface.mapCanvas().mapSettings().destinationCrs()

    def add_node_layer(self, element: Any):
        self.dataset_widget.add_node_layer(element)

    def toggle_node_buttons(self, state: bool) -> None:
        self.nodes_widget.toggle_node_buttons(state)

    def selection_names(self):
        return self.dataset_widget.selection_names()

    # QGIS layers
    # -----------
    def create_subgroup(self, name: str, part: str) -> None:
        try:
            value = self.group.addGroup(f"{name}-{part}")
            self.groups[part] = value
        except RuntimeError as e:
            if e.args[0] == PYQT_DELETED_ERROR:
                # This means the main group has been deleted: recreate
                # everything.
                self.create_groups(name)

    def create_groups(self, name: str) -> None:
        """Create an empty legend group in the QGIS Layers Panel."""
        root = QgsProject.instance().layerTreeRoot()
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
        layer: Any,
        destination: Any,
        renderer: Any = None,
        suppress: bool = None,
        on_top: bool = False,
        labels: Any = None,
    ) -> QgsMapLayer:
        """
        Add a layer to the Layers Panel

        Parameters
        ----------
        layer:
            QGIS map layer, raster or vector layer
        destination:
            Legend group
        renderer:
            QGIS layer renderer, optional
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
            return
        add_to_legend = self.group is None
        maplayer = QgsProject.instance().addMapLayer(layer, add_to_legend)
        if suppress is not None:
            config = maplayer.editFormConfig()
            config.setSuppress(
                QgsEditFormConfig.SuppressOn
                if suppress
                else QgsEditFormConfig.SuppressDefault
            )
            maplayer.setEditFormConfig(config)
        if renderer is not None:
            maplayer.setRenderer(renderer)
        if labels is not None:
            layer.setLabeling(labels)
            layer.setLabelsEnabled(True)
        if destination is not None:
            self.add_to_group(maplayer, destination, on_top)

        return maplayer
