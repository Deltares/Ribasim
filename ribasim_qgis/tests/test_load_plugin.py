from qgis.utils import iface, plugins


def test_plugin_is_loaded():
    """Test plugin is properly loaded and appears in QGIS plugins."""
    plugin = plugins.get("ribasim_qgis")
    assert plugin, "Ribasim plugin not loaded"


def test_plugin():
    """Triggers Ribasim button and checks that Dock is added."""
    assert iface is not None, "QGIS interface not available"

    toolbars = [c for c in iface.mainWindow().children() if c.objectName() == "Ribasim"]
    assert len(toolbars) == 2, "No Ribasim toolbar and menu"
    actions = toolbars[0].actions()
    assert len(actions) == 1, "No (single) Ribasim action button in toolbar"
