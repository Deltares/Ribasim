import matplotlib.pyplot as plt
import numpy as np
import xarray as xr
from mpl_toolkits.axes_grid1 import make_axes_locatable


def plot_fraction(
    model,
    node_id,
    tracers=None,
    ax=None,
):
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
        for k in tracers
        if k in groups.groups
    }

    if ax is None:
        _, ax = plt.subplots()
    key = next(iter(stack))
    time = groups.get_group(key)["time"]
    ax.stackplot(
        time,
        *stack.values(),  # pyright: ignore[reportArgumentType]
        labels=stack.keys(),
    )
    ax.plot(
        time,
        np.sum(list(stack.values()), axis=0),
        c="black",
        lw=2,
    )
    ax.legend()
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
            table["concentration"][nodes.index] + vtable["concentration"][nodes.index]  # pyright: ignore[reportPossiblyUnboundVariable]
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

    ax.get_figure().colorbar(s, cax=cax, orientation="vertical")  # pyright: ignore[reportOptionalMemberAccess]
    if versus is not None:
        cax.set_ylabel(f"{tracer} fraction vs {versus} fraction")
    else:
        cax.set_ylabel(f"Overall {tracer} fraction")
    ax.set_xlabel("x")
    ax.set_ylabel("y")

    return ax
