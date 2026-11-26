"""Generate the figures for the merging models guide using Model.plot().

Quarto runs this script before rendering the documentation.
To regenerate only the figures, run ``pixi run python docs/visualize_merge.py``
from the repository root.
The plots are written to ``docs/assets/merging-models``.
"""

from pathlib import Path

import matplotlib.pyplot as plt
from matplotlib.backends.backend_pdf import PdfPages
from matplotlib.lines import Line2D
from ribasim.geometry.node import Node
from ribasim.merge import ManningParameters, merge_models
from ribasim.nodes import flow_boundary, level_boundary, linear_resistance
from ribasim_testmodels import river_model
from shapely import LineString, Point

OUTPUT_DIR = Path(__file__).resolve().parent / "assets" / "merging-models"
MERGED_MODEL_ID_PREFIX = 2
MANNING = ManningParameters(
    length=100.0,
    manning_n=0.03,
    profile_width=10.0,
    profile_slope=2.0,
)


def _boundary_id(model, node_type: str) -> int:
    nodes = model.node.df
    return int(nodes.index[nodes["node_type"] == node_type][0])


def _set_node_positions(model, positions: dict[int, Point]) -> None:
    for node_id, position in positions.items():
        model.node.df.loc[node_id, "geometry"] = position

    nodes = model.node.df.geometry
    links = model.link.df
    links.geometry = [
        LineString((nodes.loc[row.from_node_id], nodes.loc[row.to_node_id]))
        for row in links.itertuples()
    ]


def _standard_join():
    first = river_model(bottoms=[10, 8], tail=True)
    second = river_model(bottoms=[6, 4], x0=3000.0, head=True)
    return (
        "Automatic boundary match",
        first,
        second,
        merge_models(first, second, manning=MANNING, id_prefix=MERGED_MODEL_ID_PREFIX),
        MERGED_MODEL_ID_PREFIX,
    )


def _explicit_join_across_gap():
    first = river_model(bottoms=[10, 8], tail=True)
    second = river_model(bottoms=[6, 4], x0=3500.0, head=True)
    pair = (
        _boundary_id(first, "LevelBoundary"),
        _boundary_id(second, "FlowBoundary"),
    )
    return (
        "Explicit pair across a gap",
        first,
        second,
        merge_models(
            first,
            second,
            pairs=[pair],
            manning=MANNING,
            id_prefix=MERGED_MODEL_ID_PREFIX,
        ),
        MERGED_MODEL_ID_PREFIX,
    )


def _two_joins():
    first = river_model(bottoms=[10, 8], tail=True)
    second = river_model(bottoms=[6, 4], x0=3000.0, head=True)

    resistance = first.linear_resistance.add(
        Node(20, Point(1000.0, 250.0)),
        [linear_resistance.Static(resistance=[1.0])],
    )
    terminal = first.level_boundary.add(
        Node(21, Point(1000.0, 500.0)),
        [level_boundary.Static(level=[8.0])],
    )
    first_basin = int(first.basin.node.df.index[0])
    first.link.add(first.basin[first_basin], resistance)
    first.link.add(resistance, terminal)

    flow = second.flow_boundary.add(
        Node(20, Point(1000.0, 500.0)),
        [flow_boundary.Static(flow_rate=[1.0])],
    )
    second_basin = int(second.basin.node.df.index[0])
    second.link.add(flow, second.basin[second_basin])

    _set_node_positions(
        first,
        {
            2: Point(2000.0, -500.0),
            3: Point(1500.0, -250.0),
            4: Point(2500.0, -250.0),
        },
    )
    _set_node_positions(
        second,
        {
            2: Point(4300.0, 800.0),
            3: Point(5300.0, 1200.0),
            4: Point(4800.0, 1000.0),
        },
    )
    merged = merge_models(
        first, second, manning=MANNING, id_prefix=MERGED_MODEL_ID_PREFIX
    )
    offset = MERGED_MODEL_ID_PREFIX * 10 ** len(str(int(second.node.df.index.max())))
    removed_a = set(first.node.df.index.difference(merged.node.df.index))
    removed_b = {
        node_id
        for node_id in second.node.df.index
        if node_id + offset not in merged.node.df.index
    }
    assert removed_a == {4, 5, 20, 21}
    assert removed_b == {1, 20}

    links = merged.link.df
    joins = set()
    for node_id in merged.node.df.index[
        merged.node.df["meta_merged"].fillna(False).astype(bool)
    ]:
        upstream = int(
            links.loc[links["to_node_id"] == node_id, "from_node_id"].iloc[0]
        )
        downstream = int(
            links.loc[links["from_node_id"] == node_id, "to_node_id"].iloc[0]
        )
        joins.add((upstream, downstream))
    assert joins == {(1, 202), (2, 202)}
    assert merged.node.df.geometry.y.nunique() > 1

    return (
        "Two boundary joins",
        first,
        second,
        merged,
        MERGED_MODEL_ID_PREFIX,
    )


def _figure(name: str, first, second, merged, merge_id_prefix: int):
    models = (first, second, merged)
    all_bounds = [model.node.df.total_bounds for model in models]
    xmin = min(bounds[0] for bounds in all_bounds)
    ymin = min(bounds[1] for bounds in all_bounds)
    xmax = max(bounds[2] for bounds in all_bounds)
    ymax = max(bounds[3] for bounds in all_bounds)
    span = max(xmax - xmin, ymax - ymin, 1.0)
    padding = span * 0.08
    bounds = (xmin - padding, xmax + padding, ymin - padding, ymax + padding)

    input_a_ids = first.node.df.index
    input_b_ids = second.node.df.index
    offset = merge_id_prefix * 10 ** len(str(int(input_b_ids.max())))
    removed_a = input_a_ids.difference(merged.node.df.index)
    removed_b = [
        node_id
        for node_id in input_b_ids
        if node_id + offset not in merged.node.df.index
    ]
    new_nodes = merged.node.df.loc[
        merged.node.df["meta_merged"].fillna(False).astype(bool)
    ].index

    fig, axes = plt.subplots(1, 2, figsize=(16, 8), constrained_layout=True)
    fig.get_layout_engine().set(rect=(0, 0.28, 1, 0.72))
    for ax, model, prefix, color, removed in (
        (axes[0], first, "A", "#2166ac", removed_a),
        (axes[0], second, "B", "#b35806", removed_b),
        (axes[1], merged, "", "#3690c0", []),
    ):
        existing_texts = len(ax.texts)
        existing_collections = len(ax.collections)
        existing_lines = len(ax.lines)
        model.plot(ax=ax, indicate_subnetworks=False)
        for text in list(ax.texts)[existing_texts:]:
            text.remove()
        if prefix:
            for collection in list(ax.collections)[existing_collections:]:
                collection.set_color(color)
            for line in list(ax.lines)[existing_lines:]:
                line.set_color(color)
        for node_id, row in model.node.df.iterrows():
            point = row.geometry
            label = f"{prefix}:{node_id}" if prefix else str(node_id)
            ax.annotate(
                label,
                (point.x, point.y),
                xytext=(12, -22)
                if prefix == "B"
                else (-5, 10)
                if prefix == "A"
                else (5, 10),
                textcoords="offset points",
                ha="right" if prefix == "A" else "left",
                color=color,
                fontsize=18,
            )
        if len(removed):
            points = model.node.df.loc[list(removed), "geometry"]
            ax.scatter(
                points.x,
                points.y,
                s=180,
                facecolors="none",
                edgecolors="#d73027",
                linewidths=2,
                zorder=4,
            )
        if ax.legend_ is not None:
            ax.legend_.remove()

    added_points = merged.node.df.loc[new_nodes, "geometry"]
    axes[1].scatter(
        added_points.x,
        added_points.y,
        s=180,
        facecolors="none",
        edgecolors="#1a9850",
        linewidths=2,
        zorder=4,
    )
    for ax, title in zip(axes, ("Inputs A and B", "Merged"), strict=True):
        ax.set_title(title, fontsize=24)
        ax.set_xlim(bounds[0], bounds[1])
        ax.set_ylim(bounds[2], bounds[3])
        ax.set_xlabel("X", fontsize=20)
        ax.set_ylabel("Y", fontsize=20)
        ax.tick_params(labelsize=18)
        ax.xaxis.get_offset_text().set_fontsize(18)
        ax.yaxis.get_offset_text().set_fontsize(18)
    title = name
    if name == "Explicit pair across a gap":
        pairs = [
            (_boundary_id(first, "LevelBoundary"), _boundary_id(second, "FlowBoundary"))
        ]
        title += f"\npairs={pairs}"
    fig.suptitle(title, fontsize=28)
    fig.legend(
        handles=[
            Line2D([], [], color="#2166ac", label="Input A"),
            Line2D([], [], color="#b35806", label="Input B"),
            Line2D(
                [],
                [],
                marker="o",
                color="#d73027",
                markerfacecolor="none",
                linestyle="none",
                markersize=10,
                label="Removed nodes",
            ),
            Line2D(
                [],
                [],
                marker="o",
                color="#1a9850",
                markerfacecolor="none",
                linestyle="none",
                markersize=10,
                label="Added nodes",
            ),
        ],
        loc="outside lower center",
        ncol=4,
        fontsize=18,
    )

    def label_node(node_id: int) -> str:
        if node_id in input_a_ids:
            return f"A:#{node_id}"
        if node_id - offset in input_b_ids:
            return f"B:#{node_id - offset}"
        return f"#{node_id}"

    links = merged.link.df
    join_details = []
    for node_id in new_nodes:
        upstream = int(
            links.loc[links["to_node_id"] == node_id, "from_node_id"].iloc[0]
        )
        downstream = int(
            links.loc[links["from_node_id"] == node_id, "to_node_id"].iloc[0]
        )
        join_details.append(
            f"#{node_id} {label_node(upstream)} -> {label_node(downstream)}"
        )
    reason = (
        f"Removed from A: {', '.join(f'#{i}' for i in removed_a) or 'none'}"
        f"   |   Removed from B: {', '.join(f'#{i}' for i in removed_b) or 'none'}"
        f"\nManning joins: {', '.join(join_details) or 'none'}"
        f"\nB retained IDs shift by +{offset}"
    )
    fig.text(0.5, 0.09, reason, ha="center", fontsize=18, linespacing=1.5)
    return fig


def main():
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    scenarios = (
        _standard_join,
        _explicit_join_across_gap,
        _two_joins,
    )
    pdf_path = OUTPUT_DIR / "merge-test-cases.pdf"
    with PdfPages(pdf_path) as pdf:
        for scenario in scenarios:
            name, first, second, merged, merge_id_prefix = scenario()
            fig = _figure(name, first, second, merged, merge_id_prefix)
            fig.savefig(OUTPUT_DIR / f"{name.lower().replace(' ', '-')}.png")
            pdf.savefig(fig)
            plt.close(fig)
    print(f"Wrote plots to {OUTPUT_DIR.resolve()}")


if __name__ == "__main__":
    main()
