from typing import cast

from PyQt5.QtWidgets import QFileDialog, QPushButton, QVBoxLayout, QWidget
from qgis.core import QgsVectorLayer

from ribasim_qgis.widgets.ribasim_widget import RibasimWidget


class ResultsWidget(QWidget):
    def __init__(self, parent):
        super().__init__(parent)
        self.node_results_button = QPushButton("Associate Node Results")
        self.edge_results_button = QPushButton("Associate Edge Results")
        self.node_results_button.clicked.connect(self.set_node_results)
        self.edge_results_button.clicked.connect(self.set_edge_results)
        layout = QVBoxLayout()
        layout.addWidget(self.node_results_button)
        layout.addWidget(self.edge_results_button)
        layout.addStretch()
        self.setLayout(layout)

    def _set_results(self, layer: QgsVectorLayer, column: str) -> None:
        path, _ = QFileDialog.getOpenFileName(self, "Select file", "", "*.arrow")
        if path == "":
            return
        if layer is not None:
            layer.setCustomProperty("arrow_type", "timeseries")
            layer.setCustomProperty("arrow_path", path)
            layer.setCustomProperty("arrow_fid_column", column)

    def set_node_results(self) -> None:
        node_layer = cast(RibasimWidget, self.parent()).dataset_widget.node_layer
        assert node_layer is not None
        self._set_results(node_layer, "node_id")

    def set_edge_results(self) -> None:
        edge_layer = cast(RibasimWidget, self.parent()).dataset_widget.edge_layer
        assert edge_layer is not None
        self._set_results(edge_layer, "edge_id")
