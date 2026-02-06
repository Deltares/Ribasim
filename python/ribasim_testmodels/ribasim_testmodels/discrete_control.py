from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd
from ribasim.config import Experimental, Interpolation, Node, Results
from ribasim.input_base import (
    TableModel,
)
from ribasim.model import Model, Solver
from ribasim.nodes import (
    basin,
    discrete_control,
    flow_boundary,
    level_boundary,
    linear_resistance,
    manning_resistance,
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
                resistance=[1e5, np.inf],
                control_state=["active", "inactive"],
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
                threshold_high=[0.8, 0.4],
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
                threshold_high=[0.45],
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
        interpolation=Interpolation(flow_boundary="linear"),
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
                threshold_high=[20 / (86400)],
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
        input_dir=Path("input"),
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
        [outlet.Static(flow_rate=[0.5 / 3600, 0], control_state=["on", "off"])],
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
                threshold_high=[6.0],
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

    model.level_boundary.time.filepath = Path("level-boundary-time.nc")

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
        results=Results(format="netcdf"),
        input_dir=Path("input"),
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
                threshold_high=[0.5],
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

    # write the "Basin / state" to NetCDF for testing
    model.basin.state.filepath = Path("basin-state.nc")

    return model


def compound_variable_condition_model() -> Model:
    """Model with a condition on a compound variable for DiscreteControl."""
    model = Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:28992",
        input_dir=Path("input"),
        experimental=Experimental(concentration=True),
        interpolation=Interpolation(flow_boundary="linear"),
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
                threshold_high=[0.5],
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

    model.flow_boundary.time.filepath = Path("flow-boundary-time.nc")

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
                threshold_high=[5.0, 15.0],
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


def storage_condition_model() -> Model:
    """Create a model with a discrete control condition based on the storage of a Basin."""
    model = Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:28992",
    )

    fb = model.flow_boundary.add(
        Node(1, Point(0, 0)), [flow_boundary.Static(flow_rate=[1e-3])]
    )

    bsn = model.basin.add(
        Node(2, Point(1, 0)),
        [basin.Profile(area=1000.0, level=[0.0, 10.0]), basin.State(level=[5.0])],
    )

    pmp = model.pump.add(
        Node(3, Point(2, 0)),
        [pump.Static(control_state=["off", "on"], flow_rate=[0, "1e-3"])],
    )

    tmn = model.terminal.add(Node(4, Point(3, 0)))

    dc = model.discrete_control.add(
        Node(5, Point(1, 1)),
        [
            discrete_control.Variable(
                compound_variable_id=1, listen_node_id=2, variable=["storage"]
            ),
            discrete_control.Condition(
                compound_variable_id=1, condition_id=1, threshold_high=[7500]
            ),
            discrete_control.Logic(truth_state=["F", "T"], control_state=["off", "on"]),
        ],
    )

    model.link.add(fb, bsn)
    model.link.add(bsn, pmp)
    model.link.add(pmp, tmn)
    model.link.add(dc, pmp)

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
                control_state=["On", "Off"], resistance=[1e4, np.inf]
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
                threshold_high=[1e-4], compound_variable_id=1, condition_id=1
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
        [pump.Static(control_state=["On", "Off"], flow_rate=[1e-3, 0])],
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
                threshold_high=[0.5], compound_variable_id=1, condition_id=1
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
                threshold_high=[7], compound_variable_id=1, condition_id=1
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
                threshold_high=[1.0, 3.0, 1.0],
                time=["2020-01-01", "2020-02-01", "2020-03-01"],
            ),
            discrete_control.Logic(truth_state=["F", "T"], control_state=["A", "B"]),
        ],
    )

    model.link.add(lb, pmp)
    model.link.add(pmp, bsn)
    model.link.add(dc, pmp)

    return model


def circular_flow_model() -> Model:
    """Create a model with a circular flow and a discrete control on a pump."""
    model = Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:4326",
        solver=Solver(saveat=3600),
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
        basin.Profile(area=[10, 10_000.0], level=[-10, 1.0]),
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

    ###Setup outlet:

    outlet10 = model.outlet.add(
        Node(10, Point(5.0, 0.0)),
        [outlet.Static(flow_rate=10, min_upstream_level=[1.1])],
    )

    outlet12 = model.outlet.add(
        Node(12, Point(1.0, 0)),
        [outlet.Static(flow_rate=[10])],
    )

    outlet5 = model.outlet.add(
        Node(5, Point(2, 1), name="inlaat"),
        [
            outlet.Static(
                flow_rate=2.0, min_upstream_level=[1.0], max_downstream_level=[1.0]
            )
        ],
    )

    outlet13 = model.outlet.add(
        Node(13, Point(3, 2), name="inlaat/uitlaat"),
        [
            outlet.Static(
                flow_rate=2.0, min_upstream_level=[1], max_downstream_level=[0.9]
            )
        ],
    )

    ###Setup Manning resistance:
    manning_resistance2 = model.manning_resistance.add(
        Node(2, Point(3, 0.0)),
        [
            manning_resistance.Static(
                length=[900], manning_n=[0.04], profile_width=[6.0], profile_slope=[3.0]
            )
        ],
    )

    ##Setup pump:
    control_pump = model.discrete_control.add(
        Node(1, Point(0, 0.5)),
        [
            discrete_control.Variable(
                listen_node_id=[6],
                variable=["level"],
                compound_variable_id=1,
            ),
            discrete_control.Condition(
                threshold_high=[0.95],
                threshold_low=[0.9],
                compound_variable_id=1,
                condition_id=1,
            ),
            discrete_control.Logic(truth_state=["T", "F"], control_state=["on", "off"]),
        ],
    )
    pump7 = model.pump.add(
        Node(7, Point(4.9, 0.1)),
        [
            pump.Static(
                control_state=["on", "off"],
                flow_rate=[0.1, 0.0],
            )
        ],
    )

    ##Setup level boundary:
    level_boundary11 = model.level_boundary.add(
        Node(11, Point(0, 0)), [level_boundary.Static(level=[1.1])]
    )
    level_boundary17 = model.level_boundary.add(
        Node(17, Point(6, 0)), [level_boundary.Static(level=[0.9])]
    )

    ##Setup the links:
    model.link.add(manning_resistance2, basin9)  # 1
    model.link.add(
        basin3,
        outlet5,
    )  # 2
    model.link.add(
        basin3,
        manning_resistance2,
    )  # 3

    model.link.add(outlet5, basin4)  # 4
    model.link.add(basin4, outlet13)  # 5
    model.link.add(outlet13, basin6)  # 4
    model.link.add(basin6, pump7)  # 5
    model.link.add(pump7, basin9)  # 6
    model.link.add(basin9, outlet10)  # 7
    model.link.add(level_boundary11, outlet12)  # 8
    model.link.add(outlet12, basin3)  # 9
    model.link.add(outlet10, level_boundary17)  # 10
    model.link.add(control_pump, pump7)  # 11

    return model


def invalid_ribasim_control_state_model() -> Model:
    """Create a model with an invalid reserved control state 'Ribasim.blabla'.

    This model should raise an error during validation because 'Ribasim.blabla'
    is not a recognized reserved control state.
    """
    model = Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:28992",
    )

    model.level_boundary.add(
        Node(1, Point(0, 0)),
        [level_boundary.Static(level=[1.0])],
    )

    model.pump.add(
        Node(2, Point(1, 0)),
        [
            pump.Static(
                control_state=["Ribasim.blabla", "default"], flow_rate=[1e-3, 0.0]
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
                threshold_high=[0.5],
                compound_variable_id=1,
                condition_id=1,
            ),
            discrete_control.Logic(
                truth_state=["T", "F"],
                control_state=["Ribasim.blabla", "default"],
            ),
        ],
    )

    model.link.add(model.level_boundary[1], model.pump[2])
    model.link.add(model.pump[2], model.terminal[3])
    model.link.add(model.discrete_control[4], model.pump[2])

    return model
