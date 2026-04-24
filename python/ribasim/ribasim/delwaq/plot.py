from itertools import cycle

import matplotlib.pyplot as plt
import numpy as np
import xarray as xr
from mpl_toolkits.axes_grid1 import make_axes_locatable

DEFAULT_TRACER_COLORS = {"Initial": "darkgray"}


def _sort_tracers(tracers):
    stracers = sorted(tracers)
    if "Initial" in stracers:
        stracers.insert(0, stracers.pop(stracers.index("Initial")))
    return stracers


def plot_fraction(
    model,
    node_id,
    tracers=None,
    colors=DEFAULT_TRACER_COLORS,
    ax=None,
):
    """Plot the fraction of different tracers at a given basin node over time.

    Args:
        model (Model): The Ribasim model
        node_id (int): The ID of the basin node
        tracers (list, optional): List of tracers to plot. Defaults to None.
        colors (dict, optional): Dictionary of colors for each tracer. Defaults to DEFAULT_COLORS.
        ax (matplotlib.axes.Axes, optional): Axes object to plot on. Defaults to None.

    Raises
    ------
        ValueError: If no data is found for the specified node and tracers

    Returns
    -------
        matplotlib.axes.Axes: The Axes object with the plot
    """
    if tracers is None:
        tracers = [
            "Initial",
            "Drainage",
            "SurfaceRunoff",
            "FlowBoundary",
            "LevelBoundary",
            "Precipitation",
        ]
    ds_basin = xr.open_dataset(model.results_path / "concentration.nc")
    table = ds_basin.to_dataframe().reset_index()
    table = table[table["node_id"] == node_id]
    table = table[table["substance"].isin(tracers)]
    if len(table) == 0:
        raise ValueError(f"No data found for node {node_id} with tracers {tracers}")

    groups = table.groupby("substance")
    stack = {
        k: groups.get_group(k)["concentration"].to_numpy()
        for k in _sort_tracers(tracers)
        if k in groups.groups
    }

    if ax is None:
        _, ax = plt.subplots()
    key = next(iter(stack))
    time = groups.get_group(key)["time"]

    prop_cycle = plt.rcParams["axes.prop_cycle"]
    color_iters = cycle(prop_cycle.by_key()["color"])
    ax.stackplot(
        time,
        stack.values(),  # pyrefly: ignore[bad-argument-type]
        labels=stack.keys(),
        colors=[colors.get(k, next(color_iters)) for k in stack],
    )
    ax.plot(
        time,
        np.sum(list(stack.values()), axis=0),
        c="black",
        lw=2,
    )
    handles, labels = ax.get_legend_handles_labels()
    ax.legend(handles[::-1], labels[::-1])
    ax.set_title(f"Fraction plot for node {node_id}")
    ax.set_xlabel("Time")
    ax.set_ylabel("Fraction")

    return ax


def plot_spatial(model, tracer="Initial", versus=None, limit=0.001, ax=None):
    ds_basin = xr.open_dataset(model.results_path / "concentration.nc")
    table = ds_basin.to_dataframe().reset_index()
    table = table[table["time"] == table["time"].max()]

    if versus is not None:
        vtable = table[table["substance"] == versus]
        if len(vtable) == 0:
            raise ValueError(f"No data found for versus tracer {versus}")
        vtable.set_index("node_id", inplace=True)
    table = table[table["substance"] == tracer]
    if len(table) == 0:
        raise ValueError(f"No data found for tracer {tracer}")
    table.set_index("node_id", inplace=True)

    nodes = model.node.df
    nodes = nodes[nodes.index.isin(table.index)]

    if versus is None:
        c = table["concentration"][nodes.index]
        alpha = c > limit
    else:
        total_concentration = (
            # pyrefly: ignore[unbound-name]
            table["concentration"][nodes.index] + vtable["concentration"][nodes.index]
        )
        c = table["concentration"][nodes.index] / total_concentration
        alpha = total_concentration / 2

    if ax is None:
        _, ax = plt.subplots()
    s = ax.scatter(
        nodes.geometry.x,
        nodes.geometry.y,
        c=c,
        clim=(0, 1),
        alpha=alpha,
    )
    dt = table["time"].iloc[0]
    if versus is None:
        ax.set_title(f"Scatter plot for {tracer} tracer at {dt}")
    else:
        ax.set_title(f"Scatter plot for {tracer} vs {versus} tracer at {dt}")

    divider = make_axes_locatable(ax)
    cax = divider.append_axes("right", size="5%", pad=0.05)

    fig = ax.get_figure()
    assert fig is not None
    fig.colorbar(s, cax=cax, orientation="vertical")
    if versus is not None:
        cax.set_ylabel(f"{tracer} fraction vs {versus} fraction")
    else:
        cax.set_ylabel(f"Overall {tracer} fraction")
    ax.set_xlabel("x")
    ax.set_ylabel("y")

    return ax
