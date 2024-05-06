from typing import Any

import pandas as pd
from ribasim.config import Node, Solver
from ribasim.input_base import TableModel
from ribasim.model import Model
from ribasim.nodes import (
    basin,
    discrete_control,
    flow_boundary,
    fractional_flow,
    pump,
    tabulated_rating_curve,
)
from shapely.geometry import Point


def invalid_qh_model() -> Model:
    model = Model(
        starttime="2020-01-01",
        endtime="2020-12-01",
        crs="EPSG:28992",
    )

    model.tabulated_rating_curve.add(
        Node(1, Point(0, 0)),
        # Invalid: levels must not be repeated
        [tabulated_rating_curve.Static(level=[0, 0], flow_rate=[1, 2])],
    )
    model.tabulated_rating_curve.add(
        Node(2, Point(0, 1)),
        [
            tabulated_rating_curve.Time(
                time=[
                    pd.Timestamp("2020-01-01"),
                    pd.Timestamp("2020-01-01"),
                ],
                # Invalid: levels must not be repeated
                level=[0, 0],
                flow_rate=[1, 2],
            )
        ],
    )
    model.basin.add(
        Node(3, Point(0, 2)),
        [
            basin.State(level=[1.4112729908597084]),
            basin.Profile(area=[0.01, 1], level=[0, 1]),
        ],
    )

    return model


def invalid_fractional_flow_model() -> Model:
    model = Model(
        starttime="2020-01-01",
        endtime="2020-12-01",
        crs="EPSG:28992",
    )

    basin_shared: list[TableModel[Any]] = [
        basin.Profile(area=[0.01, 1.0], level=[0.0, 1.0]),
        basin.State(level=[1.4112729908597084]),
    ]
    model.basin.add(Node(1, Point(0, 1)), basin_shared)
    model.basin.add(Node(2, Point(-1, 0)), basin_shared)
    # Invalid: fractions must be non-negative and add up to approximately 1
    model.fractional_flow.add(
        Node(3, Point(0, -1)), [fractional_flow.Static(fraction=[-0.1])]
    )
    model.fractional_flow.add(
        Node(4, Point(1, 0)), [fractional_flow.Static(fraction=[0.5])]
    )
    model.terminal.add(Node(5, Point(0, -2)))
    model.terminal.add(Node(6, Point(0, 2)))
    model.tabulated_rating_curve.add(
        Node(7, Point(0, 0)),
        [tabulated_rating_curve.Static(level=[0.0, 1.0], flow_rate=[0.0, 50.0])],
    )
    # Invalid: #8 comes from a Basin
    model.fractional_flow.add(
        Node(8, Point(-1, -1)), [fractional_flow.Static(fraction=[1.0])]
    )

    model.edge.add(
        model.basin[1],
        model.tabulated_rating_curve[7],
    )
    # Invalid: TabulatedRatingCurve #7 has outflow to FractionalFlow and other node types.
    model.edge.add(
        model.tabulated_rating_curve[7],
        model.basin[2],
    )
    model.edge.add(
        model.tabulated_rating_curve[7],
        model.fractional_flow[3],
    )
    model.edge.add(
        model.fractional_flow[3],
        model.terminal[5],
    )
    model.edge.add(
        model.tabulated_rating_curve[7],
        model.fractional_flow[4],
    )
    model.edge.add(
        model.fractional_flow[4],
        model.terminal[6],
    )
    model.edge.add(
        model.basin[2],
        model.fractional_flow[8],
    )

    return model


def invalid_discrete_control_model() -> Model:
    model = Model(
        starttime="2020-01-01",
        endtime="2020-12-01",
        crs="EPSG:28992",
    )

    basin_shared: list[TableModel[Any]] = [
        basin.Profile(area=[0.01, 1.0], level=[0.0, 1.0]),
        basin.State(level=[1.4112729908597084]),
    ]
    model.basin.add(Node(1, Point(0, 0)), basin_shared)
    # Invalid: DiscreteControl node #4 with control state 'foo'
    # points to this pump but this control state is not defined for
    # this pump. The pump having a control state that is not defined
    # for DiscreteControl node #4 is fine.
    model.pump.add(
        Node(2, Point(1, 0)), [pump.Static(control_state="bar", flow_rate=[0.5 / 3600])]
    )
    model.basin.add(Node(3, Point(2, 0)), basin_shared)
    model.flow_boundary.add(
        Node(4, Point(3, 0)),
        [
            flow_boundary.Time(
                time=["2020-01-01", "2020-11-01"],
                flow_rate=[1.0, 2.0],
            )
        ],
    )
    model.discrete_control.add(
        Node(5, Point(1, 1)),
        [
            discrete_control.Variable(
                listen_node_type=["Basin", "FlowBoundary", "FlowBoundary"],
                listen_node_id=[1, 4, 4],
                variable=["level", "flow_rate", "flow_rate"],
                # Invalid: look_ahead can only be specified for timeseries variables.
                # Invalid: this look_ahead will go past the provided timeseries during simulation.
                # Invalid: look_ahead must be non-negative.
                look_ahead=[100.0, 40 * 24 * 60 * 60, -10.0],
                compound_variable_id=[1, 2, 3],
            ),
            discrete_control.Condition(
                greater_than=[0.5, 1.5, 1.5],
                compound_variable_id=[1, 2, 3],
            ),
            # Invalid: DiscreteControl node #4 has 2 conditions so
            # truth states have to be of length 2
            discrete_control.Logic(truth_state=["FFFF"], control_state=["foo"]),
        ],
    )

    model.edge.add(
        model.basin[1],
        model.pump[2],
    )
    model.edge.add(
        model.pump[2],
        model.basin[3],
    )
    model.edge.add(
        model.flow_boundary[4],
        model.basin[3],
    )
    model.edge.add(
        model.discrete_control[5],
        model.pump[2],
    )

    return model


def invalid_edge_types_model() -> Model:
    """Set up a minimal model with invalid edge types."""

    model = Model(
        starttime="2020-01-01",
        endtime="2020-12-01",
        crs="EPSG:28992",
    )

    basin_shared: list[TableModel[Any]] = [
        basin.Profile(area=[0.01, 1000.0], level=[0.0, 1.0]),
        basin.State(level=[0.04471158417652035]),
    ]

    model.basin.add(Node(1, Point(0, 0)), basin_shared)
    model.pump.add(Node(2, Point(1, 0)), [pump.Static(flow_rate=[0.5 / 3600])])
    model.basin.add(Node(3, Point(2, 0)), basin_shared)

    model.edge.add(
        model.basin[1],
        model.pump[2],
    )
    model.edge.add(
        model.pump[2],
        model.basin[3],
    )

    assert model.edge.df is not None
    model.edge.df["edge_type"] = ["foo", "bar"]

    return model


def invalid_unstable_model() -> Model:
    """Model with several extremely quickly emptying basins."""

    model = Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:28992",
        solver=Solver(dtmin=60.0),
    )
    id_shift = 10
    for i in range(6):
        model.basin.add(
            Node(1 + id_shift * i, Point(i, 0)),
            [basin.Profile(area=1000.0, level=[0.0, 1.0]), basin.State(level=[1.0])],
        )
        flow_rate = 1.0 if (i % 2 == 0) else 1e10
        model.pump.add(
            Node(2 + id_shift * i, Point(i, 1)), [pump.Static(flow_rate=[flow_rate])]
        )
        model.terminal.add(Node(3 + id_shift * i, Point(i, 2)))

        model.edge.add(model.basin[1 + id_shift * i], model.pump[2 + id_shift * i])
        model.edge.add(model.pump[2 + id_shift * i], model.terminal[3 + id_shift * i])
    return model
