import geopandas as gpd
import numpy as np
import pandas as pd
import ribasim


def basic_model() -> ribasim.Model:
    """Set up a basic model with all node types and static forcing"""

    # Setup the basins:
    profile = pd.DataFrame(
        data={
            "node_id": [1, 1, 3, 3, 6, 6, 9, 9],
            "area": [0.0, 1000.0] * 4,
            "level": [0.0, 1.0] * 4,
        }
    )

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
    static["node_id"] = [1, 3, 6, 9]

    basin = ribasim.Basin(profile=profile, static=static)

    # Setup linear resistance:
    linear_resistance = ribasim.LinearResistance(
        static=pd.DataFrame(
            data={"node_id": [12, 10], "resistance": [5e3, (3600.0 * 24) / 100.0]}
        )
    )

    # Setup Manning resistance:
    manning_resistance = ribasim.ManningResistance(
        static=pd.DataFrame(
            data={
                "node_id": [2],
                "length": [900.0],
                "manning_n": [0.04],
                "profile_width": [1.0],
                "profile_slope": [3.0],
            }
        )
    )

    # Set up a rating curve node:
    # Discharge: lose 1% of storage volume per day at storage = 1000.0.
    q1000 = 1000.0 * 0.01 / seconds_in_day

    rating_curve = ribasim.TabulatedRatingCurve(
        static=pd.DataFrame(
            data={
                "node_id": [4, 4],
                "level": [0.0, 1.0],
                "discharge": [0.0, q1000],
            }
        )
    )

    # Setup fractional flows:
    fractional_flow = ribasim.FractionalFlow(
        static=pd.DataFrame(
            data={
                "node_id": [5, 8, 13],
                "fraction": [0.3, 0.6, 0.1],
            }
        )
    )

    # Setup pump:
    pump = ribasim.Pump(
        static=pd.DataFrame(
            data={
                "node_id": [7],
                "flow_rate": [0.5 / 3600],
            }
        )
    )

    # Setup flow boundary:
    flow_boundary = ribasim.FlowBoundary(
        static=pd.DataFrame(
            data={
                "node_id": [15, 16],
                "flow_rate": [-1e-4, 1e-4],
            }
        )
    )

    # Setup level boundary:
    level_boundary = ribasim.LevelBoundary(
        static=pd.DataFrame(
            data={
                "node_id": [11, 17],
                "level": [1.0, 1.5],
            }
        )
    )

    # Setup terminal:
    terminal = ribasim.Terminal(
        static=pd.DataFrame(
            data={
                "node_id": [14],
            }
        )
    )

    # Set up the nodes:
    xy = np.array(
        [
            (0.0, 0.0),  # 1: Basin
            (1.0, 0.0),  # 2: ManningResistance
            (2.0, 0.0),  # 3: Basin
            (3.0, 0.0),  # 4: TabulatedRatingCurve
            (3.0, 1.0),  # 5: FractionalFlow
            (3.0, 2.0),  # 6: Basin
            (4.0, 1.0),  # 7: Pump
            (4.0, 0.0),  # 8: FractionalFlow
            (5.0, 0.0),  # 9: Basin
            (6.0, 0.0),  # 10: LinearResistance
            (2.0, 2.0),  # 11: LevelBoundary
            (2.0, 1.0),  # 12: LinearResistance
            (3.0, -1.0),  # 13: FractionalFlow
            (3.0, -2.0),  # 14: Terminal
            (3.0, 3.0),  # 15: Flowboundary
            (0.0, 1.0),  # 16: FlowBoundary
            (6.0, 1.0),  # 17: LevelBoundary
        ]
    )
    node_xy = gpd.points_from_xy(x=xy[:, 0], y=xy[:, 1])

    node_id, node_type = ribasim.Node.get_node_ids_and_types(
        basin,
        level_boundary,
        flow_boundary,
        pump,
        terminal,
        linear_resistance,
        manning_resistance,
        rating_curve,
        fractional_flow,
    )

    # Make sure the feature id starts at 1: explicitly give an index.
    node = ribasim.Node(
        static=gpd.GeoDataFrame(
            data={"type": node_type},
            index=pd.Index(node_id, name="fid"),
            geometry=node_xy,
            crs="EPSG:28992",
        )
    )

    # Setup the edges:
    from_id = np.array(
        [1, 2, 3, 4, 4, 5, 6, 8, 7, 9, 11, 12, 4, 13, 15, 16, 10], dtype=np.int64
    )
    to_id = np.array(
        [2, 3, 4, 5, 8, 6, 7, 9, 9, 10, 12, 3, 13, 14, 6, 1, 17], dtype=np.int64
    )
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

    # Setup a model:
    model = ribasim.Model(
        modelname="basic",
        node=node,
        edge=edge,
        basin=basin,
        level_boundary=level_boundary,
        flow_boundary=flow_boundary,
        pump=pump,
        terminal=terminal,
        linear_resistance=linear_resistance,
        manning_resistance=manning_resistance,
        tabulated_rating_curve=rating_curve,
        fractional_flow=fractional_flow,
        starttime="2020-01-01 00:00:00",
        endtime="2021-01-01 00:00:00",
    )

    return model


def basic_transient_model(model) -> ribasim.Model:
    """Update the basic model with transient forcing"""

    time = pd.date_range(model.starttime, model.endtime)
    day_of_year = time.day_of_year.to_numpy()
    seconds_per_day = 24 * 60 * 60
    evaporation = (
        (-1.0 * np.cos(day_of_year / 365.0 * 2 * np.pi) + 1.0)
        * 0.0025
        / seconds_per_day
    )
    rng = np.random.default_rng(seed=0)
    precipitation = (
        rng.lognormal(mean=-1.0, sigma=1.7, size=time.size) * 0.001 / seconds_per_day
    )

    timeseries = pd.DataFrame(
        data={
            "node_id": 1,
            "time": time,
            "drainage": 0.0,
            "potential_evaporation": evaporation,
            "infiltration": 0.0,
            "precipitation": precipitation,
            "urban_runoff": 0.0,
        }
    )
    basin_ids = model.basin.static["node_id"].to_numpy()
    forcing = (
        pd.concat(
            [timeseries.assign(node_id=id) for id in basin_ids], ignore_index=True
        )
        .sort_values("time")
        .reset_index(drop=True)
    )

    state = pd.DataFrame(
        data={
            "node_id": basin_ids,
            "storage": 1000.0,
            "concentration": 0.0,
        }
    )

    model.basin.forcing = forcing
    model.basin.state = state

    model.modelname = "basic_transient"
    return model


def tabulated_rating_curve_model() -> ribasim.Model:
    """
    Set up a model where the upstream Basin has two TabulatedRatingCurve attached.
    They both flow to the same downstream Basin, but one has a static rating curve,
    and the other one a time-varying rating curve.
    Only the upstream Basin receives a (constant) precipitation.
    """

    # Setup the basins:
    profile = pd.DataFrame(
        data={
            "node_id": [1, 1, 4, 4],
            "area": [0.0, 1000.0] * 2,
            "level": [0.0, 1.0] * 2,
        }
    )

    # Convert steady forcing to m/s
    # 2 mm/d precipitation
    seconds_in_day = 24 * 3600
    precipitation = 0.002 / seconds_in_day
    # only the upstream basin gets precipitation
    static = pd.DataFrame(
        data={
            "node_id": [1, 4],
            "drainage": 0.0,
            "potential_evaporation": 0.0,
            "infiltration": 0.0,
            "precipitation": [precipitation, 0.0],
            "urban_runoff": 0.0,
        }
    )

    basin = ribasim.Basin(profile=profile, static=static)

    # Set up a rating curve node:
    # Discharge: lose 1% of storage volume per day at storage = 1000.0.
    q1000 = 1000.0 * 0.01 / seconds_in_day

    rating_curve = ribasim.TabulatedRatingCurve(
        static=pd.DataFrame(
            data={
                "node_id": [2, 2],
                "level": [0.0, 1.0],
                "discharge": [0.0, q1000],
            }
        ),
        time=pd.DataFrame(
            data={
                "node_id": [3, 3, 3, 3, 3, 3],
                "time": [
                    # test subsecond precision
                    pd.Timestamp("2020-01-01 00:00:00.000001"),
                    pd.Timestamp("2020-01"),
                    pd.Timestamp("2020-02"),
                    pd.Timestamp("2020-02"),
                    pd.Timestamp("2020-03"),
                    pd.Timestamp("2020-03"),
                ],
                "level": [0.0, 1.0, 0.0, 1.1, 0.0, 1.2],
                "discharge": [0.0, q1000, 0.0, q1000, 0.0, q1000],
            }
        ),
    )

    # Set up the nodes:
    xy = np.array(
        [
            (0.0, 0.0),  # 1: Basin
            (1.0, 1.0),  # 2: TabulatedRatingCurve (static)
            (1.0, -1.0),  # 3: TabulatedRatingCurve (time-varying)
            (2.0, 0.0),  # 4: Basin
        ]
    )
    node_xy = gpd.points_from_xy(x=xy[:, 0], y=xy[:, 1])

    node_id, node_type = ribasim.Node.get_node_ids_and_types(basin, rating_curve)

    # Make sure the feature id starts at 1: explicitly give an index.
    node = ribasim.Node(
        static=gpd.GeoDataFrame(
            data={"type": node_type},
            index=pd.Index(node_id, name="fid"),
            geometry=node_xy,
            crs="EPSG:28992",
        )
    )

    # Setup the edges:
    from_id = np.array([1, 1, 2, 3], dtype=np.int64)
    to_id = np.array([2, 3, 4, 4], dtype=np.int64)
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

    # Setup a model:
    model = ribasim.Model(
        modelname="tabulated_rating_curve",
        node=node,
        edge=edge,
        basin=basin,
        tabulated_rating_curve=rating_curve,
        starttime="2020-01-01 00:00:00",
        endtime="2021-01-01 00:00:00",
    )

    return model
