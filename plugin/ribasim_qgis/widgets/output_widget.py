from PyQt5.QtWidgets import (
    QFileDialog,
    QPushButton,
    QVBoxLayout,
    QWidget,
)


class OutputWidget(QWidget):
    def __init__(self, parent):
        super().__init__(parent)
        self.parent = parent
        self.output_button = QPushButton("Associate Output")

        self.output_button.clicked.connect(self.set_output)

        layout = QVBoxLayout()
        layout.addWidget(self.output_button)
        layout.addStretch()
        self.setLayout(layout)

    def set_output(self):
        path, _ = QFileDialog.getOpenFileName(self, "Select file", "", "*.arrow")
        if path == "":
            return
        node_layer = self.parent.dataset_widget.node_layer
        if node_layer is not None:
            node_layer.setCustomProperty("arrow_type", "timeseries")
            node_layer.setCustomProperty("arrow_path", path)
        return
