"""Setup a Delwaq model from a Ribasim model and results."""

import argparse
import csv
import logging
import shutil
from datetime import timedelta
from pathlib import Path

from ribasim import nodes
from ribasim.utils import MissingOptionalModule, _concat, _pascal_to_snake

try:
    import networkx as nx
except ImportError:
    nx = MissingOptionalModule("networkx", "delwaq")

import numpy as np
import pandas as pd

try:
    import jinja2
except ImportError:
    jinja2 = MissingOptionalModule("jinja2", "delwaq")  # type: ignore

import ribasim
from ribasim.delwaq.util import (
    strfdelta,
    ugrid,
    write_flows,
    write_pointer,
    write_volumes,
)

logger = logging.getLogger(__name__)
delwaq_dir = Path(__file__).parent
output_path = delwaq_dir / "model"

env = jinja2.Environment(
    autoescape=True, loader=jinja2.FileSystemLoader(delwaq_dir / "template")
)

# Add evaporation links, so mass balance is correct
# To simulate salt increase due to evaporation, set to False
USE_EVAP = True


def _boundary_name(id, type):
    # Delwaq has a limit of 12 characters for the boundary name
    return type[:9] + "_" + str(id)


def _quote(value):
    return f"'{value}'"


def _make_boundary(data, boundary_type):
    """
    Create a Delwaq boundary definition with the given data and boundary type.

    Pivot our data from long to wide format, and convert the time to a string.
    Specifically, we go from a table:
        `node_id, substance, time, concentration`
    to
        ```
        ITEM 'Drainage_6'
        CONCENTRATIONS 'Cl' 'Tracer'
        ABSOLUTE TIME
        LINEAR DATA 'Cl' 'Tracer'
        '2020/01/01-00:00:00' 0.0  1.0
        '2020/01/02-00:00:00' 1.0 -999
        ```
    """
    bid = _boundary_name(data.node_id.iloc[0], boundary_type)
    piv = (
        data.pivot_table(
            index="time", columns="substance", values="concentration", fill_value=-999
        )
        .reset_index()
        .reset_index(drop=True)
    )
    # Convert Arrow time to Numpy to avoid needing tzdata somehow
    piv.time = piv.time.astype("datetime64[ns]").dt.strftime("%Y/%m/%d-%H:%M:%S")
    boundary = {
        "name": bid,
        "substances": list(map(_quote, piv.columns[1:])),
        "df": piv.to_string(formatters={"time": _quote}, header=False, index=False),
    }
    substances = data.substance.unique()
    return boundary, substances


def _setup_graph(nodes, link, evaporate_mass=True):
    G = nx.DiGraph()

    assert nodes.df is not None
    for row in nodes.df.itertuples():
        if row.node_type not in ribasim.geometry.link.SPATIALCONTROLNODETYPES:
            G.add_node(
                row.Index,
                type=row.node_type,
                id=row.Index,
                x=row.geometry.x,
                y=row.geometry.y,
                pos=(row.geometry.x, row.geometry.y),
            )
    assert link.df is not None
    for row in link.df.itertuples():
        if row.link_type == "flow":
            G.add_edge(
                row.from_node_id,
                row.to_node_id,
                id=[row.Index],
                duplicate=None,
            )

    # Simplify network, only keeping Basins and Boundaries.
    # We find an unwanted node, remove it,
    # and merge the flow links to/from the node.
    remove_nodes = []
    for node_id, out in G.succ.items():
        if G.nodes[node_id]["type"] not in [
            "Basin",
            "Terminal",
            "LevelBoundary",
            "FlowBoundary",
            "UserDemand",
        ]:
            inneighbor_ids = G.pred[node_id]
            remove_nodes.append(node_id)

            for inneighbor_id in inneighbor_ids:
                for outneighbor_id in out.keys():
                    if outneighbor_id in remove_nodes:
                        logger.debug("Not making link to removed node.")
                        continue
                    link = (inneighbor_id, outneighbor_id)
                    link_id = G.get_edge_data(node_id, outneighbor_id)["id"][0]
                    if G.has_edge(*link):
                        data = G.get_edge_data(*link)
                        data["id"].append(link_id)
                    else:
                        G.add_edge(*link, id=[link_id])

    iso = nx.number_of_isolates(G)
    if iso > 0:
        logger.debug(f"Found {iso} isolated nodes in the network.")
        remove_nodes.extend(list(nx.isolates(G)))

    for node_id in remove_nodes:
        G.remove_node(node_id)

    # Due to the simplification, we can end up with cycles of length 2.
    # This happens when a UserDemand is connected to and from a Basin,
    # but can also happen in other cases (rivers with a outlet and pump),
    # for which we do nothing. We merge these UserDemand cycles links to
    # a single link, and later merge the flows.
    merge_links = []
    for loop in nx.simple_cycles(G):
        if len(loop) == 2:
            if (
                G.nodes[loop[0]]["type"] != "UserDemand"
                and G.nodes[loop[1]]["type"] != "UserDemand"
            ):
                logger.debug("Found cycle that is not a UserDemand.")
            else:
                link_ids = G.edges[loop]["id"]
                G.edges[reversed(loop)]["id"].extend(link_ids)
                merge_links.extend(link_ids)
                G.remove_link(*loop)

    # Remove boundary to boundary links
    remove_double_links = []
    for x in G.edges(data=True):
        a, b, d = x
        if G.nodes[a]["type"] == "Terminal" and G.nodes[b]["type"] == "UserDemand":
            logger.debug("Removing link between Terminal and UserDemand")
            remove_double_links.append(a)
        elif G.nodes[a]["type"] == "UserDemand" and G.nodes[b]["type"] == "Terminal":
            remove_double_links.append(b)
            logger.debug("Removing link between UserDemand and Terminal")

    for node_id in remove_double_links:
        G.remove_node(node_id)

    # Relabel the nodes as consecutive integers for Delwaq
    # Note that the node["id"] is the original node_id
    basin_id = 0
    boundary_id = 0
    node_mapping = {}
    basin_mapping: dict[int, int] = {}
    for node_id, node in G.nodes.items():
        if node["type"] == "Basin":
            basin_id += 1
            node_mapping[node_id] = basin_id
            basin_mapping[node["id"]] = basin_id
        elif node["type"] in [
            "Terminal",
            "UserDemand",
            "LevelBoundary",
            "FlowBoundary",
        ]:
            boundary_id -= 1
            node_mapping[node_id] = boundary_id
        else:
            raise ValueError(f"Found unexpected node {node_id} in delwaq graph.")

    nx.relabel_nodes(G, node_mapping, copy=False)

    # Add basin boundaries
    for node_id, node in list(G.nodes(data=True)):
        if node["type"] == "Basin":
            boundary_id -= 1
            G.add_node(
                boundary_id,
                type="Drainage",
                id=node["id"],
                pos=(node["pos"][0] - 0.5, node["pos"][1] + 0.5),
            )
            G.add_edge(
                boundary_id,
                node_id,
                key=link_id,
                id=[-1],
                boundary=(node["id"], "drainage"),
            )

            boundary_id -= 1
            G.add_node(
                boundary_id,
                type="Precipitation",
                id=node["id"],
                pos=(node["pos"][0] + 0, node["pos"][1] + 0.5),
            )
            G.add_edge(
                boundary_id,
                node_id,
                key=link_id,
                id=[-1],
                boundary=(node["id"], "precipitation"),
            )

            if evaporate_mass:
                boundary_id -= 1
                G.add_node(
                    boundary_id,
                    type="Evaporation",
                    id=node["id"],
                    pos=(node["pos"][0] + 0.5, node["pos"][1] + 0.5),
                )
                G.add_edge(
                    node_id,
                    boundary_id,
                    key=link_id,
                    id=[-1],
                    boundary=(node["id"], "evaporation"),
                )

    # Setup link mapping
    link_mapping = {}
    for i, (a, b, d) in enumerate(G.edges(data=True)):
        for link_id in d["id"]:
            link_mapping[link_id] = i

    assert len(basin_mapping) == basin_id

    return G, merge_links, node_mapping, link_mapping, basin_mapping


def _setup_boundaries(model):
    boundaries = []
    substances = set()

    if model.level_boundary.concentration.df is not None:
        for _, rows in model.level_boundary.concentration.df.groupby(["node_id"]):
            boundary, substance = _make_boundary(rows, "LevelBoundary")
            boundaries.append(boundary)
            substances.update(substance)

    if model.flow_boundary.concentration.df is not None:
        for _, rows in model.flow_boundary.concentration.df.groupby("node_id"):
            boundary, substance = _make_boundary(rows, "FlowBoundary")
            boundaries.append(boundary)
            substances.update(substance)

    if model.basin.concentration.df is not None:
        for _, rows in model.basin.concentration.df.groupby(["node_id"]):
            for boundary_type in ("Drainage", "Precipitation"):
                nrows = rows.rename(columns={boundary_type.lower(): "concentration"})
                boundary, substance = _make_boundary(nrows, boundary_type)
                boundaries.append(boundary)
                substances.update(substance)

    return boundaries, substances


def generate(
    toml_path: Path,
    output_path: Path = output_path,
) -> tuple[nx.DiGraph, set[str]]:
    """Generate a Delwaq model from a Ribasim model and results."""
    # Read in model and results
    model = ribasim.Model.read(toml_path)
    results_folder = toml_path.parent / model.results_dir
    evaporate_mass = model.solver.evaporate_mass

    basins = pd.read_feather(
        toml_path.parent / results_folder / "basin.arrow", dtype_backend="pyarrow"
    )
    flows = pd.read_feather(
        toml_path.parent / results_folder / "flow.arrow", dtype_backend="pyarrow"
    )

    output_path.mkdir(exist_ok=True)

    # Setup flow network
    G, merge_links, node_mapping, link_mapping, basin_mapping = _setup_graph(
        model.node_table(), model.link, evaporate_mass=evaporate_mass
    )

    # Plot
    # plt.figure(figsize=(18, 18))
    # nx.draw(
    #     G,
    #     pos={k: v["pos"] for k, v in G.nodes(data=True)},
    #     with_labels=True,
    #     labels={k: v["id"] for k, v in G.nodes(data=True)},
    # )
    # plt.savefig("after_relabeling.png", dpi=300)

    # Setup metadata
    if model.solver.saveat == 0 or np.isposinf(model.solver.saveat):
        raise ValueError("Unsupported saveat, must be positive and finite.")
    else:
        timestep = timedelta(seconds=model.solver.saveat)

    # Write topology to delwaq pointer file
    pointer = pd.DataFrame(G.edges(), columns=["from_node_id", "to_node_id"])
    write_pointer(output_path / "ribasim.poi", pointer)
    pointer["riba_link_id"] = [e[2] for e in G.edges.data("id")]
    pointer["riba_from_node_id"] = pointer["from_node_id"].map(
        {v: k for k, v in node_mapping.items()}
    )
    pointer["riba_to_node_id"] = pointer["to_node_id"].map(
        {v: k for k, v in node_mapping.items()}
    )
    pointer.to_csv(output_path / "network.csv", index=False)  # not needed

    total_segments = len(basin_mapping)
    total_exchanges = len(pointer)

    # Write attributes template
    template = env.get_template("delwaq.atr.j2")
    with open(output_path / "ribasim.atr", mode="w") as f:
        f.write(
            template.render(
                nsegments=total_segments,
            )
        )

    # Generate mesh and write to NetCDF
    uds = ugrid(G)
    uds.ugrid.to_netcdf(output_path / "ribasim.nc")

    # Generate area and flows
    # File format is int32, float32 based
    # Time is internal clock, not real time!
    flows.time = (flows.time - flows.time[0]).dt.total_seconds().astype("int32")
    basins.time = (basins.time - basins.time[0]).dt.total_seconds().astype("int32")

    # Invert flows for half-link of cycles so later summing is correct
    m = flows.link_id.isin(merge_links)
    flows.loc[m, "flow_rate"] = flows.loc[m, "flow_rate"] * -1

    # Map link_id to the new link_id and merge any duplicate flows
    flows["riba_link_id"] = flows["link_id"]
    flows["link_id"] = flows["link_id"].map(link_mapping)
    flows.dropna(subset=["link_id"], inplace=True)
    flows["link_id"] = flows["link_id"].astype("int32")
    nflows = flows.copy()
    nflows = flows.groupby(["time", "link_id"]).sum().reset_index()
    nflows.drop(
        columns=["from_node_id", "to_node_id"],
        inplace=True,
    )

    # Add basin boundaries to flows
    for link_id, (a, b, (node_id, boundary_type)) in enumerate(
        G.edges(data="boundary", default=(None, None))
    ):
        if boundary_type is None:
            continue
        df = basins[basins.node_id == node_id][["time", boundary_type]].rename(
            columns={boundary_type: "flow_rate"}
        )
        df["link_id"] = link_id
        nflows = _concat([nflows, df], ignore_index=True)

    # Save flows to Delwaq format
    nflows.sort_values(by=["time", "link_id"], inplace=True)
    nflows.to_csv(output_path / "flows.csv", index=False)  # not needed
    nflows.drop(
        columns=["link_id", "riba_link_id"],
        inplace=True,
    )
    write_flows(output_path / "ribasim.flo", nflows, timestep)
    write_flows(
        output_path / "ribasim.are", nflows, timestep
    )  # same as flow, so area becomes 1

    # Write volumes to Delwaq format
    basins.drop(columns=["level"], inplace=True)
    volumes = basins[["time", "node_id", "storage"]]
    volumes["riba_node_id"] = volumes["node_id"]
    volumes.loc[:, "node_id"] = (
        volumes["node_id"].map(basin_mapping).astype(pd.Int32Dtype())
    )
    volumes = volumes.sort_values(by=["time", "node_id"])
    volumes.to_csv(output_path / "volumes.csv", index=False)  # not needed
    volumes.drop(columns=["node_id", "riba_node_id"], inplace=True)
    write_volumes(output_path / "ribasim.vol", volumes, timestep)
    write_volumes(
        output_path / "ribasim.vel", volumes, timestep
    )  # same as volume, so vel becomes 1

    # Length file
    lengths = nflows.copy()
    lengths.flow_rate = 1
    lengths.iloc[np.repeat(np.arange(len(lengths)), 2)]
    write_flows(output_path / "ribasim.len", lengths, timestep)

    # Find all boundary substances and concentrations
    boundaries, substances = _setup_boundaries(model)

    # Write boundary data with substances and concentrations
    template = env.get_template("B5_bounddata.inc.j2")
    with open(output_path / "B5_bounddata.inc", mode="w") as f:
        f.write(
            template.render(
                states=[],  # no states yet
                boundaries=boundaries,
            )
        )

    # Setup initial basin concentrations
    defaults = {
        "Continuity": 1.0,
        "Initial": 1.0,
        "LevelBoundary": 0.0,
        "FlowBoundary": 0.0,
        "Terminal": 0.0,
        "UserDemand": 0.0,
        "Precipitation": 0.0,
        "Drainage": 0.0,
    }
    substances.update(defaults.keys())

    # Add user defined substances
    if model.basin.concentration_state.df is not None:
        initial = model.basin.concentration_state.df
        substances.update(initial.substance.unique())

    # Make a wide table with the initial default concentrations
    # using zero for all user defined substances
    icdf = pd.DataFrame(
        data={
            substance: [defaults.get(substance, 0.0)] * len(basin_mapping)
            for substance in sorted(substances)
        },
        index=list(basin_mapping.values()),
    )

    # Override default concentrations with the user defined values
    if model.basin.concentration_state.df is not None:
        for _, row in initial.iterrows():
            icdf.loc[basin_mapping[row.node_id], row.substance] = row.concentration

    # Add comment with original Basin ID
    reverse_node_mapping = {v: k for k, v in node_mapping.items()}
    icdf["comment"] = [f"; {reverse_node_mapping[k]}" for k in icdf.index]

    initial_concentrations = icdf.to_string(header=False, index=False)

    # Write boundary list, ordered by bid to map the unique boundary names
    # to the links described in the pointer file.
    bnd = pointer.copy()
    bnd["bid"] = np.minimum(bnd["from_node_id"], bnd["to_node_id"])
    bnd = bnd[bnd["bid"] < 0]
    bnd.sort_values(by="bid", ascending=False, inplace=True)
    bnd["node_type"] = [G.nodes(data="type")[bid] for bid in bnd["bid"]]
    bnd["node_id"] = [G.nodes(data="id")[bid] for bid in bnd["bid"]]
    bnd["fid"] = list(map(_boundary_name, bnd["node_id"], bnd["node_type"]))
    bnd["comment"] = ""
    bnd.to_csv(output_path / "bndlist.csv", index=False)
    bnd = bnd[["fid", "comment", "node_type"]]
    bnd.drop_duplicates(subset="fid", inplace=True)
    assert bnd["fid"].is_unique

    bnd.to_csv(
        output_path / "ribasim_bndlist.inc",
        index=False,
        header=False,
        sep=" ",
        quotechar="'",
        quoting=csv.QUOTE_ALL,
    )

    # Setup DIMR configuration for running Delwaq via DIMR
    dimrc = delwaq_dir / "reference/dimr_config.xml"
    shutil.copy(dimrc, output_path / "dimr_config.xml")

    # Write main Delwaq input file
    template = env.get_template("delwaq.inp.j2")
    with open(output_path / "delwaq.inp", mode="w") as f:
        f.write(
            template.render(
                startime=model.starttime,
                endtime=model.endtime - timestep,
                timestep=strfdelta(timestep),
                nsegments=total_segments,
                nexchanges=total_exchanges,
                substances=sorted(substances),
                initial_concentrations=initial_concentrations,
            )
        )

    # Return the graph with original links and the substances
    # so we can parse the results back to the original model
    return G, substances


def add_tracer(model, node_id, tracer_name):
    """Add a tracer to the Delwaq model."""
    n = model.node_table().df.loc[node_id]
    node_type = n.node_type
    if node_type not in [
        "Basin",
        "LevelBoundary",
        "FlowBoundary",
        "UserDemand",
    ]:
        raise ValueError("Can only trace Basins and boundaries")
    snake_node_type = _pascal_to_snake(node_type)
    nt = getattr(model, snake_node_type)

    ct = getattr(nodes, snake_node_type)
    table = ct.Concentration(
        node_id=[node_id],
        time=[model.starttime],
        substance=[tracer_name],
        concentration=[1.0],
    )
    if nt.concentration is None:
        nt.concentration = table
    else:
        nt.concentration = pd.concat([nt.concentration.df, table.df], ignore_index=True)


if __name__ == "__main__":
    # Generate a Delwaq model from the default Ribasim model

    parser = argparse.ArgumentParser(
        description="Generate Delwaq input from Ribasim results."
    )
    parser.add_argument(
        "toml_path", type=Path, help="The path to the Ribasim TOML file."
    )
    parser.add_argument(
        "--output_path",
        type=Path,
        help="The relative path to store the Delwaq model.",
        default="delwaq",
    )
    args = parser.parse_args()

    graph, substances = generate(
        args.toml_path, args.toml_path.parent / args.output_path
    )
