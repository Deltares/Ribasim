import numpy as np
import pandas as pd
from ribasim import Model, Node
from ribasim.nodes import (
    basin,
    outlet,
    pid_control,
    pump,
)
from shapely.geometry import Point


def local_pidcontrolled_cascade_model():
    """Demonstrating model for the cascade polder project from our partner"""

    model = Model(starttime="2020-01-01", endtime="2021-01-01", crs="EPSG:28992")

    # Set up basins
    time = pd.date_range(model.starttime, model.endtime)
    day_of_year = time.day_of_year.to_numpy()

    precipitation = np.zeros(day_of_year.size)
    precipitation[0:90] = 1.72e-8
    precipitation[330:366] = 1.72e-8

    evaporation = np.zeros(day_of_year.size)
    evaporation[130:270] = 2.87e-8

    drainage = np.zeros(day_of_year.size)
    drainage[120:270] = 0.4 * 2.87e-8
    drainage3 = drainage.copy()
    drainage3[210:240] = 17 * 2.87e-8
    drainage4 = drainage.copy()
    drainage4[160:240] = 13 * 2.87e-8

    infiltration = np.zeros(day_of_year.size)
    infiltration[0:90] = 5e-8

    polder_profile = basin.Profile(area=[100, 100], level=[0.0, 3.0])

    basin_time = [
        basin.Time(
            time=pd.date_range(model.starttime, model.endtime),
            drainage=drainage,
            potential_evaporation=evaporation,
            infiltration=0.0,
            precipitation=precipitation,
        ),
    ]

    basin_time4 = [
        basin.Time(
            time=pd.date_range(model.starttime, model.endtime),
            drainage=drainage4,
            potential_evaporation=evaporation,
            infiltration=0.0,
            precipitation=precipitation,
        ),
    ]
    basin_time3 = [
        basin.Time(
            time=pd.date_range(model.starttime, model.endtime),
            drainage=drainage3,
            potential_evaporation=evaporation,
            infiltration=0.0,
            precipitation=precipitation,
        ),
    ]

    model.basin.add(
        Node(1, Point(2.0, 0.0)),
        [
            basin.State(level=[2.5]),
            basin.Profile(area=[1000, 1000], level=[0.0, 3.0]),
            basin.Time(
                time=pd.date_range(model.starttime, model.endtime),
                drainage=0.0,
                potential_evaporation=0.0,
                infiltration=0.0,
                precipitation=0.0,
            ),
        ],
    )
    model.basin.add(
        Node(4, Point(0.0, -2.0)),
        [basin.State(level=[1.5]), polder_profile, *basin_time],
    )
    model.basin.add(
        Node(6, Point(0.0, -4.0)),
        [basin.State(level=[1.0]), polder_profile, *basin_time],
    )
    model.basin.add(
        Node(8, Point(2.0, -4.0)),
        [basin.State(level=[1.5]), polder_profile, *basin_time3],
    )
    model.basin.add(
        Node(10, Point(4.0, -4.0)),
        [basin.State(level=[1.3]), polder_profile, *basin_time4],
    )
    model.basin.add(
        Node(12, Point(4.0, -2.0)),
        [basin.State(level=[0.1]), polder_profile, *basin_time],
    )

    # Set up pid control
    pid_control_data = {
        "listen_node_type": "Basin",
        "proportional": [0.1],
        "integral": [0.00],
        "derivative": [0.0],
    }
    model.pid_control.add(
        Node(3, Point(-1.0, -1.0)),
        [pid_control.Static(listen_node_id=[4], target=[2.0], **pid_control_data)],
    )
    model.pid_control.add(
        Node(14, Point(-1.0, -3.0)),
        [pid_control.Static(listen_node_id=[6], target=[1.5], **pid_control_data)],
    )
    model.pid_control.add(
        Node(15, Point(1.0, -3.0)),
        [pid_control.Static(listen_node_id=[8], target=[1.0], **pid_control_data)],
    )
    model.pid_control.add(
        Node(16, Point(3.0, -3.0)),
        [pid_control.Static(listen_node_id=[10], target=[0.5], **pid_control_data)],
    )

    # Set up pump
    model.pump.add(
        Node(13, Point(4.0, -1.0)),
        [pump.Static(flow_rate=[0.5 / 3600])],
    )

    # Set up outlet
    model.outlet.add(
        Node(2, Point(0.0, -1.0)),
        [outlet.Static(flow_rate=[4 * 0.5 / 3600], min_crest_level=[0.0])],
    )
    model.outlet.add(
        Node(5, Point(0.0, -3.0)),
        [outlet.Static(flow_rate=[0.5 / 3600], min_crest_level=[1.95])],
    )
    model.outlet.add(
        Node(7, Point(1.0, -4.0)),
        [outlet.Static(flow_rate=[4 * 0.5 / 3600], min_crest_level=[1.45])],
    )
    model.outlet.add(
        Node(9, Point(3.0, -4.0)),
        [outlet.Static(flow_rate=[0.5 / 3600], min_crest_level=[0.95])],
    )
    model.outlet.add(
        Node(11, Point(4.0, -3.0)),
        [outlet.Static(flow_rate=[0.5 / 3600], min_crest_level=[0.45])],
    )

    model.edge.add(model.basin[1], model.outlet[2])
    model.edge.add(model.pid_control[3], model.outlet[2])
    model.edge.add(model.outlet[2], model.basin[4])
    model.edge.add(model.basin[4], model.outlet[5])
    model.edge.add(model.outlet[5], model.basin[6])
    model.edge.add(model.basin[6], model.outlet[7])
    model.edge.add(model.outlet[7], model.basin[8])
    model.edge.add(model.basin[8], model.outlet[9])
    model.edge.add(model.outlet[9], model.basin[10])
    model.edge.add(model.basin[10], model.outlet[11])
    model.edge.add(model.outlet[11], model.basin[12])
    model.edge.add(model.basin[12], model.pump[13])
    model.edge.add(model.pump[13], model.basin[1])
    model.edge.add(model.pid_control[14], model.outlet[5])
    model.edge.add(model.pid_control[15], model.outlet[7])
    model.edge.add(model.pid_control[16], model.outlet[9])

    return model
