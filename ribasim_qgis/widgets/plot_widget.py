"""Plot widget using plotly to render Ribasim timeseries from NetCDF results."""

import importlib.resources

import numpy as np
import plotly.graph_objs as go
import plotly.offline as po
from qgis.PyQt.QtCore import Qt, QUrl
from qgis.PyQt.QtWebKit import QWebSettings
from qgis.PyQt.QtWebKitWidgets import QWebView
from qgis.PyQt.QtWidgets import (
    QCheckBox,
    QComboBox,
    QHBoxLayout,
    QLabel,
    QMenu,
    QToolButton,
    QVBoxLayout,
    QWidget,
    QWidgetAction,
)

# Resolve the bundled plotly.min.js via importlib.resources.
_PLOTLY_JS_URL = QUrl.fromLocalFile(
    str(importlib.resources.files("plotly").joinpath("package_data", "plotly.min.js"))
).toString()

# A single trace: (time values, data values).
Trace = tuple[np.ndarray, np.ndarray]
# All traces for one variable, keyed by trace label (e.g. "#42").
VariableTraces = dict[str, Trace]
# Full plot payload: file -> variable -> traces.
PlotData = dict[str, dict[str, VariableTraces]]


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
    """Widget with file/variable selectors and a plotly timeseries plot."""

    def __init__(self, parent: QWidget | None = None):
        super().__init__(parent)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(2)

        # --- Selectors: single horizontal row ---
        row = QHBoxLayout()
        row.setContentsMargins(4, 4, 4, 0)
        row.setSpacing(4)

        row.addWidget(QLabel("Result:"))
        self._file_combo = QComboBox()
        self._file_combo.setMinimumWidth(120)
        self._file_combo.currentTextChanged.connect(self._on_file_changed)
        row.addWidget(self._file_combo)

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
        self._placeholder = QLabel(
            "Select nodes or links on the map to plot timeseries."
        )
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

    # --- Public API ---

    def preload_variables(
        self,
        available: dict[str, list[str]],
        units: dict[str, dict[str, str]] | None = None,
        defaults: dict[str, str] | None = None,
    ) -> None:
        """Pre-populate file and variable dropdowns without trace data.

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
        self._update_file_combo(sorted(available.keys()))

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
        self._units = units or {}
        self._update_file_combo(sorted(plot_data.keys()))

    def clear(self) -> None:
        self._plot_data = {}
        self._units = {}
        self._file_combo.clear()
        self._var_menu.clear()
        self._var_button.setText("Variable: ")
        self._web_view.setVisible(False)
        self._web_view.setUrl(QUrl("about:blank"))
        self._placeholder.setVisible(True)

    # --- Internal slots ---

    def _update_file_combo(self, file_names: list[str]) -> None:
        """Replace file combo items, preserving the current selection if possible."""
        current = self._file_combo.currentText()
        self._file_combo.blockSignals(True)
        self._file_combo.clear()
        self._file_combo.addItems(file_names)
        idx = self._file_combo.findText(current)
        if idx >= 0:
            self._file_combo.setCurrentIndex(idx)
        else:
            # Default to "flow" when there is no previous selection
            didx = self._file_combo.findText("flow")
            if didx >= 0:
                self._file_combo.setCurrentIndex(didx)
        self._file_combo.blockSignals(False)
        self._on_file_changed(self._file_combo.currentText())

    def _on_file_changed(self, file_name: str) -> None:
        # Use plot_data keys if available, otherwise fall back to preloaded available
        variables = list(self._plot_data.get(file_name, {}).keys())
        if not variables:
            variables = self._available.get(file_name, [])
        previously_checked = set(self._var_menu.checked_variables())
        default = self._defaults.get(file_name, "")
        self._var_menu.populate(sorted(variables), previously_checked, default)
        self._update_button_text()
        self._redraw()

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

    def _redraw(self) -> None:
        file_name = self._file_combo.currentText()
        file_data = self._plot_data.get(file_name, {})
        selected = self._var_menu.checked_variables()

        if not selected or not file_data:
            self._web_view.setVisible(False)
            self._placeholder.setVisible(True)
            return

        traces = []
        for var in selected:
            var_traces = file_data.get(var, {})
            for trace_name, (x, y) in var_traces.items():
                legend_name = (
                    f"{var} — {trace_name}" if len(selected) > 1 else trace_name
                )
                traces.append(go.Scatter(x=x, y=y, mode="lines", name=legend_name))

        if not traces:
            self._web_view.setVisible(False)
            self._placeholder.setVisible(True)
            return

        # Build y-axis title with units
        if len(selected) == 1:
            var_name = selected[0]
            file_units = self._units.get(file_name, {})
            unit = file_units.get(var_name, "")
            y_title = f"{var_name} [{unit}]" if unit else var_name
        else:
            y_title = ""
        fig_layout = go.Layout(
            xaxis={"title": None},
            yaxis={"title": y_title},
            legend={"x": 1, "y": 0, "xanchor": "right", "yanchor": "bottom"},
            margin={"l": 40, "r": 10, "t": 10, "b": 10, "pad": 0},
        )
        fig = go.Figure(data=traces, layout=fig_layout)

        config = {
            "scrollZoom": True,
            "editable": False,
            "displayModeBar": True,
            # toImage uses an <a download> click that QtWebKit silently ignores.
            "modeBarButtonsToRemove": ["toImage"],
        }
        div = po.plot(
            fig,
            output_type="div",
            include_plotlyjs=False,
            config=config,
        )
        html = (
            '<html><head><meta charset="utf-8" />'
            f'<script src="{_PLOTLY_JS_URL}"></script></head>'
            f'<body style="margin:0">{div}</body></html>'
        )
        self._placeholder.setVisible(False)
        self._web_view.setVisible(True)
        self._web_view.setHtml(html)
