import geopandas as gpd
import pytest
import shapely.geometry as sg
from pydantic import ValidationError
from ribasim.geometry.edge import Edge


@pytest.fixture(scope="session")
def edge() -> Edge:
    a = (0.0, 0.0)
    b = (0.0, 1.0)
    c = (1.0, 1.0)
    geometry = [sg.LineString([a, b]), sg.LineString([a, c])]
    df = gpd.GeoDataFrame(
        data={"from_node_id": [1, 1], "to_node_id": [2, 3]}, geometry=geometry
    )
    edge = Edge(static=df)
    return edge


def test_validation(edge):
    assert isinstance(edge, Edge)

    with pytest.raises(ValidationError):
        df = gpd.GeoDataFrame(
            data={"from_node_id": [1, 1], "to_node_id": [None, 3]},
            geometry=[None, None],
        )
        Edge(df=df)
