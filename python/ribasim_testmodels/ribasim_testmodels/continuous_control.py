from datetime import datetime

import numpy as np
import pandas as pd
from ribasim.config import Experimental
from ribasim.geometry.node import Node
from ribasim.model import Model
from ribasim.nodes import (
    basin,
    continuous_control,
    junction,
    level_boundary,
    linear_resistance,
    outlet,
    pid_control,
    pump,
    user_demand,
)
from shapely.geometry import Point


def outlet_continuous_control_model() -> Model:
    """Set up a small model that distributes flow over 2 branches."""
    model = Model(
        starttime=datetime(2020, 1, 1),
        endtime=datetime(2021, 1, 1),
        crs="EPSG:28992",
        experimental=Experimental(concentration=True),
    )

    model.level_boundary.add(
        Node(1, Point(0, 0)),
        [
            level_boundary.Time(
                time=pd.date_range(
                    start="2020-01-01", end="2021-01-01", periods=100, unit="ms"
                ),
                level=6.0 + np.sin(np.linspace(0, 6 * np.pi, 100)),
            )
        ],
    )

    model.linear_resistance.add(
        Node(2, Point(1, 0)), [linear_resistance.Static(resistance=[10.0])]
    )

    model.basin.add(
        Node(3, Point(2, 0)),
        [
            basin.Profile(area=10000.0, level=[0.0, 1.0]),
            basin.State(level=[10.0]),
        ],
    )

    model.outlet.add(Node(4, Point(3, 1)), [outlet.Static(flow_rate=[1.0])])
    model.outlet.add(Node(5, Point(3, -1)), [outlet.Static(flow_rate=[1.0])])

    model.terminal.add(Node(6, Point(4, 1)))
    model.terminal.add(Node(7, Point(4, -1)))

    model.continuous_control.add(
        Node(8, Point(2, 1)),
        [
            continuous_control.Variable(
                listen_node_id=[2],
                variable="flow_rate",
            ),
            continuous_control.Function(
                input=[0.0, 1.0],
                output=[0.0, 0.6],
                controlled_variable="flow_rate",
            ),
        ],
    )
    model.continuous_control.add(
        Node(9, Point(2, -1)),
        [
            continuous_control.Variable(
                listen_node_id=[2],
                variable="flow_rate",
            ),
            continuous_control.Function(
                input=[0.0, 1.0],
                output=[0.0, 0.4],
                controlled_variable="flow_rate",
            ),
        ],
    )

    model.link.add(model.level_boundary[1], model.linear_resistance[2])
    model.link.add(model.linear_resistance[2], model.basin[3])
    model.link.add(model.basin[3], model.outlet[4])
    model.link.add(model.basin[3], model.outlet[5])
    model.link.add(model.outlet[4], model.terminal[6])
    model.link.add(model.outlet[5], model.terminal[7])
    model.link.add(model.continuous_control[8], model.outlet[4])
    model.link.add(model.continuous_control[9], model.outlet[5])

    return model


def chained_continuous_control_model() -> Model:
    """Set up a model where ContinuousControl listens to a flow that is set by ContinuousControl.

    ContinuousControl #8 sets Outlet #4 to 60% of the flow of LinearResistance #2, and
    ContinuousControl #9 sets Outlet #5 to 2/3 of the flow of Outlet #4, so to 40% of the
    flow of LinearResistance #2 as in `outlet_continuous_control_model`.
    """
    model = outlet_continuous_control_model()
    model.experimental.concentration = False
    model.endtime = datetime(2020, 2, 1)

    variable = model.continuous_control.variable.df
    assert variable is not None
    variable.loc[variable.node_id == 9, "listen_node_id"] = 4
    function = model.continuous_control.function.df
    assert function is not None
    function.loc[(function.node_id == 9) & (function.input == 1.0), "output"] = 2 / 3
    return model


def pid_continuous_control_model() -> Model:
    """Set up a model where PidControl with a derivative term controls a Basin fed by ContinuousControl.

    ContinuousControl #6 sets Outlet #2 to twice the flow of LinearResistance #7, so the net
    inflow of Basin #3 depends on its level. PidControl #8 controls the level of Basin #3 with
    Pump #4, and the derivative term uses the storage rate of Basin #3, which includes the flow
    of Outlet #2.
    """
    model = Model(
        starttime=datetime(2020, 1, 1),
        endtime=datetime(2020, 3, 1),
        crs="EPSG:28992",
    )

    lb_upstream = model.level_boundary.add(
        Node(1, Point(0, 0)), [level_boundary.Static(level=[10.0])]
    )
    out = model.outlet.add(Node(2, Point(1, 0)), [outlet.Static(flow_rate=[0.0])])
    bsn = model.basin.add(
        Node(3, Point(2, 0)),
        [basin.Profile(area=1000.0, level=[0.0, 10.0]), basin.State(level=[6.0])],
    )
    pmp = model.pump.add(Node(4, Point(3, 0)), [pump.Static(flow_rate=[0.0])])
    trm = model.terminal.add(Node(5, Point(4, 0)))
    cc = model.continuous_control.add(
        Node(6, Point(1, 1)),
        [
            continuous_control.Variable(listen_node_id=[7], variable="flow_rate"),
            continuous_control.Function(
                input=[0.0, 1.0], output=[0.0, 2.0], controlled_variable="flow_rate"
            ),
        ],
    )
    lr = model.linear_resistance.add(
        Node(7, Point(2, -1)), [linear_resistance.Static(resistance=[1e3])]
    )
    lb_downstream = model.level_boundary.add(
        Node(9, Point(2, -2)), [level_boundary.Static(level=[2.0])]
    )
    pid = model.pid_control.add(
        Node(8, Point(3, 1)),
        [
            pid_control.Static(
                listen_node_id=[3],
                target=[5.0],
                proportional=[-1e-2],
                integral=[-1e-8],
                derivative=[-1e2],
            )
        ],
    )

    model.link.add(lb_upstream, out)
    model.link.add(out, bsn)
    model.link.add(bsn, pmp)
    model.link.add(pmp, trm)
    model.link.add(bsn, lr)
    model.link.add(lr, lb_downstream)
    model.link.add(cc, out)
    model.link.add(pid, pmp)
    return model


def pid_listened_by_continuous_control_model() -> Model:
    """Set up a model where ContinuousControl listens to a flow set by PidControl.

    PidControl #6 controls the level of Basin #3 with Pump #4, which pumps into Basin #5.
    ContinuousControl #9 sets Outlet #7 from Basin #5 to half of the flow of Pump #4, so it
    depends on the PID integral state.
    """
    model = Model(
        starttime=datetime(2020, 1, 1),
        endtime=datetime(2020, 3, 1),
        crs="EPSG:28992",
    )

    lb = model.level_boundary.add(
        Node(1, Point(0, 0)), [level_boundary.Static(level=[10.0])]
    )
    lr = model.linear_resistance.add(
        Node(2, Point(1, 0)), [linear_resistance.Static(resistance=[1e3])]
    )
    b1 = model.basin.add(
        Node(3, Point(2, 0)),
        [basin.Profile(area=1000.0, level=[0.0, 10.0]), basin.State(level=[6.0])],
    )
    pmp = model.pump.add(Node(4, Point(3, 0)), [pump.Static(flow_rate=[0.0])])
    b2 = model.basin.add(
        Node(5, Point(4, 0)),
        [basin.Profile(area=1000.0, level=[0.0, 10.0]), basin.State(level=[2.0])],
    )
    pid = model.pid_control.add(
        Node(6, Point(3, 1)),
        [
            pid_control.Static(
                listen_node_id=[3],
                target=[5.0],
                proportional=[-1e-2],
                integral=[-1e-7],
                derivative=[-1e2],
            )
        ],
    )
    out = model.outlet.add(Node(7, Point(5, 0)), [outlet.Static(flow_rate=[0.0])])
    trm = model.terminal.add(Node(8, Point(6, 0)))
    cc = model.continuous_control.add(
        Node(9, Point(5, 1)),
        [
            continuous_control.Variable(listen_node_id=[4], variable="flow_rate"),
            continuous_control.Function(
                input=[0.0, 1.0], output=[0.0, 0.5], controlled_variable="flow_rate"
            ),
        ],
    )

    model.link.add(lb, lr)
    model.link.add(lr, b1)
    model.link.add(b1, pmp)
    model.link.add(pmp, b2)
    model.link.add(b2, out)
    model.link.add(out, trm)
    model.link.add(pid, pmp)
    model.link.add(cc, out)
    return model


def junction_chained_continuous_control_model() -> Model:
    """Set up a model where ContinuousControl listens to a Junction fed by a flow set by ContinuousControl.

    ContinuousControl #10 sets Pump #2 from Basin #1 to the flow of LinearResistance #12. Pump #2
    flows into Junction #3, which supplies UserDemand #4 and passes the remainder on to Basin #5.
    ContinuousControl #9 sets Outlet #6 from Basin #5 to the flow rate of Junction #3, which is
    what UserDemand #4 leaves.
    """
    model = Model(
        starttime=datetime(2020, 1, 1),
        endtime=datetime(2020, 2, 1),
        crs="EPSG:28992",
    )

    def basin_tables(level: float) -> list:
        return [
            basin.Profile(area=1000.0, level=[0.0, 10.0]),
            basin.State(level=[level]),
        ]

    def listen_to(node_id: int) -> list:
        return [
            continuous_control.Variable(listen_node_id=[node_id], variable="flow_rate"),
            continuous_control.Function(
                input=[0.0, 1.0], output=[0.0, 1.0], controlled_variable="flow_rate"
            ),
        ]

    b1 = model.basin.add(Node(1, Point(0, 0)), basin_tables(8.0))
    pmp = model.pump.add(Node(2, Point(1, 0)), [pump.Static(flow_rate=[0.0])])
    jct = model.junction.add(
        Node(3, Point(2, 0)), [junction.Static(to_node_id=[5], fraction=[1.0])]
    )
    ud = model.user_demand.add(
        Node(4, Point(2, 1)),
        [
            user_demand.Static(
                demand_priority=[1],
                demand=[1e-3],
                return_factor=[0.0],
                min_level=[-10.0],
            )
        ],
    )
    b5 = model.basin.add(Node(5, Point(3, 0)), basin_tables(4.0))
    out = model.outlet.add(Node(6, Point(4, 0)), [outlet.Static(flow_rate=[0.0])])
    trm = model.terminal.add(Node(7, Point(5, 0)))
    trm_ud = model.terminal.add(Node(8, Point(2, 2)))
    cc_out = model.continuous_control.add(Node(9, Point(4, 1)), listen_to(3))
    cc_pump = model.continuous_control.add(Node(10, Point(1, 1)), listen_to(12))
    lb = model.level_boundary.add(
        Node(11, Point(-1, -1)), [level_boundary.Static(level=[10.0])]
    )
    lr = model.linear_resistance.add(
        Node(12, Point(0, -1)), [linear_resistance.Static(resistance=[5e2])]
    )

    model.link.add(lb, lr)
    model.link.add(lr, b1)
    model.link.add(b1, pmp)
    model.link.add(pmp, jct)
    model.link.add(jct, ud)
    model.link.add(jct, b5)
    model.link.add(ud, trm_ud)
    model.link.add(b5, out)
    model.link.add(out, trm)
    model.link.add(cc_out, out)
    model.link.add(cc_pump, pmp)
    return model
