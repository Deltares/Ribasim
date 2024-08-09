"""Setup a dockwidget to hold the ribasim plugin widgets."""

from pathlib import Path

from qgis.gui import QgsDockWidget
from qgis.PyQt.QtCore import Qt
from qgis.PyQt.QtGui import QIcon
from qgis.PyQt.QtWidgets import QAction


class RibasimDockWidget(QgsDockWidget):
    def closeEvent(self, event) -> None:
        # TODO: if we implement talking to a Julia server, shut it down here.
        event.accept()


class RibasimPlugin:
    def __init__(self, iface):
        # Save reference to the QGIS interface
        self.iface = iface
        self.ribasim_widget = None
        self.plugin_dir = Path(__file__).parent
        self.pluginIsActive = False
        self.toolbar = iface.addToolBar("Ribasim")
        self.toolbar.setObjectName("Ribasim")
        return

    def add_action(self, icon_name, text="", callback=None, add_to_menu=False):
        icon = QIcon(str(self.plugin_dir / icon_name))
        action = QAction(icon, text, self.iface.mainWindow())
        action.triggered.connect(callback)
        if add_to_menu:
            self.toolbar.addAction(action)
        return action

    def initGui(self):
        icon_name = "icon.png"
        self.action_ribasim = self.add_action(
            icon_name, "Ribasim", self.toggle_ribasim, True
        )

    def toggle_ribasim(self):
        if self.ribasim_widget is None:
            from ribasim_qgis.widgets.ribasim_widget import RibasimWidget

            self.ribasim_widget = RibasimDockWidget("Ribasim")
            self.ribasim_widget.setObjectName("RibasimDock")
            self.iface.addDockWidget(Qt.RightDockWidgetArea, self.ribasim_widget)
            widget = RibasimWidget(self.ribasim_widget, self.iface)
            self.ribasim_widget.setWidget(widget)
            self.ribasim_widget.hide()
        self.ribasim_widget.setVisible(not self.ribasim_widget.isVisible())

    def unload(self):
        self.toolbar.deleteLater()
