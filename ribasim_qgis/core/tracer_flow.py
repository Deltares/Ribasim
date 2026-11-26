"""Split the flows of the results by the tracers they carry.

The water on a link has the concentrations of the node it comes from. A Basin has the
concentrations of the results, and a FlowBoundary or LevelBoundary has its own tracer and
the concentrations of its input table. A connector node passes on the water from the node
at its other side. A UserDemand returns the water it abstracts, with the concentrations of
its input table added. A Junction with rows in ``Junction / static`` mixes its inflows,
like the core does.

The core removes the other Junctions, see :mod:`ribasim_qgis.core.junctions`. In a group of
them with one Basin, every other neighbor exchanges water with that Basin directly, so
their inflows don't mix with their outflows. A link between these Junctions, or between
a Junction and the Basin, carries the net tracer flows of the neighbors behind it. Other
groups connect their neighbors along the direction of their links, so their Junctions mix
their inflows.

The flows of the results are means over the saveat intervals, and the input tables are
averaged over each interval. The Basin results hold the concentrations at the start of each
interval, so a Basin sends the mean of those at the start and end of an interval, see
`interval_mean`. The core mixes the water within each timestep instead, so the split is
approximate where concentrations change much within an interval.
"""

from collections.abc import Callable, Collection
from dataclasses import dataclass, field
from pathlib import Path
from typing import cast

import numpy as np
import pandas as pd

from ribasim_qgis.core.geopackage import sqlite3_cursor
from ribasim_qgis.core.junctions import (
    CONNECTOR_NODE_TYPES,
    FlowGraph,
    FlowLink,
    node_flow_links,
)

# Substance name -> values over time.
Tracers = dict[str, np.ndarray]

BOUNDARY_NODE_TYPES: tuple[str, ...] = ("FlowBoundary", "LevelBoundary")
# The node types with a concentration table, see `InputConcentrations`.
CONCENTRATION_NODE_TYPES: tuple[str, ...] = (*BOUNDARY_NODE_TYPES, "UserDemand")
CONCENTRATION_TABLES: tuple[str, ...] = tuple(
    f"{node_type} / concentration" for node_type in CONCENTRATION_NODE_TYPES
)


def interval_mean(values: np.ndarray) -> np.ndarray:
    """Return the mean of the values at the start and end of each interval.

    The values are those at the start of each interval, like the Basin concentrations of
    the results. The end of the last interval is not in the results, so it keeps the value
    at its start.
    """
    values = np.asarray(values, dtype=float)
    result = values.copy()
    result[:-1] = 0.5 * (values[:-1] + values[1:])
    return result


def _add(result: Tracers, tracers: Tracers, factor: float | np.ndarray) -> None:
    for substance, values in tracers.items():
        result[substance] = result.get(substance, 0.0) + factor * values


class TracerFlows:
    """The tracer flows over the links and through the nodes of a model.

    Parameters
    ----------
    graph:
        The flow links and node types.
    flow:
        The flow rate of a link over time.
    basin_concentration:
        The concentrations of the water that leaves a Basin, per interval.
    n_time:
        The number of times, which all values must have.
    substances:
        The substances to always return, also when they are zero.
    input_concentration:
        The concentrations of a FlowBoundary, LevelBoundary or UserDemand from its input
        table.

    A missing substance has a concentration of zero. A result is ``None`` if the source of
    the water cannot be determined.
    """

    def __init__(
        self,
        graph: FlowGraph,
        flow: Callable[[int], np.ndarray | None],
        basin_concentration: Callable[[int], Tracers | None],
        n_time: int,
        substances: Collection[str] = (),
        input_concentration: Callable[[int], Tracers | None] | None = None,
    ):
        self.graph = graph
        self._flow = flow
        self._basin_concentration = basin_concentration
        self._input_concentration = input_concentration
        self._n_time = n_time
        self._substances = set(substances)
        self._sent: dict[tuple[int, int], Tracers | None] = {}
        self._visiting: set[tuple[int, int]] = set()

    def link(self, link_id: int) -> Tracers | None:
        """Return the tracer flows over a link."""
        link = self.graph.link(link_id)
        tracers = None if link is None else self._over_link(link)
        return None if tracers is None else self._complete(tracers)

    def node(
        self, node_id: int, variable: str = "flow_rate"
    ) -> tuple[np.ndarray, Tracers] | None:
        """Return a flow of a node and its tracer flows, see `node_flow_links`.

        The ``inflow_rate`` and ``outflow_rate`` of a Basin are those of the Basin results.
        """
        if variable in ("inflow_rate", "outflow_rate") and (
            self.graph.node_type(node_id) == "Basin"
        ):
            return self._basin_flow(node_id, variable == "inflow_rate")
        links = node_flow_links(self.graph, node_id, variable)
        if not links:
            return None
        total = np.zeros(self._n_time)
        result: Tracers = {}
        for link in links:
            flow = self._flow_of(link)
            tracers = self._over_link(link)
            if flow is None or tracers is None:
                return None
            total += flow
            _add(result, tracers, 1.0)
        return total, self._complete(result)

    def _basin_flow(
        self, basin_id: int, inflow: bool
    ) -> tuple[np.ndarray, Tracers] | None:
        """Return the inflow or outflow of a Basin and its tracer flows.

        Like the Basin results, these add up the water that the Basin exchanges with each
        of its neighbors, also through a Junction tree of which it is the only Basin. The
        water that flows out has the concentrations of the Basin.
        """
        basin_concentration = self._checked(self._basin_concentration(basin_id))
        if basin_concentration is None:
            return None
        total = np.zeros(self._n_time)
        result: Tracers = {}
        for link in self.graph.links(basin_id):
            other = link.other(basin_id)
            if (
                self.graph.is_plain_junction(other)
                and self.graph.junction_group(other).basin == basin_id
            ):
                exchanges = self.graph.behind(other, link)[1]
            else:
                exchanges = [(basin_id, link)]
            for near_node, exchange_link in exchanges:
                flow = self._flow_of(exchange_link)
                if flow is None:
                    return None
                # Positive flow towards the near node is water into the Basin
                inflow_part = flow * exchange_link.inflow_sign(near_node)
                part = np.maximum(inflow_part if inflow else -inflow_part, 0.0)
                if not part.any():
                    continue
                concentration = (
                    self._sent_over(exchange_link.other(near_node), exchange_link)
                    if inflow
                    else basin_concentration
                )
                if concentration is None:
                    return None
                total += part
                _add(result, concentration, part)
        return total, self._complete(result)

    def _complete(self, tracers: Tracers) -> Tracers:
        """Add the substances that are missing, with zeros."""
        return {
            substance: np.zeros(self._n_time) + tracers.get(substance, 0.0)
            for substance in self._substances | tracers.keys()
        }

    def _flow_of(self, link: FlowLink) -> np.ndarray | None:
        flow = self._flow(link.link_id)
        if flow is None or len(flow) != self._n_time:
            return None
        return np.asarray(flow, dtype=float)

    def _checked(self, tracers: Tracers | None) -> Tracers | None:
        if tracers is None or any(len(v) != self._n_time for v in tracers.values()):
            return None
        self._substances.update(tracers)
        return tracers

    def _over_link(self, link: FlowLink) -> Tracers | None:
        flow = self._flow_of(link)
        if flow is None:
            return None
        for node_id in (link.from_node_id, link.to_node_id):
            if self.graph.is_plain_junction(node_id):
                group = self.graph.junction_group(node_id)
                basin = group.basin
                if basin is not None and {
                    link.from_node_id,
                    link.to_node_id,
                } <= group.junctions | {basin}:
                    return self._over_tree_link(link, basin)
                break
        # Positive flow brings the water of the from node, negative flow that of the to node.
        result: Tracers = {}
        for node_id, part in (
            (link.from_node_id, np.maximum(flow, 0.0)),
            (link.to_node_id, np.minimum(flow, 0.0)),
        ):
            if not part.any():
                continue
            concentration = self._sent_over(node_id, link)
            if concentration is None:
                return None
            _add(result, concentration, part)
        return result

    def _over_tree_link(self, link: FlowLink, basin: int) -> Tracers | None:
        """Return the net tracer flows of the neighbors behind a link of a Junction tree.

        These are the neighbors on the side of the link away from the Basin, which each
        exchange water with the Basin directly.
        """
        towards_basin = link.to_node_id == basin or (
            link.from_node_id != basin
            and not self.graph.behind(link.from_node_id, link)[0]
        )
        behind_node, sign = (
            (link.from_node_id, 1.0) if towards_basin else (link.to_node_id, -1.0)
        )
        basin_concentration = self._checked(self._basin_concentration(basin))
        if basin_concentration is None:
            return None
        result: Tracers = {}
        for junction_id, neighbor_link in self.graph.behind(behind_node, link)[1]:
            flow = self._flow_of(neighbor_link)
            if flow is None:
                return None
            # Water into the group comes from the neighbor, water out of it from the Basin
            inflow = flow * neighbor_link.inflow_sign(junction_id)
            if (inflow > 0.0).any():
                concentration = self._sent_over(
                    neighbor_link.other(junction_id), neighbor_link
                )
                if concentration is None:
                    return None
                _add(result, concentration, sign * np.maximum(inflow, 0.0))
            _add(result, basin_concentration, sign * np.minimum(inflow, 0.0))
        return result

    def _sent_over(self, node_id: int, link: FlowLink) -> Tracers | None:
        """Return the concentrations of the water that a node sends over a link."""
        key = (node_id, link.link_id)
        if key not in self._sent:
            if key in self._visiting:
                # Water cannot flow in a loop without passing a Basin in a valid model
                return None
            self._visiting.add(key)
            try:
                self._sent[key] = self._compute_sent(node_id, link)
            finally:
                self._visiting.discard(key)
        return self._sent[key]

    def _compute_sent(self, node_id: int, link: FlowLink) -> Tracers | None:
        graph = self.graph
        node_type = graph.node_type(node_id)
        if node_type == "Basin":
            return self._checked(self._basin_concentration(node_id))
        if node_type in BOUNDARY_NODE_TYPES:
            ones = np.ones(self._n_time)
            concentration = {"Continuity": ones, node_type: ones}
            if self._input_concentration is not None:
                concentration.update(self._input_concentration(node_id) or {})
            return self._checked(concentration)
        if node_type == "Terminal":
            # A flow out of a Terminal is within the solver tolerance, without tracers
            return {}
        others = [other for other in graph.links(node_id) if other != link]
        if node_type in CONNECTOR_NODE_TYPES:
            if len(others) != 1:
                return None
            other = others[0]
            return self._sent_over(other.other(node_id), other)
        if node_type == "UserDemand":
            # The return flow has the concentrations of the water it abstracts, plus
            # those of its input table, like in the core
            abstracted = self._mix(
                node_id, [other for other in others if other.to_node_id == node_id]
            )
            added = (
                None
                if self._input_concentration is None
                else self._input_concentration(node_id)
            )
            if abstracted is None or not added:
                return abstracted
            result: Tracers = {}
            _add(result, abstracted, 1.0)
            _add(result, added, 1.0)
            return self._checked(result)
        if node_type == "Junction":
            if graph.is_plain_junction(node_id):
                basin = graph.junction_group(node_id).basin
                if basin is not None:
                    return self._checked(self._basin_concentration(basin))
            return self._mix(node_id, others)
        return None

    def _mix(self, node_id: int, links: list[FlowLink]) -> Tracers | None:
        """Return the concentrations of the water that flows into a node over *links*."""
        total = np.zeros(self._n_time)
        mass: Tracers = {}
        for link in links:
            flow = self._flow_of(link)
            if flow is None:
                return None
            inflow = np.maximum(flow * link.inflow_sign(node_id), 0.0)
            if not inflow.any():
                continue
            concentration = self._sent_over(link.other(node_id), link)
            if concentration is None:
                return None
            total += inflow
            _add(mass, concentration, inflow)
        safe_total = np.where(total > 0.0, total, 1.0)
        return {
            substance: np.where(total > 0.0, values / safe_total, 0.0)
            for substance, values in mass.items()
        }


@dataclass
class InputConcentrations:
    """The ``concentration`` input of FlowBoundary, LevelBoundary and UserDemand nodes.

    Attributes
    ----------
    series:
        Mapping ``node_id -> substance -> (times, concentrations)``, sorted by time.
    cyclic:
        The nodes with a ``cyclic_time``, whose series repeat.
    """

    series: dict[int, dict[str, tuple[np.ndarray, np.ndarray]]] = field(
        default_factory=dict
    )
    cyclic: frozenset[int] = frozenset()

    def mean(
        self, node_id: int, times: np.ndarray, end: np.datetime64
    ) -> Tracers | None:
        """Return the mean concentrations of a node over the intervals of the results.

        The intervals start at *times*, and the last one ends at *end*. These are the
        intervals the flow results are means over, so for a constant flow within an
        interval, the mean concentration gives the mass the core adds over it.

        The core uses block interpolation, which holds a value until the next time, with
        the first and last value before and after the series, or repeats the series for a
        node with a cyclic time.
        """
        node_series = self.series.get(node_id)
        if not node_series:
            return None
        bounds = np.append(
            np.asarray(times, dtype="datetime64[ns]"), np.datetime64(end, "ns")
        )
        duration = np.diff(bounds) / np.timedelta64(1, "s")
        cyclic = node_id in self.cyclic
        result: Tracers = {}
        for substance, (series_times, values) in node_series.items():
            start_value, integral = _block_interpolation(
                series_times, values, bounds, cyclic
            )
            mean = np.diff(integral) / np.where(duration > 0.0, duration, 1.0)
            result[substance] = np.where(duration > 0.0, mean, start_value[:-1])
        return result


def _block_interpolation(
    times: np.ndarray, values: np.ndarray, at: np.ndarray, cyclic: bool
) -> tuple[np.ndarray, np.ndarray]:
    """Return a block interpolated series at *at*, and its integral up to *at*.

    The integral is in seconds, from the first time of the series.
    """
    seconds = (times - times[0]) / np.timedelta64(1, "s")
    x = (at - times[0]) / np.timedelta64(1, "s")
    # The integral up to each time of the series
    cumulative = np.concatenate(([0.0], np.cumsum(values[:-1] * np.diff(seconds))))
    period = seconds[-1]
    cycles = np.zeros_like(x)
    if cyclic and period > 0.0:
        cycles = np.floor(x / period)
        x = x - cycles * period
    index = np.clip(np.searchsorted(seconds, x, side="right") - 1, 0, len(values) - 1)
    value = values[index]
    integral = (
        cycles * cumulative[-1] + cumulative[index] + value * (x - seconds[index])
    )
    return value, integral


def read_input_concentrations(gpkg_path: Path) -> InputConcentrations:
    """Read the concentration tables of FlowBoundary, LevelBoundary and UserDemand nodes.

    Ribasim Python writes these tables to the GeoPackage only, since NetCDF input doesn't
    support a substance dimension.
    """
    result = InputConcentrations()
    if not gpkg_path.is_file():
        return result
    frames = []
    with sqlite3_cursor(gpkg_path) as cursor:
        cursor.execute(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN (?, ?, ?)",
            CONCENTRATION_TABLES,
        )
        tables = [row[0] for row in cursor.fetchall()]
        for table in tables:
            # The table names are module constants, not user input.
            cursor.execute(
                f'SELECT node_id, time, substance, concentration FROM "{table}" '  # noqa: S608
                "WHERE concentration IS NOT NULL"
            )
            frames.append(
                pd.DataFrame(
                    cursor.fetchall(),
                    columns=["node_id", "time", "substance", "concentration"],
                )
            )
        if tables:
            cursor.execute("PRAGMA table_info(Node)")
            if "cyclic_time" in {row[1] for row in cursor.fetchall()}:
                cursor.execute(
                    "SELECT node_id FROM Node WHERE cyclic_time "
                    "AND node_type IN (?, ?, ?)",
                    CONCENTRATION_NODE_TYPES,
                )
                result.cyclic = frozenset(int(row[0]) for row in cursor.fetchall())

    if not frames:
        return result
    df = pd.concat(frames)
    df["time"] = pd.to_datetime(df["time"])
    df = df.sort_values("time", kind="stable")
    for key, group in df.groupby(["node_id", "substance"]):
        node_id, substance = cast(tuple[int, str], key)
        result.series.setdefault(int(node_id), {})[str(substance)] = (
            group["time"].to_numpy(dtype="datetime64[ns]"),
            group["concentration"].to_numpy(dtype=float),
        )
    return result
