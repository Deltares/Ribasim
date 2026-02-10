from typing import Any

import numpy as np
import pandas as pd
from ribasim import Model
from ribasim.config import (
    Allocation,
    Experimental,
    Interpolation,
    Results,
    Solver,
)
from ribasim.geometry.node import Node
from ribasim.input_base import TableModel
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
                time=list(pd.date_range(start="2020-08-01", end="2020-09-01"))
                + list(pd.date_range(start="2020-10-01", end="2020-11-01")),
                demand=np.concatenate(
                    [np.linspace(0.0, 1e-4, num=32), np.linspace(2e-4, 0.0, num=32)]
                ),
                min_level=0.0,
                return_factor=np.concatenate(
                    [np.linspace(0.0, 0.1, num=32), np.linspace(0.2, 0.3, num=32)]
                ),
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


def minimal_subnetwork_model() -> Model:
    """Create a subnetwork that is minimal with non-trivial allocation."""
    model = Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:28992",
        allocation=Allocation(timestep=86400),
        experimental=Experimental(concentration=True, allocation=True),
    )

    basin_data: list[TableModel[Any]] = [
        basin.Profile(area=1000.0, level=[0.0, 1000.0]),
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
                time=["2020-01-01", "2020-01-02"],
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
        allocation=Allocation(timestep=86400),
        experimental=Experimental(concentration=True, allocation=True),
        results=Results(format="netcdf"),
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


def small_primary_secondary_network_model() -> Model:
    model = Model(
        starttime="2020-01-01",
        endtime="2020-01-20",
        crs="EPSG:28992",
        allocation=Allocation(timestep=86400),
        experimental=Experimental(concentration=True, allocation=True),
    )

    basin_data: list[TableModel[Any]] = [
        basin.Profile(area=300_000.0, level=[0.0, 1.0]),
        basin.State(level=[0.9]),
    ]

    model.basin.add(Node(2, Point(1, 0), subnetwork_id=1), basin_data)
    model.user_demand.add(
        Node(3, Point(1, 1), subnetwork_id=1),
        [
            user_demand.Static(
                demand=[1.0], return_factor=0.0, min_level=0.5, demand_priority=2
            )
        ],
    )
    outlet_data = outlet.Static(
        flow_rate=[3e-3], max_flow_rate=3.0, control_state="Ribasim.allocation"
    )

    model.outlet.add(
        Node(4, Point(2, 0), subnetwork_id=1),
        [outlet_data],
    )

    #################################### begin subnetwork 2 ####################################
    model.basin.add(Node(5, Point(3, 0), subnetwork_id=2), basin_data)

    model.user_demand.add(
        Node(6, Point(3, 1), subnetwork_id=2),
        [
            user_demand.Static(
                demand=[1.0], return_factor=0.0, min_level=0.5, demand_priority=2
            )
        ],
    )
    model.level_demand.add(
        Node(7, Point(1, -1), subnetwork_id=2),
        [level_demand.Static(min_level=[0.5], max_level=1.5, demand_priority=1)],
    )
    #################################### end subnetwork 2 ####################################
    model.link.add(model.basin[2], model.user_demand[3])  # 1
    model.link.add(model.basin[2], model.outlet[4])  # 2
    model.link.add(model.outlet[4], model.basin[5])  # 3
    model.link.add(model.basin[5], model.user_demand[6])  # 4
    model.link.add(model.user_demand[3], model.basin[2])  # 5
    model.link.add(model.user_demand[6], model.basin[5])  # 6
    model.link.add(model.level_demand[7], model.basin[5])  # 7

    return model


def medium_primary_secondary_network_model() -> Model:
    model = Model(
        starttime="2020-01-01",
        endtime="2020-01-20",
        crs="EPSG:28992",
        results=Results(format="netcdf"),
        allocation=Allocation(timestep=86400),
        experimental=Experimental(allocation=True),
    )

    basin_data: list[TableModel[Any]] = [
        basin.Profile(area=100_000.0, level=[0.0, 1.0]),
        basin.State(level=[0.5]),
    ]
    outlet_data = outlet.Static(
        flow_rate=[0.0], max_flow_rate=1.0, control_state="Ribasim.allocation"
    )

    outlet_data_2 = outlet.Static(
        flow_rate=[0.0], max_flow_rate=1e-3, control_state="Ribasim.allocation"
    )

    pump_data = pump.Static(
        flow_rate=[0.0], max_flow_rate=1.0, control_state="Ribasim.allocation"
    )

    model.level_demand.add(
        Node(18, Point(2.5, -0.5), subnetwork_id=1),
        [level_demand.Static(min_level=[0.5], max_level=[0.55], demand_priority=1)],
    )

    model.level_demand.add(
        Node(19, Point(1, 2), subnetwork_id=2),
        [level_demand.Static(min_level=[0.5], max_level=[0.55], demand_priority=2)],
    )

    model.level_demand.add(
        Node(20, Point(4, 2), subnetwork_id=3),
        [level_demand.Static(min_level=[0.5], max_level=[0.55], demand_priority=2)],
    )

    ##################################### begin subnetwork 1 ####################################

    # Inlet
    model.flow_boundary.add(
        Node(1, Point(0.0, 0.0), subnetwork_id=1),
        [flow_boundary.Static(flow_rate=[0.09])],
    )

    # first basin
    model.basin.add(Node(2, Point(1, 0), subnetwork_id=1, route_priority=0), basin_data)

    # outlet towards first subnetwork
    model.outlet.add(
        Node(3, Point(1, 1), subnetwork_id=1),
        [outlet_data_2],
    )

    # outlet towards second basin
    model.outlet.add(
        Node(4, Point(1.5, 0), subnetwork_id=1, route_priority=0),
        [outlet_data],
    )

    # second basin
    model.basin.add(Node(5, Point(2, 0), subnetwork_id=1, route_priority=0), basin_data)

    # pump towards first subnetwork
    model.pump.add(
        Node(6, Point(2, 1), subnetwork_id=1, route_priority=0),
        [pump_data],
    )

    # outlet towards fourth basin
    model.outlet.add(
        Node(16, Point(2.5, 0), subnetwork_id=1, route_priority=0),
        [outlet_data],
    )

    # third basin
    model.basin.add(Node(7, Point(3, 0), subnetwork_id=1, route_priority=0), basin_data)

    # outlet towards second subnetwork
    model.outlet.add(
        Node(8, Point(3, 1), subnetwork_id=1),
        [outlet_data_2],
    )

    # outlet towards fourth basin
    model.outlet.add(
        Node(9, Point(3.5, 0), subnetwork_id=1, route_priority=0),
        [outlet_data],
    )

    # fourth basin
    model.basin.add(
        Node(10, Point(4, 0), subnetwork_id=1, route_priority=0), basin_data
    )

    # pump towards second subnetwork
    model.pump.add(
        Node(11, Point(4, 1), subnetwork_id=1, route_priority=0),
        [pump_data],
    )

    # user demand at the end of primary network
    model.user_demand.add(
        Node(12, Point(4.5, 0), subnetwork_id=1),
        [
            user_demand.Static(
                demand=[0.03], return_factor=0.0, min_level=0.0, demand_priority=3
            )
        ],
    )

    # outlet for overflow
    model.outlet.add(Node(21, Point(4, -0.5), subnetwork_id=1), [outlet_data])
    model.terminal.add(Node(22, Point(4, -1), subnetwork_id=1))

    ##################################### end subnetwork 1 #####################################

    #################################### begin subnetwork 2 ####################################
    model.basin.add(Node(13, Point(1.5, 1.5), subnetwork_id=2), basin_data)

    model.user_demand.add(
        Node(14, Point(1.5, 2), subnetwork_id=2),
        [
            user_demand.Static(
                demand=[0.03], return_factor=0.0, min_level=0.0, demand_priority=3
            )
        ],
    )

    #################################### end subnetwork 2 ####################################

    ################################# begin subnetwork 3 ####################################
    model.basin.add(Node(15, Point(3.5, 1.5), subnetwork_id=3), basin_data)
    model.user_demand.add(
        Node(17, Point(3.5, 2), subnetwork_id=3),
        [
            user_demand.Static(
                demand=[0.03], return_factor=0.0, min_level=0.0, demand_priority=3
            )
        ],
    )
    ################################# end subnetwork 3 ####################################

    model.link.add(model.flow_boundary[1], model.basin[2])
    model.link.add(model.basin[2], model.outlet[3])
    model.link.add(model.basin[2], model.outlet[4])
    model.link.add(model.outlet[4], model.basin[5])
    model.link.add(model.basin[5], model.pump[6])
    model.link.add(model.basin[5], model.outlet[16])
    model.link.add(model.outlet[16], model.basin[7])
    model.link.add(model.basin[7], model.outlet[8])
    model.link.add(model.basin[7], model.outlet[9])
    model.link.add(model.outlet[9], model.basin[10])
    model.link.add(model.basin[10], model.pump[11])
    model.link.add(model.basin[10], model.user_demand[12])
    model.link.add(model.user_demand[12], model.basin[10])
    model.link.add(model.basin[10], model.outlet[21])
    model.link.add(model.outlet[21], model.terminal[22])

    model.link.add(model.level_demand[18], model.basin[2])
    model.link.add(model.level_demand[18], model.basin[5])
    model.link.add(model.level_demand[18], model.basin[7])
    model.link.add(model.level_demand[18], model.basin[10])

    # connect to first subnetwork
    model.link.add(model.outlet[3], model.basin[13])
    model.link.add(model.pump[6], model.basin[13])
    model.link.add(model.basin[13], model.user_demand[14])
    model.link.add(model.user_demand[14], model.basin[13])
    model.link.add(model.level_demand[19], model.basin[13])

    # connect to second subnetwork
    model.link.add(model.outlet[8], model.basin[15])
    model.link.add(model.pump[11], model.basin[15])
    model.link.add(model.basin[15], model.user_demand[17])
    model.link.add(model.user_demand[17], model.basin[15])
    model.link.add(model.level_demand[20], model.basin[15])

    return model


def medium_primary_secondary_network_verification_model() -> Model:
    model = medium_primary_secondary_network_model()
    # set all subnetwork ids to 2 for verification purposes
    assert model.node.df is not None
    model.node.df.subnetwork_id = 2
    return model


def small_primary_secondary_network_verification_model() -> Model:
    model = Model(
        starttime="2020-01-01",
        endtime="2020-01-20",
        crs="EPSG:28992",
        allocation=Allocation(timestep=86400),
        experimental=Experimental(concentration=True, allocation=True),
        results=Results(format="netcdf"),
    )

    basin_data: list[TableModel[Any]] = [
        basin.Profile(area=300_000.0, level=[0.0, 1.0]),
        basin.State(level=[0.9]),
    ]

    model.basin.add(Node(2, Point(1, 0), subnetwork_id=2), basin_data)
    model.user_demand.add(
        Node(3, Point(1, 1), subnetwork_id=2),
        [
            user_demand.Static(
                demand=[1.0], return_factor=0.0, min_level=0.5, demand_priority=2
            )
        ],
    )
    outlet_data = outlet.Static(
        flow_rate=[3e-3], max_flow_rate=1.0, control_state="Ribasim.allocation"
    )

    model.outlet.add(
        Node(4, Point(2, 0), subnetwork_id=2),
        [outlet_data],
    )

    model.basin.add(Node(5, Point(3, 0), subnetwork_id=2), basin_data)

    model.user_demand.add(
        Node(6, Point(3, 1), subnetwork_id=2),
        [
            user_demand.Static(
                demand=[1.0], return_factor=0.0, min_level=0.5, demand_priority=2
            )
        ],
    )
    model.level_demand.add(
        Node(7, Point(1, -1), subnetwork_id=2),
        [level_demand.Static(min_level=[0.5], max_level=1.5, demand_priority=1)],
    )

    model.link.add(model.basin[2], model.user_demand[3])
    model.link.add(model.basin[2], model.outlet[4])
    model.link.add(model.outlet[4], model.basin[5])
    model.link.add(model.basin[5], model.user_demand[6])
    model.link.add(model.user_demand[3], model.basin[2])
    model.link.add(model.user_demand[6], model.basin[5])
    model.link.add(model.level_demand[7], model.basin[5])

    return model


def level_demand_model() -> Model:
    """Small model with LevelDemand nodes."""
    model = Model(
        starttime="2020-01-01",
        endtime="2020-02-01",
        crs="EPSG:28992",
        allocation=Allocation(timestep=86400),
        experimental=Experimental(concentration=True, allocation=True),
    )
    model.flow_boundary.add(
        Node(1, Point(0, 0), subnetwork_id=2), [flow_boundary.Static(flow_rate=[1e-3])]
    )
    model.basin.add(
        Node(2, Point(1, 0), subnetwork_id=2),
        [
            basin.Profile(area=1000.0, level=[0.0, 10.0]),
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
        [basin.Profile(area=1000.0, level=[0.0, 10.0]), basin.State(level=[0.5])],
    )

    # Isolated LevelDemand + Basin pair to test optional min_level
    model.level_demand.add(
        Node(6, Point(3, -1), subnetwork_id=3),
        [level_demand.Static(min_level=[1.0], demand_priority=1)],
    )
    model.basin.add(
        Node(7, Point(3, 0), subnetwork_id=3),
        [basin.Profile(area=1000.0, level=[0.0, 10.0]), basin.State(level=[2.0])],
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
        allocation=Allocation(timestep=1e5),
        experimental=Experimental(concentration=True, allocation=True),
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
        [basin.Profile(area=1e4, level=[0.0, 10.0]), basin.State(level=[1.0])],
    )
    model.basin.add(
        Node(7, Point(3, -1), subnetwork_id=2),
        [basin.Profile(area=1e4, level=[0.0, 10.0]), basin.State(level=[1.0])],
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
        experimental=Experimental(concentration=True, allocation=True),
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
        Node(4, Point(1, 1), subnetwork_id=2, route_priority=1),
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
        endtime="2020-01-02 00:00:00",
        crs="EPSG:28992",
        experimental=Experimental(concentration=True, allocation=True),
    )

    b = model.basin.add(
        Node(1, Point(0, 0), subnetwork_id=2),
        [basin.Profile(level=[0.0, 10.0], area=1000.0), basin.State(level=[1.0])],
    )

    n_user_demand = 25

    for i in range(n_user_demand):
        theta = 2 * np.pi * i / n_user_demand
        ud = model.user_demand.add(
            Node(i + 2, Point(np.cos(theta), np.sin(theta)), subnetwork_id=2),
            [
                user_demand.Static(
                    demand_priority=[1],
                    # Demands sum to twice the initial storage in the Basin
                    demand=2000
                    * (i + 1)
                    / (0.5 * n_user_demand * (n_user_demand + 1) * 86400),
                    return_factor=0.0,
                    min_level=0.0,
                )
            ],
        )

        model.link.add(ud, b)
        model.link.add(b, ud)

    return model


def allocation_training_model() -> Model:
    model = Model(
        starttime="2022-01-01",
        endtime="2023-01-01",
        crs="EPSG:4326",
        experimental=Experimental(allocation=True),
        interpolation=Interpolation(flow_boundary="linear"),
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
                demand_priority=4,
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
                demand_priority=3,
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
                demand_priority=2,
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


def cyclic_demand_model():
    """Create a model that has cyclic User- Flow- and LevelDemand."""
    model = Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:28992",
        experimental=Experimental(allocation=True),
    )

    fb = model.flow_boundary.add(
        Node(1, Point(0, 0), subnetwork_id=2), [flow_boundary.Static(flow_rate=[1e-3])]
    )

    bsn1 = model.basin.add(
        Node(2, Point(1, 0), subnetwork_id=2),
        [
            basin.Profile(level=[0.0, 100.0], area=1000.0),
            basin.State(level=[1.0]),
        ],
    )

    pmp = model.pump.add(
        Node(3, Point(2, 0), subnetwork_id=2),
        [pump.Static(flow_rate=[1.0], control_state="Ribasim.allocation")],
    )

    bsn2 = model.basin.add(
        Node(4, Point(3, 0), subnetwork_id=2),
        [
            basin.Profile(level=[0.0, 100.0], area=1000.0),
            basin.State(level=[1.0]),
        ],
    )

    time = ["2020-01-01", "2020-02-01", "2020-03-01"]

    ld = model.level_demand.add(
        Node(5, Point(1, 1), subnetwork_id=2, cyclic_time=True),
        [
            level_demand.Time(
                time=time,
                min_level=[0.5, 0.7, 0.5],
                max_level=[0.7, 0.9, 0.7],
                demand_priority=3,
            )
        ],
    )

    fd = model.flow_demand.add(
        Node(6, Point(2, -1), subnetwork_id=2, cyclic_time=True),
        [flow_demand.Time(time=time, demand=[5e-4, 8e-4, 5e-4], demand_priority=2)],
    )

    ud = model.user_demand.add(
        Node(7, Point(3, -1), subnetwork_id=2, cyclic_time=True),
        [
            user_demand.Time(
                time=2 * time,
                demand_priority=[1, 1, 1, 2, 2, 2],
                demand=[2e-4, 6e-4, 2e-4, 5e-4, 3e-4, 5e-4],
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


def allocation_control_model() -> Model:
    """Create a model that has a pump controlled by allocation."""
    model = Model(
        starttime="2020-01-01",
        endtime="2023-01-01",
        crs="EPSG:28992",
        experimental=Experimental(allocation=True),
    )

    lb = model.level_boundary.add(
        Node(1, Point(0, 0), subnetwork_id=1), [level_boundary.Static(level=[5.0])]
    )

    out = model.outlet.add(
        Node(2, Point(1, 0), subnetwork_id=1),
        [
            outlet.Static(
                flow_rate=[0.0], control_state="Ribasim.allocation", max_flow_rate=[9.0]
            )
        ],
    )

    bsn = model.basin.add(
        Node(3, Point(2, 0), subnetwork_id=1),
        [
            basin.State(level=[1.0]),
            basin.Profile(level=[0.0, 100.0], area=[100.0, 100.0]),
        ],
    )

    user = model.user_demand.add(
        Node(4, Point(2, -1), subnetwork_id=1, cyclic_time=True),
        [
            user_demand.Time(
                time=["2020-01-01", "2020-06-01", "2021-01-01"],
                demand=[0.0, 10.0, 0.0],
                return_factor=0.0,
                min_level=-5.0,
                demand_priority=1,
            )
        ],
    )

    model.link.add(lb, out)
    model.link.add(out, bsn)
    model.link.add(bsn, user)
    model.link.add(user, bsn)

    return model


def multi_level_demand_model() -> Model:
    """Create a model that has a level demand with multiple priorities."""
    model = Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:28992",
        experimental=Experimental(allocation=True),
    )

    fb = model.flow_boundary.add(
        Node(1, Point(0, 0), subnetwork_id=2), [flow_boundary.Static(flow_rate=[1e-3])]
    )

    b = model.basin.add(
        Node(2, Point(1, 0), subnetwork_id=2),
        [
            basin.Profile(level=[0.0, 1.0, 10.0], storage=[1000.0, 2000.0, 10000.0]),
            basin.State(level=[5.0]),
        ],
    )

    ld = model.level_demand.add(
        Node(3, Point(0, 1), subnetwork_id=2),
        [
            level_demand.Time(
                min_level=2 * [3.0, 4.0],
                max_level=2 * [6.0, 5.0],
                demand_priority=2 * [1, 3],
                time=["2020-01-01", "2020-01-01", "2021-01-01", "2021-01-01"],
            )
        ],
    )

    ud = model.user_demand.add(
        Node(4, Point(2, 0), subnetwork_id=2),
        [
            user_demand.Static(
                demand_priority=2, demand=[1e-3], return_factor=0, min_level=0
            )
        ],
    )

    model.link.add(fb, b)
    model.link.add(b, ud)
    model.link.add(ud, b)
    model.link.add(ld, b)

    return model


def invalid_infeasible_model() -> Model:
    """Set up a minimal model which uses a linear_resistance node."""
    model = Model(
        starttime="2020-01-01",
        endtime="2020-02-01",
        crs="EPSG:28992",
        experimental=Experimental(allocation=True),
    )

    model.basin.add(
        Node(1, Point(0, 0), subnetwork_id=1),
        [basin.Profile(area=100.0, level=[0.0, 10.0]), basin.State(level=[10.0])],
    )
    model.linear_resistance.add(
        Node(2, Point(1, 0), subnetwork_id=1),
        [linear_resistance.Static(resistance=[5e3], max_flow_rate=[6e-5])],
    )
    model.level_boundary.add(
        Node(3, Point(2, 0), subnetwork_id=1), [level_boundary.Static(level=[11.0])]
    )

    model.link.add(
        model.basin[1],
        model.linear_resistance[2],
    )
    model.link.add(
        model.linear_resistance[2],
        model.level_boundary[3],
    )

    return model


def drain_surplus_model() -> Model:
    """Set up a model which activates an outlet to drain surplus water out of a Basin."""
    model = Model(
        starttime="2020-01-01",
        endtime="2020-02-01",
        crs="EPSG:28992",
        experimental=Experimental(allocation=True),
    )

    bsn = model.basin.add(
        Node(1, Point(0, 0), subnetwork_id=2),
        [basin.Profile(area=100.0, level=[0.0, 12.0]), basin.State(level=[10.0])],
    )

    lvl = model.level_demand.add(
        Node(4, Point(0, 1), subnetwork_id=2),
        [level_demand.Static(demand_priority=1, max_level=[5.0])],
    )

    out = model.outlet.add(
        Node(2, Point(1, 0), subnetwork_id=2),
        [
            outlet.Static(
                flow_rate=[0.0],
                max_flow_rate=[1e-3],
                control_state="Ribasim.allocation",
            )
        ],
    )

    trm = model.terminal.add(Node(3, Point(2, 0), subnetwork_id=2))

    model.link.add(bsn, out)
    model.link.add(out, trm)
    model.link.add(lvl, bsn)

    return model


def multi_priority_flow_demand_model() -> Model:
    """Set up a model which contains a FlowDemand node with multiple demand priorities."""
    model = Model(
        starttime="2020-01-01",
        endtime="2020-01-21",
        crs="EPSG:28992",
        solver=Solver(saveat=3600),
        experimental=Experimental(allocation=True),
    )

    bsn = model.basin.add(
        Node(1, Point(3, 3), subnetwork_id=2),
        [basin.Profile(level=[0.0, 10.0], area=1000.0), basin.State(level=[3.0])],
    )

    pmp = model.pump.add(
        Node(2, Point(3, 2), subnetwork_id=2),
        [pump.Static(flow_rate=[1.0], control_state="Ribasim.allocation")],
    )

    tmn = model.terminal.add(Node(3, Point(3, 1), subnetwork_id=2))

    flb = model.flow_boundary.add(
        Node(4, Point(3, 4), subnetwork_id=2), [flow_boundary.Static(flow_rate=[5e-3])]
    )

    udm = model.user_demand.add(
        Node(5, Point(4, 3), subnetwork_id=2),
        [
            user_demand.Time(
                return_factor=0,
                min_level=0,
                demand_priority=3,
                time=[model.starttime, model.endtime],
                demand=[3e-3, 0],
            )
        ],
    )

    fdm = model.flow_demand.add(
        Node(6, Point(2, 2), subnetwork_id=2),
        [flow_demand.Static(demand_priority=[2, 4], demand=[2e-3, 3e-3])],
    )

    ldm = model.level_demand.add(
        Node(7, Point(2, 3), subnetwork_id=2),
        [level_demand.Static(demand_priority=1, min_level=[3.0])],
    )

    model.link.add(bsn, pmp)
    model.link.add(pmp, tmn)
    model.link.add(flb, bsn)
    model.link.add(bsn, udm)
    model.link.add(udm, bsn)
    model.link.add(fdm, pmp)
    model.link.add(ldm, bsn)

    return model


def allocation_off_flow_demand_model() -> Model:
    """Set up a model with a Pump with a FlowDemand but allocation turned off."""
    model = Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:28992",
        experimental=Experimental(allocation=False),
    )

    bsn = model.basin.add(
        Node(1, Point(0, 0)),
        [basin.Profile(level=[0.0, 10.0], area=1000.0), basin.State(level=[5.0])],
    )

    pmp = model.pump.add(Node(2, Point(1, 0)), [pump.Static(flow_rate=[0.0])])

    tml = model.terminal.add(Node(3, Point(2, 0)))

    fdm = model.flow_demand.add(
        Node(4, Point(1, 1)), [flow_demand.Static(demand_priority=[1], demand=1e-3)]
    )

    model.link.add(bsn, pmp)
    model.link.add(pmp, tml)
    model.link.add(fdm, pmp)

    return model


def multiple_route_priorities_model() -> Model:
    """Set up a model to test route prioritization."""
    model = Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:28992",
        experimental=Experimental(allocation=True),
    )

    ud = model.user_demand.add(
        Node(1, Point(10, 10), subnetwork_id=1),
        [
            user_demand.Time(
                demand_priority=2,
                time=pd.date_range(start="2020-01-01", end="2021-01-01"),
                demand=np.linspace(0.0, 3.0, num=367),
                return_factor=0,
                min_level=0,
            )
        ],
    )

    bsn = model.basin.add(
        Node(
            2,
            Point(10, 9),
            subnetwork_id=1,
            route_priority=100000,  # Ignore Basin as source
        ),
        [basin.Profile(area=1000, level=[0, 10]), basin.State(level=[2.0])],
    )

    # The LevelDemand node makes sure that Basins #2 and #9 are not used as sources
    ld = model.level_demand.add(
        Node(3, Point(9, 9), subnetwork_id=1),
        [level_demand.Static(min_level=[2.0], max_level=[2.0], demand_priority=1)],
    )

    for x in range(9, 12):
        pmp = model.pump.add(
            Node(x - 5, Point(x, 8), subnetwork_id=1),
            [
                pump.Static(
                    flow_rate=0, max_flow_rate=[1.0], control_state="Ribasim.allocation"
                )
            ],
        )

        lb = model.level_boundary.add(
            Node(x - 2, Point(x, 7), subnetwork_id=1, route_priority=3000 + x),
            [level_boundary.Static(level=[1.0])],
        )

        model.link.add(pmp, bsn)
        model.link.add(lb, pmp)

    model.link.add(bsn, ud)
    model.link.add(ud, bsn)
    model.link.add(ld, bsn)

    return model


def polder_management_model() -> Model:
    """Set up a model where the water level in the boezem is be higher than in the polder system.

    To maintain the target water levels in dry periods in the polder system, a water supply of 2 m³/s is required during two periods of the year: day 90 to 180 and day 270 to 366.
    Flushing is included as well: 1.5 m³/s during day 90 to 180.
    """
    model = Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:4326",
        experimental=Experimental(allocation=True),
    )

    time = pd.date_range(model.starttime, model.endtime)
    day_of_year = time.day_of_year.to_numpy()
    precipitation = np.zeros(day_of_year.size)
    precipitation[0:90] = 1e-6
    precipitation[90:180] = 0
    precipitation[180:270] = 1e-6
    precipitation[270:366] = 0

    evaporation = np.zeros(day_of_year.size)
    evaporation[0:90] = 0
    evaporation[90:180] = 1e-6
    evaporation[180:270] = 0
    evaporation[270:366] = 1e-6

    basin_data: list[TableModel[Any]] = [
        basin.Profile(
            area=[0.01, 1000000.0, 1000000.0, 1000000.0], level=[-10, 1.0, 2.0, 10]
        ),
        basin.Time(
            time=pd.date_range(model.starttime, model.endtime),
            drainage=0.0,
            potential_evaporation=evaporation,
            infiltration=0.0,
            precipitation=precipitation,
        ),
        basin.State(level=[0.9]),
    ]

    basin3 = model.basin.add(Node(3, Point(2.0, 0.0), name="Boezem"), basin_data)
    basin4 = model.basin.add(Node(4, Point(2.0, 2.0), name="Polder"), basin_data)
    basin6 = model.basin.add(Node(6, Point(4.0, 2.0), name="Polder"), basin_data)
    basin9 = model.basin.add(Node(9, Point(4.0, 0.0), name="Boezem"), basin_data)

    # Level demand on polder 4 around 1 m
    level4 = model.level_demand.add(
        Node(100, Point(2.0, 2.5), name="polder#4 level demand"),
        [level_demand.Static(min_level=[1.0], max_level=[1.0], demand_priority=[1])],
    )
    # Level demand on polder 6 around 0.9 m
    level6 = model.level_demand.add(
        Node(101, Point(4.0, 2.5), name="polder#6 level demand"),
        [level_demand.Static(min_level=[0.9], max_level=[0.9], demand_priority=[1])],
    )

    # Level demand on boezem 3 maintain 1.2 m
    level3 = model.level_demand.add(
        Node(102, Point(2.0, -1), name="boezem#3 level demand"),
        [level_demand.Static(min_level=[1.2], max_level=[1.2], demand_priority=[1])],
    )

    # increase initial level of the boezem
    assert model.basin.state.df is not None
    model.basin.state.df.loc[model.basin.state.df.node_id == 3, "level"] = 1.2
    model.basin.state.df.loc[model.basin.state.df.node_id == 9, "level"] = 1.2

    model.link.add(level4, basin4)
    model.link.add(level6, basin6)
    model.link.add(level3, basin3)
    # model.link.add(level9, basin9)

    ###Setup outlet:
    outlet10 = model.outlet.add(
        Node(10, Point(5.0, 0.0)),
        [
            outlet.Static(
                control_state="Ribasim.allocation", flow_rate=[0.0], max_flow_rate=10
            )
        ],
    )

    outlet12 = model.outlet.add(
        Node(12, Point(1.0, 0)),
        [
            outlet.Static(
                control_state="Ribasim.allocation", flow_rate=[0.0], max_flow_rate=10.0
            )
        ],
    )

    # --- Outlet 5 Controlled by Allocation ---
    outlet5 = model.outlet.add(
        Node(5, Point(2, 1), name="inlaat"),
        [
            outlet.Static(
                control_state="Ribasim.allocation",
                flow_rate=[0.0],
                max_flow_rate=5.0,
            )
        ],
    )

    # --- Outlet 13 Controlled by Allocation ---
    outlet13 = model.outlet.add(
        Node(13, Point(3, 2), name="inlaat/uitlaat"),
        [
            outlet.Static(
                control_state="Ribasim.allocation", flow_rate=[0.0], max_flow_rate=5.0
            )
        ],
    )

    ###Setup Manning resistance: Route priority to 0, ensures that this is the main water route.
    manning_resistance2 = model.manning_resistance.add(
        Node(2, Point(3, 0.0), route_priority=0),
        [
            manning_resistance.Static(
                length=[900], manning_n=[0.04], profile_width=[6.0], profile_slope=[3.0]
            )
        ],
    )

    # --- Pump 7 Controlled by Allocation ---
    pump7 = model.pump.add(
        Node(7, Point(4, 1), name="drainage pumping station"),
        [
            pump.Static(
                control_state="Ribasim.allocation",
                flow_rate=[0.0],
                max_flow_rate=20.0,
            )
        ],
    )

    # Maak een dagreeks over de hele simulatieperiode
    t = pd.date_range(model.starttime, model.endtime, freq="D")
    d = np.zeros(len(t))
    d[0:90] = 0.0
    d[90:180] = 1.5
    d[180:270] = 0.0
    d[270:366] = 0.0

    pump7_alloc = model.flow_demand.add(
        Node(70, Point(5.0, 1), name="flush=1.5m3/s"),
        [
            flow_demand.Time(
                time=t,
                demand_priority=[2] * len(t),
                demand=d,
            )
        ],
    )
    model.link.add(pump7_alloc, pump7)

    ##Setup level boundary
    level_boundary11 = model.level_boundary.add(
        Node(11, Point(0, 0)), [level_boundary.Static(level=[10])]
    )
    level_boundary17 = model.level_boundary.add(
        Node(17, Point(6, 0)), [level_boundary.Static(level=[0.9])]
    )

    ##Setup the links:
    model.link.add(manning_resistance2, basin9)
    model.link.add(
        basin3,
        outlet5,
    )
    model.link.add(
        basin3,
        manning_resistance2,
    )

    model.link.add(outlet5, basin4)
    model.link.add(basin4, outlet13)
    model.link.add(outlet13, basin6)
    model.link.add(basin6, pump7)
    model.link.add(pump7, basin9)
    model.link.add(basin9, outlet10)
    model.link.add(level_boundary11, outlet12)
    model.link.add(outlet12, basin3)
    model.link.add(outlet10, level_boundary17)

    return model


def switch_allocation_control_model() -> Model:
    """Create a model that switches allocation control on and off based on a DiscreteControl node."""
    # Basin data
    model = Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:4326",
        experimental=Experimental(allocation=True),
    )

    time = pd.date_range(model.starttime, model.endtime)
    day_of_year = time.day_of_year.to_numpy()
    precipitation = np.zeros(day_of_year.size)
    precipitation[0:90] = 1e-7
    precipitation[90:180] = 0
    precipitation[180:270] = 1e-7
    precipitation[270:366] = 0

    evaporation = np.zeros(day_of_year.size)
    evaporation[0:90] = 0
    evaporation[90:180] = 1e-7
    evaporation[180:270] = 0
    evaporation[270:366] = 1e-7

    basin_data: list[TableModel[Any]] = [
        basin.Profile(area=[1_000_000.0, 1_000_000.0], level=[-10, 20.0]),
        basin.Time(
            time=pd.date_range(model.starttime, model.endtime),
            drainage=0.0,
            potential_evaporation=evaporation,
            infiltration=0.0,
            precipitation=precipitation,
        ),
        basin.State(level=[1.25]),
    ]

    basin1 = model.basin.add(Node(1, Point(0.0, 0.0), name="Reservoir"), basin_data)

    discrete_control2 = model.discrete_control.add(
        Node(2, Point(1.0, 1.0), name="Control Node"),
        [
            discrete_control.Variable(
                compound_variable_id=[1],
                listen_node_id=[1],
                variable=["level"],
            ),
            discrete_control.Condition(
                compound_variable_id=[1],
                condition_id=[1],
                threshold_high=[1.0],
            ),
            discrete_control.Logic(
                control_state=["Ribasim.allocation", "prescribed"],
                truth_state=["F", "T"],
            ),
        ],
    )

    outlet3 = model.outlet.add(
        Node(3, Point(1.0, 0.0)),
        [
            outlet.Static(
                flow_rate=[0, 1],
                max_flow_rate=[0.08, 0.05],
                control_state=["Ribasim.allocation", "prescribed"],
            )
        ],
    )

    inlet4 = model.outlet.add(
        Node(4, Point(-1.0, 0.0)),
        [
            outlet.Static(
                flow_rate=[0, 0],
                max_flow_rate=[1, 0],
                control_state=["Ribasim.allocation", "prescribed"],
            )
        ],
    )

    level_boundary5 = model.level_boundary.add(
        Node(5, Point(-2.0, 0.0)),
        [level_boundary.Static(level=[1.0])],
    )

    terminal6 = model.terminal.add(Node(6, Point(2.0, 0.0)))

    level_demand7 = model.level_demand.add(
        Node(7, Point(0.0, 1.0)),
        [level_demand.Static(min_level=[0.9], max_level=[0.9], demand_priority=1)],
    )

    model.link.add(level_boundary5, inlet4)
    model.link.add(inlet4, basin1)
    model.link.add(basin1, outlet3)
    model.link.add(discrete_control2, outlet3)
    model.link.add(discrete_control2, inlet4)
    model.link.add(outlet3, terminal6)
    model.link.add(level_demand7, basin1)

    return model
