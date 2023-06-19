import geopandas as gpd
import numpy as np
import pandas as pd
import ribasim


def backwater_model():
    x = np.arange(0.0, 1020.0, 10.0)
    node_type = np.full(x.size, "ManningResistance")
    node_type[1::2] = "Basin"
    node_type[0] = "FlowBoundary"
    node_type[-2] = "LinearResistance"
    node_type[-1] = "LevelBoundary"

    node_xy = gpd.points_from_xy(x=x, y=np.zeros_like(x))
    _, counts = np.unique(node_type, return_counts=True)
    n_basin = counts[0]

    node = ribasim.Node(
        static=gpd.GeoDataFrame(
            data={"type": node_type},
            index=pd.Index(np.arange(len(node_xy)) + 1, name="fid"),
            geometry=node_xy,
            crs="EPSG:28992",
        )
    )

    ids = np.arange(1, x.size + 1, dtype=np.int64)
    from_id = ids[:-1]
    to_id = ids[1:]
    lines = ribasim.utils.geometry_from_connectivity(node, from_id, to_id)
    edge = ribasim.Edge(
        static=gpd.GeoDataFrame(
            data={
                "from_node_id": from_id,
                "to_node_id": to_id,
                "edge_type": len(from_id) * ["flow"],
            },
            geometry=lines,
            crs="EPSG:28992",
        )
    )
    
    flow_boundary = ribasim.FlowBoundary(
        static=pd.DataFrame(
            data={
                "node_id": ids[node_type == "FlowBoundary"],
                "flow_rate": [5.0],
            }
        )
    )

    # Rectangular profile, width of 1.0 m.
    profile = pd.DataFrame(
        data={
            "node_id": np.repeat(ids[node_type == "Basin"], 3),
            "area": [0.0, 20.0, 20.0] * n_basin,
            "level": [0.0, 0.01, 1.0] * n_basin, 
        }
    )
    static = pd.DataFrame(
        data={
            "node_id": ids[node_type == "Basin"],
            "drainage": 0.0,
            "potential_evaporation": 0.0,
            "infiltration": 0.0,
            "precipitation": 0.0,
            "urban_runoff": 0.0,
        }
    )
    basin = ribasim.Basin(profile=profile, static=static)

    manning_resistance = ribasim.ManningResistance(
        static=pd.DataFrame(
            data={
                "node_id": ids[node_type == "ManningResistance"],
                "length": 20.0,
                "manning_n": 0.04,
                "profile_width": 1.0,
                "profile_slope": 0.0,
            }
        )
    )

    linear_resistance = ribasim.LinearResistance(
        static=pd.DataFrame(
            data={
                "node_id": ids[node_type == "LinearResistance"],
                "resistance": [0.001],
            }
        )
    )
    level_boundary = ribasim.LevelBoundary(
        static=pd.DataFrame(
            data={
                "node_id": ids[node_type == "LevelBoundary"],
                "level": [2.0],
            }
        )
    )

    model = ribasim.Model(
        modelname="backwater",
        node=node,
        edge=edge,
        basin=basin,
        level_boundary=level_boundary,
        flow_boundary=flow_boundary,
        linear_resistance=linear_resistance,
        manning_resistance=manning_resistance,
        starttime="2020-01-01 00:00:00",
        endtime="2030-01-01 00:00:00",
    )
    
    return model
