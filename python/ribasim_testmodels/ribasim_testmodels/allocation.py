from typing import Any

import numpy as np
import pandas as pd
from ribasim.config import Allocation, Experimental, Node, Solver
from ribasim.geometry.link import NodeData
from ribasim.input_base import TableModel
from ribasim.model import Model
from ribasim.nodes import (
    basin,
    discrete_control,
    flow_boundary,
    flow_demand,
    level_boundary,
    level_demand,
    linear_resistance,
    manning_resistance,
    outlet,
    pump,
    tabulated_rating_curve,
    user_demand,
)
from shapely.geometry import Point


def user_demand_model() -> Model:
    """Create a UserDemand test model with static and dynamic UserDemand on the same basin."""
    model = Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:28992",
        solver=Solver(algorithm="Tsit5"),
        experimental=Experimental(concentration=True),
    )

    model.basin.add(
        Node(1, Point(0, 0)),
        [basin.Profile(area=1000.0, level=[0.0, 1.0]), basin.State(level=[1.0])],
    )
    model.user_demand.add(
        Node(2, Point(1, 0.5)),
        [
            user_demand.Static(
                demand=[1e-4], return_factor=0.9, min_level=0.9, demand_priority=1
            )
        ],
    )
    model.user_demand.add(
        Node(3, Point(1, -0.5)),
        [
            user_demand.Time(
                time=[
                    "2020-06-01 00:00:00",
                    "2020-06-01 01:00:00",
                    "2020-07-01 00:00:00",
                    "2020-07-01 01:00:00",
                ],
                demand=[0.0, 3e-4, 3e-4, 0.0],
                return_factor=0.4,
                min_level=0.5,
                demand_priority=1,
            )
        ],
    )
    model.user_demand.add(
        Node(4, Point(1, 0)),
        [
            user_demand.Time(
                time=[
                    "2020-08-01 00:00:00",
                    "2020-09-01 00:00:00",
                    "2020-10-01 00:00:00",
                    "2020-11-01 00:00:00",
                ],
                min_level=0.0,
                demand=[0.0, 1e-4, 2e-4, 0.0],
                return_factor=[0.0, 0.1, 0.2, 0.3],
                demand_priority=1,
            )
        ],
    )
    model.terminal.add(Node(5, Point(2, 0)))

    model.link.add(model.basin[1], model.user_demand[2])
    model.link.add(model.basin[1], model.user_demand[3])
    model.link.add(model.basin[1], model.user_demand[4])
    model.link.add(model.user_demand[2], model.terminal[5])
    model.link.add(model.user_demand[3], model.terminal[5])
    model.link.add(model.user_demand[4], model.terminal[5])

    return model


def subnetwork_model() -> Model:
    """Create a UserDemand testmodel representing a subnetwork.

    This model is merged into main_network_with_subnetworks_model.
    """
    model = Model(
        starttime="2020-01-01",
        endtime="2020-04-01",
        crs="EPSG:28992",
        allocation=Allocation(use_allocation=True, timestep=86400),
        experimental=Experimental(concentration=True),
    )

    basin_data: list[TableModel[Any]] = [
        basin.Profile(area=100000.0, level=[0.0, 1.0]),
        basin.State(level=[10.0]),
    ]
    outlet_data: list[TableModel[Any]] = [
        outlet.Static(flow_rate=[3.0], max_flow_rate=3.0)
    ]

    model.flow_boundary.add(
        Node(1, Point(3, 1), subnetwork_id=2),
        [
            flow_boundary.Time(
                time=pd.date_range(start="2020-01", end="2020-05", freq="MS"),
                flow_rate=np.arange(10, 0, -2),
            )
        ],
    )
    model.basin.add(Node(2, Point(2, 1), subnetwork_id=2), basin_data)
    model.outlet.add(Node(3, Point(1, 1), subnetwork_id=2), outlet_data)
    model.terminal.add(Node(4, Point(0, 1), subnetwork_id=2))
    model.pump.add(
        Node(5, Point(2, 2), subnetwork_id=2),
        [pump.Static(flow_rate=[4.0], max_flow_rate=4.0)],
    )
    model.basin.add(Node(6, Point(2, 3), subnetwork_id=2), basin_data)
    model.outlet.add(Node(7, Point(1, 3), subnetwork_id=2), outlet_data)
    model.basin.add(Node(8, Point(0, 3), subnetwork_id=2), basin_data)
    model.terminal.add(Node(9, Point(2, 5), subnetwork_id=2))
    model.user_demand.add(
        Node(10, Point(2, 0), subnetwork_id=2),
        [
            user_demand.Static(
                demand=[4.0], return_factor=0.9, min_level=0.9, demand_priority=2
            )
        ],
    )
    model.user_demand.add(
        Node(11, Point(3, 3), subnetwork_id=2),
        [
            user_demand.Static(
                demand=[5.0], return_factor=0.5, min_level=0.9, demand_priority=1
            )
        ],
    )
    model.user_demand.add(
        Node(12, Point(0, 4), subnetwork_id=2),
        [
            user_demand.Static(
                demand=[3.0], return_factor=0.9, min_level=0.9, demand_priority=2
            )
        ],
    )
    model.outlet.add(Node(13, Point(2, 4), subnetwork_id=2), outlet_data)

    model.link.add(model.flow_boundary[1], model.basin[2])
    model.link.add(model.basin[2], model.outlet[3])
    model.link.add(model.outlet[3], model.terminal[4])
    model.link.add(model.basin[2], model.user_demand[10])
    model.link.add(model.basin[2], model.pump[5])
    model.link.add(model.pump[5], model.basin[6])
    model.link.add(model.basin[6], model.outlet[7])
    model.link.add(model.outlet[7], model.basin[8])
    model.link.add(model.basin[6], model.user_demand[11])
    model.link.add(model.basin[8], model.user_demand[12])
    model.link.add(model.basin[6], model.outlet[13])
    model.link.add(model.outlet[13], model.terminal[9])
    model.link.add(model.user_demand[10], model.basin[2])
    model.link.add(model.user_demand[11], model.basin[6])
    model.link.add(model.user_demand[12], model.basin[8])

    return model


def looped_subnetwork_model() -> Model:
    """Create a UserDemand testmodel representing a subnetwork containing a loop in the topology.

    This model is merged into main_network_with_subnetworks_model.
    """
    model = Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:28992",
        allocation=Allocation(use_allocation=True, timestep=86400),
        experimental=Experimental(concentration=True),
    )

    basin_data: list[TableModel[Any]] = [
        basin.Profile(area=1000.0, level=[0.0, 1.0]),
        basin.State(level=[1.0]),
    ]
    tabulated_rating_curve_data = tabulated_rating_curve.Static(
        level=[0.0, 1.0], flow_rate=[0.0, 2.0]
    )
    outlet_data = outlet.Static(flow_rate=[3e-3], max_flow_rate=3.0)

    model.user_demand.add(
        Node(1, Point(0, 0), subnetwork_id=2),
        [
            user_demand.Static(
                demand=[1e-3], return_factor=0.9, min_level=0.9, demand_priority=2
            )
        ],
    )
    model.basin.add(Node(2, Point(0, 1), subnetwork_id=2), basin_data)
    model.outlet.add(Node(3, Point(-1, 1), subnetwork_id=2), [outlet_data])
    model.terminal.add(Node(4, Point(-2, 1), subnetwork_id=2))
    model.flow_boundary.add(
        Node(5, Point(2, 1), subnetwork_id=2),
        [flow_boundary.Static(flow_rate=[4.5e-3])],
    )
    model.pump.add(
        Node(6, Point(0, 2), subnetwork_id=2),
        [pump.Static(flow_rate=[4e-3], max_flow_rate=4e-3)],
    )
    model.basin.add(Node(7, Point(-2, 3), subnetwork_id=2), basin_data)
    model.outlet.add(Node(8, Point(-1, 3), subnetwork_id=2), [outlet_data])
    model.basin.add(Node(9, Point(0, 3), subnetwork_id=2), basin_data)
    model.outlet.add(Node(10, Point(1, 3), subnetwork_id=2), [outlet_data])
    model.basin.add(Node(11, Point(2, 3), subnetwork_id=2), basin_data)
    model.user_demand.add(
        Node(12, Point(-2, 4), subnetwork_id=2),
        [
            user_demand.Static(
                demand=[1e-3], return_factor=0.9, min_level=0.9, demand_priority=1
            )
        ],
    )
    model.tabulated_rating_curve.add(
        Node(13, Point(0, 4), subnetwork_id=2), [tabulated_rating_curve_data]
    )
    model.tabulated_rating_curve.add(
        Node(14, Point(2, 4), subnetwork_id=2), [tabulated_rating_curve_data]
    )
    model.basin.add(Node(15, Point(0, 5), subnetwork_id=2), basin_data)
    model.pump.add(
        Node(16, Point(1, 5), subnetwork_id=2),
        [pump.Static(flow_rate=[4e-3], max_flow_rate=4e-3)],
    )
    model.basin.add(Node(17, Point(2, 5), subnetwork_id=2), basin_data)
    model.user_demand.add(
        Node(18, Point(-1, 6), subnetwork_id=2),
        [
            user_demand.Static(
                demand=[1e-3], return_factor=0.9, min_level=0.9, demand_priority=3
            )
        ],
    )
    model.tabulated_rating_curve.add(
        Node(19, Point(0, 6), subnetwork_id=2), [tabulated_rating_curve_data]
    )
    model.user_demand.add(
        Node(20, Point(2, 6), subnetwork_id=2),
        [
            user_demand.Static(
                demand=[1e-3], return_factor=0.9, min_level=0.9, demand_priority=3
            )
        ],
    )
    model.basin.add(Node(21, Point(0, 7), subnetwork_id=2), basin_data)
    model.outlet.add(Node(22, Point(0, 8), subnetwork_id=2), [outlet_data])
    model.terminal.add(Node(23, Point(0, 9), subnetwork_id=2))
    model.user_demand.add(
        Node(24, Point(3, 3), subnetwork_id=2),
        [
            user_demand.Static(
                demand=[1e-3], return_factor=0.9, min_level=0.9, demand_priority=2
            )
        ],
    )

    model.link.add(model.flow_boundary[5], model.basin[2])
    model.link.add(model.basin[2], model.outlet[3])
    model.link.add(model.outlet[3], model.terminal[4])
    model.link.add(model.basin[2], model.user_demand[1])
    model.link.add(model.basin[2], model.pump[6])
    model.link.add(model.pump[6], model.basin[9])
    model.link.add(model.basin[9], model.outlet[8])
    model.link.add(model.outlet[8], model.basin[7])
    model.link.add(model.basin[7], model.user_demand[12])
    model.link.add(model.basin[9], model.tabulated_rating_curve[13])
    model.link.add(model.tabulated_rating_curve[13], model.basin[15])
    model.link.add(model.basin[15], model.pump[16])
    model.link.add(model.pump[16], model.basin[17])
    model.link.add(model.basin[17], model.user_demand[20])
    model.link.add(model.basin[15], model.tabulated_rating_curve[19])
    model.link.add(model.tabulated_rating_curve[19], model.basin[21])
    model.link.add(model.basin[15], model.user_demand[18])
    model.link.add(model.user_demand[18], model.basin[21])
    model.link.add(model.basin[21], model.outlet[22])
    model.link.add(model.outlet[22], model.terminal[23])
    model.link.add(model.basin[9], model.outlet[10])
    model.link.add(model.outlet[10], model.basin[11])
    model.link.add(model.basin[11], model.tabulated_rating_curve[14])
    model.link.add(model.tabulated_rating_curve[14], model.basin[17])
    model.link.add(model.user_demand[1], model.basin[2])
    model.link.add(model.user_demand[12], model.basin[7])
    model.link.add(model.user_demand[20], model.basin[17])
    model.link.add(model.basin[11], model.user_demand[24])
    model.link.add(model.user_demand[24], model.basin[11])

    return model


def minimal_subnetwork_model() -> Model:
    """Create a subnetwork that is minimal with non-trivial allocation."""
    model = Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:28992",
        allocation=Allocation(use_allocation=True, timestep=86400),
        experimental=Experimental(concentration=True),
    )

    basin_data: list[TableModel[Any]] = [
        basin.Profile(area=1000.0, level=[0.0, 1.0]),
        basin.State(level=[1.0]),
    ]

    model.flow_boundary.add(
        Node(1, Point(0, 0), subnetwork_id=2),
        [flow_boundary.Static(flow_rate=[2.0e-3])],
    )
    model.basin.add(Node(2, Point(0, 1), subnetwork_id=2), basin_data)
    model.pump.add(
        Node(3, Point(0, 2), subnetwork_id=2),
        [pump.Static(flow_rate=[4e-3], max_flow_rate=4e-3)],
    )
    model.basin.add(Node(4, Point(0, 3), subnetwork_id=2), basin_data)
    model.user_demand.add(
        Node(5, Point(-1, 4), subnetwork_id=2),
        [
            user_demand.Static(
                demand=[1e-3], return_factor=0.9, min_level=0.9, demand_priority=1
            )
        ],
    )
    model.user_demand.add(
        Node(6, Point(1, 4), subnetwork_id=2),
        [
            user_demand.Time(
                time=["2020-01-01", "2021-01-01"],
                demand=[1e-3, 2e-3],
                return_factor=0.9,
                min_level=0.9,
                demand_priority=1,
            )
        ],
    )

    model.link.add(model.flow_boundary[1], model.basin[2])
    model.link.add(model.basin[2], model.pump[3])
    model.link.add(model.pump[3], model.basin[4])
    model.link.add(model.basin[4], model.user_demand[5])
    model.link.add(model.basin[4], model.user_demand[6])
    model.link.add(model.user_demand[5], model.basin[4])
    model.link.add(model.user_demand[6], model.basin[4])

    return model


def allocation_example_model() -> Model:
    """Generate a model that is used as an example of allocation in the docs."""
    model = Model(
        starttime="2020-01-01",
        endtime="2020-01-20",
        crs="EPSG:28992",
        allocation=Allocation(use_allocation=True, timestep=86400),
        experimental=Experimental(concentration=True),
    )

    basin_data: list[TableModel[Any]] = [
        basin.Profile(area=300_000.0, level=[0.0, 1.0]),
        basin.State(level=[1.0]),
    ]

    model.flow_boundary.add(
        Node(1, Point(0, 0), subnetwork_id=2), [flow_boundary.Static(flow_rate=[2.0])]
    )
    model.basin.add(Node(2, Point(1, 0), subnetwork_id=2), basin_data)
    model.user_demand.add(
        Node(3, Point(1, 1), subnetwork_id=2),
        [
            user_demand.Static(
                demand=[1.5], return_factor=0.0, min_level=-1.0, demand_priority=1
            )
        ],
    )
    model.linear_resistance.add(
        Node(4, Point(2, 0), subnetwork_id=2),
        [linear_resistance.Static(resistance=[0.06])],
    )
    model.basin.add(Node(5, Point(3, 0), subnetwork_id=2), basin_data)
    model.user_demand.add(
        Node(6, Point(3, 1), subnetwork_id=2),
        [
            user_demand.Static(
                demand=[1.0], return_factor=0.0, min_level=-1.0, demand_priority=3
            )
        ],
    )
    model.tabulated_rating_curve.add(
        Node(7, Point(4, 0), subnetwork_id=2),
        [
            tabulated_rating_curve.Static(
                level=[0.0, 0.5, 1.0], flow_rate=[0.0, 0.0, 2.0]
            )
        ],
    )
    model.terminal.add(Node(8, Point(5, 0), subnetwork_id=2))

    model.link.add(model.flow_boundary[1], model.basin[2])
    model.link.add(model.basin[2], model.user_demand[3])
    model.link.add(model.basin[2], model.linear_resistance[4])
    model.link.add(model.linear_resistance[4], model.basin[5])
    model.link.add(model.basin[5], model.user_demand[6])
    model.link.add(model.basin[5], model.tabulated_rating_curve[7])
    model.link.add(model.tabulated_rating_curve[7], model.terminal[8])
    model.link.add(model.user_demand[3], model.basin[2])
    model.link.add(model.user_demand[6], model.basin[5])

    return model


def main_network_with_subnetworks_model() -> Model:
    """Generate a model which consists of a main network and multiple connected subnetworks."""
    model = Model(
        starttime="2020-01-01",
        endtime="2020-03-01",
        crs="EPSG:28992",
        allocation=Allocation(use_allocation=True, timestep=86400),
        experimental=Experimental(concentration=True),
    )

    basin_data: list[TableModel[Any]] = [
        basin.Profile(area=1000.0, level=[0.0, 1.0]),
        basin.State(level=[1.0]),
    ]
    large_basin_data: list[TableModel[Any]] = [
        basin.Profile(area=100000.0, level=[0.0, 1.0]),
        basin.State(level=[10.0]),
    ]

    model.flow_boundary.add(
        Node(1, Point(0, -1), subnetwork_id=1), [flow_boundary.Static(flow_rate=[1.0])]
    )
    model.basin.add(Node(2, Point(3, 1), subnetwork_id=1), basin_data)
    model.linear_resistance.add(
        Node(3, Point(6, -1), subnetwork_id=1),
        [linear_resistance.Static(resistance=[0.001])],
    )
    model.basin.add(Node(4, Point(9, 1), subnetwork_id=1), basin_data)
    model.linear_resistance.add(
        Node(5, Point(12, -1), subnetwork_id=1),
        [linear_resistance.Static(resistance=[0.001])],
    )
    model.basin.add(Node(6, Point(15, 1), subnetwork_id=1), basin_data)
    model.linear_resistance.add(
        Node(7, Point(18, -1), subnetwork_id=1),
        [linear_resistance.Static(resistance=[0.001])],
    )
    model.basin.add(Node(8, Point(21, 1), subnetwork_id=1), basin_data)
    model.linear_resistance.add(
        Node(9, Point(24, -1), subnetwork_id=1),
        [linear_resistance.Static(resistance=[0.001])],
    )
    model.basin.add(Node(10, Point(27, 1), subnetwork_id=1), basin_data)
    model.pump.add(
        Node(11, Point(3, 4), subnetwork_id=3),
        [pump.Static(flow_rate=[1e-3], max_flow_rate=10.0)],
    )
    model.basin.add(Node(12, Point(2, 4), subnetwork_id=3), large_basin_data)
    model.outlet.add(
        Node(13, Point(1, 4), subnetwork_id=3),
        [outlet.Static(flow_rate=[3.0], max_flow_rate=3.0)],
    )
    model.terminal.add(Node(14, Point(0, 4), subnetwork_id=3))
    model.pump.add(
        Node(15, Point(2, 5), subnetwork_id=3),
        [pump.Static(flow_rate=[4.0], max_flow_rate=4.0)],
    )
    model.basin.add(Node(16, Point(2, 6), subnetwork_id=3), large_basin_data)
    model.outlet.add(
        Node(17, Point(1, 6), subnetwork_id=3),
        [outlet.Static(flow_rate=[3.0], max_flow_rate=3.0)],
    )
    model.basin.add(Node(18, Point(0, 6), subnetwork_id=3), large_basin_data)
    model.terminal.add(Node(19, Point(2, 8), subnetwork_id=3))
    model.user_demand.add(
        Node(20, Point(2, 3), subnetwork_id=3),
        [
            user_demand.Static(
                demand=[4.0], return_factor=0.9, min_level=0.9, demand_priority=2
            )
        ],
    )
    model.user_demand.add(
        Node(21, Point(3, 6), subnetwork_id=3),
        [
            user_demand.Static(
                demand=[5.0], return_factor=0.9, min_level=0.9, demand_priority=1
            )
        ],
    )
    model.user_demand.add(
        Node(22, Point(0, 7), subnetwork_id=3),
        [
            user_demand.Static(
                demand=[3.0], return_factor=0.9, min_level=0.9, demand_priority=2
            )
        ],
    )
    model.outlet.add(
        Node(23, Point(2, 7), subnetwork_id=3),
        [outlet.Static(flow_rate=[3.0], max_flow_rate=3.0)],
    )
    model.pump.add(
        Node(24, Point(14, 3), subnetwork_id=5),
        [pump.Static(flow_rate=[1e-3], max_flow_rate=1.0)],
    )
    model.basin.add(Node(25, Point(14, 4), subnetwork_id=5), basin_data)
    model.tabulated_rating_curve.add(
        Node(26, Point(14, 5), subnetwork_id=5),
        [tabulated_rating_curve.Static(level=[0.0, 1.0], flow_rate=[0.0, 1e-4])],
    )
    model.basin.add(Node(31, Point(16, 7), subnetwork_id=5), basin_data)
    model.user_demand.add(
        Node(32, Point(17, 8), subnetwork_id=5),
        [
            user_demand.Time(
                time=["2020-01-01", "2021-01-01"],
                demand=[1e-3, 2e-3],
                return_factor=0.9,
                min_level=0.9,
                demand_priority=1,
            )
        ],
    )
    model.user_demand.add(
        Node(34, Point(26, 3), subnetwork_id=7),
        [
            user_demand.Static(
                demand=[1e-3], return_factor=0.9, min_level=0.9, demand_priority=2
            )
        ],
    )
    model.basin.add(Node(35, Point(26, 4), subnetwork_id=7), basin_data)
    model.outlet.add(
        Node(36, Point(25, 4), subnetwork_id=7),
        [outlet.Static(flow_rate=[0.003], max_flow_rate=3.0)],
    )
    model.terminal.add(Node(37, Point(24, 4), subnetwork_id=7))
    model.pump.add(
        Node(38, Point(28, 4), subnetwork_id=7),
        [pump.Static(flow_rate=[1e-3], max_flow_rate=1.0)],
    )
    model.pump.add(
        Node(39, Point(26, 5), subnetwork_id=7),
        [pump.Static(flow_rate=[4e-3], max_flow_rate=0.004)],
    )
    model.basin.add(Node(40, Point(24, 6), subnetwork_id=7), basin_data)
    model.outlet.add(
        Node(41, Point(25, 6), subnetwork_id=7),
        [outlet.Static(flow_rate=[0.003], max_flow_rate=3.0)],
    )
    model.basin.add(Node(42, Point(26, 6), subnetwork_id=7), basin_data)
    model.outlet.add(
        Node(43, Point(27, 6), subnetwork_id=7),
        [outlet.Static(flow_rate=[0.003], max_flow_rate=3.0)],
    )
    model.basin.add(Node(44, Point(28, 6), subnetwork_id=7), basin_data)
    model.user_demand.add(
        Node(45, Point(24, 7), subnetwork_id=7),
        [
            user_demand.Static(
                demand=[1e-3], return_factor=0.9, min_level=0.9, demand_priority=1
            )
        ],
    )
    model.tabulated_rating_curve.add(
        Node(46, Point(26, 7), subnetwork_id=7),
        [tabulated_rating_curve.Static(level=[0.0, 1.0], flow_rate=[0.0, 2.0])],
    )
    model.tabulated_rating_curve.add(
        Node(47, Point(28, 7), subnetwork_id=7),
        [tabulated_rating_curve.Static(level=[0.0, 1.0], flow_rate=[0.0, 2.0])],
    )
    model.basin.add(Node(48, Point(26, 8), subnetwork_id=7), basin_data)
    model.pump.add(
        Node(49, Point(27, 8), subnetwork_id=7),
        [pump.Static(flow_rate=[4e-3], max_flow_rate=0.004)],
    )
    model.basin.add(Node(50, Point(28, 8), subnetwork_id=7), basin_data)
    model.user_demand.add(
        Node(51, Point(25, 9), subnetwork_id=7),
        [
            user_demand.Static(
                demand=[1e-3], return_factor=0.9, min_level=0.9, demand_priority=3
            )
        ],
    )
    model.tabulated_rating_curve.add(
        Node(52, Point(26, 9), subnetwork_id=7),
        [tabulated_rating_curve.Static(level=[0.0, 1.0], flow_rate=[0.0, 2.0])],
    )
    model.user_demand.add(
        Node(53, Point(28, 9), subnetwork_id=7),
        [
            user_demand.Static(
                demand=[1e-3], return_factor=0.9, min_level=0.9, demand_priority=3
            )
        ],
    )
    model.basin.add(Node(54, Point(26, 10), subnetwork_id=7), basin_data)
    model.outlet.add(
        Node(55, Point(26, 11), subnetwork_id=7),
        [outlet.Static(flow_rate=[0.003], max_flow_rate=3.0)],
    )
    model.terminal.add(Node(56, Point(26, 12), subnetwork_id=7))
    model.user_demand.add(
        Node(57, Point(29, 6), subnetwork_id=7),
        [
            user_demand.Static(
                demand=[1e-3], return_factor=0.9, min_level=0.9, demand_priority=2
            )
        ],
    )

    # Missing demand
    model.user_demand.add(
        Node(60, Point(21, -1), subnetwork_id=1),
        [user_demand.Static(return_factor=[0.9], demand_priority=2, min_level=0.0)],
    )

    model.link.add(model.flow_boundary[1], model.basin[2])
    model.link.add(model.basin[2], model.linear_resistance[3])
    model.link.add(model.linear_resistance[3], model.basin[4])
    model.link.add(model.basin[4], model.linear_resistance[5])
    model.link.add(model.linear_resistance[5], model.basin[6])
    model.link.add(model.basin[6], model.linear_resistance[7])
    model.link.add(model.linear_resistance[7], model.basin[8])
    model.link.add(model.basin[8], model.linear_resistance[9])
    model.link.add(model.linear_resistance[9], model.basin[10])
    model.link.add(model.pump[11], model.basin[12])
    model.link.add(model.basin[12], model.outlet[13])
    model.link.add(model.outlet[13], model.terminal[14])
    model.link.add(model.basin[12], model.user_demand[20])
    model.link.add(model.basin[12], model.pump[15])
    model.link.add(model.pump[15], model.basin[16])
    model.link.add(model.basin[16], model.outlet[17])
    model.link.add(model.outlet[17], model.basin[18])
    model.link.add(model.basin[16], model.user_demand[21])
    model.link.add(model.basin[18], model.user_demand[22])
    model.link.add(model.basin[16], model.outlet[23])
    model.link.add(model.outlet[23], model.terminal[19])
    model.link.add(model.user_demand[20], model.basin[12])
    model.link.add(model.user_demand[21], model.basin[16])
    model.link.add(model.user_demand[22], model.basin[18])
    model.link.add(model.pump[24], model.basin[25])
    model.link.add(model.basin[25], model.tabulated_rating_curve[26])
    model.link.add(model.tabulated_rating_curve[26], model.basin[31])
    model.link.add(model.basin[31], model.user_demand[32])
    model.link.add(model.user_demand[32], model.basin[31])
    model.link.add(model.pump[38], model.basin[35])
    model.link.add(model.basin[35], model.outlet[36])
    model.link.add(model.outlet[36], model.terminal[37])
    model.link.add(model.basin[35], model.user_demand[34])
    model.link.add(model.basin[35], model.pump[39])
    model.link.add(model.pump[39], model.basin[42])
    model.link.add(model.basin[42], model.outlet[41])
    model.link.add(model.outlet[41], model.basin[40])
    model.link.add(model.basin[40], model.user_demand[45])
    model.link.add(model.basin[42], model.tabulated_rating_curve[46])
    model.link.add(model.tabulated_rating_curve[46], model.basin[48])
    model.link.add(model.basin[48], model.pump[49])
    model.link.add(model.pump[49], model.basin[50])
    model.link.add(model.basin[50], model.user_demand[53])
    model.link.add(model.basin[48], model.tabulated_rating_curve[52])
    model.link.add(model.tabulated_rating_curve[52], model.basin[54])
    model.link.add(model.basin[48], model.user_demand[51])
    model.link.add(model.user_demand[51], model.basin[54])
    model.link.add(model.basin[54], model.outlet[55])
    model.link.add(model.outlet[55], model.terminal[56])
    model.link.add(model.basin[42], model.outlet[43])
    model.link.add(model.outlet[43], model.basin[44])
    model.link.add(model.basin[44], model.tabulated_rating_curve[47])
    model.link.add(model.tabulated_rating_curve[47], model.basin[50])
    model.link.add(model.user_demand[34], model.basin[35])
    model.link.add(model.user_demand[45], model.basin[40])
    model.link.add(model.user_demand[53], model.basin[50])
    model.link.add(model.basin[44], model.user_demand[57])
    model.link.add(model.user_demand[57], model.basin[44])
    model.link.add(model.basin[2], model.pump[11])
    model.link.add(model.basin[6], model.pump[24])
    model.link.add(model.basin[10], model.pump[38])
    model.link.add(model.basin[8], model.user_demand[60])
    model.link.add(model.user_demand[60], model.basin[8])

    return model


def subnetworks_with_sources_model() -> Model:
    """Generate a model with subnetworks which contain sources."""
    model = main_network_with_subnetworks_model()

    model.flow_boundary.add(
        Node(58, Point(3, 5), subnetwork_id=3),
        [flow_boundary.Static(flow_rate=[0.003])],
    )
    model.flow_boundary.add(
        Node(59, Point(28, 5), subnetwork_id=7),
        [flow_boundary.Static(flow_rate=[0.003])],
    )

    model.link.add(model.flow_boundary[58], model.basin[16])
    model.link.add(model.flow_boundary[59], model.basin[44])

    return model


def level_demand_model() -> Model:
    """Small model with LevelDemand nodes."""
    model = Model(
        starttime="2020-01-01",
        endtime="2020-02-01",
        crs="EPSG:28992",
        allocation=Allocation(use_allocation=True, timestep=1e5),
        experimental=Experimental(concentration=True),
    )
    model.flow_boundary.add(
        Node(1, Point(0, 0), subnetwork_id=2), [flow_boundary.Static(flow_rate=[1e-3])]
    )
    model.basin.add(
        Node(2, Point(1, 0), subnetwork_id=2),
        [
            basin.Profile(area=1000.0, level=[0.0, 1.0]),
            basin.Time(
                time=["2020-01-01", "2020-01-16"],
                precipitation=[1e-6, 0.0],
            ),
            basin.State(level=[0.5]),
        ],
    )
    model.user_demand.add(
        Node(3, Point(2, 0), subnetwork_id=2),
        [
            user_demand.Static(
                demand=[1.5e-3], return_factor=0.2, min_level=0.2, demand_priority=2
            )
        ],
    )
    model.level_demand.add(
        Node(4, Point(1, -1), subnetwork_id=2),
        [level_demand.Static(min_level=[1.0], max_level=1.5, demand_priority=1)],
    )
    model.basin.add(
        Node(5, Point(2, -1), subnetwork_id=2),
        [basin.Profile(area=1000.0, level=[0.0, 1.0]), basin.State(level=[0.5])],
    )

    # Isolated LevelDemand + Basin pair to test optional min_level
    model.level_demand.add(
        Node(6, Point(3, -1), subnetwork_id=3),
        [level_demand.Static(max_level=[1.0], demand_priority=1)],
    )
    model.basin.add(
        Node(7, Point(3, 0), subnetwork_id=3),
        [basin.Profile(area=1000.0, level=[0.0, 1.0]), basin.State(level=[2.0])],
    )

    model.link.add(model.flow_boundary[1], model.basin[2])
    model.link.add(model.basin[2], model.user_demand[3])
    model.link.add(model.level_demand[4], model.basin[2])
    model.link.add(model.user_demand[3], model.basin[5])
    model.link.add(model.level_demand[4], model.basin[5])

    model.link.add(model.level_demand[6], model.basin[7])

    return model


def flow_demand_model() -> Model:
    """Small model with a FlowDemand."""
    model = Model(
        starttime="2020-01-01 00:00:00",
        endtime="2021-01-01 00:00:00",
        crs="EPSG:28992",
        allocation=Allocation(use_allocation=True, timestep=1e5),
        experimental=Experimental(concentration=True),
    )

    model.tabulated_rating_curve.add(
        Node(2, Point(1, 0), subnetwork_id=2),
        [tabulated_rating_curve.Static(level=[0.0, 2.0], flow_rate=[0.0, 2e-3])],
    )

    model.level_boundary.add(
        Node(1, Point(0, 0), subnetwork_id=2),
        [level_boundary.Static(node_id=[1], level=[2.0])],
    )

    model.basin.add(
        Node(3, Point(2, 0), subnetwork_id=2),
        [basin.Profile(area=1e3, level=[0.0, 1.0]), basin.State(level=[1.0])],
    )
    model.basin.add(
        Node(7, Point(3, -1), subnetwork_id=2),
        [basin.Profile(area=1e3, level=[0.0, 1.0]), basin.State(level=[1.0])],
    )

    model.user_demand.add(
        Node(4, Point(3, 0), subnetwork_id=2),
        [
            user_demand.Static(
                demand_priority=[3], demand=1e-3, return_factor=1.0, min_level=0.2
            )
        ],
    )
    model.user_demand.add(
        Node(6, Point(2, -1), subnetwork_id=2),
        [
            user_demand.Static(
                demand_priority=[1], demand=1e-3, return_factor=1.0, min_level=0.2
            )
        ],
    )
    model.user_demand.add(
        Node(8, Point(3, -2), subnetwork_id=2),
        [
            user_demand.Static(
                demand_priority=[4], demand=2e-3, return_factor=1.0, min_level=0.2
            )
        ],
    )

    model.flow_demand.add(
        Node(5, Point(1, -1), subnetwork_id=2),
        [flow_demand.Static(demand=2e-3, demand_priority=[2])],
    )

    model.link.add(
        model.level_boundary[1],
        model.tabulated_rating_curve[2],
    )
    model.link.add(model.tabulated_rating_curve[2], model.basin[3])
    model.link.add(model.basin[3], model.user_demand[4])
    model.link.add(model.user_demand[4], model.basin[7])
    model.link.add(model.basin[7], model.user_demand[8])
    model.link.add(model.user_demand[8], model.basin[7])
    model.link.add(model.basin[3], model.user_demand[6])
    model.link.add(model.user_demand[6], model.basin[7])
    model.link.add(model.flow_demand[5], model.tabulated_rating_curve[2])

    return model


def linear_resistance_demand_model():
    """Small model with a FlowDemand for a node with a max flow rate."""
    model = Model(
        starttime="2020-01-01 00:00:00",
        endtime="2021-01-01 00:00:00",
        crs="EPSG:28992",
        allocation=Allocation(use_allocation=True),
        experimental=Experimental(concentration=True),
    )

    model.basin.add(
        Node(1, Point(0, 0), subnetwork_id=2),
        [basin.Profile(area=1e3, level=[0.0, 1.0]), basin.State(level=[1.0])],
    )
    model.basin.add(
        Node(3, Point(2, 0), subnetwork_id=2),
        [basin.Profile(area=1e3, level=[0.0, 1.0]), basin.State(level=[1.0])],
    )

    model.linear_resistance.add(
        Node(2, Point(0, 1), subnetwork_id=2),
        [linear_resistance.Static(resistance=1.0, max_flow_rate=[2.0])],
    )

    model.flow_demand.add(
        Node(4, Point(1, 1), subnetwork_id=2, source_priority=1),
        [flow_demand.Static(demand_priority=[1], demand=2.0)],
    )

    model.link.add(model.basin[1], model.linear_resistance[2])
    model.link.add(model.linear_resistance[2], model.basin[3])
    model.link.add(model.flow_demand[4], model.linear_resistance[2])

    return model


def fair_distribution_model():
    """See the behavior of allocation with few restrictions within the graph."""
    model = Model(
        starttime="2020-01-01 00:00:00",
        endtime="2020-01-07 00:00:00",
        crs="EPSG:28992",
        allocation=Allocation(use_allocation=True),
        experimental=Experimental(concentration=True),
    )

    model.level_boundary.add(
        Node(1, Point(0, 0), subnetwork_id=1),
        [
            level_boundary.Static(
                level=[1.0],
            )
        ],
    )

    model.pump.add(
        Node(
            2,
            Point(1, 0),
            subnetwork_id=1,
        ),
        [pump.Static(flow_rate=9.0, max_flow_rate=[9.0])],
    )

    model.basin.add(
        Node(3, Point(2, 0), subnetwork_id=1),
        [basin.Profile(area=1e3, level=[0.0, 1.0]), basin.State(level=[1.0])],
    )

    model.linear_resistance.add(
        Node(4, Point(3, 0), subnetwork_id=1),
        [linear_resistance.Static(resistance=[1.0])],
    )

    model.basin.add(
        Node(5, Point(4, 0), subnetwork_id=1),
        [basin.Profile(area=1e3, level=[0.0, 1.0]), basin.State(level=[1.0])],
    )

    model.user_demand.add(
        Node(6, Point(2, 1), subnetwork_id=1),
        [
            user_demand.Static(
                demand_priority=[1], demand=1.0, return_factor=1.0, min_level=0.2
            )
        ],
    )

    model.user_demand.add(
        Node(7, Point(2, -1), subnetwork_id=1),
        [
            user_demand.Static(
                demand_priority=[1], demand=2.0, return_factor=1.0, min_level=0.2
            )
        ],
    )

    model.user_demand.add(
        Node(8, Point(4, 1), subnetwork_id=1),
        [
            user_demand.Static(
                demand_priority=[1], demand=3.0, return_factor=1.0, min_level=0.2
            )
        ],
    )

    model.user_demand.add(
        Node(9, Point(4, -1), subnetwork_id=1),
        [
            user_demand.Time(
                demand_priority=1,
                time=pd.date_range(start="2020-01", end="2021-01", freq="MS"),
                demand=np.linspace(1.0, 5.0, 13),
                return_factor=1.0,
                min_level=0.2,
            )
        ],
    )

    model.link.add(model.level_boundary[1], model.pump[2])
    model.link.add(model.pump[2], model.basin[3])
    model.link.add(model.basin[3], model.linear_resistance[4])
    model.link.add(model.linear_resistance[4], model.basin[5])
    model.link.add(model.basin[3], model.user_demand[6])
    model.link.add(model.basin[3], model.user_demand[7])
    model.link.add(model.basin[5], model.user_demand[8])
    model.link.add(model.basin[5], model.user_demand[9])
    model.link.add(model.user_demand[6], model.basin[3])
    model.link.add(model.user_demand[7], model.basin[3])
    model.link.add(model.user_demand[8], model.basin[5])
    model.link.add(model.user_demand[9], model.basin[5])

    return model


def allocation_training_model():
    model = Model(
        starttime="2022-01-01",
        endtime="2023-01-01",
        crs="EPSG:4326",
        allocation=Allocation(use_allocation=True),
        experimental=Experimental(concentration=True),
    )

    flow_boundary_times = pd.date_range(start="2022-01-01", end="2023-01-01", freq="MS")

    # Flow boundaries
    main = model.flow_boundary.add(
        Node(1, Point(0.0, 0.0), subnetwork_id=1, name="Main"),
        [
            flow_boundary.Time(
                time=flow_boundary_times,
                flow_rate=[
                    47.3,
                    156.7,
                    77.6,
                    47.8,
                    26.6,
                    23.1,
                    18.6,
                    15.6,
                    23.1,
                    35.6,
                    24.4,
                    20.0,
                    29.4,
                ],
            )
        ],
    )

    minor = model.flow_boundary.add(
        Node(2, Point(-3.0, 0.0), subnetwork_id=1, name="Minor"),
        [
            flow_boundary.Time(
                time=flow_boundary_times,
                flow_rate=[
                    0.2,
                    28.3,
                    16.0,
                    11.2,
                    8.5,
                    9.6,
                    9.2,
                    7.9,
                    7.5,
                    7.2,
                    7.4,
                    10.0,
                    8.3,
                ],
            )
        ],
    )

    level = model.level_demand.add(
        Node(11, Point(1, 1), subnetwork_id=1, name="test"),
        [
            level_demand.Static(
                min_level=[2],
                max_level=5,
                demand_priority=1,
            )
        ],
    )

    # Confluence
    conf = model.basin.add(
        Node(3, Point(-1.5, -1), subnetwork_id=1, name="confluence"),
        [
            basin.Profile(area=[672000, 5600000], level=[0, 6]),
            basin.State(level=[4]),
        ],
    )

    tbr_conf = model.tabulated_rating_curve.add(
        Node(4, Point(-1.5, -1.5), subnetwork_id=1, name="tbr_conf"),
        [
            tabulated_rating_curve.Static(
                level=[0.0, 2, 5],
                flow_rate=[0.0, 50, 200],
            )
        ],
    )

    # Irrigation
    irr = model.user_demand.add(
        Node(6, Point(-1.5, 0.5), subnetwork_id=1, name="irrigation"),
        [
            user_demand.Time(
                demand=[0.0, 0.0, 10, 12, 12, 0.0],
                return_factor=0,
                min_level=0,
                demand_priority=3,
                time=[
                    "2022-01-01",
                    "2022-03-31",
                    "2022-04-01",
                    "2022-07-01",
                    "2022-09-30",
                    "2022-10-01",
                ],
            )
        ],
    )

    # Reservoir
    reservoir = model.basin.add(
        Node(7, Point(-0.75, -0.5), subnetwork_id=1, name="reservoir"),
        [
            basin.Profile(area=[20000000, 32300000], level=[0, 7]),
            basin.State(level=[3.5]),
        ],
    )

    rsv_weir = model.tabulated_rating_curve.add(
        Node(8, Point(-1.125, -0.75), subnetwork_id=1, name="rsv_weir"),
        [
            tabulated_rating_curve.Static(
                level=[0.0, 1.5, 5],
                flow_rate=[0.0, 45, 200],
            )
        ],
    )

    # Public water use
    city = model.user_demand.add(
        Node(9, Point(-0.75, -1), subnetwork_id=1, name="city"),
        [
            user_demand.Time(
                # Total demand in m³/s
                demand=[2.0, 2.3, 2.3, 2.4, 3, 3, 4, 3, 2.5, 2.2, 2.0, 2.0],
                return_factor=0.4,
                min_level=0,
                demand_priority=2,
                time=pd.date_range(start="2022-01-01", periods=12, freq="MS"),
            )
        ],
    )

    # Industry
    industry = model.user_demand.add(
        Node(10, Point(0, -1.5), subnetwork_id=1, name="industry"),
        [
            user_demand.Time(
                # Total demand in m³/s
                demand=[4, 4, 4.5, 5, 5, 6, 7.5, 8, 5, 4, 3, 2.0],
                return_factor=0.5,
                min_level=0,
                demand_priority=1,
                time=pd.date_range(start="2022-01-01", periods=12, freq="MS"),
            )
        ],
    )

    sea = model.terminal.add(Node(5, Point(-1.5, -3.0), subnetwork_id=1, name="sea"))

    model.link.add(main, reservoir, name="main")
    model.link.add(minor, conf, name="minor")
    model.link.add(reservoir, irr, name="irr supplied")
    model.link.add(irr, conf, name="irr drain")
    model.link.add(reservoir, city, name="city supplied")
    model.link.add(city, conf, name="city returnflow")
    model.link.add(reservoir, rsv_weir, name="rsv2weir")
    model.link.add(rsv_weir, conf, name="weir2conf")
    model.link.add(conf, tbr_conf, name="conf2tbr")
    model.link.add(level, reservoir)
    model.link.add(reservoir, industry, name="industry supplied")
    model.link.add(industry, conf, name="ind2conf")
    model.link.add(tbr_conf, sea, name="sea")

    return model


def bommelerwaard_model():
    model = Model(
        starttime="2016-01-01",
        endtime="2016-03-31",
        crs="EPSG:28992",
        allocation=Allocation(use_allocation=True),
    )

    # Node coordinates
    # fmt: off
    node_x = [157911.0, 157590.0, 157144.0, 156524.0, 156002.0, 155654.0, 154861.0, 153866.0, 153371.0, 153165.0, 153165.0, 152882.0, 151979.0, 150805.0, 149859.0, 148989.0, 148000.0, 146826.0, 145826.0, 144858.0, 143868.0, 142357.0, 141183.0, 139639.0, 138552.0, 137073.0, 136170.0, 135214.0, 134496.0, 133844.0, 134006.7654029528, 140529.5715602443, 144107.29801441092, 148404.9328404525, 144565.42152378592, 132110.96228239915, 132511.25831499096, 136407.47303221817, 136532.0095756912, 150462.31150988708, 146663.9469339601, 141077.59341245628, 145534.22257531204, 144440.0800862277, 132172.17758981694, 133913.24714031082, 139241.884582289, 139229.2649554282, 141996.11814466133, 146926.18570495228, 149742.72867495014, 134001.7784781678, 140511.43071623502, 144114.159864619, 148428.15742856378, 145706.78262120075, 152711.23027878854, 134372.87504280824, 135062.73404117822, 141371.3756400652, 153748.8015887456]
    node_y = [424758.0, 424949.0, 425520.0, 426014.0, 425824.0, 425166.0, 424128.0, 422568.0, 421448.0, 420350.0, 419501.0, 418740.0, 418197.0, 417718.0, 417109.0, 416522.0, 416751.0, 416794.0, 416196.0, 416457.0, 417142.0, 416979.0, 417022.0, 417131.0, 416957.0, 416588.0, 416283.0, 415848.0, 415402.0, 414891.0, 424049.6417242855, 422282.59390241053, 420384.65364928555, 421497.23931491055, 418312.19015449396, 422732.40479873226, 422581.18185308645, 423114.90989654226, 422741.3002661232, 422065.24474441254, 417172.7376794012, 419111.94957062387, 420784.2974401186, 419476.663733652, 424021.3522585318, 422596.3658298403, 423446.61318958737, 421604.1476679087, 420427.3674631377, 418055.929248877, 420630.07021959015, 425462.30362264556, 423514.0466582834, 421751.3379762414, 422818.2405995826, 419014.5008120184, 424070.69150524394, 417854.8240475171, 425533.6683466148, 423621.0937442373, 424321.70942056755]
    def get_node(node_id) -> Node:
        return Node(node_id, Point(node_x[node_id-1], node_y[node_id-1]), subnetwork_id=1)
    # fmt: on

    model.flow_boundary.add(get_node(1), [flow_boundary.Static(flow_rate=[25.0])])

    # Basin data
    # fmt: off
    area = [[26353.574448882966, 964101.5985883019, 964101.5985883019, 635779.9835793016, 579778.6378754253, 349184.8614476993, 185573.08674421755, 180082.75873403362, 178984.6931319968, 175690.49632588646, 259143.48208068253, 173494.36512181288, 173494.36512181288, 136160.134652562, 146042.72507089312, 154827.24988718744, 102120.1009894215, 162513.70910144495, 170200.1683157025, 157023.38109126102], [206281.16814112786, 826472.9154935384, 777936.1700485671, 722658.209958461, 477277.9968755507, 226504.81207653254, 207629.41107015483, 206281.16814112786, 203584.6822830739, 208977.6539991818, 200888.19642501994, 9437.700503188857, 53929.71716107918, 76849.84695453783, 179316.30956058827, 8089.457574161877, 194146.98177988504, 194146.98177988504, 195495.22470891202, 202236.43935404692], [809990.5345369958, 1.8763071875983574e6, 1.6794487285716445e6, 1.445679308477423e6, 1.4210720010990838e6, 1.3718573863424056e6, 1.1832013631084724e6, 1.0417093456830225e6, 918672.8087913269, 1.8763071875983574e6, 393716.91805342585, 307591.34222923894, 297338.2974882643, 291186.4706436795, 282984.0348508998, 264528.5543171455, 211212.7216640774, 69720.70423862748, 38961.5700157036, 319894.9959184085], [498119.88990176126, 522718.4029833297, 694907.9945543089, 1.0116138504795028e6, 2.321484672073023e6, 2.090873611933319e6, 2.2507639469635137e6, 455072.49200901645, 1.7403448005209684e6, 439698.42133303615, 390501.3951698993, 430473.978927448, 347453.99727715447, 362828.0679531347, 384351.76689950714, 58421.46856872508, 402800.6517106835, 415099.9082514677, 421249.5365218598, 433548.7930626441], [269363.5235534985, 1.1502019071445009e6, 1.1423372787195812e6, 1.0853187226389137e6, 833650.6130414844, 749105.857473598, 540693.2042132269, 308686.6656780968, 267397.3664472686, 1.242611291137307e6, 263465.05223480874, 47187.77054951798, 245769.6382787395, 255600.4238098891, 255600.4238098891, 263465.05223480874, 259532.73802234893, 263465.05223480874, 263465.05223480874, 255600.4238098891], [313421.6892315141, 1.2779396257356377e6, 1.2051810193068935e6, 945861.8835736765, 852581.6189214401, 729451.6695804881, 393642.7168324373, 328346.5315758719, 317152.8998176035, 1.2779396257356377e6, 307824.8733523799, 300362.452180201, 294765.63630106684, 294765.63630106684, 289168.8204219327, 214544.60870014358, 154845.23932271232, 106339.50170354942, 50371.34291220762, 305959.2680593352], [449890.43875867943, 471427.74699712684, 564756.0826970657, 442711.33601253026, 2.1130492416165634e6, 2.464825276177871e6, 3.005651016387773e6, 1.122333062647982e6, 437925.2675150975, 3.005651016387773e6, 387671.5482920535, 129223.84943068451, 332631.7605715768, 346989.96606387506, 349383.00031259144, 404422.7880330682, 351776.0345613078, 351776.0345613078, 375706.37704847165, 349383.00031259144], [359253.437657411, 1.0963423873338231e6, 1.0633075884687738e6, 991043.9659514786, 964203.191873626, 875422.169923806, 759800.3738961335, 600820.4043580838, 439775.7598909686, 338606.68836675514, 332412.66357955843, 330347.98865049286, 330347.98865049286, 328283.3137214273, 320024.61400516494, 301442.53964357474, 272537.0906366566, 216790.86755188592, 128009.84560206598, 59875.572942901825], [388431.6774847039, 531168.6192110108, 666885.7113442206, 804942.753341796, 954699.5446611999, 912580.4471026176, 933639.9958819088, 379071.87802724115, 849401.800764744, 379071.87802724115, 379071.87802724115, 379071.87802724115, 292493.7330457108, 311213.33196063625, 329932.9308755617, 58498.74660914215, 365032.17884104705, 369712.0785697784, 369712.0785697784, 341632.6801973902], [390541.35730664065, 1.9571196832259337e6, 1.9372616481086467e6, 1.754126435360335e6, 1.2687077991599909e6, 800940.7497305681, 467767.0494294227, 401573.59903846664, 388334.90896027547, 375096.21888208424, 6619.345039095604, 370683.3221893538, 366270.42549662344, 357444.63211116265, 341999.49368660623, 328760.803608415, 280218.9399883806, 214025.48959742454, 22064.483463652014, 370683.3221893538], [444601.35129269253, 458074.11951368325, 476935.9950230702, 1.1748253888703876e6, 441906.7976484944, 485019.6559556646, 843395.2906340167, 1.0104576165743013e6, 476935.9950230702, 441906.7976484944, 406877.60027391865, 441906.7976484944, 24250.982797783232, 29640.0900861795, 48501.965595566464, 441906.7976484944, 412266.7075623149, 417655.8148507112, 439212.24400429626, 336819.2055247671], [463519.1766075378, 1.2422313933082013e6, 1.21044722119797e6, 1.1866090921152967e6, 1.1495275579866937e6, 1.0700671277111159e6, 1.0038501024814675e6, 593304.5460576484, 463519.1766075378, 458221.8145891659, 23838.12908267337, 444978.40954323625, 442329.72853405034, 423788.9614697488, 421140.2804605629, 415842.91844219103, 413194.2374330051, 389356.1083503317, 368166.6602768443, 455573.13357998], [616886.1998732195, 817560.0239283631, 1.5038149531045952e6, 1.0479633033990837e6, 537607.6520983479, 1.3056185836674164e6, 1.4418785876554768e6, 1.4939051346327362e6, 1.194133125859003e6, 450896.7404695821, 416212.3758180758, 418689.83043604053, 418689.83043604053, 416212.3758180758, 406302.55734621687, 393915.28425639315, 386482.9204024989, 331978.9188072747, 165989.45940363736, 445941.83123365266], [373425.3675163844, 382903.168722384, 585728.1145307756, 959153.48204716, 871957.7109519637, 943989.0001175606, 373425.3675163844, 818882.0241983659, 369634.2470339846, 344991.9638983856, 348783.08438078547, 344991.9638983856, 335514.162692386, 312767.43979798694, 308976.3193155871, 269169.55425038876, 32224.524100398656, 961049.04228836, 363947.56631038483, 961049.04228836], [375600.0, 751200.0], [919355.0, 1.83871e6], [231851.0, 463702.0], [892113.0, 1.784225e6], [302335.0, 604670.0]]
    level = [[-5.05, 8.61, 8.42, 6.33, 5.97, 5.12, 4.19, 3.33, 2.8, 2.31, 4.74, 1.35, 1.85, -3.81, -3.48, -2.1, -4.31, -0.57, 0.66, -1.59], [2.16, 8.58, 6.95, 6.26, 4.63, 3.75, 3.17, 2.66, 1.7, 3.45, 0.27, -6.8, -5.72, -5.01, -2.49, -6.98, -1.24, -0.98, -0.47, 0.96], [2.85, 8.36, 7.31, 6.21, 5.84, 5.41, 4.56, 4.24, 3.93, 8.55, 2.09, -0.3, -1.05, -2.05, -2.53, -3.53, -4.88, -5.82, -6.59, 0.89], [3.16, 3.73, 4.38, 4.79, 8.46, 6.8, 7.92, 2.08, 5.72, 1.83, -3.75, 0.17, -5.48, -5.19, -4.35, -6.46, -2.63, -1.3, -0.55, 1.13], [1.89, 7.35, 7.01, 6.6, 5.87, 5.48, 4.56, 2.64, 1.65, 8.33, 0.46, -6.02, -4.98, -4.75, -2.57, 0.95, -1.69, -0.7, -0.21, -2.37], [1.74, 8.07, 6.96, 5.4, 4.47, 4.07, 3.38, 2.76, 2.49, 8.29, -0.13, -1.34, -1.85, -2.1, -2.48, -3.78, -4.57, -5.43, -6.18, -0.61], [2.52, 3.11, 3.8, 2.27, 5.99, 6.38, 7.94, 4.71, 1.31, 8.17, -0.52, -6.07, -5.33, -4.83, -4.67, 0.85, -3.1, -2.72, -1.01, -4.39], [2.59, 7.96, 7.34, 6.15, 5.76, 4.96, 4.48, 3.96, 3.21, 1.84, 1.37, 0.92, 0.69, 0.22, -0.44, -2.68, -4.16, -5.52, -6.57, -7.78], [3.29, 4.2, 4.7, 5.5, 7.72, 6.68, 7.08, 2.13, 5.89, 1.65, 1.42, 0.96, -5.87, -5.23, -3.79, -7.65, -1.32, -0.19, 0.28, -3.08], [3.09, 7.53, 7.28, 6.1, 4.86, 4.43, 3.95, 3.46, 2.78, 2.22, -8.81, 1.5, 1.27, -0.31, -1.19, -2.81, -4.99, -6.34, -8.13, 1.96], [-0.23, 0.86, 1.74, 7.25, -0.44, 2.81, 4.57, 5.36, 2.52, -1.3, -5.03, -1.75, -8.55, -7.92, -7.5, -1.53, -4.62, -3.27, -2.22, -6.25], [2.25, 7.0, 5.88, 5.5, 5.05, 4.24, 3.82, 2.85, 1.99, 1.29, -7.12, 0.03, -0.42, -2.11, -2.79, -3.18, -3.96, -5.2, -5.45, 1.08], [3.5, 3.93, 6.84, 4.36, 3.05, 5.27, 6.11, 6.54, 4.79, 1.79, -0.93, 0.09, -0.32, -0.74, -1.6, -2.2, -3.8, -6.54, -7.19, 1.54], [1.86, 2.1, 2.42, 5.94, 3.34, 5.09, 1.38, 2.89, 0.34, -2.29, -1.45, -1.66, -2.52, -2.95, -3.85, -6.29, -7.2, 6.37, -0.86, 6.67], [-0.8, 0.2], [-0.4, 0.6], [0.0, 1.0], [1.85, 2.85], [1.15, 2.15]]
    initial_levels = [2.2, 2.15, 2.1, 2.05, 2, 1.95, 1.9, 1.85, 1.8, 1.75, 1.7, 1.65, 1.6, 1.55, 0.21, 0.61, 1.01, 2.86, 2.16]
    # fmt: on

    basin_index = 0

    for node_id in range(2, 30, 2):
        model.basin.add(
            get_node(node_id),
            [
                basin.Profile(area=area[basin_index], level=level[basin_index]),
                basin.State(level=[initial_levels[basin_index]]),
            ],
        )
        basin_index += 1

    for node_id in range(31, 36):
        model.basin.add(
            get_node(node_id),
            [
                basin.Profile(area=area[basin_index], level=level[basin_index]),
                basin.State(level=[initial_levels[basin_index]]),
                basin.Static(potential_evaporation=[3.47222e-8]),
            ],
        )
        basin_index += 1

    # Manning resistance data
    # fmt: off
    length = [1517.2787175825092, 1299.8608163460412, 3156.5555362481437, 2341.667212353994, 1660.917483492011, 2321.645616421698, 2174.5853746345365, 2189.9532110539512, 2167.7318491968667, 2723.6455761811376, 2722.6299070411033, 2625.174893926872, 2003.4327556985027, 1673.6325133202295, 9000.0, 4200.0]
    profile_width = [111.0, 54.0, 117.0, 117.0, 128.0, 123.0, 121.0, 52.0, 128.0, 130.0, 122.0, 100.0, 164.0, 161.0, 4.0, 4.0]
    profile_slope = [10.411311053984576, 12.192513368983958, 11.1716621253406, 2.9776674937965257, 6.295754026354319, 8.1351689612015, 6.308411214953271, 11.992263056092844, 8.653846153846155, 4.273504273504273, 5.541871921182267, 11.441144114411442, 2.925531914893617, 3.977272727272727, 5.0, 5.0]
    manning_n = [0.04, 0.04, 0.04, 0.04, 0.04, 0.04, 0.04, 0.04, 0.04, 0.04, 0.04, 0.04, 0.04, 0.04, 0.05, 0.05]
    # fmt: on

    manning_index = 0

    for node_id in range(3, 28, 2):
        model.manning_resistance.add(
            get_node(node_id),
            [
                manning_resistance.Static(
                    length=[length[manning_index]],
                    profile_width=profile_width[manning_index],
                    profile_slope=profile_slope[manning_index],
                    manning_n=[manning_n[manning_index]],
                )
            ],
        )
        manning_index += 1

    model.linear_resistance.add(
        get_node(29), [linear_resistance.Static(resistance=[1.0])]
    )

    model.level_boundary.add(get_node(30), [level_boundary.Static(level=[0.5])])

    pump_index = 0

    for node_id, flow_rate_node_id in zip(
        [37, 36, 39, 38, 42, 41, 40], [2.75, 2.29, 4.5, 2.0, 8.33, 1.17, 2.0]
    ):
        model.pump.add(
            get_node(node_id),
            [
                pump.Static(
                    flow_rate=[0, flow_rate_node_id],
                    max_flow_rate=[0, flow_rate_node_id],
                    control_state=["off", "on"],
                )
            ],
        )
        pump_index += 1

    for node_id, level in zip([43, 44], [[1.85, 2.85, 2.95], [1.15, 2.15, 2.25]]):
        model.tabulated_rating_curve.add(
            get_node(node_id),
            [tabulated_rating_curve.Static(level=level, flow_rate=[0.0, 0.1, 1.0])],
        )

    for node_id, listen_node_id, greater_than in zip(
        range(45, 52),
        [31, 31, 32, 32, 33, 35, 34],
        [
            [0.15, 0.25],
            [0.15, 0.25],
            [0.55, 0.65],
            [0.55, 0.65],
            [0.95, 1.05],
            [2.1, 2.2],
            [2.8, 2.9],
        ],
    ):
        # Skip this control node as it causes stability problems
        if node_id == 49:
            continue
        model.discrete_control.add(
            get_node(node_id),
            [
                discrete_control.Variable(
                    node_id=[node_id],
                    compound_variable_id=[node_id],
                    listen_node_id=[listen_node_id],
                    variable=["level"],
                ),
                discrete_control.Condition(
                    node_id=2 * [node_id],
                    compound_variable_id=2 * [node_id],
                    condition_id=[1, 2],
                    greater_than=greater_than,
                ),
                discrete_control.Logic(
                    node_id=3 * [node_id],
                    control_state=["off", "off", "on"],
                    truth_state=["FF", "TF", "TT"],
                ),
            ],
        )

    for node_id, demand, demand_priority, min_level in zip(
        range(52, 59),
        [0, 0, 0, 0, 0, 0, 24],
        [2, 2, 2, 2, 2, 3, 1],
        [-0.8, -0.4, 0, 1.85, 1.15, -6.0, -6.0],
    ):
        model.user_demand.add(
            get_node(node_id),
            [
                user_demand.Static(
                    demand=[demand],
                    demand_priority=[demand_priority],
                    min_level=[min_level],
                    return_factor=[0.0],
                )
            ],
        )

    for node_id, demand_priority, min_level in zip(
        range(59, 62), [2, 2, 3], [0.18, 0.58, 0.55]
    ):
        model.level_demand.add(
            get_node(node_id),
            [
                level_demand.Static(
                    demand_priority=[demand_priority], min_level=[min_level]
                )
            ],
        )

    # Link data
    # fmt: off
    from_node_id = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 18, 41, 35, 44, 34, 43, 33, 10, 40, 32, 38, 39, 26, 31, 36, 37, 26, 42, 45, 46, 47, 48, 49, 50, 51, 31, 52, 32, 53, 33, 54, 34, 55, 35, 56, 8, 57, 28, 58, 59, 60, 61]
    to_node_id = [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 41, 35, 44, 33, 43, 33, 42, 40, 34, 39, 32, 26, 38, 37, 31, 26, 36, 26, 36, 37, 38, 39, 42, 41, 40, 52, 31, 53, 32, 54, 33, 55, 34, 56, 35, 57, 8, 58, 28, 31, 32, 8]
    # fmt: on

    node_df = model.node_table().df

    def get_node_data(node_id):
        node_geom = get_node(node_id).geometry
        node_type = node_df.loc[node_df.index == node_id, "node_type"].to_numpy()[0]
        return NodeData(node_id, node_type, node_geom)

    # Add edges
    for from_node_id_, to_node_id_ in zip(from_node_id, to_node_id):
        # Skip DiscreteControl #49 as it causes stability problems
        if 49 in [from_node_id_, to_node_id_]:
            continue
        from_node_data = get_node_data(from_node_id_)
        to_node_data = get_node_data(to_node_id_)
        model.link.add(from_node_data, to_node_data)

    return model


def cyclic_demand_model():
    """Create a model that has cyclic User- Flow- and LevelDemand."""
    model = Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:28992",
        allocation=Allocation(use_allocation=True),
    )

    fb = model.flow_boundary.add(
        Node(1, Point(0, 0), subnetwork_id=1), [flow_boundary.Static(flow_rate=[1.0])]
    )

    bsn1 = model.basin.add(
        Node(2, Point(1, 0), subnetwork_id=1),
        [
            basin.Profile(level=[0.0, 1.0], area=[100.0, 100.0]),
            basin.State(level=[1.0]),
        ],
    )

    pmp = model.pump.add(
        Node(3, Point(2, 0), subnetwork_id=1), [pump.Static(flow_rate=[1.0])]
    )

    bsn2 = model.basin.add(
        Node(4, Point(3, 0), subnetwork_id=1),
        [
            basin.Profile(level=[0.0, 1.0], area=[100.0, 100.0]),
            basin.State(level=[1.0]),
        ],
    )

    time = ["2020-01-01", "2020-02-01", "2020-03-01"]

    ld = model.level_demand.add(
        Node(5, Point(1, 1), subnetwork_id=1, cyclic_time=True),
        [
            level_demand.Time(
                time=time,
                min_level=[0.5, 0.7, 0.5],
                max_level=[0.7, 0.9, 0.7],
                demand_priority=1,
            )
        ],
    )

    fd = model.flow_demand.add(
        Node(6, Point(2, -1), subnetwork_id=1, cyclic_time=True),
        [flow_demand.Time(time=time, demand=[0.5, 0.8, 0.5], demand_priority=2)],
    )

    ud = model.user_demand.add(
        Node(7, Point(3, -1), subnetwork_id=1, cyclic_time=True),
        [
            user_demand.Time(
                time=2 * time,
                demand_priority=[1, 1, 1, 2, 2, 2],
                demand=[0.2, 0.6, 0.2, 0.5, 0.3, 0.5],
                return_factor=[0.5, 0.7, 0.5, 0.5, 0.7, 0.5],
                min_level=0.0,
            )
        ],
    )

    model.link.add(fb, bsn1)
    model.link.add(bsn1, pmp)
    model.link.add(pmp, bsn2)
    model.link.add(ld, bsn1)
    model.link.add(fd, pmp)
    model.link.add(bsn2, ud)
    model.link.add(ud, bsn2)

    return model
