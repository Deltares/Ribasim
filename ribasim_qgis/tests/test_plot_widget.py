"""Tests for ribasim_qgis.widgets.plot_widget — PlotWidget and _VariablesMenu."""

import numpy as np

from ribasim_qgis.widgets.plot_widget import PlotData, PlotWidget, _VariablesMenu

# --- _VariablesMenu ---


def test_variables_menu_populate():
    menu = _VariablesMenu()
    menu.populate(["level", "storage", "area"], previously_checked=set())
    # First variable should be auto-checked when nothing previously checked
    assert menu.checked_variables() == ["level"]


def test_variables_menu_default():
    menu = _VariablesMenu()
    menu.populate(
        ["level", "storage", "area"], previously_checked=set(), default="storage"
    )
    assert menu.checked_variables() == ["storage"]


def test_variables_menu_previously_checked():
    menu = _VariablesMenu()
    menu.populate(
        ["level", "storage", "area"],
        previously_checked={"storage", "area"},
    )
    assert set(menu.checked_variables()) == {"storage", "area"}


def test_variables_menu_empty():
    menu = _VariablesMenu()
    menu.populate([], previously_checked=set())
    assert menu.checked_variables() == []


# --- PlotWidget ---


def test_plot_widget_creates():
    widget = PlotWidget()
    assert widget is not None


def test_plot_widget_preload_variables():
    widget = PlotWidget()
    available = {
        "basin": ["level", "storage"],
        "flow": ["flow_rate"],
    }
    units = {
        "basin": {"level": "m", "storage": "m3"},
        "flow": {"flow_rate": "m3 s-1"},
    }
    widget.preload_variables(available, units, defaults={"basin": "level"})
    assert widget._available == available
    assert widget._units == units
    assert widget._defaults == {"basin": "level"}


def test_plot_widget_set_data_and_redraw():
    """Test that set_data populates _plot_data and triggers a redraw."""
    widget = PlotWidget()

    available = {"basin": ["level"]}
    widget.preload_variables(available, defaults={"basin": "level"})

    time = np.array(["2020-01-01", "2020-01-02", "2020-01-03"])
    values = np.array([1.0, 2.0, 3.0])

    plot_data: PlotData = {
        "basin": {
            "level": {
                "#1": (time, values),
            }
        }
    }
    widget.set_data(plot_data)
    assert widget._plot_data == plot_data
    # Web view should be marked visible internally (even without a display)
    assert not widget._placeholder.isVisibleTo(widget)
    assert widget._web_view.isVisibleTo(widget)


def test_plot_widget_clear():
    widget = PlotWidget()

    available = {"basin": ["level"]}
    widget.preload_variables(available, defaults={"basin": "level"})

    time = np.array(["2020-01-01", "2020-01-02"])
    values = np.array([1.0, 2.0])
    widget.set_data({"basin": {"level": {"#1": (time, values)}}})

    widget.clear()
    assert widget._plot_data == {}
    assert widget._placeholder.isVisibleTo(widget)
    assert not widget._web_view.isVisibleTo(widget)


def test_plot_widget_empty_data_shows_placeholder():
    widget = PlotWidget()
    available = {"basin": ["level"]}
    widget.preload_variables(available, defaults={"basin": "level"})
    widget.set_data({})
    assert widget._placeholder.isVisibleTo(widget)
    assert not widget._web_view.isVisibleTo(widget)
