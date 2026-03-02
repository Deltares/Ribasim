"""Plot widget using plotly to render Ribasim timeseries from NetCDF results."""

from collections import defaultdict
from pathlib import Path

import numpy as np
import plotly.graph_objs as go
import plotly.offline as po
from plotly.subplots import make_subplots
from qgis.PyQt.QtCore import Qt, QUrl
from qgis.PyQt.QtWebKit import QWebSettings
from qgis.PyQt.QtWebKitWidgets import QWebView
from qgis.PyQt.QtWidgets import (
    QCheckBox,
    QHBoxLayout,
    QLabel,
    QMenu,
    QToolButton,
    QVBoxLayout,
    QWidget,
    QWidgetAction,
)

# Bundled plotly.js 2.30.0 — compatible with QWebView (QtWebKit) in QGIS.
# Many plotly.js 2.x versions don't work well with QtWebKit; 2.30.0 is known
# to work (same version that plotly Python 5.20 shipped).
# Once QGIS bundles QtWebEngine by default (https://github.com/qgis/QGIS/issues/54965)
# we can switch from QWebView to QWebEngineView (Chromium-based) and use the
# QGIS-bundled plotly.js without these workarounds.
_PLOTLY_JS_DIR = Path(__file__).resolve().parent
_PLOTLY_JS_URL = QUrl.fromLocalFile(
    str(_PLOTLY_JS_DIR / "plotly-2.30.0.min.js")
).toString()
_PLOTLY_BASE_URL = QUrl.fromLocalFile(str(_PLOTLY_JS_DIR) + "/")

# A single trace: (time values, data values).
Trace = tuple[np.ndarray, np.ndarray]
# All traces for one variable, keyed by trace label (e.g. "#42").
VariableTraces = dict[str, Trace]
# Full plot payload: file -> variable -> traces.
PlotData = dict[str, dict[str, VariableTraces]]

_PLACEHOLDER_DEFAULT = "Select Basin nodes and/or links on the map to plot timeseries."


class _VariablesMenu(QMenu):
    """Dropdown menu with checkboxes for multi-variable selection."""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setContentsMargins(10, 5, 5, 5)
        self._checkboxes: list[QCheckBox] = []
        self._variables: list[str] = []

    def populate(
        self, variables: list[str], previously_checked: set[str], default: str = ""
    ) -> None:
        self._checkboxes = []
        self._variables = []
        self.clear()
        for variable in variables:
            cb = QCheckBox(variable)
            if variable in previously_checked:
                cb.setChecked(True)
            self._checkboxes.append(cb)
            self._variables.append(variable)
            action = QWidgetAction(self)
            action.setDefaultWidget(cb)
            self.addAction(action)
        # If nothing ended up checked, check the default or the first
        if not any(cb.isChecked() for cb in self._checkboxes) and self._checkboxes:
            for i, v in enumerate(self._variables):
                if v == default:
                    self._checkboxes[i].setChecked(True)
                    return
            self._checkboxes[0].setChecked(True)

    def checked_variables(self) -> list[str]:
        return [
            v
            for v, cb in zip(self._variables, self._checkboxes, strict=True)
            if cb.isChecked()
        ]


class PlotWidget(QWidget):
    """Widget with variable selector and a plotly timeseries plot."""

    def __init__(self, parent: QWidget | None = None):
        super().__init__(parent)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(2)

        # --- Selectors: single horizontal row ---
        row = QHBoxLayout()
        row.setContentsMargins(4, 4, 4, 0)
        row.setSpacing(4)

        self._var_button = QToolButton()
        self._var_button.setToolButtonStyle(Qt.ToolButtonTextBesideIcon)
        self._var_button.setPopupMode(QToolButton.InstantPopup)
        self._var_menu = _VariablesMenu(self._var_button)
        self._var_menu.aboutToHide.connect(self._on_menu_closed)
        self._var_button.setMenu(self._var_menu)
        self._var_button.setText("Variable: ")
        row.addWidget(self._var_button)

        row.addStretch()
        layout.addLayout(row)

        # --- Placeholder label ---
        self._placeholder = QLabel(_PLACEHOLDER_DEFAULT)
        self._placeholder.setAlignment(Qt.AlignCenter)
        self._placeholder.setStyleSheet("color: gray; font-style: italic;")
        layout.addWidget(self._placeholder)

        # --- Web view ---
        self._web_view = QWebView()
        self._web_view.setVisible(False)
        self._web_view.setContextMenuPolicy(Qt.NoContextMenu)
        ws = self._web_view.settings()
        ws.setAttribute(QWebSettings.WebGLEnabled, True)
        ws.setAttribute(QWebSettings.Accelerated2dCanvasEnabled, True)

        layout.addWidget(self._web_view)

        # Data: {file_name: {variable: {trace_name: (x, y)}}}
        self._plot_data: PlotData = {}
        # Units: {file_name: {variable: unit_string}}
        self._units: dict[str, dict[str, str]] = {}
        # Available variables per file: {file_name: [var1, var2, ...]}
        self._available: dict[str, list[str]] = {}
        # Default variable per file: {file_name: variable}
        self._defaults: dict[str, str] = {}
        # Variable menu mapping: "file / variable" -> (file, variable)
        self._menu_to_key: dict[str, tuple[str, str]] = {}

    # --- Public API ---

    def preload_variables(
        self,
        available: dict[str, list[str]],
        units: dict[str, dict[str, str]] | None = None,
        defaults: dict[str, str] | None = None,
    ) -> None:
        """Pre-populate variable dropdown without trace data.

        Parameters
        ----------
        available:
            file_name -> list of variable names.
        units:
            file_name -> variable -> unit string.
        defaults:
            file_name -> default variable to check.
        """
        self._available = available
        self._units = units or {}
        self._defaults = defaults or {}
        previously_checked_labels = set(self._var_menu.checked_variables())
        previously_checked_keys = {
            self._menu_to_key[label]
            for label in previously_checked_labels
            if label in self._menu_to_key
        }

        menu_labels: list[str] = []
        menu_to_key: dict[str, tuple[str, str]] = {}
        for file_name, file_variables in self._available.items():
            for variable in sorted(file_variables):
                label = f"{file_name} / {variable}"
                menu_labels.append(label)
                menu_to_key[label] = (file_name, variable)

        self._menu_to_key = menu_to_key

        checked_labels = {
            label
            for label, key in self._menu_to_key.items()
            if key in previously_checked_keys
        }

        # When nothing was previously checked, check all default variables
        if not checked_labels:
            checked_labels = {
                f"{file_name} / {variable}"
                for file_name, variable in self._defaults.items()
                if f"{file_name} / {variable}" in self._menu_to_key
            }

        self._var_menu.populate(sorted(menu_labels), checked_labels)
        self._update_button_text()
        self._placeholder.setText(_PLACEHOLDER_DEFAULT)
        self._redraw()

    def set_data(
        self,
        plot_data: PlotData,
        units: dict[str, dict[str, str]] | None = None,
    ) -> None:
        """Set plot data grouped by result file.

        Parameters
        ----------
        plot_data:
            file_name -> variable -> trace_name -> (x_values, y_values).
            Both arrays are numpy arrays; plotly accepts them directly.
        units:
            file_name -> variable -> unit string (e.g. 'm3 s-1').
        """
        self._plot_data = plot_data
        if units:
            self._units = units
        self._redraw()

    def clear(self) -> None:
        self._plot_data = {}
        self._web_view.setVisible(False)
        self._web_view.setUrl(QUrl("about:blank"))
        self._placeholder.setVisible(True)

    # --- Internal slots ---

    def _on_menu_closed(self) -> None:
        """Update button text and plot when the variable menu closes."""
        self._update_button_text()
        self._redraw()

    def _update_button_text(self) -> None:
        checked = self._var_menu.checked_variables()
        if not checked:
            self._var_button.setText("Variable: ")
        elif len(checked) == 1:
            self._var_button.setText(f"Variable: {checked[0]}")
        else:
            self._var_button.setText(f"Variable: ({len(checked)} selected)")

    def _selected_keys(self) -> list[tuple[str, str]]:
        return [
            self._menu_to_key[label]
            for label in self._var_menu.checked_variables()
            if label in self._menu_to_key
        ]

    def _redraw(self) -> None:
        selected_keys = self._selected_keys()

        if not selected_keys or not self._plot_data:
            self._web_view.setVisible(False)
            self._placeholder.setVisible(True)
            return

        traces_by_unit: dict[str, list[go.Scatter]] = defaultdict(list)
        for file_name, var in selected_keys:
            file_data = self._plot_data.get(file_name, {})
            file_units = self._units.get(file_name, {})
            var_traces = file_data.get(var, {})
            if not var_traces:
                continue
            unit = file_units.get(var, "")
            unit_key = unit or "(no unit)"
            for trace_name, (x, y) in var_traces.items():
                legend_name = f"{file_name} / {var} {trace_name}"
                traces_by_unit[unit_key].append(
                    go.Scatter(x=x, y=y, mode="lines", name=legend_name)
                )

        if not traces_by_unit:
            self._web_view.setVisible(False)
            self._placeholder.setVisible(True)
            return

        config = {
            "scrollZoom": True,
            "editable": False,
            "displayModeBar": True,
            "responsive": True,
            # toImage uses an <a download> click that QtWebKit silently ignores.
            "modeBarButtonsToRemove": ["toImage"],
        }

        units = sorted(traces_by_unit)
        fig = make_subplots(
            rows=len(units),
            cols=1,
            shared_xaxes=True,
            vertical_spacing=0.04,
        )

        for row, unit in enumerate(units, start=1):
            for trace in traces_by_unit[unit]:
                fig.add_trace(trace, row=row, col=1)
            fig.update_yaxes(title_text=unit, row=row, col=1)
            fig.update_xaxes(showticklabels=row == len(units), row=row, col=1)

        fig.update_layout(
            showlegend=True,
            legend={"x": 1.01, "y": 0.01, "xanchor": "left", "yanchor": "bottom"},
            margin={"l": 40, "r": 190, "t": 10, "b": 20, "pad": 0},
        )

        div = po.plot(
            fig,
            output_type="div",
            include_plotlyjs=False,
            config=config,
        )
        html = (
            '<html><head><meta charset="utf-8" />'
            f'<script src="{_PLOTLY_JS_URL}"></script></head>'
            f'<body style="margin:0;overflow:hidden">{div}</body></html>'
        )
        self._placeholder.setVisible(False)
        self._web_view.setVisible(True)
        self._web_view.setHtml(html, _PLOTLY_BASE_URL)
