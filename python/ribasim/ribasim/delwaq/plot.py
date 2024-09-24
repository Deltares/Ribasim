import matplotlib.pyplot as plt
from mpl_toolkits.axes_grid1 import make_axes_locatable


def plot_fraction(
    model,
    node_id,
    tracers=["Basin", "LevelBoundary", "FlowBoundary", "UserDemand", "Initial"],
):
    table = model.basin.concentration_external.df
    table = table[table["node_id"] == node_id]
    table = table[table["substance"].isin(tracers)]

    groups = table.groupby("substance")
    stack = {k: v["concentration"].to_numpy() for (k, v) in groups}

    fig, ax = plt.subplots()
    ax.stackplot(
        groups.get_group(tracers[0])["time"],
        stack.values(),
        labels=stack.keys(),
    )
    ax.legend()
    ax.set_title(f"Fraction plot for node {node_id}")
    ax.set_xlabel("Time")
    ax.set_ylabel("Fraction")

    plt.show(fig)


def plot_spatial(model, tracer="Basin"):
    table = model.basin.concentration_external.df
    table = table[table["substance"] == tracer]
    table = table[table["time"] == table["time"].max()]
    table.set_index("node_id", inplace=True)

    nodes = model.node_table().df
    nodes = nodes[nodes.index.isin(table.index)]

    fig, ax = plt.subplots()
    s = ax.scatter(
        nodes.geometry.x,
        nodes.geometry.y,
        c=table["concentration"][nodes.index],
        clim=(0, 1),
    )
    ax.legend()
    ax.set_title(f"Scatter plot for {tracer} tracer at {table["time"].iloc[0]}")

    divider = make_axes_locatable(ax)
    cax = divider.append_axes("right", size="5%", pad=0.05)

    fig.colorbar(s, cax=cax, orientation="vertical")
    ax.set_xlabel("x")
    ax.set_ylabel("y")

    plt.show(fig)
