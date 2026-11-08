"""Plot allowed flow-link neighbors for the documentation, not valid models."""

from unittest.mock import patch

import matplotlib.pyplot as plt
import numpy as np
from matplotlib.collections import LineCollection
from matplotlib.figure import Figure
from matplotlib.offsetbox import AnnotationBbox
from ribasim import Model, Node
from ribasim.geometry.link import LinkTable
from ribasim.node_icons import make_icon_box
from ribasim.utils import _pascal_to_snake
from ribasim.validation import link_neighbor_amount, node_type_connectivity
from shapely.geometry import Point


def _flow_node_types() -> list[str]:
    return [
        node_type
        for node_type, bounds in link_neighbor_amount["flow"].items()
        if bounds[1] > 0 or bounds[3] > 0
    ]


def plot_node_connectivity(node_type: str) -> Figure:
    """Plot all allowed upstream and downstream flow neighbors of a node type."""
    if node_type not in _flow_node_types():
        raise ValueError(f"Node type {node_type!r} does not support flow links")
    return _plot_connectivity([node_type])


def plot_all_node_connectivity() -> Figure:
    """Plot flow-link connectivity for all applicable node types in one column."""
    return _plot_connectivity(_flow_node_types())


def _plot_connectivity(node_types: list[str]) -> Figure:
    model = Model(starttime="2020-01-01", endtime="2020-01-02", crs="EPSG:28992")
    central_ids = set()
    upstream_ids = set()
    with patch.object(LinkTable, "_validate_link", return_value=None):
        for i, node_type in enumerate(node_types):
            y = -i * 8
            central = getattr(model, _pascal_to_snake(node_type)).add(
                Node(geometry=Point(0, y), name=node_type)
            )
            central_ids.add(central.node_id)
            upstream_types = [
                upstream_type
                for upstream_type in _flow_node_types()
                if node_type in node_type_connectivity[upstream_type]
            ]
            downstream_types = node_type_connectivity[node_type]
            for direction, neighbor_types in [
                (-1, upstream_types),
                (1, downstream_types),
            ]:
                for j, neighbor_type in enumerate(neighbor_types):
                    neighbor_y = y + ((len(neighbor_types) - 1) / 2 - j) * 0.7
                    neighbor = getattr(model, _pascal_to_snake(neighbor_type)).add(
                        Node(
                            geometry=Point(direction * 3, neighbor_y),
                            name=neighbor_type,
                        )
                    )
                    if direction == -1:
                        upstream_ids.add(neighbor.node_id)
                        model.link.add(neighbor, central)
                    else:
                        model.link.add(central, neighbor)

    fig, ax = plt.subplots(figsize=(5, 30 if len(node_types) > 1 else 4))
    model.plot(ax=ax, indicate_subnetworks=False, aspect_ratio_bound=0.05)
    ax.set_aspect("auto")
    ax.get_legend().remove()
    if len(node_types) == 1:
        for collection in ax.collections:
            if isinstance(collection, LineCollection):
                collection.set_linewidths(collection.get_linewidths() * 2)
    fig.canvas.draw()
    link_direction_markers = [
        line
        for line in ax.lines
        if line.get_linestyle() == "None"
        and isinstance(line.get_marker(), tuple)
        and len(line.get_marker()) == 3
    ]
    assert model.link.df is not None
    for marker, geometry in zip(
        link_direction_markers, model.link.df.geometry, strict=True
    ):
        if len(node_types) == 1:
            marker.set_markersize(marker.get_markersize() * 2)
        start, end = ax.transData.transform(np.asarray(geometry.coords)[[0, -1], :2])
        dx, dy = end - start
        marker.set_marker((3, 0, np.degrees(np.arctan2(dy, dx)) - 90))
    for artist in list(ax.artists):
        if isinstance(artist, AnnotationBbox):
            artist.remove()
    for text in list(ax.texts):
        text.remove()
    assert model.node.df is not None
    for node_id, node in model.node.df.iterrows():
        is_central = node_id in central_ids
        is_upstream = node_id in upstream_ids
        ax.add_artist(
            AnnotationBbox(
                make_icon_box(node["node_type"], size=44),
                (node.geometry.x, node.geometry.y),
                frameon=False,
                pad=0,
                zorder=3,
            )
        )
        if is_central and len(node_types) == 1:
            continue
        ax.annotate(
            node["name"],
            xy=(node.geometry.x, node.geometry.y),
            xytext=(0, 28) if is_central else (-28 if is_upstream else 28, 0),
            textcoords="offset points",
            ha="center" if is_central else ("right" if is_upstream else "left"),
            va="bottom" if is_central else "center",
            fontsize=9,
            fontweight="bold" if is_central else "normal",
        )
    ax.axis("off")
    return fig
