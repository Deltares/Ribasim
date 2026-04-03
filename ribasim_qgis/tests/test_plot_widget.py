"""Tests for ribasim_qgis.widgets.plot_widget — PlotWidget."""

from typing import Any

import numpy as np
from qgis.PyQt.QtWidgets import QCheckBox, QWidgetAction

from ribasim_qgis.widgets.plot_widget import (
    PlotData,
    PlotWidget,
)

# --- PlotWidget ---


def _checkbox_text(action: Any) -> str | None:
    if not isinstance(action, QWidgetAction):
        return None
    widget = action.defaultWidget()
    if isinstance(widget, QCheckBox):
        return widget.text()
    return None


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
        "+ surface_runoff",
        "- infiltration",
        "+ drainage",
        "- evaporation",
        "+ precipitation",
        "- outflow_rate",
        "+ inflow_rate",
        "storage_increase",
        "balance_error",
    ]
    assert np.allclose(fig.data[0].y, np.array([3.0, 4.0]))
    assert np.allclose(fig.data[5].y, np.array([-7.0, -8.0]))
    assert np.allclose(fig.data[7].y, np.array([-9.0, -10.0]))
    assert np.allclose(fig.data[8].y, np.array([15.0, 16.0]))
    assert fig.layout.yaxis.title.text == "m3 s-1"
    assert all(trace.mode == "lines" for trace in fig.data)
    assert ".3e" in str(fig.data[0].hovertemplate)
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
        text
        for action in widget._var_menu.actions()
        if (text := _checkbox_text(action)) is not None
    }
    assert "water balance" in root_checkbox_texts
    assert "fractional storage" in root_checkbox_texts
    assert "fractional flow" in root_checkbox_texts
    assert any(
        _checkbox_text(action) == "level" for action in widget._var_menu.actions()
    )
    assert any(
        _checkbox_text(action) == "storage" for action in widget._var_menu.actions()
    )
    assert any(
        _checkbox_text(action) == "flow_rate" for action in widget._var_menu.actions()
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
        text
        for action in basin_menu.actions()
        if (text := _checkbox_text(action)) is not None
    }
    assert basin_labels == {"state"}

    flow_menu = next(
        action.menu()
        for action in widget._var_menu.actions()
        if action.menu() and action.menu().title() == "flow"
    )
    flow_labels = {
        text
        for action in flow_menu.actions()
        if (text := _checkbox_text(action)) is not None
    }
    assert flow_labels == {"q"}


def test_plot_widget_fractional_storage_preset_plots_default_tracers(monkeypatch):
    captured_figures = []

    def _capture_plot(fig, **kwargs):
        captured_figures.append(fig)
        return "<div></div>"

    monkeypatch.setattr("ribasim_qgis.widgets.plot_widget.po.plot", _capture_plot)

    widget = PlotWidget()
    widget._fractional_storage_enabled = True

    time = np.array(["2020-01-01", "2020-01-02"])
    plot_data = {
        "concentration": {
            "LevelBoundary": {"#1": (time, np.array([0.1, 0.2]))},
            "FlowBoundary": {"#1": (time, np.array([0.3, 0.4]))},
            "Initial": {"#1": (time, np.array([0.5, 0.3]))},
            "Drainage": {"#1": (time, np.array([0.05, 0.05]))},
            "Precipitation": {"#1": (time, np.array([0.05, 0.05]))},
        }
    }

    widget.set_data(plot_data)

    assert len(captured_figures) == 1
    fig = captured_figures[0]
    names = {trace.name for trace in fig.data}
    assert names == {
        "LevelBoundary",
        "FlowBoundary",
        "Initial",
        "Drainage",
        "Precipitation",
    }
    assert all(trace.stackgroup == "fractions" for trace in fig.data)
    assert fig.layout.hovermode == "x unified"


def test_plot_widget_fractional_storage_preset_requires_single_node():
    widget = PlotWidget()
    widget._fractional_storage_enabled = True

    time = np.array(["2020-01-01", "2020-01-02"])
    widget.set_data(
        {
            "concentration": {
                "LevelBoundary": {
                    "#1": (time, np.array([0.5, 0.5])),
                    "#2": (time, np.array([0.5, 0.5])),
                }
            }
        }
    )

    assert widget._placeholder.isVisibleTo(widget)
    assert not widget._web_view.isVisibleTo(widget)


def test_plot_widget_fractional_storage_preset_uses_selected_substances(monkeypatch):
    captured_figures = []

    def _capture_plot(fig, **kwargs):
        captured_figures.append(fig)
        return "<div></div>"

    monkeypatch.setattr("ribasim_qgis.widgets.plot_widget.po.plot", _capture_plot)

    widget = PlotWidget()
    widget._fractional_storage_enabled = True

    widget.preload_variables(
        {"concentration": ["LevelBoundary", "FlowBoundary", "Initial"]},
    )
    # Check only LevelBoundary in the concentration submenu.
    widget._var_menu.populate(
        widget._available,
        {"concentration / LevelBoundary"},
        widget._defaults,
        widget._water_balance_enabled,
        widget._fractional_storage_enabled,
        widget._fractional_flow_enabled,
    )

    time = np.array(["2020-01-01", "2020-01-02"])
    widget.set_data(
        {
            "concentration": {
                "LevelBoundary": {"#1": (time, np.array([0.5, 0.6]))},
                "FlowBoundary": {"#1": (time, np.array([0.3, 0.2]))},
                "Initial": {"#1": (time, np.array([0.2, 0.2]))},
            }
        },
    )

    assert len(captured_figures) == 1
    fig = captured_figures[0]
    names = [trace.name for trace in fig.data]
    assert names == ["LevelBoundary"]


def test_plot_widget_fractional_storage_distinct_from_regular_concentration(
    monkeypatch,
):
    """Concentration substances must not appear as individual standard traces.

    When a fractional storage preset is active.
    """
    captured_figures = []

    def _capture_plot(fig, **kwargs):
        captured_figures.append(fig)
        return "<div></div>"

    monkeypatch.setattr("ribasim_qgis.widgets.plot_widget.po.plot", _capture_plot)

    widget = PlotWidget()
    widget._fractional_storage_enabled = True

    widget.preload_variables(
        {
            "concentration": ["LevelBoundary", "FlowBoundary"],
            "basin": ["level"],
        },
    )
    widget._var_menu.populate(
        widget._available,
        {
            "concentration / LevelBoundary",
            "concentration / FlowBoundary",
            "basin / level",
        },
        widget._defaults,
        widget._water_balance_enabled,
        widget._fractional_storage_enabled,
        widget._fractional_flow_enabled,
    )

    time = np.array(["2020-01-01", "2020-01-02"])
    widget.set_data(
        {
            "concentration": {
                "LevelBoundary": {"#1": (time, np.array([0.5, 0.6]))},
                "FlowBoundary": {"#1": (time, np.array([0.5, 0.4]))},
            },
            "basin": {
                "level": {"#1": (time, np.array([2.0, 2.1]))},
            },
        },
        units={"basin": {"level": "m"}},
    )

    assert len(captured_figures) == 1
    fig = captured_figures[0]
    names = [trace.name for trace in fig.data]
    # Stacked fractions + basin level in an extra subplot — NO individual
    # concentration line traces.
    assert "LevelBoundary" in names
    assert "FlowBoundary" in names
    assert "basin / level #1" in names
    # Ensure the concentration substances are in the stacked area, not lines.
    for trace in fig.data:
        if trace.name in ("LevelBoundary", "FlowBoundary"):
            assert trace.stackgroup == "fractions"
        else:
            assert trace.stackgroup is None


def test_plot_widget_fractional_flow_plots_multiplied_values(monkeypatch):
    captured_figures = []

    def _capture_plot(fig, **kwargs):
        captured_figures.append(fig)
        return "<div></div>"

    monkeypatch.setattr("ribasim_qgis.widgets.plot_widget.po.plot", _capture_plot)

    time = np.array(["2020-01-01", "2020-01-02"])

    def _conc_getter(node_id):
        if node_id == 5:
            return {
                "LevelBoundary": (time, np.array([0.4, 0.5])),
                "FlowBoundary": (time, np.array([0.6, 0.5])),
            }
        return None

    widget = PlotWidget(concentration_for_node_getter=_conc_getter)
    widget._fractional_flow_enabled = True

    # Patch layer lookups: link 42 goes from Basin 5 → Basin 6.
    monkeypatch.setattr(PlotWidget, "_get_link_endpoints", lambda self, lid: (5, 6))
    monkeypatch.setattr(
        PlotWidget,
        "_endpoint_concentration",
        lambda self, nid, lid, n, ft: _conc_getter(nid),
    )

    widget.set_data(
        {
            "flow": {
                "flow_rate": {"#42": (time, np.array([10.0, 20.0]))},
            },
        },
        units={"flow": {"flow_rate": "m3 s-1"}},
    )

    assert len(captured_figures) == 1
    fig = captured_figures[0]
    names = {trace.name for trace in fig.data}
    assert names == {"LevelBoundary", "FlowBoundary", "flow_rate"}
    stacked = [t for t in fig.data if t.name != "flow_rate"]
    assert all(trace.stackgroup == "fractions" for trace in stacked)

    # Verify multiplication: concentration * flow_rate
    for trace in fig.data:
        if trace.name == "LevelBoundary":
            assert np.allclose(trace.y, np.array([4.0, 10.0]))
        elif trace.name == "FlowBoundary":
            assert np.allclose(trace.y, np.array([6.0, 10.0]))
        elif trace.name == "flow_rate":
            assert trace.line.color == "black"
            assert np.allclose(trace.y, np.array([10.0, 20.0]))

    assert fig.layout.yaxis.title.text == "m3 s-1"
    assert fig.layout.hovermode == "x unified"


def test_plot_widget_fractional_flow_requires_single_link():
    widget = PlotWidget()
    widget._fractional_flow_enabled = True

    time = np.array(["2020-01-01", "2020-01-02"])
    widget.set_data(
        {
            "flow": {
                "flow_rate": {
                    "#1": (time, np.array([5.0, 6.0])),
                    "#2": (time, np.array([3.0, 4.0])),
                },
            },
        },
    )

    assert widget._placeholder.isVisibleTo(widget)
    assert not widget._web_view.isVisibleTo(widget)


def test_plot_widget_fractional_flow_junction(monkeypatch):
    """Fractional flow through a Junction aggregates source basin concentrations."""
    captured_figures = []

    def _capture_plot(fig, **kwargs):
        captured_figures.append(fig)
        return "<div></div>"

    monkeypatch.setattr("ribasim_qgis.widgets.plot_widget.po.plot", _capture_plot)

    time = np.array(["2020-01-01", "2020-01-02"])

    # Network: Basin(10) --link20--> Junction(50) --link1--> Basin(60)
    #          Basin(11) --link21-->
    # Selected link: link 1 (from Junction 50 to Basin 60).
    # Basin 10 has LevelBoundary=0.6, Basin 11 has LevelBoundary=0.4.
    # Flow on link 20: [6.0, 12.0], flow on link 21: [4.0, 8.0].
    # Total inflow to junction: [10.0, 20.0] (matches selected link flow).
    # Effective concentration at junction:
    #   (0.6*6 + 0.4*4) / (6+4) = 5.2/10 = 0.52  at t=0
    #   (0.6*12 + 0.4*8) / (12+8) = 10.4/20 = 0.52  at t=1
    # Fractional values = effective_conc * selected_flow = [0.52*10, 0.52*20] = [5.2, 10.4]

    def _conc_getter(node_id):
        if node_id == 10:
            return {"LevelBoundary": (time, np.array([0.6, 0.6]))}
        if node_id == 11:
            return {"LevelBoundary": (time, np.array([0.4, 0.4]))}
        if node_id == 60:
            return {"LevelBoundary": (time, np.array([1.0, 1.0]))}
        return None

    def _flow_getter(link_id):
        if link_id == 20:
            return (time, np.array([6.0, 12.0]))
        if link_id == 21:
            return (time, np.array([4.0, 8.0]))
        return None

    widget = PlotWidget(
        concentration_for_node_getter=_conc_getter,
        flow_for_link_getter=_flow_getter,
    )
    widget._fractional_flow_enabled = True

    monkeypatch.setattr(PlotWidget, "_get_link_endpoints", lambda self, lid: (50, 60))
    monkeypatch.setattr(
        PlotWidget,
        "_get_node_type",
        lambda self, nid: {
            50: "Junction",
            60: "Basin",
            10: "Basin",
            11: "Basin",
        }.get(nid),
    )
    monkeypatch.setattr(
        PlotWidget,
        "_resolve_junction_sources",
        lambda self, jid, lid: [(10, 20, 1), (11, 21, 1)],
    )

    widget.set_data(
        {
            "flow": {
                "flow_rate": {"#1": (time, np.array([10.0, 20.0]))},
            },
        },
        units={"flow": {"flow_rate": "m3 s-1"}},
    )

    assert len(captured_figures) == 1
    fig = captured_figures[0]
    names = {trace.name for trace in fig.data}
    assert "LevelBoundary" in names
    assert "flow_rate" in names

    for trace in fig.data:
        if trace.name == "LevelBoundary":
            assert np.allclose(trace.y, np.array([5.2, 10.4]))
        elif trace.name == "flow_rate":
            assert np.allclose(trace.y, np.array([10.0, 20.0]))


def test_plot_widget_fractional_flow_traverses_connector(monkeypatch):
    """Fractional flow should traverse a connector node to find the Basin."""
    captured_figures = []

    def _capture_plot(fig, **kwargs):
        captured_figures.append(fig)
        return "<div></div>"

    monkeypatch.setattr("ribasim_qgis.widgets.plot_widget.po.plot", _capture_plot)

    time = np.array(["2020-01-01", "2020-01-02"])

    def _conc_getter(node_id):
        if node_id == 10:
            return {
                "LevelBoundary": (time, np.array([0.3, 0.7])),
            }
        return None

    widget = PlotWidget(concentration_for_node_getter=_conc_getter)
    widget._fractional_flow_enabled = True

    # Link 1: from ManningResistance(2) → Basin(3).
    # _endpoint_concentration traverses connector 2 to find Basin 10.
    def _endpoint_conc(self, nid, lid, n, ft):
        if nid == 2:
            return _conc_getter(10)
        if nid == 3:
            return _conc_getter(3)  # None — no concentration for Basin 3
        return None

    monkeypatch.setattr(PlotWidget, "_get_link_endpoints", lambda self, lid: (2, 3))
    monkeypatch.setattr(PlotWidget, "_endpoint_concentration", _endpoint_conc)

    widget.set_data(
        {
            "flow": {
                "flow_rate": {"#1": (time, np.array([10.0, 20.0]))},
            },
        },
    )

    assert len(captured_figures) == 1
    fig = captured_figures[0]
    # With positive flow, source is from-side Basin 10.
    for trace in fig.data:
        if trace.name == "LevelBoundary":
            assert np.allclose(trace.y, np.array([3.0, 14.0]))


def test_plot_widget_fractional_flow_sign_flip(monkeypatch):
    """When flow_rate sign flips, the source basin should switch."""
    captured_figures = []

    def _capture_plot(fig, **kwargs):
        captured_figures.append(fig)
        return "<div></div>"

    monkeypatch.setattr("ribasim_qgis.widgets.plot_widget.po.plot", _capture_plot)

    time = np.array(["2020-01-01", "2020-01-02"])

    def _conc_getter(node_id):
        if node_id == 5:
            return {"LevelBoundary": (time, np.array([0.4, 0.4]))}
        if node_id == 6:
            return {"LevelBoundary": (time, np.array([0.8, 0.8]))}
        return None

    widget = PlotWidget(concentration_for_node_getter=_conc_getter)
    widget._fractional_flow_enabled = True

    monkeypatch.setattr(PlotWidget, "_get_link_endpoints", lambda self, lid: (5, 6))
    monkeypatch.setattr(
        PlotWidget,
        "_endpoint_concentration",
        lambda self, nid, lid, n, ft: _conc_getter(nid),
    )

    # flow_rate: +10 at t0 (source=from=5), -10 at t1 (source=to=6)
    widget.set_data(
        {
            "flow": {
                "flow_rate": {"#1": (time, np.array([10.0, -10.0]))},
            },
        },
    )

    assert len(captured_figures) == 1
    fig = captured_figures[0]
    for trace in fig.data:
        if trace.name == "LevelBoundary":
            # t0: 0.4 * 10 = 4.0,  t1: 0.8 * -10 = -8.0
            assert np.allclose(trace.y, np.array([4.0, -8.0]))


def test_plot_widget_fractional_flow_connector_to_junction(monkeypatch):
    """Fractional flow through ManningResistance → Junction resolves sources."""
    captured_figures = []

    def _capture_plot(fig, **kwargs):
        captured_figures.append(fig)
        return "<div></div>"

    monkeypatch.setattr("ribasim_qgis.widgets.plot_widget.po.plot", _capture_plot)

    time = np.array(["2020-01-01", "2020-01-02"])

    # Network:
    #   Basin(10) --link20--> Junction(50) --link30--> Manning(60) --link1--> Basin(70)
    #   Basin(11) --link21-->
    # Selected link: link 1 (Manning 60 → Basin 70).
    # _endpoint_concentration for Manning(60) traverses to Junction(50),
    # then resolves junction sources.

    def _conc_getter(node_id):
        if node_id == 10:
            return {"Tracer": (time, np.array([0.8, 0.8]))}
        if node_id == 11:
            return {"Tracer": (time, np.array([0.2, 0.2]))}
        if node_id == 70:
            return {"Tracer": (time, np.array([1.0, 1.0]))}
        return None

    def _flow_getter(link_id):
        if link_id == 20:
            return (time, np.array([8.0, 16.0]))
        if link_id == 21:
            return (time, np.array([2.0, 4.0]))
        return None

    widget = PlotWidget(
        concentration_for_node_getter=_conc_getter,
        flow_for_link_getter=_flow_getter,
    )
    widget._fractional_flow_enabled = True

    monkeypatch.setattr(PlotWidget, "_get_link_endpoints", lambda self, lid: (60, 70))

    node_types = {
        60: "ManningResistance",
        70: "Basin",
        50: "Junction",
        10: "Basin",
        11: "Basin",
    }
    monkeypatch.setattr(
        PlotWidget, "_get_node_type", lambda self, nid: node_types.get(nid)
    )
    # Manning(60) traversal: arrived on link 1, other link is link 30 to Junction(50).
    monkeypatch.setattr(
        PlotWidget, "_traverse_connector", lambda self, nid, lid: (50, 30)
    )
    monkeypatch.setattr(
        PlotWidget,
        "_resolve_junction_sources",
        lambda self, jid, lid: [(10, 20, 1), (11, 21, 1)],
    )

    widget.set_data(
        {
            "flow": {
                "flow_rate": {"#1": (time, np.array([10.0, 20.0]))},
            },
        },
        units={"flow": {"flow_rate": "m3 s-1"}},
    )

    assert len(captured_figures) == 1
    fig = captured_figures[0]

    # Junction effective conc: (0.8*8 + 0.2*2)/(8+2) = 6.8/10 = 0.68
    # Fractional values: 0.68 * [10, 20] = [6.8, 13.6]
    for trace in fig.data:
        if trace.name == "Tracer":
            assert np.allclose(trace.y, np.array([6.8, 13.6]))
