import geopandas as gpd
import pytest
import shapely.geometry as sg
from matplotlib import axes
from pydantic import ValidationError
from ribasim.edge import Edge


def test():
    a = (0.0, 0.0)
    b = (0.0, 1.0)
    c = (1.0, 1.0)
    geometry = [sg.LineString([a, b]), sg.LineString([a, c])]
    df = gpd.GeoDataFrame(
        data={"from_node_id": [1, 1], "to_node_id": [2, 3]}, geometry=geometry
    )
    edge = Edge(static=df)
    assert isinstance(edge, Edge)

    # Plotting
    ax = edge.plot(legend=True)
    assert isinstance(ax, axes._axes.Axes)

    with pytest.raises(ValidationError):
        df = gpd.GeoDataFrame(
            data={"from_node_id": [1, 1], "to_node_id": [2, 3]}, geometry=[None, None]
        )
        Edge(static=df)
