import numpy as np
import pandas as pd
from ribasim.config import Experimental, Node
from ribasim.model import Model, Solver
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
    Set up a basic model with a Pump controlled based on Basin levels.

    The LinearResistance is deactivated when the levels are almost equal.
    """
    model = Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:28992",
        experimental=Experimental(concentration=True),
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
            discrete_control.Variable(
                listen_node_id=[1, 3],
                variable="level",
                compound_variable_id=[1, 2],
            ),
            discrete_control.Condition(
                greater_than=[0.8, 0.4],
                compound_variable_id=[1, 2],
                condition_id=[1, 1],
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
            discrete_control.Variable(
                listen_node_id=[3],
                variable="level",
                compound_variable_id=1,
            ),
            discrete_control.Condition(
                greater_than=[0.45],
                compound_variable_id=1,
                condition_id=1,
            ),
            discrete_control.Logic(
                truth_state=["T", "F"],
                control_state=["inactive", "active"],
            ),
        ],
    )

    model.link.add(
        model.basin[1],
        model.linear_resistance[2],
    )
    model.link.add(
        model.linear_resistance[2],
        model.basin[3],
    )
    model.link.add(
        model.basin[1],
        model.pump[4],
    )
    model.link.add(
        model.pump[4],
        model.basin[3],
    )
    model.link.add(
        model.discrete_control[5],
        model.pump[4],
    )
    model.link.add(
        model.discrete_control[6],
        model.linear_resistance[2],
    )

    return model


def flow_condition_model() -> Model:
    """Set up a basic model that involves discrete control based on a flow condition."""
    model = Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:28992",
        experimental=Experimental(concentration=True),
    )

    model.flow_boundary.add(
        Node(1, Point(0, 0)),
        [
            flow_boundary.Time(
                time=["2020-01-01", "2022-01-01"],
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
            discrete_control.Variable(
                listen_node_id=[1],
                variable="flow_rate",
                look_ahead=60 * 86400,
                compound_variable_id=1,
            ),
            discrete_control.Condition(
                greater_than=[20 / (86400)],
                compound_variable_id=1,
                condition_id=1,
            ),
            discrete_control.Logic(truth_state=["T", "F"], control_state=["off", "on"]),
        ],
    )

    model.link.add(
        model.flow_boundary[1],
        model.basin[2],
    )
    model.link.add(
        model.basin[2],
        model.pump[3],
    )
    model.link.add(
        model.pump[3],
        model.terminal[4],
    )
    model.link.add(
        model.discrete_control[5],
        model.pump[3],
    )

    return model


def level_boundary_condition_model() -> Model:
    """Set up a small model with a condition on a level boundary."""
    model = Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:28992",
        experimental=Experimental(concentration=True),
    )

    model.level_boundary.add(
        Node(1, Point(0, 0)),
        [level_boundary.Time(time=["2020-01-01", "2022-01-01"], level=[5.0, 10.0])],
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
            discrete_control.Variable(
                listen_node_id=[1],
                variable="level",
                look_ahead=60 * 86400,
                compound_variable_id=1,
            ),
            discrete_control.Condition(
                greater_than=[6.0],
                compound_variable_id=1,
                condition_id=1,
            ),
            discrete_control.Logic(truth_state=["T", "F"], control_state=["on", "off"]),
        ],
    )

    model.link.add(
        model.level_boundary[1],
        model.linear_resistance[2],
    )
    model.link.add(
        model.linear_resistance[2],
        model.basin[3],
    )
    model.link.add(
        model.basin[3],
        model.outlet[4],
    )
    model.link.add(
        model.outlet[4],
        model.terminal[5],
    )
    model.link.add(
        model.discrete_control[6],
        model.outlet[4],
    )

    return model


def tabulated_rating_curve_control_model() -> Model:
    """Discrete control on a TabulatedRatingCurve.

    The Basin drains over a TabulatedRatingCurve into a Terminal. The Control
    node will effectively increase the crest level to prevent further drainage
    at some threshold level.
    """
    model = Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:28992",
        experimental=Experimental(concentration=True),
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
            discrete_control.Variable(
                listen_node_id=[1],
                variable="level",
                compound_variable_id=1,
            ),
            discrete_control.Condition(
                greater_than=[0.5],
                compound_variable_id=1,
                condition_id=1,
            ),
            discrete_control.Logic(
                truth_state=["T", "F"], control_state=["low", "high"]
            ),
        ],
    )

    model.link.add(
        model.basin[1],
        model.tabulated_rating_curve[2],
    )
    model.link.add(
        model.tabulated_rating_curve[2],
        model.terminal[3],
    )
    model.link.add(
        model.discrete_control[4],
        model.tabulated_rating_curve[2],
    )

    return model


def compound_variable_condition_model() -> Model:
    """Model with a condition on a compound variable for DiscreteControl."""
    model = Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:28992",
        experimental=Experimental(concentration=True),
    )

    model.basin.add(
        Node(1, Point(1, 0)),
        [
            basin.Profile(area=1000.0, level=[0.0, 1.0]),
            basin.State(level=[1.0]),
        ],
    )
    model.flow_boundary.add(
        Node(2, Point(0, 0)), [flow_boundary.Static(flow_rate=[0.0])]
    )
    model.flow_boundary.add(
        Node(3, Point(0, 1)),
        [flow_boundary.Time(time=["2020-01-01", "2021-01-01"], flow_rate=[0.0, 2.0])],
    )
    model.pump.add(
        Node(4, Point(2, 0)),
        [pump.Static(control_state=["Off", "On"], flow_rate=[0.0, 1.0])],
    )
    model.terminal.add(Node(5, Point(3, 0)))
    model.discrete_control.add(
        Node(6, Point(1, 1)),
        [
            discrete_control.Variable(
                listen_node_id=[2, 3],
                variable="flow_rate",
                weight=0.5,
                compound_variable_id=1,
            ),
            discrete_control.Condition(
                greater_than=[0.5],
                compound_variable_id=1,
                condition_id=1,
            ),
            discrete_control.Logic(truth_state=["T", "F"], control_state=["On", "Off"]),
        ],
    )

    model.link.add(model.flow_boundary[2], model.basin[1])
    model.link.add(model.flow_boundary[3], model.basin[1])
    model.link.add(model.basin[1], model.pump[4])
    model.link.add(model.pump[4], model.terminal[5])
    model.link.add(model.discrete_control[6], model.pump[4])

    return model


def level_range_model() -> Model:
    """
    Keep the level of a Basin within a range around a setpoint, under the influence of time-varying forcing.

    This is done by bringing the level back to the setpoint once the level goes beyond this range.
    """
    model = Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:28992",
        solver=Solver(abstol=1e-6, reltol=1e-5),
        experimental=Experimental(concentration=True),
    )

    model.basin.add(
        Node(1, Point(0, 0)),
        [
            basin.Profile(area=1000.0, level=[0.0, 1.0]),
            basin.State(level=[20.0]),
            basin.Time(time=["2020-01-01", "2020-07-01"], precipitation=[0.0, 3e-6]),
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
        [tabulated_rating_curve.Static(level=[2.0, 15.0], flow_rate=[0.0, 2e-3])],
    )
    model.terminal.add(Node(6, Point(-2, 0)))
    model.discrete_control.add(
        Node(7, Point(1, 0)),
        [
            discrete_control.Variable(
                listen_node_id=[1],
                variable="level",
                compound_variable_id=1,
            ),
            discrete_control.Condition(
                # min, max
                greater_than=[5.0, 15.0],
                compound_variable_id=1,
                condition_id=[1, 2],
            ),
            discrete_control.Logic(
                truth_state=["FF", "TF", "TT"],
                control_state=["in", "none", "out"],
            ),
        ],
    )

    model.link.add(
        model.basin[1],
        model.pump[3],
    )
    model.link.add(
        model.pump[3],
        model.level_boundary[4],
    )
    model.link.add(
        model.level_boundary[4],
        model.pump[2],
    )
    model.link.add(
        model.pump[2],
        model.basin[1],
    )
    model.link.add(
        model.basin[1],
        model.tabulated_rating_curve[5],
    )
    model.link.add(
        model.tabulated_rating_curve[5],
        model.terminal[6],
    )
    model.link.add(
        model.discrete_control[7],
        model.pump[2],
    )
    model.link.add(
        model.discrete_control[7],
        model.pump[3],
    )

    return model


def connector_node_flow_condition_model() -> Model:
    """DiscreteControl with a condition on the flow through a connector node."""
    model = Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:28992",
        experimental=Experimental(concentration=True),
    )

    model.basin.add(
        Node(1, Point(0, 0)),
        [
            basin.Profile(area=1000.0, level=[0.0, 1.0]),
            basin.State(level=[20.0]),
        ],
    )
    model.linear_resistance.add(
        Node(2, Point(1, 0)),
        [
            linear_resistance.Static(
                control_state=["On", "Off"], resistance=1e4, active=[True, False]
            )
        ],
    )
    model.basin.add(
        Node(3, Point(2, 0)),
        [
            basin.Profile(area=1000.0, level=[0.0, 1.0]),
            basin.State(level=[10.0]),
        ],
    )
    model.discrete_control.add(
        Node(4, Point(0.5, 0.8660254037844386)),
        [
            discrete_control.Variable(
                listen_node_id=[2],
                variable=["flow_rate"],
                compound_variable_id=1,
            ),
            discrete_control.Condition(
                greater_than=[1e-4], compound_variable_id=1, condition_id=1
            ),
            discrete_control.Logic(truth_state=["T", "F"], control_state=["On", "Off"]),
        ],
    )

    model.link.add(model.basin[1], model.linear_resistance[2])
    model.link.add(model.linear_resistance[2], model.basin[3])
    model.link.add(model.discrete_control[4], model.linear_resistance[2])

    return model


def concentration_condition_model() -> Model:
    """DiscreteControl based on a concentration condition."""
    model = Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:28992",
        experimental=Experimental(concentration=True),
    )

    model.basin.add(
        Node(1, Point(0, 0)),
        [
            basin.Profile(area=1000.0, level=[0.0, 1.0]),
            basin.State(level=[20.0]),
            basin.ConcentrationExternal(
                time=pd.date_range(
                    start="2020-01-01", end="2021-01-01", periods=100, unit="ms"
                ),
                substance="kryptonite",
                concentration=np.sin(np.linspace(0, 6 * np.pi, 100)) ** 2,
            ),
        ],
    )

    model.pump.add(
        Node(2, Point(1, 0)),
        [
            pump.Static(
                control_state=["On", "Off"], active=[True, False], flow_rate=1e-3
            )
        ],
    )

    model.terminal.add(Node(3, Point(2, 0)))

    model.discrete_control.add(
        Node(4, Point(1, 1)),
        [
            discrete_control.Variable(
                listen_node_id=[1],
                variable=["concentration_external.kryptonite"],
                compound_variable_id=1,
            ),
            discrete_control.Condition(
                greater_than=[0.5], compound_variable_id=1, condition_id=1
            ),
            discrete_control.Logic(truth_state=["T", "F"], control_state=["On", "Off"]),
        ],
    )

    model.link.add(model.basin[1], model.pump[2])
    model.link.add(model.pump[2], model.terminal[3])
    model.link.add(model.discrete_control[4], model.pump[2])

    return model


def continuous_concentration_condition_model() -> Model:
    """
    DiscreteControl based on a continuous (calculated) concentration condition.

    In this case, we setup a salt concentration and mimic the Dutch coast.

               dc
             /   |
    lb --> lr -> basin <-- fb
                 |
                out
                 |
                term
    """
    model = Model(
        starttime="2020-01-01",
        endtime="2020-02-01",
        crs="EPSG:28992",
        solver=Solver(saveat=86400 / 8),
        experimental=Experimental(concentration=True),
    )

    basi = model.basin.add(
        Node(1, Point(0, 0)),
        [
            basin.Profile(area=[10.0, 100.0], level=[0.0, 1.0]),
            basin.State(level=[10.0]),
            basin.ConcentrationState(
                substance=["Cl"],
                concentration=[35.0],  # slightly salty start
            ),
            basin.Concentration(
                time=pd.date_range(
                    start="2020-01-01", end="2021-01-01", periods=10, unit="ms"
                ),
                substance="Bar",
                precipitation=0.1,
            ),
        ],
    )

    linearr = model.linear_resistance.add(
        Node(2, Point(-1, 0)),
        [
            linear_resistance.Static(
                control_state=["On", "Off"],
                resistance=[0.001, 10],
                max_flow_rate=[0.2, 0.0001],
            )
        ],
    )

    levelb = model.level_boundary.add(
        Node(3, Point(-2, 0)),
        [
            level_boundary.Static(level=[35.0]),
            level_boundary.Concentration(
                time=pd.date_range(
                    start="2020-01-01", end="2021-01-01", periods=10, unit="ms"
                ),
                substance="Cl",
                concentration=35.0,
            ),
        ],
    )

    flowb = model.flow_boundary.add(
        Node(4, Point(1, 0)),
        [
            flow_boundary.Static(flow_rate=[0.1]),
            flow_boundary.Concentration(
                time=pd.date_range(
                    start="2020-01-01", end="2021-01-01", periods=11, unit="ms"
                ),
                substance="Foo",
                concentration=1.0,
            ),
        ],
    )

    discretec = model.discrete_control.add(
        Node(5, Point(0, 0.5)),
        [
            discrete_control.Variable(
                listen_node_id=[1],
                variable=["concentration.Cl"],
                compound_variable_id=1,
            ),
            # More than 20% of seawater (35 g/L)
            discrete_control.Condition(
                greater_than=[7], compound_variable_id=1, condition_id=1
            ),
            discrete_control.Logic(truth_state=["T", "F"], control_state=["Off", "On"]),
        ],
    )

    outl = model.outlet.add(Node(6, Point(0, -0.5)), [outlet.Static(flow_rate=[0.11])])
    term = model.terminal.add(Node(7, Point(0, -1)))

    model.link.add(levelb, linearr)
    model.link.add(linearr, basi)
    model.link.add(flowb, basi)
    model.link.add(discretec, linearr)
    model.link.add(basi, outl)
    model.link.add(outl, term)

    return model


def transient_condition_model() -> Model:
    """DiscreteControl based on transient condition."""
    model = Model(starttime="2020-01-01", endtime="2020-03-01", crs="EPSG:28992")

    lb = model.level_boundary.add(
        Node(1, Point(0, 0)), [level_boundary.Static(level=[2.0])]
    )

    pmp = model.pump.add(
        Node(2, Point(1, 0)),
        [pump.Static(control_state=["A", "B"], flow_rate=[1.0, 2.0])],
    )

    bsn = model.basin.add(
        Node(3, Point(2, 0)),
        [
            basin.State(level=[2.0]),
            basin.Profile(level=[0.0, 1.0], area=[100.0, 100.0]),
        ],
    )

    dc = model.discrete_control.add(
        Node(4, Point(1, 1), cyclic_time=True),
        [
            discrete_control.Variable(
                listen_node_id=[1], variable=["level"], compound_variable_id=1
            ),
            discrete_control.Condition(
                compound_variable_id=1,
                condition_id=1,
                greater_than=[1.0, 3.0, 1.0],
                time=["2020-01-01", "2020-02-01", "2020-03-01"],
            ),
            discrete_control.Logic(truth_state=["F", "T"], control_state=["A", "B"]),
        ],
    )

    model.edge.add(lb, pmp)
    model.edge.add(pmp, bsn)
    model.edge.add(dc, pmp)

    return model
