import matplotlib.pyplot as plt
import numpy as np
from mpl_toolkits.axes_grid1 import make_axes_locatable


def plot_fraction(
    model,
    node_id,
    tracers=[
        "LevelBoundary",
        "FlowBoundary",
        "UserDemand",
        "Initial",
        "Drainage",
        "Precipitation",
        "SurfaceRunoff",
    ],
):
    table = model.basin.concentration_external.df
    table = table[table["node_id"] == node_id]
    table = table[table["substance"].isin(tracers)]
    if len(table) == 0:
        raise ValueError(f"No data found for node {node_id} with tracers {tracers}")

    groups = table.groupby("substance")
    stack = {k: v["concentration"].to_numpy() for (k, v) in groups}

    fig, ax = plt.subplots()
    key = next(iter(groups.groups))
    time = groups.get_group(key)["time"]
    ax.stackplot(
        time,
        stack.values(),
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

    plt.show(fig)


def plot_spatial(model, tracer="Initial", versus=None, limit=0.001):
    table = model.basin.concentration_external.df
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

    nodes = model.node_table().df
    nodes = nodes[nodes.index.isin(table.index)]

    if versus is None:
        c = table["concentration"][nodes.index]
        alpha = c > limit
    else:
        total_concentration = (
            table["concentration"][nodes.index] + vtable["concentration"][nodes.index]
        )
        c = table["concentration"][nodes.index] / total_concentration
        alpha = total_concentration / 2

    fig, ax = plt.subplots()
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

    fig.colorbar(s, cax=cax, orientation="vertical")
    if versus is not None:
        cax.set_ylabel(f"{tracer} fraction vs {versus} fraction")
    else:
        cax.set_ylabel(f"Overall {tracer} fraction")
    ax.set_xlabel("x")
    ax.set_ylabel("y")

    plt.show(fig)
