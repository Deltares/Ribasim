import numpy as np
import pandas as pd
from ribasim.config import Node
from ribasim.model import Model
from ribasim.nodes import (
    basin,
    discrete_control,
    flow_boundary,
    level_boundary,
    linear_resistance,
    pid_control,
    pump,
    tabulated_rating_curve,
)
from shapely.geometry import Point


def dutch_waterways_model() -> Model:
    """Set up a model that is representative of the main Dutch rivers."""

    model = Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:28992",
    )

    profile_level = np.array([1.86, 3.21, 4.91, 6.61, 8.31, 10.07, 10.17, 10.27, 11.61, 12.94, 13.05, 13.69, 14.32, 14.96, 15.59])  # fmt: skip
    width = np.array([10.0, 88.0, 137.0, 139.0, 141.0, 219.0, 220.0, 221.0, 302.0, 606.0, 837.0, 902.0, 989.0, 1008.0, 1011.0])  # fmt: skip
    basin_profile = basin.Profile(level=profile_level, area=1e4 * width)

    linear_resistance_shared = [linear_resistance.Static(resistance=[1e-2])]

    # Flow rate curve from sine series
    n_times = 250
    time = pd.date_range(start="2020-01-01", end="2021-01-01", periods=n_times).astype(
        "datetime64[s]"
    )
    flow_rate = np.zeros(n_times)
    x = np.linspace(0, 1, n_times)
    n_terms = 5
    for i in np.arange(1, 2 * n_terms, 2):
        flow_rate += 4 / (i * np.pi) * np.sin(2 * i * np.pi * x)

    # Scale to desired magnitude
    b = (250 + 800) / 2
    a = 800 - b
    flow_rate = a * flow_rate + b

    model.flow_boundary.add(
        Node(1, Point(196212, 436220)),
        [flow_boundary.Time(time=time, flow_rate=flow_rate)],
    )
    model.basin.add(
        Node(2, Point(194292, 439828), name="IJsselkop"),
        [basin.State(level=[8.31]), basin_profile],
    )
    model.linear_resistance.add(
        Node(3, Point(195237, 442337)), linear_resistance_shared
    )
    model.linear_resistance.add(
        Node(4, Point(187489, 442384)), linear_resistance_shared
    )
    model.basin.add(
        Node(5, Point(199198, 445557), name="IJssel Westervoort"),
        [basin.State(level=[7.5]), basin_profile],
    )
    model.basin.add(
        Node(6, Point(184906, 441999), name="Nederrijn Arnhem"),
        [basin.State(level=[7.5]), basin_profile],
    )
    model.level_boundary.add(
        Node(7, Point(208272, 454422)), [level_boundary.Static(level=[3.0])]
    )
    model.tabulated_rating_curve.add(
        Node(8, Point(183819, 442076), name="Driel open"),
        [
            tabulated_rating_curve.Static(
                control_state=["pump_low", "pump_high", "rating_curve", "rating_curve"],
                active=[False, False, True, True],
                # The level and flow rate for "pump_low", "pump_high" are irrelevant
                # since the rating curve is not active here
                level=[0.0, 0.0, 7.45, 7.46],
                flow_rate=[0.0, 0.0, 418, 420.15],
            )
        ],
    )
    model.pump.add(
        Node(9, Point(183859, 441561), name="Driel gecontroleerd"),
        [
            pump.Static(
                active=[True, True, False],
                control_state=["pump_low", "pump_high", "rating_curve"],
                flow_rate=[15.0, 25.0, 1.0],
            )
        ],
    )
    model.basin.add(
        Node(10, Point(178532, 442187)), [basin.State(level=[7.0]), basin_profile]
    )
    model.linear_resistance.add(
        Node(11, Point(170775, 439396)), linear_resistance_shared
    )
    model.basin.add(
        Node(12, Point(162995, 443270)), [basin.State(level=[6.0]), basin_profile]
    )
    model.tabulated_rating_curve.add(
        Node(13, Point(156421, 443460), name="Amerongen open"),
        [tabulated_rating_curve.Static(level=[4.45, 4.46], flow_rate=[418, 420.15])],
    )
    model.pump.add(
        Node(14, Point(156882, 441920), name="Amerongen gecontroleerd"),
        [pump.Static(flow_rate=[1.0], min_flow_rate=0.0, max_flow_rate=50.0)],
    )
    model.basin.add(
        Node(15, Point(154547, 442540)), [basin.State(level=[5.5]), basin_profile]
    )
    model.level_boundary.add(
        Node(16, Point(151776, 441465), name="Kruising ARK"),
        [level_boundary.Static(level=[3.0])],
    )
    model.discrete_control.add(
        Node(17, Point(183612, 441833), name="Controller Driel"),
        [
            discrete_control.Condition(
                listen_node_type="FlowBoundary",
                listen_node_id=1,
                variable="flow_rate",
                greater_than=[250, 275, 750, 800],
            ),
            discrete_control.Logic(
                truth_state=["FFFF", "U***", "T**F", "***D", "TTTT"],
                control_state=[
                    "pump_low",
                    "pump_low",
                    "pump_high",
                    "rating_curve",
                    "rating_curve",
                ],
            ),
        ],
    )
    model.linear_resistance.add(
        Node(18, Point(201507, 447443)), linear_resistance_shared
    )
    model.linear_resistance.add(
        Node(19, Point(153039, 442444)), linear_resistance_shared
    )
    model.pid_control.add(
        Node(20, Point(155961, 442714), name="Controller Amerongen"),
        [
            pid_control.Static(
                listen_node_type="Basin",
                listen_node_id=[12],
                target=6.0,
                proportional=-0.005,
                integral=0.0,
                derivative=-0.002,
            )
        ],
    )

    model.edge.add(
        model.flow_boundary[1],
        model.basin[2],
        name="Pannerdensch Kanaal",
    )
    model.edge.add(
        model.basin[2],
        model.linear_resistance[3],
        name="Start IJssel",
    )
    model.edge.add(
        model.linear_resistance[3],
        model.basin[5],
    )
    model.edge.add(
        model.basin[2],
        model.linear_resistance[4],
        name="Start Nederrijn",
    )
    model.edge.add(
        model.linear_resistance[4],
        model.basin[6],
    )
    model.edge.add(
        model.basin[6],
        model.pump[9],
    )
    model.edge.add(
        model.pump[9],
        model.basin[10],
    )
    model.edge.add(
        model.basin[10],
        model.linear_resistance[11],
    )
    model.edge.add(
        model.linear_resistance[11],
        model.basin[12],
    )
    model.edge.add(
        model.basin[12],
        model.pump[14],
    )
    model.edge.add(
        model.pump[14],
        model.basin[15],
    )
    model.edge.add(
        model.basin[6],
        model.tabulated_rating_curve[8],
    )
    model.edge.add(
        model.tabulated_rating_curve[8],
        model.basin[10],
    )
    model.edge.add(
        model.basin[12],
        model.tabulated_rating_curve[13],
    )
    model.edge.add(
        model.tabulated_rating_curve[13],
        model.basin[15],
    )
    model.edge.add(
        model.basin[5],
        model.linear_resistance[18],
    )
    model.edge.add(
        model.linear_resistance[18],
        model.level_boundary[7],
    )
    model.edge.add(
        model.basin[15],
        model.linear_resistance[19],
    )
    model.edge.add(
        model.linear_resistance[19],
        model.level_boundary[16],
    )
    model.edge.add(
        model.pid_control[20],
        model.pump[14],
    )
    model.edge.add(
        model.discrete_control[17],
        model.tabulated_rating_curve[8],
    )
    model.edge.add(
        model.discrete_control[17],
        model.pump[9],
    )

    return model
