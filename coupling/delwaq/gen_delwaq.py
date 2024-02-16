"""Setup a Delwaq model from a Ribasim model and results."""
import csv
import math
import shutil
from datetime import timedelta
from pathlib import Path

import meshkernel as mk
import numpy as np
import pandas as pd
import ribasim
import xugrid as xu
from delwaq_util import (
    strfdelta,
    ugridify,
    write_flows,
    write_pointer,
    write_volumes,
)
from jinja2 import Environment, FileSystemLoader

env = Environment(loader=FileSystemLoader("template"))

fillvolume = 0.0

# Read in model and results
modelfn = Path("../../generated_testmodels/basic/ribasim.toml")
modelfn = Path("../../nl/hws.toml")  # fixed hws model
model = ribasim.Model.read(modelfn)
basins = pd.read_feather(modelfn.parent / "results" / "basin.arrow")
flows = pd.read_feather(modelfn.parent / "results" / "flow.arrow")

output_folder = Path("model")

# Setup metadata
if model.solver.dt is None:
    timestep = timedelta(seconds=3600)
elif isinstance(model.solver.dt, list):
    raise ValueError("Multiple timesteps not supported")
else:
    timestep = timedelta(seconds=model.solver.dt)

# Setup topology, write to pointer file
node = model.network.node.df
edge = model.network.edge.df
edge = edge[edge.edge_type == "flow"]  # no control or allocation stuff please

# Flows on non-existing edges indicate where the boundaries are
tg = flows.groupby("time")
g = tg.get_group(flows.time[0])
nboundary = g.edge_id.isna().sum()
boundary_nodes = g.to_node_id[g.edge_id.isna()]
new_boundary_ids = np.tile(-np.arange(1, nboundary + 1), tg.ngroups)
flows.from_node_id.loc[flows.edge_id.isna()] = new_boundary_ids
flows.to_csv(output_folder / "flows.csv", index=False)  # not needed


tg = flows.groupby("time")
pointer = tg.get_group(flows.time[0])
pointer.drop(columns=["time", "flow", "edge_id"], inplace=True)
write_pointer(output_folder / "ribasim.poi", pointer)

total_segments = len(node.index)
total_exchanges = len(edge.index) + nboundary


# Write attributes template
template = env.get_template("delwaq.atr.j2")
with open(output_folder / "ribasim.atr", mode="w") as f:
    f.write(
        template.render(
            nsegments=total_segments,
        )
    )

# Generate mesh and write to NetCDF
edges = np.array(list(zip(edge.from_node_id, edge.to_node_id))).flatten()
mesh1d = mk.Mesh1d(node.geometry.x, node.geometry.y, edges)
ugrid = xu.Ugrid1d.from_meshkernel(mesh1d)
ugrid.set_crs(epsg=28992)
ds = ugrid.to_dataset()
# ds.to_netcdf("ribasim.nc")
ds = ugridify(model)
ds.ugrid.to_netcdf(output_folder / "ribasim.nc")

# Generate area and flows
# File format is int32, float32 based
# Time is internal clock, not real time!
flows.time = (flows.time - flows.time[0]).dt.total_seconds().astype("int32")
flows.drop(columns=["edge_id", "from_node_id", "to_node_id"], inplace=True)
write_flows(output_folder / "ribasim.flo", flows)
write_flows(
    output_folder / "ribasim.are", flows
)  # same as flow, so velocity becomes 1 m/s


basins.time = (basins.time - basins.time[0]).dt.total_seconds().astype("int32")
ntime = basins.time.unique()
basins.drop(columns=["level"], inplace=True)

non_basins = set(node.index) - set(basins.node_id)
rtime = ntime - ntime[0]
volumes_nbasin = pd.DataFrame(
    {
        "time": np.repeat(rtime, len(non_basins)),
        "node_id": np.tile(list(non_basins), len(rtime)),
        "storage": fillvolume,
    }
)
volumes = pd.concat([basins, volumes_nbasin])
volumes.sort_values(by=["time", "node_id"], inplace=True)
volumes.to_csv(output_folder / "volumes.csv", index=False)  # not needed
volumes.drop(columns=["node_id"], inplace=True)
write_volumes(output_folder / "ribasim.vol", volumes)
volumes.storage = 1  # m/s
write_volumes(output_folder / "ribasim.vel", volumes)

# Length file
# Timestep and flattened (2, nsegments) of identical lengths
# for left right, so 0, 1., 1., 3., 3., 4., 4. etc.
lengths = np.repeat(edge.geometry.length.to_numpy() / 2, 2).astype("float32")
lengths = pd.DataFrame(
    {
        "time": np.repeat(rtime, len(lengths)),
        "flow": np.tile(list(lengths), len(rtime)),
    }
)
write_flows(output_folder / "ribasim.len", lengths)

# Find our boundaries
bnd = node[node.index.isin(boundary_nodes)]["type"].reset_index()

boundaries = []
substances = set()


def make_boundary(id, type):
    return type + "_" + "#" + str(id)


for i, row in model.level_boundary.static.df.iterrows():
    if not math.isnan(row.concentration):
        bid = make_boundary(row.node_id, "LevelBoundary")
        boundaries.append(
            {
                "name": bid,
                "concentrations": [row.concentration],
                "substances": ["Cl"],
            }
        )
        substances.add("Cl")


for i, row in model.flow_boundary.static.df.iterrows():
    if not math.isnan(row.concentration):
        bid = make_boundary(row.node_id, "FlowBoundary")
        substances.add(bid)
        boundaries.append(
            {
                "name": bid,
                "concentrations": [row.concentration],
                "substances": [bid],
            }
        )

template = env.get_template("B5_bounddata.inc.j2")
with open(output_folder / "B5_bounddata.inc", mode="w") as f:
    f.write(
        template.render(
            states=[],  # no states yet
            boundaries=boundaries,
        )
    )


bnd["fid"] = bnd["type"] + "_" + "#" + bnd["fid"].astype(str)
bnd["comment"] = ""
bnd = bnd[["fid", "comment", "type"]]
bnd.to_csv(
    output_folder / "ribasim_bndlist.inc",
    index=False,
    header=False,
    sep=" ",
    quotechar="'",
    quoting=csv.QUOTE_ALL,
)

dimrc = Path("reference/dimr_config.xml")
shutil.copy(dimrc, output_folder / "dimr_config.xml")

# Write input template
template = env.get_template("delwaq.inp.j2")
with open(output_folder / "delwaq.inp", mode="w") as f:
    f.write(
        template.render(
            startime=model.starttime,
            endtime=model.endtime,
            timestep=strfdelta(timestep),
            nsegments=total_segments,
            nexchanges=total_exchanges,
            substances=substances,
        )
    )
