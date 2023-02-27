# %%
import os

os.environ["USE_PYGEOS"] = "0"

import geopandas as gpd
import numpy as np
import pandas as pd

import ribasim

# %%
# Set up the nodes:

xy = np.array(
    [
        (0.0, 0.0),  # 1: Basin,
        (1.0, 0.0),  # 2: LinearLevelConnection
        (2.0, 0.0),  # 3: Basin
        (3.0, 0.0),  # 4: TabulatedRatingCurve
        (3.0, 1.0),  # 5: FractionalFlow
        (3.0, 2.0),  # 6: Basin
        (4.0, 0.0),  # 7: FractionalFlow
        (5.0, 0.0),  # 8: Basin
        (6.0, 0.0),  # 9: LevelControl
    ]
)
node_xy = gpd.points_from_xy(x=xy[:, 0], y=xy[:, 1])

node_type = [
    "Basin",
    "LinearLevelConnection",
    "Basin",
    "TabulatedRatingCurve",
    "FractionalFlow",
    "Basin",
    "FractionalFlow",
    "Basin",
    "LevelControl",
]

# Make sure the feature id starts at 1: explicitly give an index.
node = ribasim.Node(
    static=gpd.GeoDataFrame(
        data={"type": node_type},
        index=np.arange(len(xy)) + 1,
        geometry=node_xy,
        crs="EPSG:28992",
    )
)

# %%
# Setup the edges:

from_id = np.array([1, 2, 3, 4, 4, 5, 7, 8], dtype=np.int64)
to_id = np.array([2, 3, 4, 5, 7, 6, 8, 9], dtype=np.int64)
lines = ribasim.utils.geometry_from_connectivity(node, from_id, to_id)
edge = ribasim.Edge(
    static=gpd.GeoDataFrame(
        data={"from_node_id": from_id, "to_node_id": to_id},
        geometry=lines,
        crs="EPSG:28992",
    )
)

# %%
# Setup the basins:

profile = pd.DataFrame(
    data={
        "node_id": [0, 0],
        "storage": [0.0, 1000.0],
        "area": [0.0, 1000.0],
        "level": [0.0, 1.0],
    }
)
repeat = np.tile([0, 1], 4)
profile = profile.iloc[repeat]
profile["node_id"] = [1, 1, 3, 3, 6, 6, 8, 8]


# Convert steady forcing to m/s
# 2 mm/d precipitation, 1 mm/d evaporation
seconds_in_day = 24 * 3600
precipitation = 0.002 / seconds_in_day
evaporation = 0.001 / seconds_in_day


static = pd.DataFrame(
    data={
        "node_id": [0],
        "drainage": [0.0],
        "potential_evaporation": [evaporation],
        "infiltration": [0.0],
        "precipitation": [precipitation],
        "urban_runoff": [0.0],
    }
)
static = static.iloc[[0, 0, 0, 0]]
static["node_id"] = [1, 3, 6, 8]

basin = ribasim.Basin(profile=profile, static=static)

# %%
# Setup linear level connection:

linear_connection = ribasim.LinearLevelConnection(
    static=pd.DataFrame(data={"node_id": [2], "conductance": [1.5e-4]})
)


# %%
# Set up a rating curve node:

rating_curve = ribasim.TabulatedRatingCurve(
    static=pd.DataFrame(
        data={
            "node_id": [4, 4],
            "storage": [0.0, 1000.0],
            "discharge": [0.0, 1.5e-4],
        }
    )
)

# %%
# Setup fractional flows:

fractional_flow = ribasim.FractionalFlow(
    static=pd.DataFrame(
        data={
            "node_id": [5, 7],
            "fraction": [0.3, 0.7],
        }
    )
)

# %%
# Setup level control:

level_control = ribasim.LevelControl(
    static=pd.DataFrame(
        data={
            "node_id": [9],
            "target_level": [1.5],
        }
    )
)

# %%
# Setup a model:

model = ribasim.Model(
    modelname="basic",
    node=node,
    edge=edge,
    basin=basin,
    level_control=level_control,
    linear_level_connection=linear_connection,
    tabulated_rating_curve=rating_curve,
    fractional_flow=fractional_flow,
    starttime="2020-01-01 00:00:00",
    endtime="2021-01-01 00:00:00",
)

# %%
# Write the model to a TOML and GeoPackage:

model.write("basic")
# %%
