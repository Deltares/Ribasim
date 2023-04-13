from PyQt5.QtWidgets import QFileDialog, QPushButton, QVBoxLayout, QWidget


class OutputWidget(QWidget):
    def __init__(self, parent):
        super().__init__(parent)
        self.parent = parent
        self.node_output_button = QPushButton("Associate Node Output")
        self.edge_output_button = QPushButton("Associate Edge Output")
        self.node_output_button.clicked.connect(self.set_node_output)
        self.edge_output_button.clicked.connect(self.set_edge_output)

        layout = QVBoxLayout()
        layout.addWidget(self.node_output_button)
        layout.addWidget(self.edge_output_button)
        layout.addStretch()
        self.setLayout(layout)

    def set_output(self, layer, fid_column: str):
        path, _ = QFileDialog.getOpenFileName(self, "Select file", "", "*.arrow")
        if path == "":
            return
        if layer is not None:
            layer.setCustomProperty("arrow_type", "timeseries")
            layer.setCustomProperty("arrow_path", path)
            layer.setCustomProperty(
                "arrow_fid_column",
                fid_column,
            )
        return

    def set_node_output(self):
        self.set_output(
            self.parent.dataset_widget.node_layer,
            "node_id",
        )

    def set_edge_output(self):
        self.set_output(self.parent.dataset_widget.edge_layer, "edge_id")
