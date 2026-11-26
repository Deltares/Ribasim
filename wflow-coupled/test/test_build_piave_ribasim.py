import datetime
from pathlib import Path

import numpy as np
import pytest
import ribasim
import xarray as xr
from build_piave_ribasim import (
    ALLOCATION_AREA,
    IRRIGATED,
    IRRIGATION_MIN_DEPTH,
    add_irrigation_demands,
)
from ribasim import Node
from ribasim.nodes import basin
from shapely import MultiPolygon, Point, box

# Bottom levels of the two Basins
BOTTOMS = {1: 10.0, 2: 20.0}


@pytest.fixture
def model() -> ribasim.Model:
    """Two Basins next to each other, Basin #1 from x = 0 to 3 and #2 from x = 3 to 6."""
    model = ribasim.Model(
        starttime=datetime.datetime(2010, 7, 1),
        endtime=datetime.datetime(2010, 7, 31),
        crs="EPSG:4326",
    )
    for node_id, bottom in BOTTOMS.items():
        x_min = 3.0 * (node_id - 1)
        model.basin.add(
            Node(node_id, Point(x_min + 1.5, 3.0)),
            [
                basin.Profile(level=[bottom, bottom + 5.0], area=[100.0, 100.0]),
                basin.State(level=[bottom + 2.0]),
                basin.Area(
                    geometry=[MultiPolygon([box(x_min, 0.0, x_min + 3.0, 2.0)])]
                ),
            ],
        )
    return model


def staticmaps() -> xr.Dataset:
    """Wflow static maps with 2 rows of 7 cells, the last column is outside the Basins."""
    x = np.arange(7) + 0.5
    y = np.array([1.5, 0.5])
    # An allocation area ID of 0 or NaN means the cell is outside the allocation areas
    allocation_area = np.array(
        [
            [4, 4, 5, 4, 4, 4, 4],
            [4, 4, 5, 4, 4, np.nan, 4],
        ]
    )
    allocation_area[0, 5] = 0
    irrigated = np.array(
        [
            [1, 0, 0, 0, 0, 1, 1],
            [0, 1, 0, 1, 0, 1, 1],
        ]
    )
    return xr.Dataset(
        {
            ALLOCATION_AREA: (("y", "x"), allocation_area),
            IRRIGATED: (("y", "x"), irrigated),
        },
        coords={"x": x, "y": y},
    )


def test_user_demand_per_basin_and_allocation_area(model):
    add_irrigation_demands(model, staticmaps())

    nodes = model.node.df
    user_demands = nodes[nodes.node_type == "UserDemand"]
    # Area 5 in Basin #1 has no irrigated cells, and the other irrigated cells are
    # outside the Basins or the allocation areas
    assert list(user_demands.meta_allocation_area_id) == [4, 4]
    assert list(user_demands.name) == [
        "irrigation Basin 1 allocation area 4",
        "irrigation Basin 2 allocation area 4",
    ]
    # At the mean location of the irrigated cells
    assert user_demands.geometry.iloc[0].coords[0] == pytest.approx((1.0, 1.0))
    assert user_demands.geometry.iloc[1].coords[0] == pytest.approx((3.5, 0.5))

    # Abstracting from and returning to the Basin
    links = model.link.df
    pairs = set(zip(links.from_node_id, links.to_node_id, strict=True))
    first, second = user_demands.index
    assert pairs == {(1, first), (first, 1), (2, second), (second, 2)}

    static = model.user_demand.static.df.sort_values("node_id")
    assert list(static.demand) == [0.0, 0.0]
    assert list(static.return_factor) == [0.0, 0.0]
    assert list(static.demand_priority) == [1, 1]
    assert list(static.min_level) == pytest.approx(
        [bottom + IRRIGATION_MIN_DEPTH for bottom in BOTTOMS.values()]
    )


def test_model_with_irrigation_demands_is_valid(model, tmp_path: Path):
    add_irrigation_demands(model, staticmaps())
    model.experimental.allocation = True

    model.write(tmp_path / "ribasim.toml")

    written = ribasim.Model.read(tmp_path / "ribasim.toml")
    nodes = written.node.df
    areas = nodes[nodes.node_type == "UserDemand"].meta_allocation_area_id
    assert list(areas) == [4, 4]


def test_no_irrigated_cells(model, capsys):
    maps = staticmaps()
    maps[IRRIGATED][:] = 0

    add_irrigation_demands(model, maps)

    assert "UserDemand" not in set(model.node.df.node_type)
    assert "0 with irrigated cells" in capsys.readouterr().out
