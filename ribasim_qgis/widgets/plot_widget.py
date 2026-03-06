"""Plot widget using plotly to render Ribasim timeseries from NetCDF results."""

import importlib.resources
from collections import defaultdict
from collections.abc import Callable
from enum import Enum, auto
from pathlib import Path
from typing import Any

import numpy as np
from qgis.PyQt.QtCore import Qt, pyqtSignal
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

try:
    import plotly.graph_objs as go
    import plotly.offline as po
    from plotly.subplots import make_subplots

    HAS_PLOTLY = True
except (ImportError, ModuleNotFoundError):
    HAS_PLOTLY = False

# ---------------------------------------------------------------------------
# Web-view backend detection
# ---------------------------------------------------------------------------
# Preferred: QtWebEngine (Chromium-based, available in QGIS 4 / Qt6).
# Uses the latest plotly.min.js bundled with the plotly Python package —
# no version workarounds needed.
#
# Fallback: QtWebKit (QGIS 3 / Qt5).  Uses a vendored plotly-2.4.2.min.js
# because many later plotly.js 2.x versions break in QtWebKit.  We also
# call .tolist() on numpy arrays since plotly.js <2.28 cannot decode bdata.
#
# The HTML is always written to a temp file and loaded via setUrl() to
# side-step QtWebKit's ~2 MB setHtml() limit (plotly.js alone is ~3.5 MB)
# and intermittent baseUrl failures.
# ---------------------------------------------------------------------------


class _WebViewBackend(Enum):
    """Available web-view backends for the plot widget."""

    WEBENGINE = auto()  # QtWebEngine (Chromium) — QGIS 4 / Qt6
    WEBKIT = auto()  # QtWebKit — QGIS 3 / Qt5
    NONE = auto()  # No web view found


def _detect_backend() -> _WebViewBackend:
    """Probe for an available web-view backend at import time."""
    try:
        from qgis.PyQt.QtWebEngineWidgets import QWebEngineView  # noqa: F401

        return _WebViewBackend.WEBENGINE
    except (ImportError, ModuleNotFoundError):
        pass
    try:
        from qgis.PyQt.QtWebKit import QWebSettings  # noqa: F401
        from qgis.PyQt.QtWebKitWidgets import QWebView  # noqa: F401

        return _WebViewBackend.WEBKIT
    except (ImportError, ModuleNotFoundError):
        pass
    return _WebViewBackend.NONE


_BACKEND: _WebViewBackend = _detect_backend()


def _log_backend() -> None:
    """Log the detected web-view backend to the QGIS message log."""
    from qgis.core import Qgis, QgsMessageLog

    QgsMessageLog.logMessage(
        f"Ribasim plot widget backend: {_BACKEND.name}",
        tag="Ribasim",
        level=Qgis.MessageLevel.Info,
    )


_log_backend()

# QUrl is needed by both backends; import it once the backend is known.
if _BACKEND is not _WebViewBackend.NONE:
    from qgis.PyQt.QtCore import QUrl

# Import the backend-specific widget classes at module scope so PlotWidget
# can reference them by name.
if _BACKEND is _WebViewBackend.WEBENGINE:
    from qgis.PyQt.QtWebEngineWidgets import QWebEngineView
elif _BACKEND is _WebViewBackend.WEBKIT:
    from qgis.PyQt.QtWebKit import QWebSettings
    from qgis.PyQt.QtWebKitWidgets import QWebView

# Resolve the plotly.js script path for the active backend.
if _BACKEND is _WebViewBackend.WEBENGINE:
    # Use the latest plotly.min.js shipped with the plotly Python package.
    _PLOTLY_JS_URL = QUrl.fromLocalFile(
        str(
            importlib.resources.files("plotly").joinpath(
                "package_data", "plotly.min.js"
            )
        )
    )
    _PLOT_HTML_FILE = Path(__file__).resolve().parent / "_plot.html"
elif _BACKEND is _WebViewBackend.WEBKIT:
    # Vendored plotly.js 2.4.2 — the latest confirmed to work in QtWebKit.
    _PLOTLY_JS_DIR = Path(__file__).resolve().parent
    _PLOTLY_JS_FILE = "plotly-2.4.2.min.js"
    _PLOT_HTML_FILE = _PLOTLY_JS_DIR / "_plot.html"

# A single trace: (time values, data values).
Trace = tuple[np.ndarray, np.ndarray]
# All traces for one variable, keyed by trace label (e.g. "#42").
VariableTraces = dict[str, Trace]
# Full plot payload: file -> variable -> traces.
PlotData = dict[str, dict[str, VariableTraces]]

_PLACEHOLDER_DEFAULT = "Select Basin nodes and/or links on the map to plot timeseries."
_PLACEHOLDER_WATER_BALANCE = (
    "Basin water balance requires exactly one Basin node selection."
)
_PLACEHOLDER_FRACTIONAL_STORAGE = (
    "Fractional storage requires exactly one Basin node selection."
)
_PLACEHOLDER_FRACTIONAL_FLOW = "Fractional flow requires exactly one link selection."
_PLACEHOLDER_FRACTIONAL_FLOW_JUNCTION = (
    "Fractional flow over Junction nodes is not yet implemented."
)
_PLACEHOLDER_FRACTIONAL_FLOW_NO_BASIN = (
    "Fractional flow: could not find a Basin on either side of the selected link."
)
_PLACEHOLDER_FRACTIONAL_FLOW_NO_CONCENTRATION = (
    "Fractional flow: no concentration data found for the resolved Basin side(s)."
)

_TRAVERSABLE_NODE_TYPES: frozenset[str] = frozenset(
    {
        "TabulatedRatingCurve",
        "Outlet",
        "Pump",
        "LinearResistance",
        "ManningResistance",
        "UserDemand",
    }
)

_DEFAULT_TRACERS: tuple[str, ...] = (
    "LevelBoundary",
    "FlowBoundary",
    "UserDemand",
    "Drainage",
    "Precipitation",
    "SurfaceRunoff",
    "Initial",
)

_BASIN_WATER_BALANCE_TERMS: tuple[tuple[str, int], ...] = (
    ("storage_rate", -1),
    ("inflow_rate", 1),
    ("outflow_rate", -1),
    ("precipitation", 1),
    ("evaporation", -1),
    ("drainage", 1),
    ("infiltration", -1),
    ("surface_runoff", 1),
    ("balance_error", 1),
)

_ROOT_VARIABLES: tuple[str, ...] = (
    "basin / level",
    "basin / storage",
    "flow / flow_rate",
)

_PLOT_LAYOUT = {
    "showlegend": True,
    "legend": {"x": 1.01, "y": 0.01, "xanchor": "left", "yanchor": "bottom"},
    "margin": {"l": 40, "r": 190, "t": 10, "b": 20, "pad": 0},
}


class _PlotMenu(QMenu):
    """Combined menu for plot preset and variable selections."""

    waterBalanceChanged = pyqtSignal(bool)
    fractionalStorageChanged = pyqtSignal(bool)
    fractionalFlowChanged = pyqtSignal(bool)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setContentsMargins(10, 5, 5, 5)
        self._checkboxes: list[QCheckBox] = []
        self._variables: list[str] = []

    def populate(
        self,
        available: dict[str, list[str]],
        previously_checked: set[str],
        defaults: dict[str, str] | None = None,
        water_balance_enabled: bool = False,
        fractional_storage_enabled: bool = False,
        fractional_flow_enabled: bool = False,
    ) -> None:
        self.clear()
        self._checkboxes = []
        self._variables = []

        wb_cb = QCheckBox("water balance")
        wb_cb.setChecked(water_balance_enabled)
        wb_cb.stateChanged.connect(
            lambda state: self.waterBalanceChanged.emit(
                state == int(Qt.CheckState.Checked)
            )
        )
        wb_action = QWidgetAction(self)
        wb_action.setDefaultWidget(wb_cb)
        self.addAction(wb_action)

        fs_cb = QCheckBox("fractional storage")
        fs_cb.setChecked(fractional_storage_enabled)
        fs_cb.stateChanged.connect(
            lambda state: self.fractionalStorageChanged.emit(
                state == int(Qt.CheckState.Checked)
            )
        )
        fs_action = QWidgetAction(self)
        fs_action.setDefaultWidget(fs_cb)
        self.addAction(fs_action)

        ff_cb = QCheckBox("fractional flow")
        ff_cb.setChecked(fractional_flow_enabled)
        ff_cb.stateChanged.connect(
            lambda state: self.fractionalFlowChanged.emit(
                state == int(Qt.CheckState.Checked)
            )
        )
        ff_action = QWidgetAction(self)
        ff_action.setDefaultWidget(ff_cb)
        self.addAction(ff_action)

        self.addSeparator()

        defaults = defaults or {}
        root_variables: set[str] = set()
        for label in _ROOT_VARIABLES:
            file_name, variable = label.split(" / ", 1)
            if file_name in available and variable in available[file_name]:
                root_variables.add(label)
        for label in sorted(root_variables):
            _, variable = label.split(" / ", 1)
            cb = QCheckBox(variable)
            if label in previously_checked:
                cb.setChecked(True)
            self._checkboxes.append(cb)
            self._variables.append(label)
            action = QWidgetAction(self)
            action.setDefaultWidget(cb)
            self.addAction(action)

        if root_variables:
            self.addSeparator()

        for file_name in sorted(available):
            variables_for_submenu = [
                variable
                for variable in sorted(available[file_name])
                if f"{file_name} / {variable}" not in root_variables
            ]
            if not variables_for_submenu:
                continue
            submenu = self.addMenu(file_name)
            for variable in variables_for_submenu:
                label = f"{file_name} / {variable}"
                cb = QCheckBox(variable)
                if label in previously_checked:
                    cb.setChecked(True)
                self._checkboxes.append(cb)
                self._variables.append(label)
                action = QWidgetAction(submenu)
                action.setDefaultWidget(cb)
                submenu.addAction(action)

        if not any(cb.isChecked() for cb in self._checkboxes) and self._checkboxes:
            default_labels = {
                f"{file_name} / {default_var}"
                for file_name, default_var in defaults.items()
            }
            for i, label in enumerate(self._variables):
                if label in default_labels:
                    self._checkboxes[i].setChecked(True)
            if not any(cb.isChecked() for cb in self._checkboxes):
                self._checkboxes[0].setChecked(True)

    def checked_variables(self) -> list[str]:
        return [
            label
            for label, cb in zip(self._variables, self._checkboxes, strict=True)
            if cb.isChecked()
        ]


class PlotWidget(QWidget):
    """Widget with variable selector and a plotly timeseries plot.

    Supports two web-view backends:

    * **QtWebEngine** (preferred, QGIS 4) - uses the latest ``plotly.min.js``
      bundled with the ``plotly`` Python package.
    * **QtWebKit** (fallback, QGIS 3) - uses a vendored ``plotly-2.4.2.min.js``
      with numpy-array workarounds.

    If neither backend is available the widget shows a static notice.
    """

    def __init__(
        self,
        parent: QWidget | None = None,
        iface: Any | None = None,
        node_layer_getter: Callable[[], Any | None] | None = None,
        link_layer_getter: Callable[[], Any | None] | None = None,
        concentration_for_node_getter: Callable[[int], dict[str, Trace] | None]
        | None = None,
    ):
        super().__init__(parent)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(2)

        if _BACKEND is _WebViewBackend.NONE or not HAS_PLOTLY:
            # No usable backend — the dock cannot be opened (toggle_plot_dock
            # blocks it), so just bail out of __init__.
            return

        # --- Selectors: single horizontal row ---
        row = QHBoxLayout()
        row.setContentsMargins(4, 4, 4, 0)
        row.setSpacing(4)

        self._iface = iface
        self._node_layer_getter = node_layer_getter
        self._link_layer_getter = link_layer_getter

        row.addWidget(QLabel("Select"))

        self._water_balance_enabled = False
        self._fractional_storage_enabled = False
        self._fractional_flow_enabled = False
        self._concentration_for_node_getter = concentration_for_node_getter
        self._plot_button = QToolButton()
        self._plot_button.setToolButtonStyle(
            Qt.ToolButtonStyle.ToolButtonTextBesideIcon
        )
        self._plot_button.setPopupMode(QToolButton.ToolButtonPopupMode.InstantPopup)
        self._var_menu = _PlotMenu(self._plot_button)
        self._var_menu.waterBalanceChanged.connect(self._on_water_balance_changed)
        self._var_menu.fractionalStorageChanged.connect(
            self._on_fractional_storage_changed
        )
        self._var_menu.fractionalFlowChanged.connect(self._on_fractional_flow_changed)
        self._var_menu.aboutToHide.connect(self._on_menu_closed)
        self._plot_button.setMenu(self._var_menu)
        self._plot_button.setText("variable")
        row.addWidget(self._plot_button)

        row.addSpacing(10)
        row.addWidget(QLabel("Select on map"))

        self._node_button = QToolButton()
        self._node_button.setText("node")
        self._node_button.clicked.connect(self._activate_node_selection)
        row.addWidget(self._node_button)

        self._link_button = QToolButton()
        self._link_button.setText("link")
        self._link_button.clicked.connect(self._activate_link_selection)
        row.addWidget(self._link_button)

        row.addStretch()
        layout.addLayout(row)

        # --- Placeholder label ---
        self._placeholder = QLabel(_PLACEHOLDER_DEFAULT)
        self._placeholder.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self._placeholder.setStyleSheet("color: gray; font-style: italic;")
        layout.addWidget(self._placeholder)

        # --- Web view (backend-specific) ---
        if _BACKEND is _WebViewBackend.WEBENGINE:
            self._web_view = QWebEngineView()
        else:
            self._web_view = QWebView()  # type: ignore[assignment]
            ws = self._web_view.settings()
            ws.setAttribute(QWebSettings.WebGLEnabled, True)  # type: ignore[arg-type]
            ws.setAttribute(QWebSettings.Accelerated2dCanvasEnabled, True)  # type: ignore[arg-type]

        self._web_view.setVisible(False)
        self._web_view.setContextMenuPolicy(Qt.ContextMenuPolicy.NoContextMenu)
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

    @property
    def plotting_supported(self) -> bool:
        """Whether the interactive plot backend is available."""
        return _BACKEND is not _WebViewBackend.NONE and HAS_PLOTLY

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
        if not self.plotting_supported:
            return
        self._available = available
        self._units = units or {}
        self._defaults = defaults or {}
        previously_checked_labels = set(self._var_menu.checked_variables())
        previously_checked_keys = {
            self._menu_to_key[label]
            for label in previously_checked_labels
            if label in self._menu_to_key
        }

        menu_to_key: dict[str, tuple[str, str]] = {}
        for file_name, file_variables in self._available.items():
            for variable in sorted(file_variables):
                label = f"{file_name} / {variable}"
                menu_to_key[label] = (file_name, variable)

        self._menu_to_key = menu_to_key

        checked_labels = {
            label
            for label, key in self._menu_to_key.items()
            if key in previously_checked_keys
        }

        self._var_menu.populate(
            self._available,
            checked_labels,
            self._defaults,
            self._water_balance_enabled,
            self._fractional_storage_enabled,
            self._fractional_flow_enabled,
        )
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
        if not self.plotting_supported:
            return
        self._plot_data = plot_data
        if units:
            self._units = units
        self._redraw()

    def clear(self) -> None:
        if not self.plotting_supported:
            return
        self._plot_data = {}
        self._web_view.setVisible(False)
        self._web_view.setUrl(QUrl("about:blank"))
        self._placeholder.setVisible(True)

    # --- Internal slots ---

    def _on_menu_closed(self) -> None:
        """Redraw the plot when the variable menu closes."""
        self._redraw()

    def _on_water_balance_changed(self, enabled: bool) -> None:
        self._water_balance_enabled = enabled
        self._redraw()

    def _on_fractional_storage_changed(self, enabled: bool) -> None:
        self._fractional_storage_enabled = enabled
        self._redraw()

    def _on_fractional_flow_changed(self, enabled: bool) -> None:
        self._fractional_flow_enabled = enabled
        self._redraw()

    def _activate_node_selection(self) -> None:
        self._activate_selection_target(self._node_layer_getter)

    def _activate_link_selection(self) -> None:
        self._activate_selection_target(self._link_layer_getter)

    def _activate_selection_target(
        self, layer_getter: Callable[[], Any | None] | None
    ) -> None:
        if self._iface is None or layer_getter is None:
            return
        layer = layer_getter()
        if layer is None:
            return
        self._iface.setActiveLayer(layer)
        self._activate_qgis_select_tool()

    def _activate_qgis_select_tool(self) -> None:
        if self._iface is None:
            return
        action = self._iface.actionSelect()
        if action is not None:
            action.trigger()

    def _selected_keys(self) -> list[tuple[str, str]]:
        return [
            self._menu_to_key[label]
            for label in self._var_menu.checked_variables()
            if label in self._menu_to_key
        ]

    def _to_plotly_xy(
        self, x: np.ndarray, y: np.ndarray
    ) -> tuple[np.ndarray | list[str], np.ndarray | list[float]]:
        if _BACKEND is _WebViewBackend.WEBKIT:
            return x.tolist(), y.tolist()
        return x, y

    def _collect_standard_traces(
        self,
        selected_keys: list[tuple[str, str]],
        excluded_variables: set[str] | None = None,
        excluded_files: set[str] | None = None,
    ) -> dict[str, list[go.Scatter]]:
        traces_by_unit: dict[str, list[go.Scatter]] = defaultdict(list)
        excluded_variables = excluded_variables or set()
        excluded_files = excluded_files or set()
        for file_name, var in selected_keys:
            if file_name in excluded_files:
                continue
            if var in excluded_variables:
                continue
            file_data = self._plot_data.get(file_name, {})
            file_units = self._units.get(file_name, {})
            var_traces = file_data.get(var, {})
            if not var_traces:
                continue
            unit = file_units.get(var, "")
            unit_key = unit or "(no unit)"
            for trace_name, (x, y) in var_traces.items():
                x_data, y_data = self._to_plotly_xy(x, y)
                legend_name = f"{file_name} / {var} {trace_name}"
                traces_by_unit[unit_key].append(
                    go.Scatter(x=x_data, y=y_data, mode="lines", name=legend_name)
                )
        return traces_by_unit

    def _placeholder_for_current_preset(self) -> str:
        if self._water_balance_enabled:
            return _PLACEHOLDER_WATER_BALANCE
        if self._fractional_storage_enabled:
            return _PLACEHOLDER_FRACTIONAL_STORAGE
        if self._fractional_flow_enabled:
            return _PLACEHOLDER_FRACTIONAL_FLOW
        return _PLACEHOLDER_DEFAULT

    def _show_placeholder(self, text: str | None = None) -> None:
        if text is not None:
            self._placeholder.setText(text)
        self._web_view.setVisible(False)
        self._placeholder.setVisible(True)

    def _render_figure(self, fig, config: dict[str, bool | list[str]]) -> None:
        div = po.plot(
            fig,
            output_type="div",
            include_plotlyjs=False,
            config=config,
        )

        if _BACKEND is _WebViewBackend.WEBENGINE:
            js_src = _PLOTLY_JS_URL.toString()
        else:
            js_src = _PLOTLY_JS_FILE

        html = (
            '<html><head><meta charset="utf-8" />'
            f'<script src="{js_src}"></script></head>'
            f'<body style="margin:0;overflow:hidden">{div}</body></html>'
        )
        _PLOT_HTML_FILE.write_text(html, encoding="utf-8")
        self._placeholder.setVisible(False)
        self._web_view.setVisible(True)
        self._web_view.setUrl(QUrl.fromLocalFile(str(_PLOT_HTML_FILE)))

    def _redraw_standard(
        self, selected_keys: list[tuple[str, str]], config: dict[str, bool | list[str]]
    ) -> None:
        if not selected_keys or not self._plot_data:
            self._show_placeholder(self._placeholder_for_current_preset())
            return

        traces_by_unit = self._collect_standard_traces(selected_keys)

        if not traces_by_unit:
            self._show_placeholder(self._placeholder_for_current_preset())
            return

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

        fig.update_layout(**_PLOT_LAYOUT)
        self._render_figure(fig, config)

    def _redraw_basin_water_balance(
        self, selected_keys: list[tuple[str, str]], config: dict[str, bool | list[str]]
    ) -> None:
        if not self._plot_data:
            self._show_placeholder(self._placeholder_for_current_preset())
            return

        water_balance_terms = {term for term, _ in _BASIN_WATER_BALANCE_TERMS}
        selected_files = {
            file_name
            for file_name, variable in selected_keys
            if variable in water_balance_terms
        }
        candidate_files = selected_files or {
            file_name
            for file_name, file_data in self._plot_data.items()
            if any(term in file_data for term in water_balance_terms)
        }
        if len(candidate_files) != 1:
            self._show_placeholder(_PLACEHOLDER_WATER_BALANCE)
            return

        file_name = next(iter(candidate_files))
        file_data = self._plot_data.get(file_name, {})
        file_units = self._units.get(file_name, {})

        trace_names: set[str] = set()
        for term, _ in _BASIN_WATER_BALANCE_TERMS:
            trace_names.update(file_data.get(term, {}))

        if len(trace_names) != 1:
            self._show_placeholder(_PLACEHOLDER_WATER_BALANCE)
            return

        selected_trace = next(iter(trace_names))

        # Keep selected non-water-balance variables visible as extra rows.
        traces_by_unit = self._collect_standard_traces(
            selected_keys,
            excluded_variables=water_balance_terms,
        )

        units = sorted(traces_by_unit)
        fig = make_subplots(
            rows=1 + len(units),
            cols=1,
            shared_xaxes=True,
            vertical_spacing=0.04,
        )
        used_terms = 0

        for term, sign in reversed(_BASIN_WATER_BALANCE_TERMS):
            traces = file_data.get(term, {})
            if selected_trace not in traces:
                continue
            x, y = traces[selected_trace]
            signed_y = sign * y
            x_data, y_data = self._to_plotly_xy(x, signed_y)
            stackgroup = "inflow" if sign > 0 else "outflow"
            legend_prefix = "+" if sign > 0 else "-"
            fig.add_trace(
                go.Scatter(
                    x=x_data,
                    y=y_data,
                    mode="lines",
                    stackgroup=stackgroup,
                    hoveron="points+fills",
                    line={"width": 0},
                    name=f"{legend_prefix} {term}",
                ),
                row=1,
                col=1,
            )
            used_terms += 1

        if used_terms == 0:
            self._show_placeholder(_PLACEHOLDER_WATER_BALANCE)
            return

        unit_values = {
            file_units.get(term, "")
            for term, _ in _BASIN_WATER_BALANCE_TERMS
            if file_units.get(term, "")
        }
        yaxis_title = unit_values.pop() if len(unit_values) == 1 else "(no unit)"
        fig.update_yaxes(title_text=yaxis_title, row=1, col=1)

        for row, unit in enumerate(units, start=2):
            for trace in traces_by_unit[unit]:
                fig.add_trace(trace, row=row, col=1)
            fig.update_yaxes(title_text=unit, row=row, col=1)

        last_row = 1 + len(units)
        for row in range(1, last_row + 1):
            fig.update_xaxes(showticklabels=row == last_row, row=row, col=1)

        fig.update_layout(**_PLOT_LAYOUT, hovermode="x unified")
        self._render_figure(fig, config)

    def _selected_tracers(
        self,
        selected_keys: list[tuple[str, str]],
        available_substances: set[str],
    ) -> list[str]:
        """Return the tracer names to use for a fractional preset.

        Uses checked concentration variables when present, otherwise falls
        back to the default tracers, then to all available substances.
        """
        selected = [
            var
            for file_name, var in selected_keys
            if file_name == "concentration" and var in available_substances
        ]
        if not selected:
            selected = [t for t in _DEFAULT_TRACERS if t in available_substances]
        if not selected:
            selected = sorted(available_substances)
        return selected

    def _redraw_fractional_storage(
        self, selected_keys: list[tuple[str, str]], config: dict[str, bool | list[str]]
    ) -> None:
        if not self._plot_data:
            self._show_placeholder(self._placeholder_for_current_preset())
            return

        concentration_data = self._plot_data.get("concentration", {})
        if not concentration_data:
            self._show_placeholder(_PLACEHOLDER_FRACTIONAL_STORAGE)
            return

        # Collect trace names (node ids) across all substances.
        trace_names: set[str] = set()
        for var_traces in concentration_data.values():
            trace_names.update(var_traces)

        if len(trace_names) != 1:
            self._show_placeholder(_PLACEHOLDER_FRACTIONAL_STORAGE)
            return

        selected_trace = next(iter(trace_names))
        selected_substances = self._selected_tracers(
            selected_keys, set(concentration_data)
        )

        # Keep selected non-concentration variables visible as extra rows.
        traces_by_unit = self._collect_standard_traces(
            selected_keys,
            excluded_files={"concentration"},
        )

        units = sorted(traces_by_unit)
        fig = make_subplots(
            rows=1 + len(units),
            cols=1,
            shared_xaxes=True,
            vertical_spacing=0.04,
        )
        used = 0

        for substance in reversed(selected_substances):
            traces = concentration_data.get(substance, {})
            if selected_trace not in traces:
                continue
            x, y = traces[selected_trace]
            x_data, y_data = self._to_plotly_xy(x, y)
            fig.add_trace(
                go.Scatter(
                    x=x_data,
                    y=y_data,
                    mode="lines",
                    stackgroup="fractions",
                    hoveron="points+fills",
                    line={"width": 0},
                    name=substance,
                ),
                row=1,
                col=1,
            )
            used += 1

        if used == 0:
            self._show_placeholder(_PLACEHOLDER_FRACTIONAL_STORAGE)
            return

        file_units = self._units.get("concentration", {})
        unit_values = {
            file_units.get(sub, "")
            for sub in selected_substances
            if file_units.get(sub, "")
        }
        yaxis_title = unit_values.pop() if len(unit_values) == 1 else "fraction"
        fig.update_yaxes(title_text=yaxis_title, row=1, col=1)

        for row, unit in enumerate(units, start=2):
            for trace in traces_by_unit[unit]:
                fig.add_trace(trace, row=row, col=1)
            fig.update_yaxes(title_text=unit, row=row, col=1)

        last_row = 1 + len(units)
        for row in range(1, last_row + 1):
            fig.update_xaxes(showticklabels=row == last_row, row=row, col=1)

        fig.update_layout(**_PLOT_LAYOUT, hovermode="x unified")
        self._render_figure(fig, config)

    # --- Fractional flow helpers ---

    def _get_link_endpoints(self, link_id: int) -> tuple[int, int] | None:
        """Return (from_node_id, to_node_id) for *link_id* via the QGIS link layer."""
        if self._link_layer_getter is None:
            return None
        layer = self._link_layer_getter()
        if layer is None:
            return None
        from qgis.core import QgsFeatureRequest

        request = QgsFeatureRequest().setFilterExpression(f'"link_id" = {int(link_id)}')
        for feat in layer.getFeatures(request):
            return int(feat["from_node_id"]), int(feat["to_node_id"])
        return None

    def _get_node_type(self, node_id: int) -> str | None:
        """Look up node_type for *node_id* via the QGIS node layer."""
        if self._node_layer_getter is None:
            return None
        layer = self._node_layer_getter()
        if layer is None:
            return None
        from qgis.core import QgsFeatureRequest

        request = QgsFeatureRequest().setFilterExpression(f'"node_id" = {int(node_id)}')
        for feat in layer.getFeatures(request):
            return str(feat["node_type"])
        return None

    def _find_basin_through_connector(
        self, connector_node_id: int, current_link_id: int
    ) -> int | None:
        """Traverse a connector node to find the Basin on the other side.

        Given a connector node and the link we arrived on, find the *other*
        link connected to this connector and return the node on its far side
        if that node is a Basin.
        """
        if self._link_layer_getter is None:
            return None
        layer = self._link_layer_getter()
        if layer is None:
            return None
        from qgis.core import QgsFeatureRequest

        expr = (
            f'"from_node_id" = {int(connector_node_id)} '
            f'OR "to_node_id" = {int(connector_node_id)}'
        )
        request = QgsFeatureRequest().setFilterExpression(expr)
        for feat in layer.getFeatures(request):
            if int(feat["link_id"]) == current_link_id:
                continue
            from_id = int(feat["from_node_id"])
            to_id = int(feat["to_node_id"])
            far_node = to_id if from_id == connector_node_id else from_id
            if self._get_node_type(far_node) == "Basin":
                return far_node
        return None

    def _resolve_basin(
        self, node_id: int, link_id: int
    ) -> tuple[int | None, str | None]:
        """Return (basin_id, error_placeholder) for a link endpoint.

        If the node is a Basin, return it directly.  If it is a connector
        node, traverse it.  If it is a Junction, return the junction
        placeholder.  Otherwise return a generic error placeholder.
        """
        node_type = self._get_node_type(node_id)
        if node_type == "Basin":
            return node_id, None
        if node_type == "Junction":
            return None, _PLACEHOLDER_FRACTIONAL_FLOW_JUNCTION
        if node_type in _TRAVERSABLE_NODE_TYPES:
            basin = self._find_basin_through_connector(node_id, link_id)
            if basin is not None:
                return basin, None
            return None, _PLACEHOLDER_FRACTIONAL_FLOW_NO_BASIN
        return None, _PLACEHOLDER_FRACTIONAL_FLOW_NO_BASIN

    def _redraw_fractional_flow(
        self, selected_keys: list[tuple[str, str]], config: dict[str, bool | list[str]]
    ) -> None:
        if not self._plot_data:
            self._show_placeholder(self._placeholder_for_current_preset())
            return

        # Need exactly one link in flow data.
        flow_data = self._plot_data.get("flow", {})
        flow_rate_traces = flow_data.get("flow_rate", {})
        if len(flow_rate_traces) != 1:
            self._show_placeholder(_PLACEHOLDER_FRACTIONAL_FLOW)
            return

        trace_name = next(iter(flow_rate_traces))
        link_id = int(trace_name.lstrip("#"))
        flow_time, flow_values = flow_rate_traces[trace_name]

        # Resolve both endpoints to Basins (traversing connectors).
        endpoints = self._get_link_endpoints(link_id)
        if endpoints is None:
            self._show_placeholder(_PLACEHOLDER_FRACTIONAL_FLOW)
            return

        from_node_id, to_node_id = endpoints
        from_basin, from_err = self._resolve_basin(from_node_id, link_id)
        to_basin, to_err = self._resolve_basin(to_node_id, link_id)

        # At least one endpoint must resolve to a Basin. A single-sided Basin
        # is valid: concentration is then only available for the matching flow
        # direction where that side is the source.
        if from_basin is None and to_basin is None:
            err = from_err or to_err or _PLACEHOLDER_FRACTIONAL_FLOW_NO_BASIN
            self._show_placeholder(err)
            return

        if self._concentration_for_node_getter is None:
            self._show_placeholder(_PLACEHOLDER_FRACTIONAL_FLOW)
            return

        from_conc = (
            self._concentration_for_node_getter(from_basin)
            if from_basin is not None
            else None
        )
        to_conc = (
            self._concentration_for_node_getter(to_basin)
            if to_basin is not None
            else None
        )
        if not from_conc and not to_conc:
            self._show_placeholder(_PLACEHOLDER_FRACTIONAL_FLOW_NO_CONCENTRATION)
            return

        available_substances: set[str] = set()
        if from_conc:
            available_substances.update(from_conc)
        if to_conc:
            available_substances.update(to_conc)

        selected_substances = self._selected_tracers(
            selected_keys, available_substances
        )

        # Build a boolean mask: True where flow is positive (from→to).
        positive_mask = flow_values >= 0

        # Extra traces — exclude concentration and flow files.
        traces_by_unit = self._collect_standard_traces(
            selected_keys,
            excluded_files={"concentration", "flow"},
        )

        units = sorted(traces_by_unit)
        fig = make_subplots(
            rows=1 + len(units),
            cols=1,
            shared_xaxes=True,
            vertical_spacing=0.04,
        )
        used = 0

        for substance in reversed(selected_substances):
            # Build per-timestep concentration from the appropriate basin.
            from_vals = from_conc.get(substance) if from_conc else None
            to_vals = to_conc.get(substance) if to_conc else None
            if from_vals is None and to_vals is None:
                continue

            conc = np.zeros_like(flow_values)
            if from_vals is not None:
                _ft, fv = from_vals
                if len(fv) == len(flow_values):
                    conc = np.where(positive_mask, fv, conc)
            if to_vals is not None:
                _tt, tv = to_vals
                if len(tv) == len(flow_values):
                    conc = np.where(~positive_mask, tv, conc)

            fractional_values = conc * flow_values
            x_data, y_data = self._to_plotly_xy(flow_time, fractional_values)
            fig.add_trace(
                go.Scatter(
                    x=x_data,
                    y=y_data,
                    mode="lines",
                    stackgroup="fractions",
                    hoveron="points+fills",
                    line={"width": 0},
                    name=substance,
                ),
                row=1,
                col=1,
            )
            used += 1

        if used == 0:
            self._show_placeholder(_PLACEHOLDER_FRACTIONAL_FLOW)
            return

        # Total flow_rate as a black line on top.
        x_flow, y_flow = self._to_plotly_xy(flow_time, flow_values)
        fig.add_trace(
            go.Scatter(
                x=x_flow,
                y=y_flow,
                mode="lines",
                line={"color": "black", "width": 1.5},
                name="flow_rate",
            ),
            row=1,
            col=1,
        )

        flow_units = self._units.get("flow", {})
        yaxis_title = flow_units.get("flow_rate", "m3 s-1")
        fig.update_yaxes(title_text=yaxis_title, row=1, col=1)

        for row, unit in enumerate(units, start=2):
            for trace in traces_by_unit[unit]:
                fig.add_trace(trace, row=row, col=1)
            fig.update_yaxes(title_text=unit, row=row, col=1)

        last_row = 1 + len(units)
        for row in range(1, last_row + 1):
            fig.update_xaxes(showticklabels=row == last_row, row=row, col=1)

        fig.update_layout(**_PLOT_LAYOUT, hovermode="x unified")
        self._render_figure(fig, config)

    def _redraw(self) -> None:
        selected_keys = self._selected_keys()
        config: dict[str, bool | list[str]] = {
            "scrollZoom": True,
            "editable": False,
            "displayModeBar": True,
            "responsive": True,
        }
        # toImage uses an <a download> click that QtWebKit silently ignores.
        if _BACKEND is _WebViewBackend.WEBKIT:
            config["modeBarButtonsToRemove"] = ["toImage"]

        if self._water_balance_enabled:
            self._redraw_basin_water_balance(selected_keys, config)
            return
        if self._fractional_storage_enabled:
            self._redraw_fractional_storage(selected_keys, config)
            return
        if self._fractional_flow_enabled:
            self._redraw_fractional_flow(selected_keys, config)
            return
        self._redraw_standard(selected_keys, config)
