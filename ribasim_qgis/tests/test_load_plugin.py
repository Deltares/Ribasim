from typing import Any

from qgis.PyQt.QtWidgets import QToolBar, QToolButton


def test_plugin(ribasim_plugin: Any):
    """Checks that the Ribasim toolbar and tool button menu are set up."""
    from qgis.utils import iface

    assert iface is not None, "QGIS interface not available"
    main_window = iface.mainWindow()

    toolbars = [
        c
        for c in main_window.children()
        if isinstance(c, QToolBar) and c.objectName() == "Ribasim"
    ]
    assert len(toolbars) == 1, "No Ribasim toolbar"
    toolbar = toolbars[0]
    actions = toolbar.actions()
    assert len(actions) == 1, "No (single) Ribasim action button in toolbar"

    tool_button = toolbar.widgetForAction(actions[0])
    assert isinstance(tool_button, QToolButton)

    menu = tool_button.menu()
    assert menu is not None
    menu_actions = [action.text() for action in menu.actions() if action.text()]
    assert "Set Ribasim home" in menu_actions
