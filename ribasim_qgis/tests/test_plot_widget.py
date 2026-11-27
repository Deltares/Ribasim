"""Tests for ribasim_qgis.widgets.plot_widget — PlotWidget."""

import sqlite3
from typing import Any

import netCDF4 as nc4
import numpy as np
import pandas as pd
import pytest
from qgis.core import QgsFeature, QgsVectorLayer
from qgis.PyQt.QtWidgets import QCheckBox, QWidgetAction

from ribasim_qgis.core.junctions import (
    JUNCTION_STATIC_TABLE,
    FlowGraph,
    read_junctions_in_static,
)
from ribasim_qgis.core.netcdf import NetCDFResult
from ribasim_qgis.core.tracer_flow import (
    InputConcentrations,
    TracerFlows,
    read_input_concentrations,
)
from ribasim_qgis.widgets.dataset_widget import DatasetWidget
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
    widget.preload_variables(available, units, defaults={"basin": ["level"]})
    assert widget._available == available
    assert widget._units == units
    assert widget._defaults == {"basin": ["level"]}
    assert set(widget._var_menu.checked_keys()) == {("basin", "level")}


def test_plot_widget_preload_multiple_defaults():
    """All defaults are checked so both node and link selections produce plots."""
    widget = PlotWidget()
    available = {
        "basin": ["level", "storage"],
        "flow": ["flow_rate"],
    }
    defaults = {"basin": ["level"], "flow": ["flow_rate"]}
    widget.preload_variables(available, defaults=defaults)
    assert set(widget._var_menu.checked_keys()) == {
        ("basin", "level"),
        ("flow", "flow_rate"),
    }


def test_plot_widget_flow_rate_group_toggles_all_constituents():
    """The synthetic 'flow_rate' root checkbox toggles all three keys."""
    widget = PlotWidget()
    available = {
        "basin": ["level", "inflow_rate", "outflow_rate"],
        "flow": ["flow_rate"],
    }
    defaults = {
        "basin": ["level", "inflow_rate", "outflow_rate"],
        "flow": ["flow_rate"],
    }
    widget.preload_variables(available, defaults=defaults)

    # Default-on: level + flow_rate group => 4 keys.
    assert set(widget._var_menu.checked_keys()) == {
        ("basin", "level"),
        ("basin", "inflow_rate"),
        ("basin", "outflow_rate"),
        ("flow", "flow_rate"),
    }

    # All basin variables are constituents of root groups, so no basin
    # submenu is created.
    submenu_titles = {
        action.menu().title() for action in widget._var_menu.actions() if action.menu()
    }
    assert "basin" not in submenu_titles
    assert "flow" not in submenu_titles


def test_plot_widget_set_data_and_redraw():
    """Test that set_data populates _plot_data and triggers a redraw."""
    widget = PlotWidget()

    available = {"basin": ["level"], "flow": ["flow_rate"]}
    units = {
        "basin": {"level": "m"},
        "flow": {"flow_rate": "m3 s-1"},
    }
    widget.preload_variables(available, units=units, defaults={"basin": ["level"]})
    widget._var_menu.populate(
        widget._available,
        {("basin", "level"), ("flow", "flow_rate")},
        widget._defaults,
        widget._water_balance_enabled,
    )

    time = np.array(["2020-01-01", "2020-01-02", "2020-01-03"])
    basin_values = np.array([1.0, 2.0, 3.0])
    flow_values = np.array([10.0, 11.0, 12.0])

    plot_data: PlotData = {
        "basin": {
            "level": {
                "Basin #1": (time, basin_values),
            }
        },
        "flow": {
            "flow_rate": {
                "Link #3": (time, flow_values),
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
    widget.preload_variables(available, defaults={"basin": ["level"]})

    time = np.array(["2020-01-01", "2020-01-02"])
    values = np.array([1.0, 2.0])
    widget.set_data({"basin": {"level": {"Basin #1": (time, values)}}})

    widget.clear()
    assert widget._plot_data == {}
    assert widget._placeholder.isVisibleTo(widget)
    assert not widget._web_view.isVisibleTo(widget)


def test_plot_widget_empty_data_shows_placeholder():
    widget = PlotWidget()
    available = {"basin": ["level"]}
    widget.preload_variables(available, defaults={"basin": ["level"]})
    widget.set_data({})
    assert widget._placeholder.isVisibleTo(widget)
    assert not widget._web_view.isVisibleTo(widget)


def test_plot_widget_legend_uses_entity_and_variable(monkeypatch):
    captured_figures = []

    def _capture_plot(fig, **kwargs):
        captured_figures.append(fig)
        return "<div></div>"

    monkeypatch.setattr("ribasim_qgis.widgets.plot_widget.po.plot", _capture_plot)

    widget = PlotWidget()
    widget.preload_variables(
        {"basin": ["level"], "flow": ["level"]},
        units={"basin": {"level": "m"}, "flow": {"level": "m"}},
        defaults={"basin": ["level"]},
    )
    widget._var_menu.populate(
        widget._available,
        {("basin", "level"), ("flow", "level")},
        widget._defaults,
        widget._water_balance_enabled,
    )

    time = np.array(["2020-01-01", "2020-01-02"])
    widget.set_data(
        {
            "basin": {"level": {"Basin #1": (time, np.array([1.0, 2.0]))}},
            "flow": {"level": {"Link #9": (time, np.array([3.0, 4.0]))}},
        }
    )

    assert len(captured_figures) == 1
    names = {trace.name for trace in captured_figures[0].data}
    assert names == {"Basin #1 level", "Link #9 level"}


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
        defaults={"basin": ["level"]},
    )
    widget._var_menu.populate(
        widget._available,
        {("basin", "level"), ("basin", "state")},
        widget._defaults,
        widget._water_balance_enabled,
    )

    time = np.array(["2020-01-01", "2020-01-02"])
    widget.set_data(
        {
            "basin": {
                "level": {"Basin #1": (time, np.array([1.0, 2.0]))},
                "state": {"Basin #1": (time, np.array([0.0, 1.0]))},
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
            "inflow_rate": {"Basin #1": (time, np.array([10.0, 11.0]))},
            "precipitation": {"Basin #1": (time, np.array([1.0, 2.0]))},
            "surface_runoff": {"Basin #1": (time, np.array([3.0, 4.0]))},
            "drainage": {"Basin #1": (time, np.array([5.0, 6.0]))},
            "outflow_rate": {"Basin #1": (time, np.array([7.0, 8.0]))},
            "storage_rate": {"Basin #1": (time, np.array([9.0, 10.0]))},
            "evaporation": {"Basin #1": (time, np.array([11.0, 12.0]))},
            "infiltration": {"Basin #1": (time, np.array([13.0, 14.0]))},
            "balance_error": {"Basin #1": (time, np.array([15.0, 16.0]))},
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
                    "Basin #1": (time, np.array([1.0, 2.0])),
                    "Basin #2": (time, np.array([3.0, 4.0])),
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
        defaults={"flow": ["flow_rate"]},
    )
    widget._var_menu.populate(
        widget._available,
        {("flow", "flow_rate")},
        widget._defaults,
        widget._water_balance_enabled,
    )

    time = np.array(["2020-01-01", "2020-01-02"])
    widget.set_data(
        {
            "basin": {
                "inflow_rate": {"Basin #1": (time, np.array([10.0, 11.0]))},
                "outflow_rate": {"Basin #1": (time, np.array([7.0, 8.0]))},
            },
            "flow": {
                "flow_rate": {"Link #9": (time, np.array([2.0, 3.0]))},
            },
        },
        units={
            "basin": {"inflow_rate": "m3 s-1", "outflow_rate": "m3 s-1"},
            "flow": {"flow_rate": "m3 s-1"},
        },
    )

    assert len(captured_figures) == 1
    names = [trace.name for trace in captured_figures[0].data]
    assert names == ["- outflow_rate", "+ inflow_rate", "Link #9 flow_rate"]
    assert captured_figures[0].layout.yaxis2.title.text == "m3 s-1"


def test_plot_widget_combined_menu_has_presets_and_file_submenus():
    widget = PlotWidget()
    widget.preload_variables(
        {"basin": ["level", "storage", "state"], "flow": ["flow_rate", "q"]},
        defaults={"basin": ["level"]},
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


# --- _selected_tracers ordering ---

_ST = PlotWidget()._selected_tracers


def test_selected_tracers_default_order():
    all_defaults = {
        "Precipitation",
        "LevelBoundary",
        "FlowBoundary",
        "SurfaceRunoff",
        "Drainage",
        "Initial",
    }
    assert _ST([], all_defaults) == [
        "Precipitation",
        "LevelBoundary",
        "FlowBoundary",
        "SurfaceRunoff",
        "Drainage",
        "Initial",
    ]


def test_selected_tracers_initial_last_among_defaults():
    assert _ST([], {"Precipitation", "LevelBoundary", "Initial"}) == [
        "Precipitation",
        "LevelBoundary",
        "Initial",
    ]


def test_selected_tracers_user_selected_initial_last():
    keys = [
        ("concentration", "Initial"),
        ("concentration", "FlowBoundary"),
        ("concentration", "Custom"),
    ]
    assert _ST(keys, {"Initial", "FlowBoundary", "Custom"}) == [
        "FlowBoundary",
        "Custom",
        "Initial",
    ]


def test_selected_tracers_only_custom_sorted():
    assert _ST([], {"Zebra", "Alpha", "Mango"}) == ["Alpha", "Mango", "Zebra"]


def test_selected_tracers_no_initial():
    assert _ST([], {"Precipitation", "Drainage"}) == ["Precipitation", "Drainage"]


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
            "LevelBoundary": {"Basin #1": (time, np.array([0.1, 0.2]))},
            "FlowBoundary": {"Basin #1": (time, np.array([0.3, 0.4]))},
            "Initial": {"Basin #1": (time, np.array([0.5, 0.3]))},
            "Drainage": {"Basin #1": (time, np.array([0.05, 0.05]))},
            "Precipitation": {"Basin #1": (time, np.array([0.05, 0.05]))},
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
                    "Basin #1": (time, np.array([0.5, 0.5])),
                    "Basin #2": (time, np.array([0.5, 0.5])),
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
        {("concentration", "LevelBoundary")},
        widget._defaults,
        widget._water_balance_enabled,
        widget._fractional_storage_enabled,
        widget._fractional_flow_enabled,
    )

    time = np.array(["2020-01-01", "2020-01-02"])
    widget.set_data(
        {
            "concentration": {
                "LevelBoundary": {"Basin #1": (time, np.array([0.5, 0.6]))},
                "FlowBoundary": {"Basin #1": (time, np.array([0.3, 0.2]))},
                "Initial": {"Basin #1": (time, np.array([0.2, 0.2]))},
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
            ("concentration", "LevelBoundary"),
            ("concentration", "FlowBoundary"),
            ("basin", "level"),
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
                "LevelBoundary": {"Basin #1": (time, np.array([0.5, 0.6]))},
                "FlowBoundary": {"Basin #1": (time, np.array([0.5, 0.4]))},
            },
            "basin": {
                "level": {"Basin #1": (time, np.array([2.0, 2.1]))},
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
    assert "Basin #1 level" in names
    # Ensure the concentration substances are in the stacked area, not lines.
    for trace in fig.data:
        if trace.name in ("LevelBoundary", "FlowBoundary"):
            assert trace.stackgroup == "fractions"
        else:
            assert trace.stackgroup is None


def _memory_layer(fields: str, rows: list[tuple[Any, ...]]) -> QgsVectorLayer:
    layer = QgsVectorLayer(f"None?{fields}", "layer", "memory")
    features = []
    for row in rows:
        feature = QgsFeature(layer.fields())
        feature.setAttributes(list(row))
        features.append(feature)
    provider = layer.dataProvider()
    assert provider is not None
    provider.addFeatures(features)
    return layer


def _layers(
    node_types: dict[int, str],
    links: dict[int, tuple[int, int]],
    observation_links: dict[int, tuple[int, int]] | None = None,
) -> tuple[QgsVectorLayer, QgsVectorLayer]:
    """Return a node and a link layer with flow links and observation links."""
    node_layer = _memory_layer(
        "field=node_id:integer&field=node_type:string", list(node_types.items())
    )
    link_layer = _memory_layer(
        "field=link_id:integer&field=from_node_id:integer"
        "&field=to_node_id:integer&field=link_type:string",
        [(lid, *link, "flow") for lid, link in links.items()]
        + [
            (lid, *link, "observation")
            for lid, link in (observation_links or {}).items()
        ],
    )
    return node_layer, link_layer


_TIME = np.array(["2020-01-01", "2020-01-02"])


def _tracer(concentration: float) -> dict[str, list[float]]:
    """Return the concentrations of a Basin: Tracer and the Other rest of the water."""
    return {
        "Continuity": [1.0, 1.0],
        "Tracer": [concentration] * 2,
        "Other": [1.0 - concentration] * 2,
    }


def _tracer_flows(
    node_types: dict[int, str],
    links: dict[int, tuple[int, int]],
    flows: dict[int, list[float]],
    concentrations: dict[int, dict[str, list[float]]],
    junctions_in_static: frozenset[int] = frozenset(),
    input_concentrations: dict[int, dict[str, list[float]]] | None = None,
) -> TracerFlows:
    """Return the tracer flows of a network with flows and Basin concentrations."""

    def _as_arrays(
        values: dict[int, dict[str, list[float]]], node_id: int
    ) -> dict[str, np.ndarray] | None:
        if node_id not in values:
            return None
        return {s: np.array(v) for s, v in values[node_id].items()}

    return TracerFlows(
        FlowGraph(*_layers(node_types, links), junctions_in_static),
        lambda link_id: np.array(flows[link_id]) if link_id in flows else None,
        lambda node_id: _as_arrays(concentrations, node_id),
        n_time=2,
        input_concentration=lambda node_id: _as_arrays(
            input_concentrations or {}, node_id
        ),
    )


def _assert_tracers(
    tracers: dict[str, np.ndarray] | None,
    expected: dict[str, list[float]],
    total: Any,
) -> None:
    """Check the tracer flows, and that the Continuity tracer adds up to the total."""
    assert tracers is not None
    for name in {"FlowBoundary", "LevelBoundary", "Tracer", "Other", *expected}:
        assert np.allclose(tracers.get(name, 0.0), expected.get(name, [0.0, 0.0])), name
    assert np.allclose(tracers["Continuity"], total)


# Junction 2 has rows, and divides the flow of FlowBoundary 1 over Junction 4 and 5, which
# have none. Junction 4 joins it with FlowBoundary 3 into Basin 6. Junction 5 connects Basin 7
# with LinearResistance 8, which drains Basin 7 into LevelBoundary 9 and then reverses.
#
#   FlowBoundary 1 --1--> Junction 2 --2--> Junction 4 --4--> Basin 6
#   FlowBoundary 3 --3--> Junction 4
#   Junction 2 --5--> Junction 5 --6--> Basin 7
#   Junction 5 --7--> LinearResistance 8 --8--> LevelBoundary 9
_INTO_NETWORK = (
    {
        1: "FlowBoundary",
        2: "Junction",
        3: "FlowBoundary",
        4: "Junction",
        5: "Junction",
        6: "Basin",
        7: "Basin",
        8: "LinearResistance",
        9: "LevelBoundary",
    },
    {
        1: (1, 2),
        2: (2, 4),
        3: (3, 4),
        4: (4, 6),
        5: (2, 5),
        6: (5, 7),
        7: (5, 8),
        8: (8, 9),
    },
    {
        1: [10.0, 10.0],
        2: [4.0, 4.0],
        3: [5.0, 5.0],
        4: [9.0, 9.0],
        5: [6.0, 6.0],
        6: [5.0, 7.0],
        7: [1.0, -1.0],
        8: [1.0, -1.0],
    },
    {6: _tracer(0.5), 7: _tracer(0.2)},
    frozenset({2}),
)
# The net flow of the group of Junction 5 to Basin 7: the inflow from Junction 2, minus the
# outflow of Basin 7 over the LinearResistance, which reverses to bring in the LevelBoundary.
_INTO_BASIN_7 = {
    "FlowBoundary": [6.0, 6.0],
    "Tracer": [-0.2, 0.0],
    "Other": [-0.8, 0.0],
    "LevelBoundary": [0.0, 1.0],
}
_INTO_LINEAR_RESISTANCE = {
    "Tracer": [0.2, 0.0],
    "Other": [0.8, 0.0],
    "LevelBoundary": [0.0, -1.0],
}


@pytest.mark.parametrize(
    ("link_id", "expected"),
    [
        # The Junction with rows passes on the water of FlowBoundary 1
        (2, {"FlowBoundary": [4.0, 4.0]}),
        # The group of Junction 4 only brings FlowBoundary water to Basin 6
        (4, {"FlowBoundary": [9.0, 9.0]}),
        (6, _INTO_BASIN_7),
        (8, _INTO_LINEAR_RESISTANCE),
    ],
)
def test_tracer_flows_junction_into_junction_link(link_id, expected):
    tracer_flows = _tracer_flows(*_INTO_NETWORK)
    _assert_tracers(tracer_flows.link(link_id), expected, _INTO_NETWORK[2][link_id])


@pytest.mark.parametrize(
    ("node_id", "expected_total", "expected"),
    [
        # A connector node has the flow of its outflow link
        (8, [1.0, -1.0], _INTO_LINEAR_RESISTANCE),
        # A Junction with rows has its total inflow
        (2, [10.0, 10.0], {"FlowBoundary": [10.0, 10.0]}),
        # A Junction without rows has the flow on its link towards the Basin
        (5, [5.0, 7.0], _INTO_BASIN_7),
    ],
)
def test_tracer_flows_junction_into_junction_node(node_id, expected_total, expected):
    node_flows = _tracer_flows(*_INTO_NETWORK).node(node_id)
    assert node_flows is not None
    total, tracers = node_flows
    assert np.allclose(total, expected_total)
    _assert_tracers(tracers, expected, total)


# UserDemand 4 abstracts from Junction 3, which passes the rest of the Pump flow on to
# Basin 6. Its return flow joins FlowBoundary 7 in Junction 5, which flows into Basin 6, and
# into Terminal 8 with a flow that is zero within the solver tolerance.
#
#   Basin 1 --1--> Pump 2 --2--> Junction 3 --3--> UserDemand 4 --4--> Junction 5 --7--> Basin 6
#                                Junction 3 --5--> Basin 6
#   FlowBoundary 7 --6--> Junction 5 --8--> Terminal 8
_USER_DEMAND_NETWORK = (
    {
        1: "Basin",
        2: "Pump",
        3: "Junction",
        4: "UserDemand",
        5: "Junction",
        6: "Basin",
        7: "FlowBoundary",
        8: "Terminal",
    },
    {
        1: (1, 2),
        2: (2, 3),
        3: (3, 4),
        4: (4, 5),
        5: (3, 6),
        6: (7, 5),
        7: (5, 6),
        8: (5, 8),
    },
    {
        1: [4.0, 4.0],
        2: [4.0, 4.0],
        3: [3.0, 3.0],
        4: [1.5, 1.5],
        5: [1.0, 1.0],
        6: [0.5, 0.5],
        7: [2.0, 2.0],
        8: [0.0, -1e-12],
    },
    {1: _tracer(0.4), 6: _tracer(0.9)},
    frozenset({3, 5}),
    {4: {"Bar": [4.0, 4.0]}, 7: {"Foo": [2.0, 2.0]}},
)


def test_tracer_flows_user_demand_return():
    tracer_flows = _tracer_flows(*_USER_DEMAND_NETWORK)
    # The return flow has the water of Basin 1 plus the substance of the input table of
    # the UserDemand, and mixes with the FlowBoundary water and the substance of its table
    expected = {
        "Tracer": [0.6, 0.6],
        "Other": [0.9, 0.9],
        "FlowBoundary": [0.5, 0.5],
        "Foo": [1.0, 1.0],
        "Bar": [6.0, 6.0],
    }
    _assert_tracers(tracer_flows.link(7), expected, [2.0, 2.0])
    # The total inflow of the Junction is the same water
    node_flows = tracer_flows.node(5)
    assert node_flows is not None
    _assert_tracers(node_flows[1], expected, [2.0, 2.0])
    # A UserDemand has its abstraction
    node_flows = tracer_flows.node(4, "inflow_rate")
    assert node_flows is not None
    _assert_tracers(
        node_flows[1],
        {"Tracer": [1.2, 1.2], "Other": [1.8, 1.8], "Bar": [0.0, 0.0]},
        3.0,
    )
    # A flow out of a Terminal brings no tracers
    tracers = tracer_flows.link(8)
    assert tracers is not None
    assert np.allclose(tracers["Continuity"], 0.0)


def test_tracer_flows_junction_group_without_one_basin():
    """A group with two Basins connects them to the UserDemand, mixing their water."""
    # Basin 1 --1--> Junction 3 --3--> UserDemand 4 --4--> Basin 5
    # Basin 2 --2--> Junction 3
    tracer_flows = _tracer_flows(
        {1: "Basin", 2: "Basin", 3: "Junction", 4: "UserDemand", 5: "Basin"},
        {1: (1, 3), 2: (2, 3), 3: (3, 4), 4: (4, 5)},
        {1: [6.0, 12.0], 2: [4.0, 8.0], 3: [10.0, 20.0], 4: [5.0, 10.0]},
        {1: _tracer(0.6), 2: _tracer(0.4), 5: _tracer(1.0)},
    )
    # (0.6 * 6 + 0.4 * 4) / 10 = 0.52 of the abstraction, also in the return flow
    _assert_tracers(
        tracer_flows.link(3),
        {"Tracer": [5.2, 10.4], "Other": [4.8, 9.6]},
        [10.0, 20.0],
    )
    _assert_tracers(
        tracer_flows.link(4),
        {"Tracer": [2.6, 5.2], "Other": [2.4, 4.8]},
        [5.0, 10.0],
    )


@pytest.mark.parametrize("node_id", [2, 3])
def test_tracer_flows_chained_junctions(node_id):
    """Chained Junctions without rows have the flow on their link towards the Basin."""
    # Basin 1 --1--> Junction 2 --2--> Junction 3 --3--> LinearResistance 4 --5--> Basin 6
    #                                  Junction 3 --4--> LinearResistance 5 --6--> Basin 7
    node_flows = _tracer_flows(
        {
            1: "Basin",
            2: "Junction",
            3: "Junction",
            4: "LinearResistance",
            5: "LinearResistance",
            6: "Basin",
            7: "Basin",
        },
        {1: (1, 2), 2: (2, 3), 3: (3, 4), 4: (3, 5), 5: (4, 6), 6: (5, 7)},
        {
            1: [3.0, 3.0],
            2: [3.0, 3.0],
            3: [1.0, 1.0],
            4: [2.0, 2.0],
            5: [1.0, 1.0],
            6: [2.0, 2.0],
        },
        {1: _tracer(0.1), 6: _tracer(0.5), 7: _tracer(0.5)},
    ).node(node_id)
    assert node_flows is not None
    total, tracers = node_flows
    assert np.allclose(total, [3.0, 3.0])
    _assert_tracers(tracers, {"Tracer": [0.3, 0.3], "Other": [2.7, 2.7]}, total)


# One Junction tree connects the inflows and outflows of Basin 1:
#
#   Basin 1 --1--> Junction 2 <--2-- Junction 3
#   Basin 10 --3--> LinearResistance 4 --4--> Junction 2 --5--> Pump 5 --6--> Basin 11
#   Basin 12 --7--> LinearResistance 7 --8--> Junction 3 --9--> Pump 8 --10--> Basin 13
_TREE_NODE_TYPES = {
    1: "Basin",
    2: "Junction",
    3: "Junction",
    4: "LinearResistance",
    5: "Pump",
    7: "LinearResistance",
    8: "Pump",
    10: "Basin",
    11: "Basin",
    12: "Basin",
    13: "Basin",
}
_TREE_LINKS = {
    1: (1, 2),
    2: (3, 2),
    3: (10, 4),
    4: (4, 2),
    5: (2, 5),
    6: (5, 11),
    7: (12, 7),
    8: (7, 3),
    9: (3, 8),
    10: (8, 13),
}
_TREE_CONCENTRATIONS = {
    1: _tracer(0.1),
    10: _tracer(0.2),
    11: _tracer(0.9),
    12: _tracer(0.4),
    13: _tracer(0.9),
}
# At the first time the inflows dominate, at the second the outflows, and the
# connector with an inflow to Junction 2 reverses.
_TREE_FLOWS = {
    1: [-4.0, 7.0],
    2: [1.0, -3.0],
    3: [6.0, -1.0],
    4: [6.0, -1.0],
    5: [3.0, 3.0],
    6: [3.0, 3.0],
    7: [2.0, 2.0],
    8: [2.0, 2.0],
    9: [1.0, 5.0],
    10: [1.0, 5.0],
}


@pytest.mark.parametrize(
    ("link_id", "expected"),
    [
        # An outflow is water from Basin 1, not mixed with the inflow at Junction 2.
        (5, [0.1 * 3.0, 0.1 * 3.0]),
        # Also behind the connector.
        (6, [0.1 * 3.0, 0.1 * 3.0]),
        # A connector with an inflow takes water from Basin 1 if it reverses.
        (4, [0.2 * 6.0, 0.1 * -1.0]),
        # A link points towards Basin 1 and has the net tracer flow behind it.
        (2, [0.4 * 2.0 - 0.1 * 1.0, 0.4 * 2.0 - 0.1 * 5.0]),
        # The link of Basin 1 points away from it and has all neighbors behind it.
        (
            1,
            [
                -(0.2 * 6.0 - 0.1 * 3.0 + 0.4 * 2.0 - 0.1 * 1.0),
                -(0.1 * -1.0 - 0.1 * 3.0 + 0.4 * 2.0 - 0.1 * 5.0),
            ],
        ),
    ],
)
def test_tracer_flows_junction_tree(link_id, expected):
    """A Junction group with one Basin doesn't mix its inflows with its outflows."""
    tracers = _tracer_flows(
        _TREE_NODE_TYPES, _TREE_LINKS, _TREE_FLOWS, _TREE_CONCENTRATIONS
    ).link(link_id)
    assert tracers is not None
    assert np.allclose(tracers["Tracer"], expected)
    # The tracers add up to the net flow of the link.
    assert np.allclose(tracers["Tracer"] + tracers["Other"], _TREE_FLOWS[link_id])


@pytest.mark.parametrize(
    ("variable", "expected_total", "expected_tracer"),
    [
        # Each inflow to the tree counts: from Basin 10 until LinearResistance 4
        # reverses, and from Basin 12
        ("inflow_rate", [8.0, 2.0], [0.2 * 6.0 + 0.4 * 2.0, 0.4 * 2.0]),
        # The outflows over the Pumps, and over LinearResistance 4 when it reverses,
        # are water from Basin 1
        ("outflow_rate", [4.0, 9.0], [0.1 * 4.0, 0.1 * 9.0]),
    ],
)
def test_tracer_flows_basin_inflow_outflow(variable, expected_total, expected_tracer):
    """A Basin has the inflow and outflow of the Basin results, also through a tree."""
    node_flows = _tracer_flows(
        _TREE_NODE_TYPES, _TREE_LINKS, _TREE_FLOWS, _TREE_CONCENTRATIONS
    ).node(1, variable)
    assert node_flows is not None
    total, tracers = node_flows
    assert np.allclose(total, expected_total)
    assert np.allclose(tracers["Tracer"], expected_tracer)
    assert np.allclose(tracers["Continuity"], total)


def test_tracer_flows_connector_between_junction_groups():
    """A connector takes its water from the one Basin of the group upstream of it."""
    tracers = _tracer_flows(
        {
            1: "Basin",
            2: "Junction",
            3: "Pump",
            4: "Junction",
            5: "Basin",
            6: "Basin",
            7: "LinearResistance",
            8: "Basin",
            9: "LinearResistance",
        },
        {
            1: (1, 2),
            2: (2, 3),
            3: (3, 4),
            4: (4, 5),
            5: (6, 7),
            6: (7, 2),
            7: (8, 9),
            8: (9, 4),
        },
        {3: [2.0, 2.0], 4: [4.0, 4.0], 6: [4.0, 4.0], 8: [2.0, 2.0]},
        {1: _tracer(0.1), 5: _tracer(0.9), 6: _tracer(0.7), 8: _tracer(0.5)},
    ).link(4)
    # The inflow of Basin 6 to the upstream group goes to Basin 1, not over the Pump.
    # 0.1 * 2 + 0.5 * 2 = 1.2
    assert tracers is not None
    assert np.allclose(tracers["Tracer"], [1.2, 1.2])


@pytest.mark.parametrize(
    ("junctions_in_static", "expected"),
    [
        # All water over the link to Basin 4 comes from Basin 1: 0.2 * 3
        (frozenset({3}), [0.6, 0.6]),
        # Without rows it is a Junction group with one Basin, where the UserDemand
        # abstracts from Basin 4: 0.2 * 5 - 0.8 * 2
        (frozenset(), [-0.6, -0.6]),
    ],
)
def test_tracer_flows_junction_in_static(junctions_in_static, expected):
    """A Junction in Junction / static mixes its inflows, also next to one Basin."""
    # Basin 1 --1--> Pump 2 --2--> Junction 3 --3--> Basin 4
    #                              Junction 3 --4--> UserDemand 5 --5--> Basin 4
    tracers = _tracer_flows(
        {1: "Basin", 2: "Pump", 3: "Junction", 4: "Basin", 5: "UserDemand"},
        {1: (1, 2), 2: (2, 3), 3: (3, 4), 4: (3, 5), 5: (5, 4)},
        {2: [5.0, 5.0], 3: [3.0, 3.0], 4: [2.0, 2.0]},
        {1: _tracer(0.2), 4: _tracer(0.8)},
        junctions_in_static,
    ).link(3)
    assert tracers is not None
    assert np.allclose(tracers["Tracer"], expected)


def _fractional_flow(
    monkeypatch,
    node_types: dict[int, str],
    links: dict[int, tuple[int, int]],
    flows: dict[int, list[float]],
    concentrations: dict[int, dict[str, list[float]]],
    traces: list[str],
    available: dict[str, list[str]] | None = None,
    junctions_in_static: frozenset[int] = frozenset(),
    observation: dict[str, dict[str, tuple[np.ndarray, np.ndarray]]] | None = None,
    observation_links: dict[int, tuple[int, int]] | None = None,
) -> tuple[PlotWidget, Any]:
    """Plot the fractional flow of the selected link or node on real layers.

    *traces* are the names of the flow traces of the selection, as the DatasetWidget
    names them, and *observation* the traces of a selected Observation node. Returns
    the widget and the figure, or ``None`` for a placeholder.
    """
    captured_figures = []

    def _capture_plot(fig, **kwargs):
        captured_figures.append(fig)
        return "<div></div>"

    monkeypatch.setattr("ribasim_qgis.widgets.plot_widget.po.plot", _capture_plot)

    node_layer, link_layer = _layers(node_types, links, observation_links)
    widget = PlotWidget(
        node_layer_getter=lambda: node_layer,
        link_layer_getter=lambda: link_layer,
        concentration_for_node_getter=lambda node_id: (
            {s: (_TIME, np.array(v)) for s, v in concentrations[node_id].items()}
            if node_id in concentrations
            else None
        ),
        flow_for_link_getter=lambda link_id: (
            (_TIME, np.array(flows[link_id])) if link_id in flows else None
        ),
        junctions_in_static_getter=lambda: junctions_in_static,
    )
    widget.preload_variables(
        available or {"flow": ["flow_rate"], "concentration": ["Tracer", "Other"]}
    )
    widget._fractional_flow_enabled = True
    selection = {
        name: (
            _TIME,
            np.array(flows[int(name.removeprefix("Link #"))])
            if name.startswith("Link #")
            else np.zeros(2),
        )
        for name in traces
    }
    widget.set_data(
        {"flow": {"flow_rate": selection}, "observation": observation or {}},
        units={"flow": {"flow_rate": "m3 s-1"}},
    )
    if not widget._web_view.isVisibleTo(widget):
        return widget, None
    return widget, captured_figures[-1]


def _signed_values(traces: tuple[Any, ...], name: str) -> np.ndarray:
    """Add up the positive and negative stack of a tracer."""
    return np.sum([t.y for t in traces if t.name == name], axis=0)


# Basin 5 --1--> LinearResistance 7 --2--> Basin 6
_RESISTANCE_NETWORK = (
    {5: "Basin", 6: "Basin", 7: "LinearResistance"},
    {1: (5, 7), 2: (7, 6)},
)


def test_plot_widget_fractional_flow_plots_multiplied_values(monkeypatch):
    _, fig = _fractional_flow(
        monkeypatch,
        *_RESISTANCE_NETWORK,
        {1: [10.0, 20.0], 2: [10.0, 20.0]},
        {
            5: {"LevelBoundary": [0.4, 0.5], "FlowBoundary": [0.6, 0.5]},
            6: {"LevelBoundary": [1.0, 1.0], "FlowBoundary": [0.0, 0.0]},
        },
        ["Link #1"],
        {"flow": ["flow_rate"], "concentration": ["LevelBoundary", "FlowBoundary"]},
    )
    assert fig is not None
    names = {trace.name for trace in fig.data}
    assert names == {"LevelBoundary", "FlowBoundary", "flow_rate"}
    stacked = [t for t in fig.data if t.name != "flow_rate"]
    # Positive flows don't need a stack for negative values.
    assert all(trace.stackgroup == "positive" for trace in stacked)

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


def test_plot_widget_fractional_flow_sign_flip(monkeypatch):
    """When flow_rate sign flips, the source basin should switch."""
    _, fig = _fractional_flow(
        monkeypatch,
        *_RESISTANCE_NETWORK,
        {1: [10.0, -10.0], 2: [10.0, -10.0]},
        {5: {"LevelBoundary": [0.4, 0.4]}, 6: {"LevelBoundary": [0.8, 0.8]}},
        ["Link #1"],
        {"flow": ["flow_rate"], "concentration": ["LevelBoundary"]},
    )
    assert fig is not None
    positive, negative = (t for t in fig.data if t.name == "LevelBoundary")
    # t0: 0.4 * 10 = 4.0,  t1: 0.8 * -10 = -8.0
    assert np.allclose(positive.y, np.array([4.0, 0.0]))
    assert np.allclose(negative.y, np.array([0.0, -8.0]))
    # The hover label of the first trace has the signed value of both.
    assert np.allclose(positive.customdata, np.array([4.0, -8.0]))


def test_plot_widget_fractional_flow_opposite_signs(monkeypatch):
    """Tracer flows with opposite signs are stacked on either side of zero."""
    _, fig = _fractional_flow(
        monkeypatch,
        _TREE_NODE_TYPES,
        _TREE_LINKS,
        _TREE_FLOWS,
        _TREE_CONCENTRATIONS,
        ["Link #2"],
    )
    assert fig is not None
    traces = fig.data
    # At the second time the net flow is negative, but the Tracer flow is positive.
    tracer = [t for t in traces if t.name == "Tracer"]
    assert len(tracer) == 1
    assert tracer[0].stackgroup == "positive"
    assert np.allclose(tracer[0].y, [0.7, 0.3])

    positive, negative = (t for t in traces if t.name == "Other")
    assert (positive.stackgroup, negative.stackgroup) == ("positive", "negative")
    assert np.allclose(positive.y, [0.3, 0.0])
    assert np.allclose(negative.y, [0.0, -3.3])
    assert np.allclose(positive.customdata, [0.3, -3.3])
    # Both parts look like one tracer.
    assert positive.line.color == negative.line.color
    assert positive.line.color != tracer[0].line.color
    assert positive.legendgroup == negative.legendgroup
    assert negative.showlegend is False
    assert negative.hoverinfo == "skip"


def test_plot_widget_fractional_flow_user_demand(monkeypatch):
    """A UserDemand has two flow traces and shows the tracers of its abstraction."""
    node_types, links, flows, concentrations, junctions_in_static, _ = (
        _USER_DEMAND_NETWORK
    )
    _, fig = _fractional_flow(
        monkeypatch,
        node_types,
        links,
        flows,
        concentrations,
        ["UserDemand #4 inflow_rate", "UserDemand #4 outflow_rate"],
        junctions_in_static=junctions_in_static,
    )
    assert fig is not None
    total = next(t for t in fig.data if t.line.color == "black")
    assert total.name == "inflow_rate"
    assert np.allclose(total.y, [3.0, 3.0])
    assert np.allclose(_signed_values(fig.data, "Tracer"), [1.2, 1.2])


def test_plot_widget_fractional_flow_observation(monkeypatch):
    """An Observation node splits the simulated flow of the node it observes."""
    network = (
        _TREE_NODE_TYPES | {20: "Observation"},
        _TREE_LINKS,
        _TREE_FLOWS,
        _TREE_CONCENTRATIONS,
        [],
    )
    observed = "Observation #20 observed flow_rate"
    simulated = "Observation #20 simulated flow_rate"
    observed_time = np.array(["2020-01-01T12:00:00", "2020-01-02T12:00:00"])
    _, fig = _fractional_flow(
        monkeypatch,
        *network,
        observation={
            "flow_rate": {
                observed: (observed_time, np.array([2.5, 3.5])),
                simulated: (_TIME, np.array([3.0, 3.0])),
            }
        },
        observation_links={11: (20, 5)},
    )
    assert fig is not None
    # Pump 5 takes water from Basin 1 through the Junction tree
    assert np.allclose(_signed_values(fig.data, "Tracer"), [0.3, 0.3])
    # The observed flow is black and the simulated flow red, like in the standard plot
    lines = {t.name: t for t in fig.data if t.stackgroup is None}
    assert lines.keys() == {observed, simulated}
    assert lines[observed].line.color == "black"
    assert lines[simulated].line.color == "red"
    assert list(lines[observed].x) == list(observed_time)

    # Without an observed flow there is nothing to split
    widget, fig = _fractional_flow(
        monkeypatch,
        *network,
        observation={
            "level": {"Observation #20 observed level": (_TIME, np.array([1.0, 1.1]))}
        },
        observation_links={11: (20, 1)},
    )
    assert fig is None
    assert "observes a flow_rate" in widget._placeholder.text()


@pytest.mark.parametrize(
    ("traces", "available", "placeholder"),
    [
        # Two selected links
        (
            ["Link #1", "Link #2"],
            None,
            "Fractional flow requires exactly one link or node selection",
        ),
        # A node with a flow in both directions
        (["LevelBoundary #9 outflow_rate"], None, "other than a Basin, LevelBoundary"),
        # No concentration results
        (["Link #1"], {"flow": ["flow_rate"]}, "requires concentration results"),
        # Basin 6 has no concentration
        (["Link #4"], None, "could not determine where the water"),
    ],
)
def test_plot_widget_fractional_flow_placeholder(
    monkeypatch, traces, available, placeholder
):
    node_types, links, flows, _, junctions_in_static = _INTO_NETWORK
    widget, fig = _fractional_flow(
        monkeypatch,
        node_types,
        links,
        flows,
        {},
        traces,
        available,
        junctions_in_static,
    )
    assert fig is None
    assert placeholder in widget._placeholder.text()


def _junction_flow_column(
    node_types: dict[int, str],
    links: list[tuple[int, int]],
    flows: list[float],
    junctions_in_static: frozenset[int] = frozenset(),
) -> np.ndarray | None:
    """Return the flow rate of Junction 2 for flows given at a single time."""
    node_layer = _memory_layer(
        "field=node_id:integer&field=node_type:string", list(node_types.items())
    )
    link_layer = _memory_layer(
        "field=link_id:integer&field=from_node_id:integer"
        "&field=to_node_id:integer&field=link_type:string",
        [(i, *link, "flow") for i, link in enumerate(links)],
    )
    return DatasetWidget._node_flow_column(
        link_layer,
        node_layer,
        2,
        {i: i for i in range(len(flows))},
        np.array([flows]),
        junctions_in_static,
    )


# Junction 2 with connectors 1 and 3, and Basin 4.
_ONE_BASIN = {1: "Pump", 2: "Junction", 3: "Pump", 4: "Basin"}


@pytest.mark.parametrize(
    ("node_types", "links", "flows", "expected"),
    [
        # The flow on the link to the Basin, with its sign.
        (_ONE_BASIN, [(1, 2), (3, 2), (2, 4)], [5.0, -2.0, 3.0], 3.0),
        (_ONE_BASIN, [(1, 2), (3, 2), (2, 4)], [-3.0, -2.0, -5.0], -5.0),
        # In a shared tree it is the net flow, in the direction of that link.
        (_ONE_BASIN, [(1, 2), (2, 3), (2, 4)], [6.0, 4.0, 2.0], 2.0),
        (_ONE_BASIN, [(1, 2), (2, 3), (4, 2)], [6.0, 4.0, -2.0], -2.0),
        # The link that leads to the Basin can go to another Junction.
        (
            {1: "Pump", 2: "Junction", 3: "Junction", 4: "Basin"},
            [(1, 2), (2, 3), (3, 4)],
            [6.0, 6.0, 6.0],
            6.0,
        ),
        # With two Basins it is the sum of the incoming links.
        (
            {1: "Basin", 2: "Junction", 3: "Basin", 4: "Pump"},
            [(1, 2), (3, 2), (2, 4)],
            [3.0, 2.0, 5.0],
            5.0,
        ),
    ],
)
def test_junction_flow_column(node_types, links, flows, expected):
    column = _junction_flow_column(node_types, links, flows)
    assert column is not None
    assert np.allclose(column, [expected])


@pytest.mark.parametrize(
    ("node_types", "links", "flows", "junctions_in_static", "expected"),
    [
        # A Junction in Junction / static: its total inflow, before the abstraction
        # of the UserDemand, not the flow on the link to the Basin.
        (
            {1: "Pump", 2: "Junction", 3: "UserDemand", 4: "Basin"},
            [(1, 2), (2, 3), (2, 4), (3, 4)],
            [5.0, 2.0, 3.0, 1.0],
            frozenset({2}),
            5.0,
        ),
        # A confluence in Junction / static.
        (
            {1: "Pump", 2: "Junction", 3: "Pump", 4: "Basin"},
            [(1, 2), (3, 2), (2, 4)],
            [5.0, 2.0, 7.0],
            frozenset({2}),
            7.0,
        ),
        # Junction 3 in Junction / static is not part of the group of Junction 2,
        # which has Basin 4 only: the net flow on the link to that Basin.
        (
            {
                1: "FlowBoundary",
                2: "Junction",
                3: "Junction",
                4: "Basin",
                5: "LinearResistance",
                6: "Basin",
            },
            [(1, 3), (3, 2), (3, 6), (2, 4), (2, 5)],
            [10.0, 4.0, 6.0, 3.0, 1.0],
            frozenset({3}),
            3.0,
        ),
    ],
)
def test_junction_flow_column_in_static(
    node_types, links, flows, junctions_in_static, expected
):
    column = _junction_flow_column(node_types, links, flows, junctions_in_static)
    assert column is not None
    assert np.allclose(column, [expected])


def test_user_demand_flow_traces_add_up_its_links():
    # UserDemand 3 abstracts from Basins 1 and 2, and returns to Basin 1
    _, link_layer = _layers(
        {1: "Basin", 2: "Basin", 3: "UserDemand"},
        {10: (1, 3), 20: (2, 3), 30: (3, 1)},
    )
    widget = DatasetWidget.__new__(DatasetWidget)
    widget.results = {
        "flow": NetCDFResult(
            time=pd.DatetimeIndex(["2020-01-01"]),
            ids=np.array([10, 20, 30]),
            variables={"flow_rate": np.array([[1.0, 3.0, 2.0]])},
            units={},
        )
    }
    plot_data: PlotData = {}
    widget._inject_node_flow_rate_traces(plot_data, [(3, "UserDemand")], link_layer)
    traces = plot_data["flow"]["flow_rate"]
    assert traces["UserDemand #3 inflow_rate"][1].tolist() == [4.0]
    assert traces["UserDemand #3 outflow_rate"][1].tolist() == [2.0]


def test_load_netcdf_results_forgets_removed_files(results_dir, monkeypatch):
    widget = DatasetWidget.__new__(DatasetWidget)
    widget.results = {}
    monkeypatch.setattr(widget, "_results_dir", lambda: results_dir)
    widget._load_netcdf_results()
    assert "concentration" in widget.results
    (results_dir / "concentration.nc").unlink()
    widget._load_netcdf_results()
    assert "concentration" not in widget.results


def test_read_junctions_in_static(tmp_path):
    path = tmp_path / "database.gpkg"
    assert read_junctions_in_static(path) == frozenset()

    con = sqlite3.connect(path)
    con.execute("CREATE TABLE Node (node_id INTEGER)")
    con.commit()
    assert read_junctions_in_static(path) == frozenset()

    con.execute(
        f'CREATE TABLE "{JUNCTION_STATIC_TABLE}" '
        "(fid INTEGER PRIMARY KEY, node_id INTEGER, to_node_id INTEGER, fraction REAL)"
    )
    con.executemany(
        # JUNCTION_STATIC_TABLE is a trusted module constant, not user input.
        f'INSERT INTO "{JUNCTION_STATIC_TABLE}" '  # noqa: S608
        "(node_id, to_node_id, fraction) VALUES (?, ?, ?)",
        [(22, 4, 0.75), (22, 3, None), (6, 25, 1.0)],
    )
    con.commit()
    con.close()
    assert read_junctions_in_static(path) == frozenset({6, 22})

    # Like the core, read the table from NetCDF if the TOML names a file for it
    netcdf_path = tmp_path / "junction-static.nc"
    with nc4.Dataset(netcdf_path, "w") as ds:
        ds.createDimension("node_id", 2)
        ds.createVariable("node_id", "i4", ("node_id",))[:] = [2, 2]
        ds.createVariable("to_node_id", "i4", ("node_id",))[:] = [4, 5]
    assert read_junctions_in_static(path, netcdf_path) == frozenset({2})


def test_read_input_concentrations(tmp_path):
    path = tmp_path / "database.gpkg"
    con = sqlite3.connect(path)
    con.execute("CREATE TABLE Node (node_id INTEGER, node_type TEXT, cyclic_time BOOL)")
    con.executemany(
        "INSERT INTO Node VALUES (?, ?, ?)",
        [
            (1, "FlowBoundary", False),
            (2, "LevelBoundary", True),
            (3, "UserDemand", True),
        ],
    )
    rows = {
        "FlowBoundary / concentration": [
            (1, "2020-01-04 00:00:00", "Foo", 3.0),
            (1, "2020-01-02 00:00:00", "Foo", 2.0),
            (1, "2020-01-02 00:00:00", "Bar", None),
        ],
        "LevelBoundary / concentration": [
            (2, "2020-01-01 00:00:00", "Foo", 1.0),
            (2, "2020-01-02 00:00:00", "Foo", 5.0),
            (2, "2020-01-03 00:00:00", "Foo", 1.0),
        ],
        "UserDemand / concentration": [
            (3, "2020-01-01 00:00:00", "Bar", 1.0),
            (3, "2020-01-02 00:00:00", "Bar", 4.0),
            (3, "2020-01-03 00:00:00", "Bar", 1.0),
        ],
    }
    for table, table_rows in rows.items():
        con.execute(
            f'CREATE TABLE "{table}" (fid INTEGER PRIMARY KEY, node_id INTEGER, '
            "time DATETIME, substance TEXT, concentration REAL)"
        )
        con.executemany(
            # The table names are constants in this test, not user input.
            f'INSERT INTO "{table}" (node_id, time, substance, concentration) '  # noqa: S608
            "VALUES (?, ?, ?, ?)",
            table_rows,
        )
    con.commit()
    con.close()

    concentrations = read_input_concentrations(path)
    times = np.array(
        ["2020-01-01", "2020-01-02", "2020-01-03", "2020-01-04", "2020-01-05"],
        dtype="datetime64[ns]",
    )
    end = np.datetime64("2020-01-06", "ns")
    # Block interpolation, with the first and last value outside the series
    flow_boundary = concentrations.mean(1, times, end)
    assert flow_boundary is not None
    assert flow_boundary.keys() == {"Foo"}
    assert np.allclose(flow_boundary["Foo"], [2.0, 2.0, 2.0, 3.0, 3.0])
    # A cyclic series repeats
    level_boundary = concentrations.mean(2, times, end)
    assert level_boundary is not None
    assert np.allclose(level_boundary["Foo"], [1.0, 5.0, 1.0, 5.0, 1.0])
    user_demand = concentrations.mean(3, times, end)
    assert user_demand is not None
    assert np.allclose(user_demand["Bar"], [1.0, 4.0, 1.0, 4.0, 1.0])
    assert concentrations.mean(4, times, end) is None
    # The mean over intervals in which the concentration changes
    times = times[[0, 2]]
    flow_boundary = concentrations.mean(1, times, end)
    assert flow_boundary is not None
    assert np.allclose(flow_boundary["Foo"], [2.0, 8.0 / 3.0])
    level_boundary = concentrations.mean(2, times, end)
    assert level_boundary is not None
    assert np.allclose(level_boundary["Foo"], [3.0, 7.0 / 3.0])
    assert read_input_concentrations(tmp_path / "missing.gpkg") == (
        InputConcentrations()
    )


def test_plot_widget_observation_grouped_with_results():
    """A single root checkbox toggles both result and observation variables."""
    widget = PlotWidget()
    available = {
        "basin": ["level"],
        "observation": ["level"],
    }
    units = {
        "basin": {"level": "m"},
        "observation": {"level": "m"},
    }
    widget.preload_variables(available, units=units, defaults={"basin": ["level"]})

    # The 'level' root checkbox toggles both basin and observation level.
    assert set(widget._var_menu.checked_keys()) == {
        ("basin", "level"),
        ("observation", "level"),
    }

    # No observation submenu: its 'level' is a grouped constituent.
    submenu_titles = {
        action.menu().title() for action in widget._var_menu.actions() if action.menu()
    }
    assert "observation" not in submenu_titles


def test_plot_widget_renders_observed_and_simulated_observation_traces(monkeypatch):
    """Observed and simulated observation traces render on a shared unit subplot."""
    captured_figures = []

    def _capture_plot(fig, **kwargs):
        captured_figures.append(fig)
        return "<div></div>"

    monkeypatch.setattr("ribasim_qgis.widgets.plot_widget.po.plot", _capture_plot)

    widget = PlotWidget()
    widget.preload_variables(
        {"observation": ["level"]},
        units={"observation": {"level": "m"}},
        defaults={"observation": ["level"]},
    )
    widget._var_menu.populate(
        widget._available,
        {("observation", "level")},
        widget._defaults,
        widget._water_balance_enabled,
    )

    time = np.array(["2020-01-01", "2020-01-02"])
    widget.set_data(
        {
            "observation": {
                "level": {
                    "Observation #4 observed level": (time, np.array([0.5, 0.3])),
                    "Observation #4 simulated level": (time, np.array([0.4, 0.35])),
                }
            }
        },
        units={"observation": {"level": "m"}},
    )

    assert len(captured_figures) == 1
    fig = captured_figures[0]
    names = {trace.name for trace in fig.data}
    assert names == {
        "Observation #4 observed level",
        "Observation #4 simulated level",
    }
    # Both share the same unit subplot.
    assert fig.layout.yaxis.title.text == "m"


def test_plot_widget_observation_trace_colors(monkeypatch):
    """Observed traces render black, simulated traces render red."""
    captured_figures = []

    def _capture_plot(fig, **kwargs):
        captured_figures.append(fig)
        return "<div></div>"

    monkeypatch.setattr("ribasim_qgis.widgets.plot_widget.po.plot", _capture_plot)

    widget = PlotWidget()
    widget.preload_variables(
        {"observation": ["level"]},
        units={"observation": {"level": "m"}},
        defaults={"observation": ["level"]},
    )
    widget._var_menu.populate(
        widget._available,
        {("observation", "level")},
        widget._defaults,
        widget._water_balance_enabled,
    )

    time = np.array(["2020-01-01", "2020-01-02"])
    widget.set_data(
        {
            "observation": {
                "level": {
                    "Observation #4 observed level": (time, np.array([0.5, 0.3])),
                    "Observation #4 simulated level": (time, np.array([0.4, 0.35])),
                }
            }
        },
        units={"observation": {"level": "m"}},
    )

    assert len(captured_figures) == 1
    colors = {trace.name: trace.line.color for trace in captured_figures[0].data}
    assert colors["Observation #4 observed level"] == "black"
    assert colors["Observation #4 simulated level"] == "red"


def test_plot_widget_observation_only_flow_rate_checked_by_default(monkeypatch):
    """Without results, a non-first observation group still renders by default.

    The flow_rate root group is only reachable here via its observation
    constituent. It must be default-checked, not just the first ('level') group.
    """
    captured_figures = []

    def _capture_plot(fig, **kwargs):
        captured_figures.append(fig)
        return "<div></div>"

    monkeypatch.setattr("ribasim_qgis.widgets.plot_widget.po.plot", _capture_plot)

    widget = PlotWidget()
    # Mirror DatasetWidget: observation variables are passed as defaults so each
    # available observation root group is checked, even without results.
    widget.preload_variables(
        {"observation": ["flow_rate", "level"]},
        units={"observation": {}},
        defaults={"observation": ["flow_rate", "level"]},
    )

    time = np.array(["2020-01-01", "2020-01-02"])
    widget.set_data(
        {
            "observation": {
                "level": {
                    "Observation #4 observed level": (time, np.array([0.5, 0.3])),
                },
                "flow_rate": {
                    "Observation #5 observed flow_rate": (time, np.array([0.0, 0.05])),
                },
            }
        },
        units={"observation": {}},
    )

    assert captured_figures
    names = {trace.name for trace in captured_figures[-1].data}
    assert "Observation #5 observed flow_rate" in names
    assert "Observation #4 observed level" in names


def test_plot_widget_defaults_x_axis_to_simulated_period(monkeypatch):
    """Plots open on the simulated period, not the full (longer) data span."""
    captured_figures = []

    def _capture_plot(fig, **kwargs):
        captured_figures.append(fig)
        return "<div></div>"

    monkeypatch.setattr("ribasim_qgis.widgets.plot_widget.po.plot", _capture_plot)

    widget = PlotWidget()
    widget.preload_variables(
        {"observation": ["level"]},
        units={"observation": {"level": "m"}},
        defaults={"observation": ["level"]},
    )
    widget._var_menu.populate(
        widget._available,
        {("observation", "level")},
        widget._defaults,
        widget._water_balance_enabled,
    )
    widget.set_simulated_period("2020-01-01T00:00:00", "2020-12-31T00:00:00")

    # Observed series runs well past the simulated end.
    time = np.array(["2020-06-01T00:00:00", "2021-06-01T00:00:00"])
    widget.set_data(
        {
            "observation": {
                "level": {
                    "Observation #4 observed level": (time, np.array([0.5, 0.3])),
                }
            }
        },
        units={"observation": {"level": "m"}},
    )

    assert len(captured_figures) == 1
    fig = captured_figures[0]
    assert tuple(fig.layout.xaxis.range) == (
        "2020-01-01T00:00:00",
        "2020-12-31T00:00:00",
    )


def test_plot_widget_simulated_period_can_be_cleared(monkeypatch):
    """Clearing the simulated period restores auto-ranging (no explicit range)."""
    captured_figures = []

    def _capture_plot(fig, **kwargs):
        captured_figures.append(fig)
        return "<div></div>"

    monkeypatch.setattr("ribasim_qgis.widgets.plot_widget.po.plot", _capture_plot)

    widget = PlotWidget()
    widget.preload_variables(
        {"basin": ["level"]},
        units={"basin": {"level": "m"}},
        defaults={"basin": ["level"]},
    )
    widget.set_simulated_period("2020-01-01T00:00:00", "2020-12-31T00:00:00")
    widget.set_simulated_period(None, None)

    time = np.array(["2020-06-01T00:00:00", "2020-07-01T00:00:00"])
    widget.set_data(
        {"basin": {"level": {"Basin #1": (time, np.array([0.5, 0.3]))}}},
        units={"basin": {"level": "m"}},
    )

    assert len(captured_figures) == 1
    assert captured_figures[0].layout.xaxis.range is None
