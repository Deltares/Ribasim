from pathlib import Path

from qgis.core import QgsProject
from qgis.testing import unittest
from qgis.utils import iface, plugins

from ribasim_qgis.core.geopackage import sqlite3_cursor


class TestPlugin(unittest.TestCase):
    def test_plugin_is_loaded(self):
        """Test plugin is properly loaded and appears in QGIS plugins."""
        plugin = plugins.get("ribasim_qgis")
        self.assertTrue(plugin, "Ribasim plugin not loaded")

    def test_plugin(self):
        """Triggers Ribasim button and checks that Dock is added."""
        # This checks the *actual* QGIS interface, not just a stub
        self.assertTrue(iface is not None, "QGIS interface not available")

        toolbars = [
            c for c in iface.mainWindow().children() if c.objectName() == "Ribasim"
        ]
        self.assertTrue(len(toolbars) == 1, "No (single) Ribasim toolbar")
        actions = toolbars[0].actions()
        self.assertTrue(
            len(actions) == 1, "No (single) Ribasim action button in toolbar"
        )

        docks = [
            c for c in iface.mainWindow().children() if c.objectName() == "RibasimDock"
        ]
        self.assertTrue(len(docks) == 0, "Ribasim dock already activated")

        actions[0].trigger()

        docks = [
            c for c in iface.mainWindow().children() if c.objectName() == "RibasimDock"
        ]
        self.assertTrue(len(docks) == 1, "Ribasim dock not activated")

        # Get the required widgets via the dock
        ribadock = docks[0]
        ribawidget = ribadock.widget()
        datawidget = ribawidget.tabwidget.widget(0)

        # Write an empty model
        datawidget._new_model("test.toml")
        self.assertTrue(Path("test.toml").exists(), "test.toml not created")
        self.assertTrue(Path("database.gpkg").exists(), "database.gpkg not created")
        self.assertTrue(
            len(QgsProject.instance().mapLayers()) == 2,
            "Not just the Node and Link layers",
        )

        # Check schema version
        with sqlite3_cursor("database.gpkg") as cursor:
            cursor.execute(
                "SELECT value FROM ribasim_metadata WHERE key='schema_version'"
            )
            self.assertTrue(int(cursor.fetchone()[0]) == 6, "schema_version is wrong")

        # Open the model
        datawidget._open_model("test.toml")
        self.assertTrue(
            len(QgsProject.instance().mapLayers()) == 4,
            "Not just the Node and Link layers twice",
        )
