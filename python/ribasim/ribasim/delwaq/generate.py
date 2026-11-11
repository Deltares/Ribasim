"""
Generate Delwaq input from Ribasim results.

Can be used as a command line tool:

usage: generate.py [-h] [--output_path OUTPUT_PATH] [-v] toml_path

positional arguments:
  toml_path             The path to the Ribasim TOML file.

options:
  -h, --help            show this help message and exit
  --output_path OUTPUT_PATH
                        The relative path to store the Delwaq model.
  -v, --verbose         Increase verbosity (-v for info, -vv for debug).
"""

import argparse
import csv
import logging
import shutil
from collections import defaultdict
from datetime import timedelta
from pathlib import Path
from typing import Any, cast

from ribasim import Model, nodes
from ribasim.config import Verbosity
from ribasim.utils import (
    MissingOptionalModule,
    _concat,
    _pascal_to_snake,
)

try:
    import networkx as _nx
except ImportError:
    _nx = MissingOptionalModule("networkx", "delwaq")

import numpy as np
import pandas as pd
import xarray as xr

from ribasim.geometry.link import SPATIALCONTROLNODETYPES

try:
    import jinja2 as _jinja2
except ImportError:
    _jinja2 = MissingOptionalModule("jinja2", "delwaq")

import ribasim
from ribasim.delwaq.util import (
    check_substance_uniqueness,
    delwaq_dir,
    is_valid_substance,
    strfdelta,
    ugrid,
    write_flows,
    write_pointer,
    write_volumes,
)

logger = logging.getLogger(__name__)

jinja2 = cast(Any, _jinja2)
env = jinja2.Environment(
    autoescape=False, loader=jinja2.FileSystemLoader(delwaq_dir / "template")
)


def _boundary_name(id, type):
    # Delwaq has a limit of 12 characters for the boundary name
    return type.replace("_", "")[:9] + "_" + str(id)


def _quote(value):
    return f'"{value}"'


def _make_boundary(data, boundary_type, values="concentration"):
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
        data.pivot_table(index="time", columns="substance", values=values)
        .reset_index()
        .reset_index(drop=True)
    )
    piv.time = piv.time.dt.strftime("%Y/%m/%d-%H:%M:%S")
    boundary = {
        "name": bid,
        "substances": list(map(_quote, piv.columns[1:])),
        "df": piv.to_string(
            formatters={"time": _quote},
            float_format="{:.9g}".format,
            header=False,
            index=False,
            na_rep=-999,
        ),
    }
    substances = data.substance.unique()
    assert all(map(is_valid_substance, substances)), (
        "Invalid Delwaq substance name(s) found."
    )
    return boundary, substances


def _junction_term_flows(G, flows: pd.DataFrame) -> pd.DataFrame | None:
    """Compute the flows over the links that bypass the Junction nodes that divide the flow, see ``_setup_graph``.

    Each term is the flow of a link into such a Junction node, times the share of each
    outflow link of the Junction along the way: the flow of that link divided by the total
    outflow of the Junction node, per timestep. The result has the Delwaq link index as
    ``link_id``, like the mapped flows.
    """
    wide = flows.pivot_table(
        index="time", columns="link_id", values="flow_rate", aggfunc="sum"
    )
    dfs = []
    for i, (_a, _b, d) in enumerate(G.edges(data=True)):
        terms = d.get("terms")
        if not terms:
            continue
        total = np.zeros(len(wide.index))
        for base, ratios, sign in terms:
            contribution = sign * wide[base].to_numpy(dtype=float)
            for numerator_ids, denominator_ids in ratios:
                numerator = wide[numerator_ids].sum(axis=1).to_numpy(dtype=float)
                denominator = wide[denominator_ids].sum(axis=1).to_numpy(dtype=float)
                share = np.divide(
                    numerator,
                    denominator,
                    out=np.zeros_like(numerator),
                    where=denominator != 0,
                )
                contribution = contribution * share
            total += contribution
        dfs.append(pd.DataFrame({"time": wide.index, "link_id": i, "flow_rate": total}))
    return _concat(dfs, ignore_index=True) if dfs else None


def _setup_graph(nodes, link, evaporate_mass=True, routed_junction_ids=frozenset()):
    """Set up the Delwaq network graph from the Ribasim nodes and links.

    ``routed_junction_ids`` are the Junction nodes with rows in `Junction / static`, which
    divide the flow or supply a UserDemand. They are removed with the flow per source,
    unlike the other Junction nodes, which only connect their neighbors.
    """
    nx = cast(Any, _nx)
    G = nx.DiGraph()

    for row in nodes.df.itertuples():
        if row.node_type not in SPATIALCONTROLNODETYPES:
            G.add_node(
                row.Index,
                type=row.node_type,
                routed=row.Index in routed_junction_ids,
                id=row.Index,
                x=row.geometry.x,
                y=row.geometry.y,
                pos=(row.geometry.x, row.geometry.y),
            )
    for row in link.df.itertuples():
        if row.link_type == "flow":
            G.add_edge(
                row.from_node_id,
                row.to_node_id,
                id=[row.Index],
            )

    # The links into each UserDemand, whose flows add up to its abstraction
    user_demand_inflow_ids = {
        node_id: [
            link_id for _, _, d in G.in_edges(node_id, data=True) for link_id in d["id"]
        ]
        for node_id, node_type in G.nodes(data="type")
        if node_type == "UserDemand"
    }

    # Simplify network, only keeping Basins and Boundaries.
    # We find an unwanted node, remove it,
    # and merge the flow links to/from the node.
    # Remove Junctions first, as they can be chained
    # A connected group of Junctions with one Basin connects its other neighbors to
    # that Basin, and the flow is the one on the link of the neighbor with the group.
    junction_ids = [
        n for n, d in G.nodes(data=True) if d["type"] == "Junction" and not d["routed"]
    ]
    for group in list(nx.weakly_connected_components(G.subgraph(junction_ids))):
        basin_ids = {
            neighbor
            for node_id in group
            for neighbor in nx.all_neighbors(G, node_id)
            if G.nodes[neighbor]["type"] == "Basin"
        }
        if len(basin_ids) != 1:
            continue
        basin_id = basin_ids.pop()
        new_links = []
        for node_id in group:
            for neighbor, data in G.pred[node_id].items():
                if neighbor not in group and neighbor != basin_id:
                    new_links.append((neighbor, basin_id, data["id"]))
            for neighbor, data in G.succ[node_id].items():
                if neighbor not in group and neighbor != basin_id:
                    new_links.append((basin_id, neighbor, data["id"]))
        for from_id, to_id, link_ids in new_links:
            if G.has_edge(from_id, to_id):
                raise ValueError("Merging links would create duplicate links.")
            G.add_edge(from_id, to_id, id=link_ids)
        G.remove_nodes_from(group)

    remove_nodes = []
    for node_id, out in G.succ.items():
        if G.nodes[node_id]["type"] == "Junction" and not G.nodes[node_id]["routed"]:
            inneighbor_ids = G.pred[node_id]
            remove_nodes.append(node_id)

            converging = True
            n_in = len(set(inneighbor_ids.keys()) - set(remove_nodes))
            n_out = len(set(out.keys()) - set(remove_nodes))
            if n_in > 1 and n_out > 1:
                raise ValueError(
                    f"Cannot simplify network for Junction #{node_id} that has multiple inflow ({list(inneighbor_ids.keys())}) and outflow ({list(out.keys())}) links."
                )
            elif n_in == 1 and n_out >= 1:
                converging = False

            for inneighbor_id in inneighbor_ids:
                for outneighbor_id in out:
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

    # Remove the Junction nodes that divide the flow or supply a UserDemand next. They have no
    # storage, so the flow over each link into such a Junction is passed on over its outflow
    # links in proportion to their flows. A link that bypasses the Junction therefore carries
    # the flow of the link into the node times the share of the outflow link, per timestep:
    # see `_junction_term_flows`. Such a link has `terms` instead of `id`:
    # (link_id, [(numerator link ids, denominator link ids), ...], sign).
    # Upstream nodes are removed first, so that the terms compose along chains.
    #
    # A UserDemand passes on water in the same way: its return flow carries the concentrations
    # of the water it abstracted. Each link into a UserDemand is passed on over its return
    # links, with the share of the return flow in the abstraction. The UserDemand stays in the
    # network as a boundary, that only receives the water it consumes: the links into it get
    # the passed on flow as negative terms.
    routed_ids = [
        n for n, d in G.nodes(data=True) if d["routed"] or d["type"] == "UserDemand"
    ]
    while routed_ids:
        node_id = next(
            (n for n in routed_ids if not any(m in routed_ids for m in G.pred[n])),
            None,
        )
        if node_id is None:
            raise ValueError(
                f"Cannot simplify network with a cycle of UserDemand and Junction nodes: {routed_ids}."
            )
        routed_ids.remove(node_id)
        is_user_demand = G.nodes[node_id]["type"] == "UserDemand"
        out_edges = list(G.out_edges(node_id, data=True))
        if is_user_demand:
            denominator = user_demand_inflow_ids[node_id]
        else:
            denominator = [link_id for _, _, d in out_edges for link_id in d["id"]]
        for in_id, _, d_in in list(G.in_edges(node_id, data=True)):
            in_terms = [
                *d_in.get("terms", []),
                *((link_id, [], 1) for link_id in d_in["id"]),
            ]
            for _, out_id, d_out in out_edges:
                ratio = (list(d_out["id"]), denominator)
                new_terms = [
                    (base, [*ratios, ratio], sign) for base, ratios, sign in in_terms
                ]
                if G.has_edge(in_id, out_id):
                    G.edges[in_id, out_id].setdefault("terms", []).extend(new_terms)
                else:
                    G.add_edge(in_id, out_id, id=[], terms=new_terms)
                if is_user_demand:
                    d_in.setdefault("terms", []).extend(
                        (base, ratios, -sign) for base, ratios, sign in new_terms
                    )
        if is_user_demand:
            G.remove_edges_from(list(G.out_edges(node_id)))
        else:
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
                for outneighbor_id in out:
                    if outneighbor_id in remove_nodes:
                        logger.debug("Not making link to removed node.")
                        continue
                    link = (inneighbor_id, outneighbor_id)
                    d_out = G.get_edge_data(node_id, outneighbor_id)
                    if G.has_edge(*link):
                        data = G.get_edge_data(*link)
                        data["id"].extend(d_out["id"])
                        data.setdefault("terms", []).extend(d_out.get("terms", []))
                    else:
                        G.add_edge(
                            *link,
                            id=list(d_out["id"]),
                            terms=list(d_out.get("terms", [])),
                        )

    for node_id in remove_nodes:
        G.remove_node(node_id)

    # Water that returns to where it came from, through a UserDemand, needs no link
    G.remove_edges_from(list(nx.selfloop_edges(G)))

    # Remove boundary to boundary links
    remove_double_boundary = []
    boundary_nodes = [
        "Terminal",
        "LevelBoundary",
        "FlowBoundary",
        "UserDemand",
    ]
    for x in G.edges(data=True):
        a, b, d = x
        if (
            G.nodes[a]["type"] in boundary_nodes
            and G.nodes[b]["type"] in boundary_nodes
        ):
            logger.debug(
                f"Removing link between {G.nodes[a]['type']} #{G.nodes[a]['id']} and {G.nodes[b]['type']} #{G.nodes[b]['id']}."
            )
            remove_double_boundary.append((a, b))

    for edge in remove_double_boundary:
        G.remove_edge(*edge)

    remove_nodes = [
        node_id for node_id in nx.isolates(G) if G.nodes[node_id]["type"] != "Basin"
    ]

    for node_id in remove_nodes:
        logger.debug(
            f"Removing isolated {G.nodes[node_id]['type']} #{node_id} from the network."
        )
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
    for i, (_a, _b, d) in enumerate(G.edges(data=True)):
        for link_id in d["id"]:
            link_mapping[link_id] = i

    assert len(basin_mapping) == basin_id

    return G, node_mapping, link_mapping, basin_mapping


def _setup_boundaries(model, node_mapping):
    concentrations = []
    mass_load = []
    substances = set()

    if model.level_boundary.concentration.df is not None:
        for _, rows in model.level_boundary.concentration.df.groupby(["node_id"]):
            boundary, substance = _make_boundary(rows, "LevelBoundary")
            concentrations.append(boundary)
            substances.update(substance)

    if model.flow_boundary.concentration.df is not None:
        for _, rows in model.flow_boundary.concentration.df.groupby("node_id"):
            boundary, substance = _make_boundary(rows, "FlowBoundary")
            concentrations.append(boundary)
            substances.update(substance)

    if model.basin.concentration.df is not None:
        for _, rows in model.basin.concentration.df.groupby(["node_id"]):
            for boundary_type in ("Drainage", "Precipitation", "Surface_Runoff"):
                nrows = rows.rename(columns={boundary_type.lower(): "concentration"})
                boundary, substance = _make_boundary(nrows, boundary_type)
                concentrations.append(boundary)
                substances.update(substance)

    if model.basin.mass_load.df is not None:
        for node_id, rows in model.basin.mass_load.df.groupby(["node_id"]):
            boundary, substance = _make_boundary(rows, "Basin", "load")
            boundary["node_id"] = node_mapping[node_id[0]]
            mass_load.append(boundary)
            substances.update(substance)

    return concentrations, substances, mass_load


def generate(
    model: Path | Model,
    output_path: Path | None = None,
) -> Model:
    """Generate a Delwaq model from a Ribasim model and results.

    Substance and process specific input is written to the ``include`` subfolder
    of ``output_path``, so other water quality simulations can be set up by
    replacing these files rather than editing ``delwaq.inp``.
    Only the empty ``B7_*.inc`` process files can be replaced independently;
    ``B1_substances.inc``, ``B5_bounddata.inc``, ``B6_wasteloads.inc`` and
    ``B8_initials.inc`` all depend on the substances found in the Ribasim model,
    and must be kept consistent when substances are added.

    Every call overwrites all generated files, including those in ``include``.
    """
    # Read in model and results
    if not isinstance(model, Model):
        model = Model.read(model)

    evaporate_mass = model.solver.evaporate_mass

    basin_fn = model.results_path / "basin.nc"
    assert basin_fn.exists(), f"Missing results file {basin_fn}."
    basins = xr.open_dataset(basin_fn).to_dataframe().reset_index()

    flow_fn = model.results_path / "flow.nc"
    assert flow_fn.exists(), f"Missing results file {flow_fn}."
    flows = xr.open_dataset(flow_fn)["flow_rate"].to_dataframe().reset_index()

    assert len(basins) > 0, "Empty basin results file."
    assert len(flows) > 0, "Empty flows results file."
    endtime = basins.time.max()

    if output_path is None:
        assert model.filepath is not None
        output_path = model.filepath.parent / "delwaq"
    output_path.mkdir(exist_ok=True)

    include_path = output_path / "include"
    include_path.mkdir(exist_ok=True)

    # Setup flow network
    G, node_mapping, link_mapping, basin_mapping = _setup_graph(
        model.node,
        model.link,
        evaporate_mass=evaporate_mass,
        routed_junction_ids=model.junction._routed_node_ids(),
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
    # For links that bypass Junction nodes that divide the flow, the links into these Junction nodes
    pointer["riba_link_id"] = [
        d["id"] + [base for base, _, _ in d.get("terms", [])]
        for _, _, d in G.edges(data=True)
    ]
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
    with (output_path / "ribasim.atr").open(mode="w") as f:
        f.write(
            template.render(
                nsegments=total_segments,
            )
        )

    # Generate mesh and write to NetCDF, adding attributes to avoid Delwaq warnings.
    # The dataset is written further down, once the substance set is complete, so
    # the graph mapping (node_id <-> ribasim_node_id) and substances are stored
    # alongside the mesh for parsing the results back.
    uds = ugrid(G, crs=model.crs)
    grid = uds.ugrid.grid
    dataset = uds.ugrid.to_dataset(optional_attributes=True)
    grid_name = cast(Any, grid).name
    dataset[grid_name].attrs["node_id"] = grid.node_dimension
    dataset[grid_name].attrs["node_long_name"] = "Node dimension of 1D network"

    # Generate area and flows
    # File format is int32, float32 based
    # Time is internal clock, not real time!
    flows["time"] = (
        (flows["time"] - flows["time"].iloc[0]).dt.total_seconds().astype("int32")
    )
    basins["time"] = (
        (basins["time"] - basins["time"].iloc[0]).dt.total_seconds().astype("int32")
    )

    # The flows over links that bypass the UserDemand nodes and the Junction nodes that divide
    # the flow are computed from the original flows
    term_flows = _junction_term_flows(G, flows)

    # Map link_id to the new link_id and merge any duplicate flows
    flows["riba_link_id"] = flows["link_id"]
    flows["link_id"] = flows["link_id"].map(link_mapping)
    flows.dropna(subset=["link_id"], inplace=True)
    flows["link_id"] = flows["link_id"].astype("int32")
    nflows = flows.groupby(["time", "link_id"]).sum().reset_index()
    if term_flows is not None:
        nflows = (
            _concat([nflows, term_flows], ignore_index=True)
            .groupby(["time", "link_id"])
            .sum(min_count=1)
            .reset_index()
        )

    # Add basin boundaries to flows
    # Map all boundary node_ids to link_ids (unique per boundary type)
    lookups: defaultdict[str, dict[int, int]] = defaultdict(dict)
    dfs = []
    for link_id, (_a, _b, (node_id, boundary_type)) in enumerate(
        G.edges(data="boundary", default=(None, None))
    ):
        if boundary_type is None:
            continue
        lookups[boundary_type][node_id] = link_id

    for boundary_type in lookups:
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
    assert (nflows.groupby("time").size() == total_exchanges).all()
    nflows.drop(
        columns=["link_id", "riba_link_id"],
        inplace=True,
    )
    write_flows(output_path / "ribasim.flo", nflows, timestep)
    write_flows(
        output_path / "ribasim.are", nflows, timestep
    )  # same as flow, so velocity becomes 1

    # Write volumes to Delwaq format
    # copy is to avoid false positive SettingWithCopyWarning on pandas 2
    volumes = basins[["time", "node_id", "storage"]].copy()
    volumes["riba_node_id"] = volumes["node_id"]
    mapped_node_id = volumes["node_id"].map(basin_mapping)
    assert mapped_node_id.notna().all(), "basin_mapping is incomplete"
    volumes.loc[:, "node_id"] = mapped_node_id.astype("int32")
    volumes = volumes.sort_values(by=["time", "node_id"])
    # volumes.to_csv(output_path / "volumes.csv", index=False)  # not needed
    volumes.drop(columns=["node_id", "riba_node_id"], inplace=True)
    write_volumes(output_path / "ribasim.vol", volumes, timestep)

    # Length file
    lengths = nflows
    lengths["flow_rate"] = 1.0
    lengths.iloc[np.repeat(np.arange(len(lengths)), 2)]
    write_flows(output_path / "ribasim.len", lengths, timestep)

    # Find all boundary substances and concentrations
    boundaries, substances, loads = _setup_boundaries(model, node_mapping)
    # Write boundary data with substances and concentrations
    template = env.get_template("B5_bounddata.inc.j2")
    with (include_path / "B5_bounddata.inc").open(mode="w") as f:
        f.write(
            template.render(
                boundaries=boundaries,
            )
        )

    # Write load data with substances and masses
    template = env.get_template("B6_wasteloads.inc.j2")
    with (include_path / "B6_wasteloads.inc").open(mode="w") as f:
        f.write(
            template.render(
                loads=loads,
            )
        )

    # Setup initial basin concentrations
    defaults = {
        "Continuity": 1.0,
        "Initial": 1.0,
        "LevelBoundary": 0.0,
        "FlowBoundary": 0.0,
        "Precipitation": 0.0,
        "Drainage": 0.0,
        "SurfaceRunoff": 0.0,
    }
    substances.update(defaults.keys())

    # Add user defined substances
    if model.basin.concentration_state.df is not None:
        initial = model.basin.concentration_state.df
        substances.update(initial.substance.unique())

    check_substance_uniqueness(substances)

    # Store the complete substance set alongside the mesh and write ribasim.nc,
    # so parse() can recover the substances and the node mapping from this file.
    dataset["substances"] = ("substance", sorted(substances))
    dataset.to_netcdf(output_path / "ribasim.nc")

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
        initial = model.basin.concentration_state.df
        for _, row in initial.iterrows():
            icdf.loc[basin_mapping[row.node_id], row.substance] = row.concentration

    # Add comment with original Basin ID
    reverse_node_mapping = {v: k for k, v in node_mapping.items()}
    icdf["comment"] = [f"; {reverse_node_mapping[k]}" for k in icdf.index]

    initial_concentrations = icdf.to_string(header=False, index=False)

    # Write boundary list, ordered by bid to map the unique boundary names
    # to the links described in the pointer file.
    bnd = pointer
    bnd["bid"] = np.minimum(bnd["from_node_id"], bnd["to_node_id"])
    # copy is to avoid false positive SettingWithCopyWarning on pandas 2
    bnd = bnd[bnd["bid"] < 0].copy()
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
        include_path / "B5_bndlist.inc",
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
    with (output_path / "delwaq.inp").open(mode="w") as f:
        f.write(
            template.render(
                startime=model.starttime,
                endtime=endtime - timestep,
                timestep=strfdelta(timestep),
                nsegments=total_segments,
                nexchanges=total_exchanges,
                ribasim_version=ribasim.__version__,
                loglevel=loglevel(model.logging.verbosity),
            )
        )

    template = env.get_template("B1_substances.inc.j2")
    with (include_path / "B1_substances.inc").open(mode="w") as f:
        f.write(
            template.render(
                substances=sorted(substances),
            )
        )

    template = env.get_template("B8_initials.inc.j2")
    with (include_path / "B8_initials.inc").open(mode="w") as f:
        f.write(
            template.render(
                substances=sorted(substances),
                initial_concentrations=initial_concentrations,
            )
        )

    # Empty process input files, to be replaced for other water quality simulations
    for name in (
        "B7_processes.inc",
        "B7_constants.inc",
        "B7_functions.inc",
        "B7_parameters.inc",
        "B7_segfunctions.inc",
    ):
        (include_path / name).write_text("")

    # Return the model so the results can be parsed back. The graph mapping and
    # substances needed by parse() are stored in output_path / "ribasim.nc".
    return model


def add_tracer(
    model: Model, node_id: int, tracer_name: str, concentration: float = 1.0
) -> None:
    """Add a tracer to the Delwaq model."""
    if not is_valid_substance(tracer_name):
        raise ValueError(f"Invalid Delwaq substance name {tracer_name}")

    df = model.node.df
    assert df is not None
    n = df.loc[node_id]
    node_type = n.node_type
    if node_type not in [
        "Basin",
        "LevelBoundary",
        "FlowBoundary",
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


def loglevel(verbosity: Verbosity) -> int:
    if verbosity == Verbosity.debug:
        # administration of monitoring locations, boundary link administration,
        # boundary names and IDs, boundary time lags, waste load names and IDs,
        # specific information on cells where defaults are overridden
        # any variable time step specification
        return 9
    elif verbosity == Verbosity.info:
        # grid layouts, dispersion IDs and fields, boundary types,
        # waste load types, names of constants, parameters, functions, segment functions
        return 2
    else:
        # only very basic output + substance names
        return 1


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
    parser.add_argument(
        "-v",
        "--verbose",
        action="count",
        default=0,
        help="Increase verbosity (-v for info, -vv for debug).",
    )
    args = parser.parse_args()

    log_level = logging.WARNING
    if args.verbose >= 2:
        log_level = logging.DEBUG
    elif args.verbose >= 1:
        log_level = logging.INFO
    logging.basicConfig(level=log_level)

    generate(args.toml_path, args.toml_path.parent / args.output_path)
