from ribasim.config import Node
from ribasim.model import Model
from ribasim.nodes import (
    basin,
    discrete_control,
    flow_boundary,
    level_boundary,
    outlet,
    pid_control,
    pump,
    tabulated_rating_curve,
)
from shapely.geometry import Point


def pid_control_model() -> Model:
    """Set up a basic model with a PID controlled pump controlling a basin with abundant inflow."""
    model = Model(
        starttime="2020-01-01",
        endtime="2020-12-01",
        crs="EPSG:28992",
    )

    model.flow_boundary.add(
        Node(1, Point(0, 0)), [flow_boundary.Static(flow_rate=[1e-3])]
    )
    model.basin.add(
        Node(2, Point(1, 0)),
        [basin.Profile(area=1000.0, level=[0.0, 1.0]), basin.State(level=[6.0])],
    )
    # Flow rate will be overwritten by PID controller
    model.pump.add(Node(3, Point(2, 0.5)), [pump.Static(flow_rate=[0.0])])

    model.level_boundary.add(Node(4, Point(3, 0)), [level_boundary.Static(level=[5.0])])

    model.pid_control.add(
        Node(5, Point(1.5, 1)),
        [
            pid_control.Time(
                time=[
                    "2020-01-01",
                    "2020-05-01",
                    "2020-07-01",
                    "2020-12-01",
                ],
                listen_node_id=2,
                target=[5.0, 5.0, 7.5, 7.5],
                proportional=-1e-3,
                integral=-1e-7,
                derivative=0.0,
            )
        ],
    )

    # Flow rate will be overwritten by PID controller
    model.outlet.add(Node(6, Point(2, -0.5)), [outlet.Static(flow_rate=[0.0])])
    model.pid_control.add(
        Node(7, Point(1.5, -1)),
        [
            pid_control.Time(
                time=[
                    "2020-01-01",
                    "2020-05-01",
                    "2020-07-01",
                    "2020-12-01",
                ],
                listen_node_id=2,
                target=[5.0, 5.0, 7.5, 7.5],
                proportional=1e-3,
                integral=1e-7,
                derivative=0.0,
            )
        ],
    )

    model.edge.add(model.flow_boundary[1], model.basin[2])
    model.edge.add(model.basin[2], model.pump[3])
    model.edge.add(model.pump[3], model.level_boundary[4])
    model.edge.add(model.level_boundary[4], model.outlet[6])
    model.edge.add(model.pid_control[5], model.pump[3])
    model.edge.add(model.outlet[6], model.basin[2])
    model.edge.add(model.pid_control[7], model.outlet[6])

    return model


def discrete_control_of_pid_control_model() -> Model:
    """Set up a basic model where a discrete control node sets the target level of a pid control node."""
    model = Model(
        starttime="2020-01-01",
        endtime="2020-12-01",
        crs="EPSG:28992",
    )

    model.level_boundary.add(
        Node(1, Point(0, 0)),
        [level_boundary.Time(time=["2020-01-01", "2021-01-01"], level=[7.0, 3.0])],
    )

    # The flow_rate will be overwritten by PID controller
    model.outlet.add(Node(2, Point(1, 0)), [outlet.Static(flow_rate=[0.0])])
    model.basin.add(
        Node(3, Point(2, 0)),
        [basin.State(level=[6.0]), basin.Profile(area=1000.0, level=[0.0, 1.0])],
    )
    model.tabulated_rating_curve.add(
        Node(4, Point(3, 0)),
        [tabulated_rating_curve.Static(level=[0.0, 1.0], flow_rate=[0.0, 10 / 86400])],
    )
    model.terminal.add(Node(5, Point(4, 0)))
    model.pid_control.add(
        Node(6, Point(1, 1)),
        [
            pid_control.Static(
                listen_node_id=3,
                control_state=["target_high", "target_low"],
                target=[5.0, 3.0],
                proportional=1e-2,
                integral=1e-8,
                derivative=-1e-1,
            )
        ],
    )
    model.discrete_control.add(
        Node(7, Point(0, 1)),
        [
            discrete_control.Variable(
                listen_node_id=[1],
                variable="level",
                compound_variable_id=1,
            ),
            discrete_control.Condition(
                greater_than=[5.0],
                compound_variable_id=1,
            ),
            discrete_control.Logic(
                truth_state=["T", "F"], control_state=["target_high", "target_low"]
            ),
        ],
    )

    model.edge.add(
        model.level_boundary[1],
        model.outlet[2],
    )
    model.edge.add(
        model.outlet[2],
        model.basin[3],
    )
    model.edge.add(
        model.basin[3],
        model.tabulated_rating_curve[4],
    )
    model.edge.add(
        model.tabulated_rating_curve[4],
        model.terminal[5],
    )
    model.edge.add(
        model.pid_control[6],
        model.outlet[2],
    )
    model.edge.add(
        model.discrete_control[7],
        model.pid_control[6],
    )

    return model
