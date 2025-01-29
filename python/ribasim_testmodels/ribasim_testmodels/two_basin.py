from typing import Any

from ribasim.config import Experimental, Node, Results
from ribasim.input_base import TableModel
from ribasim.model import Model
from ribasim.nodes import basin, flow_boundary, tabulated_rating_curve
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
    model = Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:28992",
        experimental=Experimental(concentration=True),
        results=Results(subgrid=True),
    )

    model.flow_boundary.add(
        Node(1, Point(0, 0)), [flow_boundary.Static(flow_rate=[1e-2])]
    )
    basin_shared: list[TableModel[Any]] = [
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
            # Raise the subgrid levels by a meter after a month
            basin.SubgridTime(
                subgrid_id=2,
                time=["2020-01-01", "2020-01-01", "2020-02-01", "2020-02-01"],
                basin_level=[0.0, 1.0, 0.0, 1.0],
                subgrid_level=[0.0, 1.0, 1.0, 2.0],
                meta_x=750.0,
                meta_y=0.0,
            ),
        ],
    )
    model.tabulated_rating_curve.add(
        Node(4, Point(1000, 0)),
        [tabulated_rating_curve.Static(level=[0.0, 1.0], flow_rate=[0.0, 0.01])],
    )
    model.terminal.add(Node(5, Point(1100, 0)))

    model.link.add(model.flow_boundary[1], model.basin[2])
    model.link.add(
        model.basin[3],
        model.tabulated_rating_curve[4],
    )
    model.link.add(
        model.tabulated_rating_curve[4],
        model.terminal[5],
    )
    return model
