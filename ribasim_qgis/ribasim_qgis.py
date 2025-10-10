"""Setup a dockwidget to hold the ribasim plugin widgets."""

import tomllib
from pathlib import Path

from qgis.gui import QgsCustomDropHandler
from qgis.PyQt.QtGui import QIcon
from qgis.PyQt.QtWidgets import QAction

icondir = Path(__file__).parent


class RibasimDropHandler(QgsCustomDropHandler):
    def __init__(self, plugin):
        super().__init__()
        self.parent = plugin

    def handleFileDrop(self, path):
        if not path.lower().endswith(".toml"):
            return False

        with open(path, "rb") as f:
            data = tomllib.load(f)
            if "ribasim_version" not in data:
                return False

        self.parent.open_model(path)

        return True


class RibasimPlugin:
    def __init__(self, iface):
        # Save reference to the QGIS interface
        self.iface = iface
        self.ribasim_widget = None
        self.plugin_dir = Path(__file__).parent
        self.toolbar = iface.addToolBar("Ribasim")
        self.toolbar.setObjectName("Ribasim")
        self.pluginIsActive = True
        self.drop_handler = RibasimDropHandler(self)

    def add_action(self, icon_name, text="", callback=None, add_to_menu=True):
        icon = QIcon(str(self.plugin_dir / icon_name))
        action = QAction(
            icon,
            text,
            self.iface.mainWindow(),
        )
        action.triggered.connect(callback)
        if add_to_menu:
            self.toolbar.addAction(action)
        if add_to_menu:
            self.iface.addPluginToMenu("Ribasim", action)

        return action

    def initGui(self):
        icon_name = "icon.png"
        self.action_ribasim = self.add_action(
            icon_name, "Open Ribasim Model", self.open_model, True
        )
        self.iface.registerCustomDropHandler(self.drop_handler)

    def open_model(self, path=None):
        if self.ribasim_widget is None:
            from ribasim_qgis.widgets.ribasim_widget import RibasimWidget

            self.ribasim_widget = RibasimWidget(self.iface)
        self.ribasim_widget.open_model(path)

    def unload(self):
        if self.toolbar:
            self.toolbar.deleteLater()
        self.iface.removePluginMenu("Ribasim", self.action_ribasim)
        self.iface.unregisterCustomDropHandler(self.drop_handler)
