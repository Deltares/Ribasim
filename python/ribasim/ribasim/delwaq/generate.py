"""Setup a Delwaq model from a Ribasim model and results."""

import csv
import shutil
from datetime import timedelta
from pathlib import Path

from ribasim.utils import MissingOptionalModule

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

from .util import (
    strfdelta,
    ugrid,
    write_flows,
    write_pointer,
    write_volumes,
)

delwaq_dir = Path(__file__).parent

env = jinja2.Environment(
    autoescape=True, loader=jinja2.FileSystemLoader(delwaq_dir / "template")
)

# Add evaporation edges, so mass balance is correct
# To simulate salt increase due to evaporation, set to False
USE_EVAP = True


def generate(toml_path: Path) -> tuple[nx.DiGraph, set[str]]:
    """Generate a Delwaq model from a Ribasim model and results."""

    # Read in model and results
    model = ribasim.Model.read(toml_path)
    basins = pd.read_feather(toml_path.parent / "results" / "basin.arrow")
    flows = pd.read_feather(toml_path.parent / "results" / "flow.arrow")

    output_folder = delwaq_dir / "model"
    output_folder.mkdir(exist_ok=True)

    # Setup flow network
    G = nx.DiGraph()
    nodes = model.node_table()
    assert nodes.df is not None
    for row in nodes.df.itertuples():
        if row.node_type not in ribasim.geometry.edge.SPATIALCONTROLNODETYPES:
            G.add_node(
                f"{row.node_type} #{row.node_id}",
                type=row.node_type,
                id=row.node_id,
                x=row.geometry.x,
                y=row.geometry.y,
                pos=(row.geometry.x, row.geometry.y),
            )
    assert model.edge.df is not None
    for row in model.edge.df.itertuples():
        if row.edge_type == "flow":
            G.add_edge(
                f"{row.from_node_type} #{row.from_node_id}",
                f"{row.to_node_type} #{row.to_node_id}",
                id=[row.Index],
                duplicate=None,
            )

    # Simplify network, only keeping Basins and Boundaries.
    # We find an unwanted node, remove it,
    # and merge the flow edges to/from the node.
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
            assert len(inneighbor_ids) == 1
            inneighbor_id = list(inneighbor_ids)[0]
            remove_nodes.append(node_id)

            for outneighbor_id in out.keys():
                if outneighbor_id in remove_nodes:
                    print("Not making edge to removed node.")
                    continue
                edge = (inneighbor_id, outneighbor_id)
                edge_id = G.get_edge_data(node_id, outneighbor_id)["id"][0]
                if G.has_edge(*edge):
                    data = G.get_edge_data(*edge)
                    data["id"].append(edge_id)
                else:
                    G.add_edge(*edge, id=[edge_id])

    for node_id in remove_nodes:
        G.remove_node(node_id)

    # Due to the simplification, we can end up with cycles of length 2.
    # This happens when a UserDemand is connected to and from a Basin,
    # but can also happen in other cases (rivers with a outlet and pump),
    # for which we do nothing. We merge these UserDemand cycles edges to
    # a single edge, and later merge the flows.
    merge_edges = []
    for loop in nx.simple_cycles(G):
        if len(loop) == 2:
            if (
                G.nodes[loop[0]]["type"] != "UserDemand"
                and G.nodes[loop[1]]["type"] != "UserDemand"
            ):
                print("Found cycle that is not a UserDemand.")
            else:
                edge_ids = G.edges[loop]["id"]
                G.edges[reversed(loop)]["id"].extend(edge_ids)
                merge_edges.extend(edge_ids)
                G.remove_edge(*loop)

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
            raise Exception("Found unexpected node $node_id in delwaq graph.")

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
                key=edge_id,
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
                key=edge_id,
                id=[-1],
                boundary=(node["id"], "precipitation"),
            )

            if USE_EVAP:
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
                    key=edge_id,
                    id=[-1],
                    boundary=(node["id"], "evaporation"),
                )

    # Setup edge mapping
    edge_mapping = {}
    for i, (a, b, d) in enumerate(G.edges(data=True)):
        for edge_id in d["id"]:
            edge_mapping[edge_id] = i

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
    pointer.to_csv(output_folder / "network.csv", index=False)  # not needed
    write_pointer(output_folder / "ribasim.poi", pointer)

    total_segments = basin_id
    total_exchanges = len(pointer)

    # Write attributes template
    template = env.get_template("delwaq.atr.j2")
    with open(output_folder / "ribasim.atr", mode="w") as f:
        f.write(
            template.render(
                nsegments=total_segments,
            )
        )

    # Generate mesh and write to NetCDF
    uds = ugrid(G)
    uds.ugrid.to_netcdf(output_folder / "ribasim.nc")

    # Generate area and flows
    # File format is int32, float32 based
    # Time is internal clock, not real time!
    flows.time = (flows.time - flows.time[0]).dt.total_seconds().astype("int32")
    basins.time = (basins.time - basins.time[0]).dt.total_seconds().astype("int32")

    # Invert flows for half-edge of cycles so later summing is correct
    m = flows.edge_id.isin(merge_edges)
    flows.loc[m, "flow_rate"] = flows.loc[m, "flow_rate"] * -1

    # Map edge_id to the new edge_id and merge any duplicate flows
    flows["edge_id"] = flows["edge_id"].map(edge_mapping)
    flows.dropna(subset=["edge_id"], inplace=True)
    flows["edge_id"] = flows["edge_id"].astype("int32")
    nflows = flows.copy()
    nflows = flows.groupby(["time", "edge_id"]).sum().reset_index()
    nflows.drop(
        columns=["from_node_id", "from_node_type", "to_node_id", "to_node_type"],
        inplace=True,
    )

    # Add basin boundaries to flows
    for edge_id, (a, b, (node_id, boundary_type)) in enumerate(
        G.edges(data="boundary", default=(None, None))
    ):
        if boundary_type is None:
            continue
        df = basins[basins.node_id == node_id][["time", boundary_type]].rename(
            columns={boundary_type: "flow_rate"}
        )
        df["edge_id"] = edge_id
        nflows = pd.concat([nflows, df], ignore_index=True)

    # Save flows to Delwaq format
    nflows.sort_values(by=["time", "edge_id"], inplace=True)
    nflows.to_csv(output_folder / "flows.csv", index=False)  # not needed
    nflows.drop(
        columns=["edge_id"],
        inplace=True,
    )
    write_flows(output_folder / "ribasim.flo", nflows, timestep)
    write_flows(
        output_folder / "ribasim.are", nflows, timestep
    )  # same as flow, so area becomes 1

    # Write volumes to Delwaq format
    basins.drop(columns=["level"], inplace=True)
    volumes = basins[["time", "node_id", "storage"]]
    volumes.loc[:, "node_id"] = (
        volumes["node_id"].map(basin_mapping).astype(pd.Int32Dtype())
    )
    volumes = volumes.sort_values(by=["time", "node_id"])
    volumes.to_csv(output_folder / "volumes.csv", index=False)  # not needed
    volumes.drop(columns=["node_id"], inplace=True)
    write_volumes(output_folder / "ribasim.vol", volumes, timestep)
    write_volumes(
        output_folder / "ribasim.vel", volumes, timestep
    )  # same as volume, so vel becomes 1

    # Length file
    lengths = nflows.copy()
    lengths.flow_rate = 1
    lengths.iloc[np.repeat(np.arange(len(lengths)), 2)]
    write_flows(output_folder / "ribasim.len", lengths, timestep)

    # Find all boundary substances and concentrations
    boundaries = []
    substances = set()

    def boundary_name(id, type):
        # Delwaq has a limit of 12 characters for the boundary name
        return type[:9] + "_" + str(id)

    def quote(value):
        return f"'{value}'"

    def make_boundary(data, boundary_type):
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
        bid = boundary_name(data.node_id.iloc[0], boundary_type)
        piv = (
            data.pivot_table(index="time", columns="substance", values="concentration")
            .reset_index()
            .reset_index(drop=True)
        )
        piv.time = piv.time.dt.strftime("%Y/%m/%d-%H:%M:%S")
        boundary = {
            "name": bid,
            "substances": list(map(quote, piv.columns[1:])),
            "df": piv.to_string(
                formatters={"time": quote}, header=False, index=False, na_rep=-999
            ),
        }
        substances = data.substance.unique()
        return boundary, substances

    if model.level_boundary.concentration.df is not None:
        for _, rows in model.level_boundary.concentration.df.groupby(["node_id"]):
            boundary, substance = make_boundary(rows, "LevelBoundary")
            boundaries.append(boundary)
            substances.update(substance)

    if model.flow_boundary.concentration.df is not None:
        for _, rows in model.flow_boundary.concentration.df.groupby("node_id"):
            boundary, substance = make_boundary(rows, "FlowBoundary")
            boundaries.append(boundary)
            substances.update(substance)

    if model.basin.concentration.df is not None:
        for _, rows in model.basin.concentration.df.groupby(["node_id"]):
            for boundary_type in ("Drainage", "Precipitation"):
                nrows = rows.rename(columns={boundary_type.lower(): "concentration"})
                boundary, substance = make_boundary(nrows, boundary_type)
                boundaries.append(boundary)
                substances.update(substance)

    # Write boundary data with substances and concentrations
    template = env.get_template("B5_bounddata.inc.j2")
    with open(output_folder / "B5_bounddata.inc", mode="w") as f:
        f.write(
            template.render(
                states=[],  # no states yet
                boundaries=boundaries,
            )
        )

    # Setup initial basin concentrations
    defaults = {
        "Continuity": 1.0,
        "Basin": 0.0,
        "LevelBoundary": 0.0,
        "FlowBoundary": 0.0,
        "Terminal": 0.0,
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
    # to the edges described in the pointer file.
    bnd = pointer.copy()
    bnd["bid"] = np.minimum(bnd["from_node_id"], bnd["to_node_id"])
    bnd = bnd[bnd["bid"] < 0]
    bnd.sort_values(by="bid", ascending=False, inplace=True)
    bnd["node_type"] = [G.nodes(data="type")[bid] for bid in bnd["bid"]]
    bnd["node_id"] = [G.nodes(data="id")[bid] for bid in bnd["bid"]]
    bnd["fid"] = list(map(boundary_name, bnd["node_id"], bnd["node_type"]))
    bnd["comment"] = ""
    bnd = bnd[["fid", "comment", "node_type"]]
    bnd.to_csv(
        output_folder / "ribasim_bndlist.inc",
        index=False,
        header=False,
        sep=" ",
        quotechar="'",
        quoting=csv.QUOTE_ALL,
    )

    # Setup DIMR configuration for running Delwaq via DIMR
    dimrc = delwaq_dir / "reference/dimr_config.xml"
    shutil.copy(dimrc, output_folder / "dimr_config.xml")

    # Write main Delwaq input file
    template = env.get_template("delwaq.inp.j2")
    with open(output_folder / "delwaq.inp", mode="w") as f:
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

    # Return the graph with original edges and the substances
    # so we can parse the results back to the original model
    return G, substances


if __name__ == "__main__":
    # Generate a Delwaq model from the default Ribasim model
    repo_dir = delwaq_dir.parents[1]
    toml_path = repo_dir / "generated_testmodels/basic/ribasim.toml"
    graph, substances = generate(toml_path)
