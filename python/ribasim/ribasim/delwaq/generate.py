"""Setup a Delwaq model from a Ribasim model and results."""

import argparse
import csv
import logging
import shutil
from collections import defaultdict
from datetime import timedelta
from pathlib import Path

from ribasim import Model, nodes
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
    delwaq_dir,
    is_valid_substance,
    strfdelta,
    ugrid,
    write_flows,
    write_pointer,
    write_volumes,
)

logger = logging.getLogger(__name__)

env = jinja2.Environment(
    autoescape=False, loader=jinja2.FileSystemLoader(delwaq_dir / "template")
)


def _boundary_name(id, type):
    # Delwaq has a limit of 12 characters for the boundary name
    return type.replace("_", "")[:9] + "_" + str(id)


def _quote(value):
    return f'"{value}"'


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
        data.pivot_table(index="time", columns="substance", values="concentration")
        .reset_index()
        .reset_index(drop=True)
    )
    piv.time = piv.time.dt.strftime("%Y/%m/%d-%H:%M:%S")
    boundary = {
        "name": bid,
        "substances": list(map(_quote, piv.columns[1:])),
        "df": piv.to_string(
            formatters={"time": _quote}, header=False, index=False, na_rep=-999
        ),
    }
    substances = data.substance.unique()
    assert all(map(is_valid_substance, substances)), (
        "Invalid Delwaq substance name(s) found."
    )
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
            )

    # Simplify network, only keeping Basins and Boundaries.
    # We find an unwanted node, remove it,
    # and merge the flow links to/from the node.
    # Remove Junctions first, as they can be chained
    remove_nodes = []
    for node_id, out in G.succ.items():
        if G.nodes[node_id]["type"] == "Junction":
            inneighbor_ids = G.pred[node_id]
            remove_nodes.append(node_id)

            converging = True
            if len(inneighbor_ids) > 1 and len(out) > 1:
                raise ValueError(
                    "Cannot simplify network with junctions that have multiple inflow and outflow links."
                )
            elif len(inneighbor_ids) == 1 and len(out) >= 1:
                converging = False

            for inneighbor_id in inneighbor_ids:
                for outneighbor_id in out.keys():
                    link = (inneighbor_id, outneighbor_id)
                    if converging:
                        link_id = G.get_edge_data(inneighbor_id, node_id)["id"][0]
                    else:
                        link_id = G.get_edge_data(node_id, outneighbor_id)["id"][0]
                    if G.has_edge(*link):
                        raise ValueError("Merging links would create duplicate links.")
                    else:
                        G.add_edge(*link, id=[link_id])

    for node_id in remove_nodes:
        G.remove_node(node_id)

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
    for loop in nx.simple_cycles(G, length_bound=2):
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
                G.remove_edge(*loop)

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
                id=[-1],
                boundary=(node["id"], "drainage"),
            )

            boundary_id -= 1
            G.add_node(
                boundary_id,
                type="Precipitation",
                id=node["id"],
                pos=(node["pos"][0] + -0.25, node["pos"][1] + 0.5),
            )
            G.add_edge(
                boundary_id,
                node_id,
                id=[-1],
                boundary=(node["id"], "precipitation"),
            )

            boundary_id -= 1
            G.add_node(
                boundary_id,
                type="SurfaceRunoff",
                id=node["id"],
                pos=(node["pos"][0] + 0, node["pos"][1] + 0.5),
            )
            G.add_edge(
                boundary_id,
                node_id,
                id=[-1],
                boundary=(node["id"], "surface_runoff"),
            )

            boundary_id -= 1
            G.add_node(
                boundary_id,
                type="Infiltration",
                id=node["id"],
                pos=(node["pos"][0] + 0.25, node["pos"][1] + 0.5),
            )
            G.add_edge(
                node_id,
                boundary_id,
                id=[-1],
                boundary=(node["id"], "infiltration"),
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

    if model.user_demand.concentration.df is not None:
        for _, rows in model.flow_boundary.concentration.df.groupby("node_id"):
            boundary, substance = _make_boundary(rows, "UserDemand")
            boundaries.append(boundary)
            substances.update(substance)

    if model.basin.concentration.df is not None:
        for _, rows in model.basin.concentration.df.groupby(["node_id"]):
            for boundary_type in ("Drainage", "Precipitation", "Surface_Runoff"):
                nrows = rows.rename(columns={boundary_type.lower(): "concentration"})
                boundary, substance = _make_boundary(nrows, boundary_type)
                boundaries.append(boundary)
                substances.update(substance)

    return boundaries, substances


def generate(
    model: Path | ribasim.Model,
    output_path: Path | None = None,
) -> tuple[nx.DiGraph, set[str]]:
    """Generate a Delwaq model from a Ribasim model and results."""
    # Read in model and results
    if not isinstance(model, ribasim.Model):
        model = ribasim.Model.read(model)

    evaporate_mass = model.solver.evaporate_mass

    basin_fn = model.results_path / "basin.arrow"
    assert basin_fn.exists(), f"Missing results file {basin_fn}."
    basins = pd.read_feather(basin_fn)

    flow_fn = model.results_path / "flow.arrow"
    assert flow_fn.exists(), f"Missing results file {flow_fn}."
    flows = pd.read_feather(flow_fn)

    assert len(basins) > 0, "Empty basin results file."
    assert len(flows) > 0, "Empty flows results file."
    endtime = basins.time.max()

    if output_path is None:
        assert model.filepath is not None
        output_path = model.filepath.parent / "delwaq"
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

    # Generate mesh and write to NetCDF, adding attributes to avoid Delwaq warnings
    uds = ugrid(G)
    grid = uds.ugrid.grid
    dataset = uds.ugrid.to_dataset(optional_attributes=True)
    dataset[grid.name].attrs["node_id"] = grid.node_dimension
    dataset[grid.name].attrs["node_long_name"] = "Node dimension of 1D network"
    dataset.to_netcdf(output_path / "ribasim.nc")

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
        columns=["from_node_id", "to_node_id", "convergence"],
        inplace=True,
        errors="ignore",
    )

    # Add basin boundaries to flows
    # Map all boundary node_ids to link_ids (unique per boundary type)
    lookups: defaultdict[str, dict[int, int]] = defaultdict(dict)
    dfs = []
    for link_id, (a, b, (node_id, boundary_type)) in enumerate(
        G.edges(data="boundary", default=(None, None))
    ):
        if boundary_type is None:
            continue
        lookups[boundary_type][node_id] = link_id

    for boundary_type in lookups.keys():
        df = basins[basins.node_id.isin(lookups[boundary_type].keys())][
            ["node_id", "time", boundary_type]
        ].rename(columns={boundary_type: "flow_rate"})
        df["link_id"] = df.node_id.map(lookups[boundary_type])
        df.drop(
            columns=["node_id"],
            inplace=True,
            errors="ignore",
        )
        dfs.append(df)

    nflows = _concat([nflows, *dfs], ignore_index=True)

    # Save flows to Delwaq format
    nflows.sort_values(by=["time", "link_id"], inplace=True)
    # nflows.to_csv(output_path / "flows.csv", index=False)  # not needed
    nflows.drop(
        columns=["link_id", "riba_link_id"],
        inplace=True,
    )
    write_flows(output_path / "ribasim.flo", nflows, timestep)
    write_flows(
        output_path / "ribasim.are", nflows, timestep
    )  # same as flow, so area becomes 1

    # Write volumes to Delwaq format
    volumes = basins[["time", "node_id", "storage"]]
    volumes["riba_node_id"] = volumes["node_id"]
    volumes.loc[:, "node_id"] = (
        volumes["node_id"].map(basin_mapping).astype(pd.Int32Dtype())
    )
    volumes = volumes.sort_values(by=["time", "node_id"])
    # volumes.to_csv(output_path / "volumes.csv", index=False)  # not needed
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
        "UserDemand": 0.0,
        "Precipitation": 0.0,
        "Drainage": 0.0,
        "SurfaceRunoff": 0.0,
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
    if (model.endtime - timestep) > endtime:
        logger.warning(
            f"Model endtime {model.endtime} is later than the result time {endtime}, adjusting endtime."
        )
    else:
        endtime = model.endtime

    template = env.get_template("delwaq.inp.j2")
    with open(output_path / "delwaq.inp", mode="w") as f:
        f.write(
            template.render(
                startime=model.starttime,
                endtime=endtime - timestep,
                timestep=strfdelta(timestep),
                nsegments=total_segments,
                nexchanges=total_exchanges,
                substances=sorted(substances),
                ribasim_version=ribasim.__version__,
            )
        )

    # Create wasteloads file with zero loads that can be
    # extended by the user later
    wasteloads = output_path / "B6_wasteloads.inc"
    if not wasteloads.exists():
        with open(wasteloads, mode="w") as f:
            f.write("0; Number of loads\n")

    template = env.get_template("B8_initials.inc.j2")
    with open(output_path / "B8_initials.inc", mode="w") as f:
        f.write(
            template.render(
                substances=sorted(substances),
                initial_concentrations=initial_concentrations,
            )
        )

    # Return the graph with original links and the substances
    # so we can parse the results back to the original model
    return G, substances


def add_tracer(
    model: Model, node_id: int, tracer_name: str, concentration: float = 1.0
) -> None:
    """Add a tracer to the Delwaq model."""
    if not is_valid_substance(tracer_name):
        raise ValueError(f"Invalid Delwaq substance name {tracer_name}")

    df = model.node_table().df
    assert df is not None
    n = df.loc[node_id]
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
        concentration=[concentration],
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
