"""Setup a Delwaq model from a Ribasim model and results."""

import csv
import shutil
from datetime import timedelta
from pathlib import Path

import networkx as nx
import numpy as np
import pandas as pd
import ribasim
from jinja2 import Environment, FileSystemLoader
from util import (
    strfdelta,
    ugrid,
    write_flows,
    write_pointer,
    write_volumes,
)

delwaq_dir = Path(__file__).parent

env = Environment(autoescape=True, loader=FileSystemLoader(delwaq_dir / "template"))

# Add evaporation edges, so mass balance is correct
# To simulate salt increase due to evaporation, set to False
USE_EVAP = True


def generate(modelfn: Path) -> tuple[nx.DiGraph, set[str]]:
    """Generate a Delwaq model from a Ribasim model and results."""

    # Read in model and results
    model = ribasim.Model.read(modelfn)
    basins = pd.read_feather(modelfn.parent / "results" / "basin.arrow")
    flows = pd.read_feather(modelfn.parent / "results" / "flow.arrow")

    output_folder = delwaq_dir / "model"
    output_folder.mkdir(exist_ok=True)

    # Simplify network, only keep Basins and Boundaries
    G = nx.DiGraph()
    for row in model.node_table().df.itertuples():
        if "Control" not in row.node_type:
            G.add_node(
                row.node_id,
                type=row.node_type,
                id=row.node_id,
                x=row.geometry.x,
                y=row.geometry.y,
                pos=(row.geometry.x, row.geometry.y),
            )
    for row in model.edge.df.itertuples():
        if row.edge_type == "flow":
            G.add_edge(row.from_node_id, row.to_node_id, id=[row.Index], duplicate=None)

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

    merge_edges = []
    for loop in nx.simple_cycles(G):
        if len(loop) == 2:
            if (
                G.nodes[loop[0]]["type"] != "UserDemand"
                and G.nodes[loop[1]]["type"] != "UserDemand"
            ):
                print("Found cycle that is not a UserDemand.")
            else:
                edge_ids = G.edges[*loop]["id"]
                G.edges[*reversed(loop)]["id"].extend(edge_ids)
                merge_edges.extend(edge_ids)
                G.remove_edge(*loop)

    # Relabel as consecutive integers
    basin_id = 0
    boundary_id = 0
    node_mapping = {}
    for node_id, node in G.nodes.items():
        if node["type"] == "Basin":
            basin_id += 1
            node_mapping[node_id] = basin_id
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
                pos=(node["pos"][0] - 0.2, node["pos"][1] + 0.2),
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
                pos=(node["pos"][0] + 0, node["pos"][1] + 0.2),
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
                    pos=(node["pos"][0] + 0.2, node["pos"][1] + 0.2),
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
    # nx.draw(
    #     G,
    #     pos={k: v["pos"] for k, v in G.nodes(data=True)},
    #     with_labels=True,
    #     labels={k: v["id"] for k, v in G.nodes(data=True)},
    # )

    # Setup metadata
    if model.solver.saveat == 0 or np.isposinf(model.solver.saveat):
        raise ValueError("Unsupported saveat, must be positive and finite.")
    else:
        timestep = timedelta(seconds=model.solver.saveat)

    # Write topology to d file
    pointer = pd.DataFrame(G.edges(), columns=["from_node_id", "to_node_id"])
    pointer.to_csv(output_folder / "network.csv", index=False)  # not needed
    write_pointer(output_folder / "ribasim.poi", pointer)

    # nboundary = abs(boundary_id)
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

    flows["edge_id"] = flows["edge_id"].map(edge_mapping)
    flows.dropna(subset=["edge_id"], inplace=True)
    flows["edge_id"] = flows["edge_id"].astype("int32")
    nflows = flows.copy()
    nflows = flows.groupby(["time", "edge_id"]).sum().reset_index()
    nflows.drop(
        columns=["from_node_id", "from_node_type", "to_node_id", "to_node_type"],
        inplace=True,
    )

    # Add basin boundaries
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
    nflows.sort_values(by=["time", "edge_id"], inplace=True)
    nflows.to_csv(output_folder / "flows.csv", index=False)  # not needed
    nflows.drop(
        columns=["edge_id"],
        inplace=True,
    )
    write_flows(output_folder / "ribasim.flo", nflows, timestep)
    # nflows.loc[:, "flow_rate"] = 1  # m/s
    write_flows(
        output_folder / "ribasim.are", nflows, timestep
    )  # same as flow, so velocity becomes 1 m/s

    basins.drop(columns=["level"], inplace=True)
    volumes = basins[["time", "node_id", "storage"]]
    volumes.loc[:, "node_id"] = (
        volumes["node_id"].map(node_mapping).astype(pd.Int32Dtype())
    )
    volumes = volumes.sort_values(by=["time", "node_id"])
    volumes.to_csv(output_folder / "volumes.csv", index=False)  # not needed
    volumes.drop(columns=["node_id"], inplace=True)
    write_volumes(output_folder / "ribasim.vol", volumes, timestep)
    # volumes.loc[:, "storage"] = 1  # m/s
    write_volumes(output_folder / "ribasim.vel", volumes, timestep)

    # Length file
    # Timestep and flattened (2, nsegments) of identical lengths
    # for left right, so 0, 1., 1., 3., 3., 4., 4. etc.
    # TODO(Maarten) Make use of geometry to calculate lengths
    lengths = nflows.copy()
    lengths.flow_rate = 1
    lengths.iloc[np.repeat(np.arange(len(lengths)), 2)]
    write_flows(output_folder / "ribasim.len", lengths, timestep)

    # Find our boundaries
    boundaries = []
    substances = set()

    def make_boundary(id, type):
        return type[:9] + "_" + str(id)

    assert model.level_boundary.concentration.df is not None
    for i, row in model.level_boundary.concentration.df.groupby(["node_id"]):
        row = row.drop_duplicates(subset=["substance"])
        bid = make_boundary(row.node_id.iloc[0], "LevelBoundary")
        boundaries.append(
            {
                "name": bid,
                "concentrations": row.concentration.to_list(),
                "substances": row.substance.to_list(),
            }
        )
        substances.update(row.substance)

    assert model.flow_boundary.concentration.df is not None
    for i, row in model.flow_boundary.concentration.df.groupby("node_id"):
        row = row.drop_duplicates(subset=["substance"])
        bid = make_boundary(row.node_id.iloc[0], "FlowBoundary")
        boundaries.append(
            {
                "name": bid,
                "concentrations": row.concentration.to_list(),
                "substances": row.substance.to_list(),
            }
        )
        substances.update(row.substance)

    template = env.get_template("B5_bounddata.inc.j2")
    with open(output_folder / "B5_bounddata.inc", mode="w") as f:
        f.write(
            template.render(
                states=[],  # no states yet
                boundaries=boundaries,
            )
        )

    bnd = pointer.copy()
    bnd["bid"] = np.minimum(bnd["from_node_id"], bnd["to_node_id"])
    bnd = bnd[bnd["bid"] < 0]
    bnd.sort_values(by="bid", ascending=False, inplace=True)
    bnd["node_type"] = [G.nodes(data="type")[bid] for bid in bnd["bid"]]
    bnd["node_id"] = [G.nodes(data="id")[bid] for bid in bnd["bid"]]
    bnd["fid"] = list(map(make_boundary, bnd["node_id"], bnd["node_type"]))
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

    dimrc = delwaq_dir / "reference/dimr_config.xml"
    shutil.copy(dimrc, output_folder / "dimr_config.xml")

    # Write input template
    template = env.get_template("delwaq.inp.j2")
    with open(output_folder / "delwaq.inp", mode="w") as f:
        f.write(
            template.render(
                startime=model.starttime,
                endtime=model.endtime - timestep,
                timestep=strfdelta(timestep),
                nsegments=total_segments,
                nexchanges=total_exchanges,
                substances=substances,
            )
        )
    return G, substances


if __name__ == "__main__":
    # Generate a Delwaq model from the default Ribasim model
    repo_dir = delwaq_dir.parents[1]
    modelfn = repo_dir / "generated_testmodels/basic/ribasim.toml"
    graph, substances = generate(modelfn)
