import geopandas as gpd
import pytest
import shapely.geometry as sg
from pydantic import ValidationError
from ribasim.geometry.edge import EdgeTable


@pytest.fixture(scope="session")
def edge() -> EdgeTable:
    a = (0.0, 0.0)
    b = (0.0, 1.0)
    c = (0.2, 0.5)
    d = (1.0, 1.0)
    geometry = [sg.LineString([a, b, c]), sg.LineString([a, d])]
    df = gpd.GeoDataFrame(
        data={"edge_id": [0, 1], "from_node_id": [1, 1], "to_node_id": [2, 3]},
        geometry=geometry,
    )
    df.set_index("edge_id", inplace=True)
    edge = EdgeTable(df=df)
    return edge


def test_validation(edge):
    assert isinstance(edge, EdgeTable)

    with pytest.raises(ValidationError):
        df = gpd.GeoDataFrame(
            data={
                "edge_id": [0, 1],
                "from_node_id": [1, 1],
                "to_node_id": ["foo", 3],
            },  # None is coerced to 0 without errors
            geometry=[None, None],
        )
        df.set_index("edge_id", inplace=True)
        EdgeTable(df=df)


def test_edge_plot(edge):
    edge.plot()


def test_edge_indexing(edge):
    with pytest.raises(NotImplementedError):
        edge[1]
