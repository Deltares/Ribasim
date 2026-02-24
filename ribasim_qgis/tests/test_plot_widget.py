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
    assert set(widget._var_menu.checked_variables()) == {"basin / level"}
    assert widget._menu_to_key == {
        "basin / level": ("basin", "level"),
        "basin / storage": ("basin", "storage"),
        "flow / flow_rate": ("flow", "flow_rate"),
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
        ["basin / level", "flow / flow_rate"],
        {"basin / level", "flow / flow_rate"},
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
        ["basin / level", "flow / level"], {"basin / level", "flow / level"}
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
        ["basin / level", "basin / state"],
        {"basin / level", "basin / state"},
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

    assert len(captured_figures) == 2
    y_titles = {fig.layout.yaxis.title.text for fig in captured_figures}
    assert y_titles == {"m", "(no unit)"}
