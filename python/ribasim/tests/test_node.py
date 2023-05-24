import geopandas as gpd
import numpy as np
import pandas as pd
import pytest
from matplotlib import axes
from ribasim.node import Node


@pytest.fixture(scope="session")
def node() -> Node:
    node_type = ("Basin", "LinearResistance", "Basin")

    xy = np.array([(0.0, 0.0), (1.0, 0.0), (2.0, 0.0)])

    node_xy = gpd.points_from_xy(x=xy[:, 0], y=xy[:, 1])

    node = Node(
        static=gpd.GeoDataFrame(
            data={"type": node_type},
            index=pd.Index(np.arange(len(xy)) + 1, name="fid"),
            geometry=node_xy,
            crs="EPSG:28992",
        )
    )
    return node


def test_plotting(node):
    assert Node.hasfid()

    # Plotting
    ax = node.plot(legend=True)
    assert isinstance(ax, axes._axes.Axes)
    assert ax.get_legend() is not None

    return
