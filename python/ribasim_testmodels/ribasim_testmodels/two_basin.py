from ribasim.config import Node
from ribasim.model import Model
from ribasim.nodes import basin, flow_boundary, tabulated_rating_curve, terminal
from shapely.geometry import Point


def two_basin_model() -> Model:
    """
    Create a model of two basins.

    The basins are not connected; the model is mostly designed to test in
    combination with a groundwater model.

    The left basin receives water. In case of a coupled run, the water
    infiltrates in the left basin, and exfiltrates in the right basin.
    The right basin fills up and discharges over the rating curve.
    """

    model = Model(starttime="2020-01-01 00:00:00", endtime="2021-01-01 00:00:00")

    model.flow_boundary.add(
        Node(1, Point(0, 0)), [flow_boundary.Static(flow_rate=[1e-2])]
    )
    basin_shared = [
        basin.Profile(area=400.0, level=[0.0, 1.0]),
        basin.State(level=[0.01]),
    ]
    model.basin.add(
        Node(2, Point(250, 0)),
        [
            *basin_shared,
            basin.Subgrid(
                subgrid_id=1,
                basin_level=[0.0, 1.0],
                subgrid_level=[0.0, 1.0],
                meta_x=250.0,
                meta_y=0.0,
            ),
        ],
    )
    model.basin.add(
        Node(3, Point(750, 0)),
        [
            *basin_shared,
            basin.Subgrid(
                subgrid_id=2,
                basin_level=[0.0, 1.0],
                subgrid_level=[0.0, 1.0],
                meta_x=750.0,
                meta_y=0.0,
            ),
        ],
    )
    model.tabulated_rating_curve.add(
        Node(4, Point(1000, 0)),
        [tabulated_rating_curve.Static(level=[0.0, 1.0], flow_rate=[0.0, 0.01])],
    )
    model.terminal.add(Node(5, Point(1100, 0)), [terminal.Static()])

    model.edge.add(
        from_node=model.flow_boundary[1], to_node=model.basin[2], edge_type="flow"
    )
    model.edge.add(
        from_node=model.basin[3],
        to_node=model.tabulated_rating_curve[4],
        edge_type="flow",
    )
    model.edge.add(
        from_node=model.tabulated_rating_curve[4],
        to_node=model.terminal[5],
        edge_type="flow",
    )
    return model
