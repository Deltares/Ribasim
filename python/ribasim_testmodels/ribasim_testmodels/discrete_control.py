from ribasim.config import Node
from ribasim.model import Model
from ribasim.nodes import (
    basin,
    discrete_control,
    flow_boundary,
    level_boundary,
    linear_resistance,
    outlet,
    pump,
    tabulated_rating_curve,
)
from shapely.geometry import Point


def pump_discrete_control_model() -> Model:
    """
    Set up a basic model with a pump controlled based on basin levels.
    The LinearResistance is deactivated when the levels are almost equal.
    """

    model = Model(
        starttime="2020-01-01 00:00:00",
        endtime="2021-01-01 00:00:00",
    )

    model.basin.add(
        Node(1, Point(0, 0)),
        [basin.State(level=[1.0]), basin.Profile(level=[0.0, 1.0], area=100.0)],
    )
    model.linear_resistance.add(
        Node(2, Point(1, -1)),
        [
            linear_resistance.Static(
                resistance=1e5,
                control_state=["active", "inactive"],
                active=[True, False],
            )
        ],
    )
    model.basin.add(
        Node(3, Point(2, 0)),
        [
            basin.State(level=[1e-5]),
            basin.Static(precipitation=[1e-9]),
            basin.Profile(level=[0.0, 1.0], area=100.0),
        ],
    )
    model.pump.add(
        Node(4, Point(1, 0)),
        [pump.Static(flow_rate=[0.0, 1e-5], control_state=["off", "on"])],
    )
    model.discrete_control.add(
        Node(5, Point(1, 1)),
        [
            discrete_control.Condition(
                listen_feature_id=1,
                variable="level",
                greater_than=[0.8, 0.4],
            ),
            discrete_control.Logic(
                truth_state=["FF", "TF", "FT", "TT"],
                control_state=["on", "off", "off", "on"],
            ),
        ],
    )
    model.discrete_control.add(
        Node(6, Point(2, -1)),
        [
            discrete_control.Condition(
                listen_feature_id=3,
                variable="level",
                greater_than=[0.45],
            ),
            discrete_control.Logic(
                truth_state=["T", "F"],
                control_state=["inactive", "active"],
            ),
        ],
    )

    model.edge.add(
        from_node=model.basin[1],
        to_node=model.linear_resistance[2],
        edge_type="flow",
    )
    model.edge.add(
        from_node=model.linear_resistance[2],
        to_node=model.basin[3],
        edge_type="flow",
    )
    model.edge.add(
        from_node=model.basin[1],
        to_node=model.pump[4],
        edge_type="flow",
    )
    model.edge.add(
        from_node=model.pump[4],
        to_node=model.basin[3],
        edge_type="flow",
    )
    model.edge.add(
        from_node=model.discrete_control[5],
        to_node=model.pump[4],
        edge_type="control",
    )
    model.edge.add(
        from_node=model.discrete_control[6],
        to_node=model.linear_resistance[2],
        edge_type="control",
    )

    return model


def flow_condition_model() -> Model:
    """Set up a basic model that involves discrete control based on a flow condition"""

    model = Model(
        starttime="2020-01-01 00:00:00",
        endtime="2021-01-01 00:00:00",
    )

    model.flow_boundary.add(
        Node(1, Point(0, 0)),
        [
            flow_boundary.Time(
                time=["2020-01-01 00:00:00", "2022-01-01 00:00:00"],
                flow_rate=[0.0, 40 / 86400],
            )
        ],
    )
    model.basin.add(
        Node(2, Point(1, 0)),
        [basin.Profile(level=[0.0, 1.0], area=100.0), basin.State(level=[2.5])],
    )
    model.pump.add(
        Node(3, Point(2, 0)),
        [pump.Static(flow_rate=[0.0, 1e-3], control_state=["off", "on"])],
    )
    model.terminal.add(Node(4, Point(3, 0)))
    model.discrete_control.add(
        Node(5, Point(1, 1)),
        [
            discrete_control.Condition(
                listen_feature_id=1,
                variable="flow_rate",
                greater_than=[20 / (86400)],
                look_ahead=60 * 86400,
            ),
            discrete_control.Logic(truth_state=["T", "F"], control_state=["off", "on"]),
        ],
    )

    model.edge.add(
        from_node=model.flow_boundary[1],
        to_node=model.basin[2],
        edge_type="flow",
    )
    model.edge.add(
        from_node=model.basin[2],
        to_node=model.pump[3],
        edge_type="flow",
    )
    model.edge.add(
        from_node=model.pump[3],
        to_node=model.terminal[4],
        edge_type="flow",
    )
    model.edge.add(
        from_node=model.discrete_control[5],
        to_node=model.pump[3],
        edge_type="control",
    )

    return model


def level_boundary_condition_model() -> Model:
    """Set up a small model with a condition on a level boundary."""

    model = Model(
        starttime="2020-01-01 00:00:00",
        endtime="2021-01-01 00:00:00",
    )

    model.level_boundary.add(
        Node(1, Point(0, 0)),
        [
            level_boundary.Time(
                time=["2020-01-01 00:00:00", "2022-01-01 00:00:00"], level=[5.0, 10.0]
            )
        ],
    )
    model.linear_resistance.add(
        Node(2, Point(1, 0)), [linear_resistance.Static(resistance=[5e3])]
    )
    model.basin.add(
        Node(3, Point(2, 0)),
        [basin.Profile(level=[0.0, 1.0], area=100.0), basin.State(level=[2.5])],
    )
    model.outlet.add(
        Node(4, Point(3, 0)),
        [
            outlet.Static(
                active=[True, False], flow_rate=0.5 / 3600, control_state=["on", "off"]
            )
        ],
    )
    model.terminal.add(Node(5, Point(4, 0)))
    model.discrete_control.add(
        Node(6, Point(1.5, 1)),
        [
            discrete_control.Condition(
                listen_feature_id=[1],
                variable="level",
                greater_than=6.0,
                look_ahead=60 * 86400,
            ),
            discrete_control.Logic(truth_state=["T", "F"], control_state=["on", "off"]),
        ],
    )

    model.edge.add(
        from_node=model.level_boundary[1],
        to_node=model.linear_resistance[2],
        edge_type="flow",
    )
    model.edge.add(
        from_node=model.linear_resistance[2],
        to_node=model.basin[3],
        edge_type="flow",
    )
    model.edge.add(
        from_node=model.basin[3],
        to_node=model.outlet[4],
        edge_type="flow",
    )
    model.edge.add(
        from_node=model.outlet[4],
        to_node=model.terminal[5],
        edge_type="flow",
    )
    model.edge.add(
        from_node=model.discrete_control[6],
        to_node=model.outlet[4],
        edge_type="control",
    )

    return model


def tabulated_rating_curve_control_model() -> Model:
    """Discrete control on a TabulatedRatingCurve.

    The Basin drains over a TabulatedRatingCurve into a Terminal. The Control
    node will effectively increase the crest level to prevent further drainage
    at some threshold level.
    """

    model = Model(
        starttime="2020-01-01 00:00:00",
        endtime="2021-01-01 00:00:00",
    )

    model.basin.add(
        Node(1, Point(0, 0)),
        [
            # 2 mm/d precipitation
            basin.Static(precipitation=[0.002 / 86400]),
            basin.State(level=[0.04471158417652035]),
            basin.Profile(area=[0.01, 1000.0], level=[0.0, 1.0]),
        ],
    )
    model.tabulated_rating_curve.add(
        Node(2, Point(1, 0)),
        [
            tabulated_rating_curve.Static(
                level=[0.0, 1.2, 0.0, 1.0],
                flow_rate=[0.0, 1 / 86400, 0.0, 1 / 86400],
                control_state=["low", "low", "high", "high"],
            )
        ],
    )
    model.terminal.add(Node(3, Point(2, 0)))
    model.discrete_control.add(
        Node(4, Point(1, 1)),
        [
            discrete_control.Condition(
                listen_feature_id=[1],
                variable="level",
                greater_than=0.5,
            ),
            discrete_control.Logic(
                truth_state=["T", "F"], control_state=["low", "high"]
            ),
        ],
    )

    model.edge.add(
        from_node=model.basin[1],
        to_node=model.tabulated_rating_curve[2],
        edge_type="flow",
    )
    model.edge.add(
        from_node=model.tabulated_rating_curve[2],
        to_node=model.terminal[3],
        edge_type="flow",
    )
    model.edge.add(
        from_node=model.discrete_control[4],
        to_node=model.tabulated_rating_curve[2],
        edge_type="control",
    )

    return model


def level_setpoint_with_minmax_model() -> Model:
    """
    Set up a minimal model in which the level of a basin is kept within an acceptable range
    around a setpoint while being affected by time-varying forcing.
    This is done by bringing the level back to the setpoint once the level goes beyond this range.
    """

    model = Model(
        starttime="2020-01-01 00:00:00",
        endtime="2021-01-01 00:00:00",
    )

    model.basin.add(
        Node(1, Point(0, 0)),
        [
            basin.Profile(area=1000.0, level=[0.0, 1.0]),
            basin.State(level=[20.0]),
        ],
    )
    model.pump.add(
        Node(2, Point(1, 1)),
        [pump.Static(control_state=["none", "in", "out"], flow_rate=[0.0, 2e-3, 0.0])],
    )
    model.pump.add(
        Node(3, Point(1, -1)),
        [pump.Static(control_state=["none", "in", "out"], flow_rate=[0.0, 0.0, 2e-3])],
    )
    model.level_boundary.add(
        Node(4, Point(2, 0)), [level_boundary.Static(level=[10.0])]
    )
    model.tabulated_rating_curve.add(
        Node(5, Point(-1, 0)),
        [tabulated_rating_curve.Static(level=[2.0, 15.0], flow_rate=[0.0, 1e-3])],
    )
    model.terminal.add(Node(6, Point(-2, 0)))
    model.discrete_control.add(
        Node(7, Point(1, 0)),
        [
            discrete_control.Condition(
                listen_feature_id=1,
                variable="level",
                # min, setpoint, max
                greater_than=[5.0, 10.0, 15.0],
            ),
            discrete_control.Logic(
                truth_state=["FFF", "U**", "T*F", "**D", "TTT"],
                control_state=["in", "in", "none", "out", "out"],
            ),
        ],
    )

    model.edge.add(
        from_node=model.basin[1],
        to_node=model.pump[3],
        edge_type="flow",
    )
    model.edge.add(
        from_node=model.pump[3],
        to_node=model.level_boundary[4],
        edge_type="flow",
    )
    model.edge.add(
        from_node=model.level_boundary[4],
        to_node=model.pump[2],
        edge_type="flow",
    )
    model.edge.add(
        from_node=model.pump[2],
        to_node=model.basin[1],
        edge_type="flow",
    )
    model.edge.add(
        from_node=model.basin[1],
        to_node=model.tabulated_rating_curve[5],
        edge_type="flow",
    )
    model.edge.add(
        from_node=model.tabulated_rating_curve[5],
        to_node=model.terminal[6],
        edge_type="flow",
    )
    model.edge.add(
        from_node=model.discrete_control[7],
        to_node=model.pump[2],
        edge_type="control",
    )
    model.edge.add(
        from_node=model.discrete_control[7],
        to_node=model.pump[3],
        edge_type="control",
    )

    return model
