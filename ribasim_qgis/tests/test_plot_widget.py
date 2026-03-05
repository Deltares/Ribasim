"""Tests for ribasim_qgis.widgets.plot_widget — PlotWidget."""

import numpy as np
from qgis.PyQt.QtWidgets import QCheckBox

from ribasim_qgis.widgets.plot_widget import (
    PlotData,
    PlotWidget,
)

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
    assert set(widget._var_menu.checked_variables()) == {"basin / level"}
    assert widget._menu_to_key == {
        "basin / level": ("basin", "level"),
        "basin / storage": ("basin", "storage"),
        "flow / flow_rate": ("flow", "flow_rate"),
    }


def test_plot_widget_preload_multiple_defaults():
    """All defaults are checked so both node and link selections produce plots."""
    widget = PlotWidget()
    available = {
        "basin": ["level", "storage"],
        "flow": ["flow_rate"],
    }
    defaults = {"basin": "level", "flow": "flow_rate"}
    widget.preload_variables(available, defaults=defaults)
    assert set(widget._var_menu.checked_variables()) == {
        "basin / level",
        "flow / flow_rate",
    }


def test_plot_widget_set_data_and_redraw():
    """Test that set_data populates _plot_data and triggers a redraw."""
    widget = PlotWidget()

    available = {"basin": ["level"], "flow": ["flow_rate"]}
    units = {
        "basin": {"level": "m"},
        "flow": {"flow_rate": "m3 s-1"},
    }
    widget.preload_variables(available, units=units, defaults={"basin": "level"})
    widget._var_menu.populate(
        widget._available,
        {"basin / level", "flow / flow_rate"},
        widget._defaults,
        widget._water_balance_enabled,
    )

    time = np.array(["2020-01-01", "2020-01-02", "2020-01-03"])
    basin_values = np.array([1.0, 2.0, 3.0])
    flow_values = np.array([10.0, 11.0, 12.0])

    plot_data: PlotData = {
        "basin": {
            "level": {
                "#1": (time, basin_values),
            }
        },
        "flow": {
            "flow_rate": {
                "#3": (time, flow_values),
            }
        },
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


def test_plot_widget_legend_includes_file_and_variable(monkeypatch):
    captured_figures = []

    def _capture_plot(fig, **kwargs):
        captured_figures.append(fig)
        return "<div></div>"

    monkeypatch.setattr("ribasim_qgis.widgets.plot_widget.po.plot", _capture_plot)

    widget = PlotWidget()
    widget.preload_variables(
        {"basin": ["level"], "flow": ["level"]},
        units={"basin": {"level": "m"}, "flow": {"level": "m"}},
        defaults={"basin": "level"},
    )
    widget._var_menu.populate(
        widget._available,
        {"basin / level", "flow / level"},
        widget._defaults,
        widget._water_balance_enabled,
    )

    time = np.array(["2020-01-01", "2020-01-02"])
    widget.set_data(
        {
            "basin": {"level": {"#1": (time, np.array([1.0, 2.0]))}},
            "flow": {"level": {"#9": (time, np.array([3.0, 4.0]))}},
        }
    )

    assert len(captured_figures) == 1
    names = {trace.name for trace in captured_figures[0].data}
    assert names == {"basin / level #1", "flow / level #9"}


def test_plot_widget_groups_unitless_into_no_unit_subplot(monkeypatch):
    captured_figures = []

    def _capture_plot(fig, **kwargs):
        captured_figures.append(fig)
        return "<div></div>"

    monkeypatch.setattr("ribasim_qgis.widgets.plot_widget.po.plot", _capture_plot)

    widget = PlotWidget()
    widget.preload_variables(
        {"basin": ["level", "state"]},
        units={"basin": {"level": "m", "state": ""}},
        defaults={"basin": "level"},
    )
    widget._var_menu.populate(
        widget._available,
        {"basin / level", "basin / state"},
        widget._defaults,
        widget._water_balance_enabled,
    )

    time = np.array(["2020-01-01", "2020-01-02"])
    widget.set_data(
        {
            "basin": {
                "level": {"#1": (time, np.array([1.0, 2.0]))},
                "state": {"#1": (time, np.array([0.0, 1.0]))},
            }
        }
    )

    assert len(captured_figures) == 1
    fig = captured_figures[0]
    y_titles = {fig.layout.yaxis.title.text, fig.layout.yaxis2.title.text}
    assert y_titles == {"m", "(no unit)"}


def test_plot_widget_basin_water_balance_preset_applies_signs(monkeypatch):
    captured_figures = []

    def _capture_plot(fig, **kwargs):
        captured_figures.append(fig)
        return "<div></div>"

    monkeypatch.setattr("ribasim_qgis.widgets.plot_widget.po.plot", _capture_plot)

    widget = PlotWidget()
    widget._water_balance_enabled = True

    time = np.array(["2020-01-01", "2020-01-02"])
    plot_data = {
        "basin": {
            "inflow_rate": {"#1": (time, np.array([10.0, 11.0]))},
            "precipitation": {"#1": (time, np.array([1.0, 2.0]))},
            "surface_runoff": {"#1": (time, np.array([3.0, 4.0]))},
            "drainage": {"#1": (time, np.array([5.0, 6.0]))},
            "outflow_rate": {"#1": (time, np.array([7.0, 8.0]))},
            "storage_rate": {"#1": (time, np.array([9.0, 10.0]))},
            "evaporation": {"#1": (time, np.array([11.0, 12.0]))},
            "infiltration": {"#1": (time, np.array([13.0, 14.0]))},
            "balance_error": {"#1": (time, np.array([15.0, 16.0]))},
        }
    }
    units = {
        "basin": {
            "inflow_rate": "m3 s-1",
            "precipitation": "m3 s-1",
            "surface_runoff": "m3 s-1",
            "drainage": "m3 s-1",
            "outflow_rate": "m3 s-1",
            "storage_rate": "m3 s-1",
            "evaporation": "m3 s-1",
            "infiltration": "m3 s-1",
            "balance_error": "m3 s-1",
        }
    }

    widget.set_data(plot_data, units=units)

    assert len(captured_figures) == 1
    fig = captured_figures[0]
    assert [trace.name for trace in fig.data] == [
        "+ balance_error",
        "+ surface_runoff",
        "- infiltration",
        "+ drainage",
        "- evaporation",
        "+ precipitation",
        "- outflow_rate",
        "+ inflow_rate",
        "- storage_rate",
    ]
    assert np.allclose(fig.data[0].y, np.array([15.0, 16.0]))
    assert np.allclose(fig.data[6].y, np.array([-7.0, -8.0]))
    assert np.allclose(fig.data[8].y, np.array([-9.0, -10.0]))
    assert fig.layout.yaxis.title.text == "m3 s-1"
    assert all(trace.mode == "lines" for trace in fig.data)
    assert fig.data[0].hovertemplate is None
    assert fig.layout.hovermode == "x unified"


def test_plot_widget_basin_water_balance_preset_requires_single_basin():
    widget = PlotWidget()
    widget._water_balance_enabled = True

    time = np.array(["2020-01-01", "2020-01-02"])
    widget.set_data(
        {
            "basin": {
                "inflow_rate": {
                    "#1": (time, np.array([1.0, 2.0])),
                    "#2": (time, np.array([3.0, 4.0])),
                }
            }
        }
    )

    assert widget._placeholder.isVisibleTo(widget)
    assert not widget._web_view.isVisibleTo(widget)


def test_plot_widget_basin_water_balance_preset_includes_other_selected_variables(
    monkeypatch,
):
    captured_figures = []

    def _capture_plot(fig, **kwargs):
        captured_figures.append(fig)
        return "<div></div>"

    monkeypatch.setattr("ribasim_qgis.widgets.plot_widget.po.plot", _capture_plot)

    widget = PlotWidget()
    widget._water_balance_enabled = True

    widget.preload_variables(
        {"basin": ["inflow_rate"], "flow": ["flow_rate"]},
        defaults={"flow": "flow_rate"},
    )
    widget._var_menu.populate(
        widget._available,
        {"flow / flow_rate"},
        widget._defaults,
        widget._water_balance_enabled,
    )

    time = np.array(["2020-01-01", "2020-01-02"])
    widget.set_data(
        {
            "basin": {
                "inflow_rate": {"#1": (time, np.array([10.0, 11.0]))},
                "outflow_rate": {"#1": (time, np.array([7.0, 8.0]))},
            },
            "flow": {
                "flow_rate": {"#9": (time, np.array([2.0, 3.0]))},
            },
        },
        units={
            "basin": {"inflow_rate": "m3 s-1", "outflow_rate": "m3 s-1"},
            "flow": {"flow_rate": "m3 s-1"},
        },
    )

    assert len(captured_figures) == 1
    names = [trace.name for trace in captured_figures[0].data]
    assert names == ["- outflow_rate", "+ inflow_rate", "flow / flow_rate #9"]
    assert captured_figures[0].layout.yaxis2.title.text == "m3 s-1"


def test_plot_widget_combined_menu_has_presets_and_file_submenus():
    widget = PlotWidget()
    widget.preload_variables(
        {"basin": ["level", "storage", "state"], "flow": ["flow_rate", "q"]},
        defaults={"basin": "level"},
    )

    root_checkbox_texts = {
        action.defaultWidget().text()
        for action in widget._var_menu.actions()
        if hasattr(action, "defaultWidget")
        and isinstance(action.defaultWidget(), QCheckBox)
    }
    assert "water balance" in root_checkbox_texts
    assert any(
        isinstance(action.defaultWidget(), QCheckBox)
        and action.defaultWidget().text() == "level"
        for action in widget._var_menu.actions()
        if hasattr(action, "defaultWidget")
    )
    assert any(
        isinstance(action.defaultWidget(), QCheckBox)
        and action.defaultWidget().text() == "storage"
        for action in widget._var_menu.actions()
        if hasattr(action, "defaultWidget")
    )
    assert any(
        isinstance(action.defaultWidget(), QCheckBox)
        and action.defaultWidget().text() == "flow_rate"
        for action in widget._var_menu.actions()
        if hasattr(action, "defaultWidget")
    )

    submenu_texts = [
        action.menu().title() for action in widget._var_menu.actions() if action.menu()
    ]
    assert set(submenu_texts) == {"basin", "flow"}

    basin_menu = next(
        action.menu()
        for action in widget._var_menu.actions()
        if action.menu() and action.menu().title() == "basin"
    )
    basin_labels = {
        action.defaultWidget().text()
        for action in basin_menu.actions()
        if hasattr(action, "defaultWidget")
        and isinstance(action.defaultWidget(), QCheckBox)
    }
    assert basin_labels == {"state"}

    flow_menu = next(
        action.menu()
        for action in widget._var_menu.actions()
        if action.menu() and action.menu().title() == "flow"
    )
    flow_labels = {
        action.defaultWidget().text()
        for action in flow_menu.actions()
        if hasattr(action, "defaultWidget")
        and isinstance(action.defaultWidget(), QCheckBox)
    }
    assert flow_labels == {"q"}
